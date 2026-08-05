import { supabase } from './supabase.js';

// "Golden Hour" — the modal the customer app shows on launch when a beach cart
// is already chosen. Four time-of-day variants, edited in Marketing → Golden
// Hour, resolved to at most one here on every `/api/customer/home`.
//
// This module is the shared vocabulary between the two halves: the admin routes
// validate against it, the customer route resolves through it. The app knows
// the same mode names and the same scheme keys.

const BUSINESS_TIME_ZONE = 'Africa/Cairo';

// Order matters: it is the order the dashboard lists them in, and the order the
// resolver walks when more than one window happens to match.
export const GOLDEN_HOUR_MODES = ['morning', 'afternoon', 'sunset', 'evening'];

export const GOLDEN_HOUR_MODE_LABELS = {
  morning: 'Morning',
  afternoon: 'Afternoon',
  sunset: 'Sunset',
  evening: 'Evening'
};

// The pill palette, drawn from the app's own tokens (`EbtlColors` in
// customer-app/lib/core/theme/ebtl_colors.dart). Marketing picks a scheme by
// key and never types a colour; the hex here is only so the dashboard can draw
// a swatch of what it is choosing. The app maps the same keys to the same
// colours locally and falls back to `sand` for one it does not know, so adding
// a scheme is a backend + app change, not a backend-only one.
export const GOLDEN_HOUR_PILL_SCHEMES = [
  { key: 'sand', label: 'Sand', background: '#F3E5D0', foreground: '#0E2238' },
  { key: 'seafoam', label: 'Seafoam', background: '#C9E3DD', foreground: '#1F6F68' },
  { key: 'blush', label: 'Blush', background: '#F8C9BD', foreground: '#0E2238' },
  { key: 'gold', label: 'Gold', background: '#E7BD68', foreground: '#0E2238' },
  { key: 'coral', label: 'Coral', background: '#F35F4B', foreground: '#FFFFFF' },
  { key: 'teal', label: 'Teal', background: '#1F6F68', foreground: '#FFFFFF' },
  { key: 'navy', label: 'Navy', background: '#0E2238', foreground: '#FFF8EE' },
  { key: 'cream', label: 'Cream', background: '#FFF8EE', foreground: '#1F2933' }
];

export const GOLDEN_HOUR_PILL_SCHEME_KEYS = GOLDEN_HOUR_PILL_SCHEMES.map((scheme) => scheme.key);
export const DEFAULT_PILL_SCHEME = 'sand';

// What the modal's pill row fits on the narrowest phone the app targets. The
// check constraint on the table holds the same line.
export const MAX_EXTRA_PILLS = 4;

// Shown when the chosen cocktail has no liquor type recorded against it. The
// leading pill always says "Your <something>", so it needs a word even then.
const FALLBACK_SPIRIT_LABEL = 'bottle';

/** `'09:00'` / `'09:00:00'` → 540. Returns null for anything else. */
export function timeToMinutes(value) {
  const match = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(String(value || '').trim());
  if (!match) return null;

  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (hours > 23 || minutes > 59) return null;

  return hours * 60 + minutes;
}

/** 540 → `'09:00'`. */
export function minutesToTime(minutes) {
  const safe = ((Math.round(Number(minutes) || 0) % 1440) + 1440) % 1440;
  return `${String(Math.floor(safe / 60)).padStart(2, '0')}:${String(safe % 60).padStart(2, '0')}`;
}

/** Minutes since midnight, right now, in Cairo. */
export function cairoMinutesNow(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: BUSINESS_TIME_ZONE,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23'
  }).formatToParts(date);

  const hour = Number(parts.find((part) => part.type === 'hour')?.value || 0);
  const minute = Number(parts.find((part) => part.type === 'minute')?.value || 0);

  return hour * 60 + minute;
}

/**
 * Is `nowMinutes` inside the window? Start is inclusive, end exclusive.
 *
 * A start later than the end is a window that wraps past midnight — evening's
 * default 19:00–02:00 covers 19:00 through 01:59, not the 22 hours in between.
 */
export function isWithinWindow({ startMinutes, endMinutes, nowMinutes }) {
  if (startMinutes == null || endMinutes == null) return false;
  if (startMinutes === endMinutes) return false;

  return startMinutes < endMinutes
    ? nowMinutes >= startMinutes && nowMinutes < endMinutes
    : nowMinutes >= startMinutes || nowMinutes < endMinutes;
}

