import { Router } from 'express';
import { z } from 'zod';
import { requireArea } from '../middleware/auth.js';
import { supabase } from '../lib/supabase.js';
import {
  DEFAULT_PILL_SCHEME,
  GOLDEN_HOUR_MODES,
  GOLDEN_HOUR_MODE_LABELS,
  GOLDEN_HOUR_PILL_SCHEMES,
  GOLDEN_HOUR_PILL_SCHEME_KEYS,
  MAX_EXTRA_PILLS,
  cairoMinutesNow,
  ensureGoldenHourModes,
  minutesToTime,
  timeToMinutes,
  windowCoverage
} from '../lib/goldenHour.js';
import {
  SHOP_ASSETS_BUCKET,
  parseWebpUpload,
  removeStoredAsset,
  uploadWebpAsset,
  zodErrorMessage
} from '../lib/webpUploads.js';

export const goldenHourRouter = Router();

// Marketing → Golden Hour edits four fixed rows. There is deliberately no
// create and no delete here: the modes are a vocabulary the app also knows, so
// a fifth one could only ever reach it as something it cannot draw. `is_active`
// is how a mode is turned off.

const modeParam = z.enum(GOLDEN_HOUR_MODES);

// Accepts what an <input type="time"> sends (`09:00`) and what Postgres returns
// (`09:00:00`), and normalizes both to the former.
const timeOfDay = z
  .string()
  .trim()
  .transform((value, ctx) => {
    const minutes = timeToMinutes(value);
    if (minutes == null) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Use a 24-hour time like 09:00.' });
      return z.NEVER;
    }
    return minutesToTime(minutes);
  });

// An optional column the dashboard clears by sending ''. Undefined keeps
// meaning "field not sent", so a PATCH leaves the column alone.
function optionalText(max) {
  return z
    .string()
    .trim()
    .max(max)
    .nullable()
    .optional()
    .transform((value) => (value === '' ? null : value));
}

const pillScheme = z.enum(GOLDEN_HOUR_PILL_SCHEME_KEYS);

// The pills after the leading spirit pill. The array is the whole list every
// time — its length is the "how many" the tab controls, so a shorter array is
// how a pill is removed.
const pillsSchema = z
  .array(z.object({
    label: z.string().trim().min(1, 'Give the pill some text or remove it.').max(24),
    scheme: pillScheme.optional().default(DEFAULT_PILL_SCHEME)
  }))
  .max(MAX_EXTRA_PILLS, `A mode can show at most ${MAX_EXTRA_PILLS} pills after the spirit pill.`);

const modePatchSchema = z.object({
  is_active: z.boolean().optional(),
  start_time: timeOfDay.optional(),
  end_time: timeOfDay.optional(),
  title: optionalText(60),
  subtitle: optionalText(160),
  product_id: z.string().uuid().nullable().optional(),
  image_caption: optionalText(120),
  spirit_pill_scheme: pillScheme.optional(),
  pills: pillsSchema.optional()
}).strict();

/**
 * What the row will look like once the patch lands — the patch's own values
 * where it has them, the stored ones everywhere else.
 *
 * Validation that spans fields (the window's two ends, "active needs a title
 * and a cocktail") has to run against that merged shape rather than the patch:
 * the tab sends only what changed, so a PATCH flipping `is_active` alone still
 * has to be judged on the title already in the row.
 */
function mergedMode(current, patch) {
  return { ...current, ...patch };
}

function windowProblem(mode) {
  const start = timeToMinutes(mode.start_time);
  const end = timeToMinutes(mode.end_time);

  if (start == null || end == null) return 'Both the start and end of the window are required.';
  if (start === end) return 'The window\'s start and end cannot be the same time.';

  return null;
}

function activationProblem(mode) {
  if (!mode.is_active) return null;
  if (!String(mode.title || '').trim()) return 'Give the mode a title before switching it on.';
  if (!mode.product_id) return 'Choose a cocktail before switching the mode on.';

  return null;
}

// Normalizes what Postgres returns (`09:00:00`) to what the tab's time inputs
// expect (`09:00`), so a round-trip through the form does not look like a change.
function adminMode(row) {
  return {
    ...row,
    start_time: minutesToTime(timeToMinutes(row.start_time) ?? 0),
    end_time: minutesToTime(timeToMinutes(row.end_time) ?? 0),
    pills: Array.isArray(row.pills) ? row.pills : []
  };
}