/**
 * A mode with nothing to say is not shown, however active the row claims to be.
 *
 * The dashboard refuses to switch a mode on without these, but the row can lose
 * them afterwards — the cocktail is archived, or `product_id` is nulled when a
 * product is deleted — and the modal must not open on a half-empty card.
 */
export function isRenderableMode(mode) {
  return Boolean(mode?.is_active)
    && Boolean(String(mode?.title || '').trim())
    && Boolean(mode?.product_id);
}

/**
 * The hours the given modes cover between them, and where they leave the day
 * uncovered or doubled up. Only the modes that would actually show are counted.
 *
 * Overlaps are legal — the resolver takes the first match in mode order — but
 * they are almost always a typo, and a gap means a customer opening the app at
 * that hour gets no card. Neither is worth refusing a save over, so Marketing →
 * Golden Hour shows them as a warning rather than the API rejecting them.
 */
export function windowCoverage(modes) {
  const active = (modes || []).filter((mode) => isRenderableMode(mode));

  const overlaps = [];
  for (let left = 0; left < active.length; left += 1) {
    for (let right = left + 1; right < active.length; right += 1) {
      if (windowsOverlap(active[left], active[right])) {
        overlaps.push([active[left].mode, active[right].mode]);
      }
    }
  }

  // Walk the day a minute at a time and collect the runs nothing covers. 1440
  // iterations over at most four windows, once per page load — small enough
  // that clarity beats interval arithmetic, especially with wrapping windows.
  const gaps = [];
  let runStart = null;

  for (let minute = 0; minute < 1440; minute += 1) {
    const covered = active.some((mode) => isWithinWindow({
      startMinutes: timeToMinutes(mode.start_time),
      endMinutes: timeToMinutes(mode.end_time),
      nowMinutes: minute
    }));

    if (!covered && runStart == null) runStart = minute;
    if (covered && runStart != null) {
      gaps.push({ start: minutesToTime(runStart), end: minutesToTime(minute) });
      runStart = null;
    }
  }

  // Only a run still open when the day runs out is closed here, and at 24:00
  // rather than 00:00 so "22:00–24:00" does not read as a window that wraps.
  // Closing it inside the loop instead would open a run on the last iteration
  // of a fully covered day and report the whole day as a gap.
  if (runStart != null) gaps.push({ start: minutesToTime(runStart), end: '24:00' });

  return { overlaps, gaps };
}

function windowsOverlap(left, right) {
  const leftStart = timeToMinutes(left.start_time);
  const leftEnd = timeToMinutes(left.end_time);
  const rightStart = timeToMinutes(right.start_time);
  const rightEnd = timeToMinutes(right.end_time);

  for (let minute = 0; minute < 1440; minute += 1) {
    const inLeft = isWithinWindow({ startMinutes: leftStart, endMinutes: leftEnd, nowMinutes: minute });
    const inRight = isWithinWindow({ startMinutes: rightStart, endMinutes: rightEnd, nowMinutes: minute });
    if (inLeft && inRight) return true;
  }

  return false;
}

function normalizeScheme(value) {
  const key = String(value || '').trim();
  return GOLDEN_HOUR_PILL_SCHEME_KEYS.includes(key) ? key : DEFAULT_PILL_SCHEME;
}

/**
 * The stored `pills` jsonb, cleaned for the app: labelled pills only, capped,
 * and every scheme one the app knows how to draw.
 */
export function publicPills(pills) {
  if (!Array.isArray(pills)) return [];

  return pills
    .map((pill) => ({
      label: String(pill?.label || '').trim(),
      scheme: normalizeScheme(pill?.scheme)
    }))
    .filter((pill) => pill.label.length > 0)
    .slice(0, MAX_EXTRA_PILLS);
}

/**
 * The liquor type the leading pill names.
 *
 * "The first one recorded" for a cocktail with several: `product_liquor_compatibility`
 * carries no timestamp of its own, so first means first in catalogue order —
 * the same order the liquor types are listed in everywhere else in the app
 * (`display_order`, then name). Deterministic, and it matches what a customer
 * would call the cocktail's spirit.
 */
async function loadPrimaryLiquorTypeName(productId) {
  const compatibility = await supabase
    .from('product_liquor_compatibility')
    .select('liquor_type_id, liquor_types(name, display_order, is_active)')
    .eq('product_id', productId);

  if (compatibility.error) return null;

  const named = (compatibility.data || [])
    .map((row) => row.liquor_types)
    .filter((liquorType) => liquorType && String(liquorType.name || '').trim() && liquorType.is_active !== false)
    .sort((left, right) => {
      const byOrder = Number(left.display_order || 0) - Number(right.display_order || 0);
      return byOrder !== 0 ? byOrder : String(left.name).localeCompare(String(right.name));
    });

  return named[0]?.name?.trim() || null;
}

/**
 * The modal to show right now, or null.
 *
 * Every failure path answers null rather than throwing: the modal is a nice
 * greeting, and a missing table or an archived cocktail must cost the customer
 * a home screen, not break one. `/api/customer/home` reads this alongside the
 * rest of its payload for exactly that reason.
 */
export async function loadActiveGoldenHourModal({ nowMinutes = cairoMinutesNow() } = {}) {
  const modes = await supabase
    .from('golden_hour_modes')
    .select('mode, is_active, start_time, end_time, title, subtitle, product_id, image_url, image_caption, spirit_pill_scheme, pills')
    .eq('is_active', true);

  if (modes.error) return null;

  const byMode = new Map((modes.data || []).map((row) => [row.mode, row]));

  const match = GOLDEN_HOUR_MODES
    .map((mode) => byMode.get(mode))
    .filter((row) => row && isRenderableMode(row))
    .find((row) => isWithinWindow({
      startMinutes: timeToMinutes(row.start_time),
      endMinutes: timeToMinutes(row.end_time),
      nowMinutes
    }));

  if (!match) return null;

  // Only the fields the modal needs to render and to add the right thing to the
  // cart. The app opens the cocktail by slug, exactly as "Order It Again" does,
  // so it picks up today's price and availability rather than a snapshot.
  const product = await supabase
    .from('products')
    .select('id, slug, name, status')
    .eq('id', match.product_id)
    .maybeSingle();

  if (product.error || !product.data) return null;

  // Archived or draft cocktails are not orderable, and a modal whose only
  // action fails is worse than no modal.
  if (product.data.status !== 'active' || !String(product.data.slug || '').trim()) return null;

  const liquorTypeName = await loadPrimaryLiquorTypeName(match.product_id);

  return {
    mode: match.mode,
    title: String(match.title || '').trim(),
    subtitle: String(match.subtitle || '').trim() || null,
    image_url: String(match.image_url || '').trim() || null,
    image_caption: String(match.image_caption || '').trim() || null,
    cocktail: {
      id: product.data.id,
      slug: product.data.slug,
      name: product.data.name
    },
    spirit_pill: {
      label: `Your ${liquorTypeName || FALLBACK_SPIRIT_LABEL}`,
      scheme: normalizeScheme(match.spirit_pill_scheme)
    },
    pills: publicPills(match.pills)
  };
}

/**
 * The four rows, in mode order, standing any missing one back up.
 *
 * The migration seeds them, so this only matters for a project the migration
 * has not reached yet and for a row someone deleted by hand — the API offers no
 * create, so without this the tab would have nothing to edit.
 */
export async function ensureGoldenHourModes() {
  const existing = await supabase.from('golden_hour_modes').select('*');
  if (existing.error) return existing;

  const found = new Map((existing.data || []).map((row) => [row.mode, row]));
  const missing = GOLDEN_HOUR_MODES.filter((mode) => !found.has(mode));

  if (missing.length) {
    const seeded = await supabase
      .from('golden_hour_modes')
      .insert(missing.map((mode) => ({ mode, ...DEFAULT_WINDOWS[mode] })))
      .select('*');

    if (seeded.error) return seeded;
    for (const row of seeded.data || []) found.set(row.mode, row);
  }

  return { data: GOLDEN_HOUR_MODES.map((mode) => found.get(mode)).filter(Boolean), error: null };
}

// Matches the seed in the migration, so a row rebuilt here is the row the
// migration would have made.
const DEFAULT_WINDOWS = {
  morning: { start_time: '06:00', end_time: '11:00', spirit_pill_scheme: 'sand' },
  afternoon: { start_time: '11:00', end_time: '16:00', spirit_pill_scheme: 'seafoam' },
  sunset: { start_time: '16:00', end_time: '19:00', spirit_pill_scheme: 'gold' },
  evening: { start_time: '19:00', end_time: '02:00', spirit_pill_scheme: 'navy' }
};