// Everything the Golden Hour tab needs in one call: the four modes, the
// cocktails behind the picker, the pill palette, and where the windows are
// thin. `now_minutes` is what the tab uses to point at the mode showing now.
goldenHourRouter.get('/golden-hour', requireArea('golden-hour'), async (_req, res) => {
  const [modes, cocktails] = await Promise.all([
    ensureGoldenHourModes(),
    supabase
      .from('products')
      .select('id,name,slug')
      .eq('status', 'active')
      .eq('product_type', 'cocktail')
      .order('name')
  ]);

  for (const result of [modes, cocktails]) {
    if (result.error) return res.status(400).json({ error: result.error.message });
  }

  const rows = (modes.data || []).map(adminMode);

  res.json({
    modes: rows,
    modeLabels: GOLDEN_HOUR_MODE_LABELS,
    pillSchemes: GOLDEN_HOUR_PILL_SCHEMES,
    maxPills: MAX_EXTRA_PILLS,
    cocktails: (cocktails.data || []).filter((cocktail) => cocktail.slug),
    coverage: windowCoverage(rows),
    now_minutes: cairoMinutesNow()
  });
});

goldenHourRouter.patch('/golden-hour/:mode', requireArea('golden-hour'), async (req, res) => {
  const mode = modeParam.safeParse(req.params.mode);
  if (!mode.success) return res.status(400).json({ error: 'Unknown Golden Hour mode.' });

  const parsed = modePatchSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid Golden Hour mode.') });

  const patch = parsed.data;
  if (!Object.keys(patch).length) return res.status(400).json({ error: 'No Golden Hour fields were provided to update.' });

  const current = await supabase
    .from('golden_hour_modes')
    .select('*')
    .eq('mode', mode.data)
    .maybeSingle();

  if (current.error) return res.status(400).json({ error: current.error.message });
  if (!current.data) return res.status(404).json({ error: 'Golden Hour mode not found. Has the migration been applied?' });

  const merged = mergedMode(current.data, patch);

  const problem = windowProblem(merged) || activationProblem(merged);
  if (problem) return res.status(400).json({ error: problem });

  const updated = await supabase
    .from('golden_hour_modes')
    .update(patch)
    .eq('mode', mode.data)
    .select('*')
    .single();

  if (updated.error) return res.status(400).json({ error: updated.error.message });
  res.json({ mode: adminMode(updated.data) });
});

goldenHourRouter.post('/golden-hour/:mode/image', requireArea('golden-hour'), async (req, res) => {
  const mode = modeParam.safeParse(req.params.mode);
  if (!mode.success) return res.status(400).json({ error: 'Unknown Golden Hour mode.' });

  const imageBuffer = parseWebpUpload(req.body, res, 'Golden Hour image');
  if (!imageBuffer) return;

  const current = await supabase
    .from('golden_hour_modes')
    .select('mode,image_url')
    .eq('mode', mode.data)
    .maybeSingle();

  if (current.error) return res.status(400).json({ error: current.error.message });
  if (!current.data) return res.status(404).json({ error: 'Golden Hour mode not found. Has the migration been applied?' });

  const uploaded = await uploadWebpAsset({ folder: 'golden-hour', ownerId: mode.data, buffer: imageBuffer });
  if (uploaded.error) return res.status(400).json({ error: uploaded.error.message });

  const updated = await supabase
    .from('golden_hour_modes')
    .update({ image_url: uploaded.publicUrl })
    .eq('mode', mode.data)
    .select('*')
    .single();

  // The row is what makes the upload reachable, so a failed update leaves an
  // orphan in storage — drop it rather than paying for it forever.
  if (updated.error) {
    await supabase.storage.from(SHOP_ASSETS_BUCKET).remove([uploaded.storagePath]);
    return res.status(400).json({ error: updated.error.message });
  }

  await removeStoredAsset(current.data.image_url);

  res.json({ mode: adminMode(updated.data), image_url: uploaded.publicUrl, storage_path: uploaded.storagePath });
});

goldenHourRouter.delete('/golden-hour/:mode/image', requireArea('golden-hour'), async (req, res) => {
  const mode = modeParam.safeParse(req.params.mode);
  if (!mode.success) return res.status(400).json({ error: 'Unknown Golden Hour mode.' });

  const current = await supabase
    .from('golden_hour_modes')
    .select('mode,image_url')
    .eq('mode', mode.data)
    .maybeSingle();

  if (current.error) return res.status(400).json({ error: current.error.message });
  if (!current.data) return res.status(404).json({ error: 'Golden Hour mode not found. Has the migration been applied?' });

  await removeStoredAsset(current.data.image_url);

  const updated = await supabase
    .from('golden_hour_modes')
    .update({ image_url: null })
    .eq('mode', mode.data)
    .select('*')
    .single();

  if (updated.error) return res.status(400).json({ error: updated.error.message });
  res.json({ mode: adminMode(updated.data) });
});
