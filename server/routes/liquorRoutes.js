import { Router } from 'express';
import { z } from 'zod';
import { clean } from '../lib/objectUtils.js';
import { supabase } from '../lib/supabase.js';
import { sb } from '../lib/supabaseResponse.js';
import { requireArea } from '../middleware/auth.js';

export const liquorRouter = Router();

const LIQUOR_IMAGE_BUCKET = 'liquors';
const MAX_LIQUOR_IMAGE_BYTES = 3 * 1024 * 1024;

const liquorCreateSchema = z.object({
  name: z.string().min(1),
  image_url: z.string().nullable().optional(),
  display_order: z.coerce.number().int().optional(),
  is_active: z.boolean().optional()
});

const liquorUpdateSchema = liquorCreateSchema.partial();

function zodErrorMessage(error, fallback) {
  const first = error?.issues?.[0];
  if (!first) return fallback;
  const path = first.path?.length ? `${first.path.join('.')}: ` : '';
  return `${path}${first.message}`;
}

function isWebpBuffer(buffer) {
  return buffer.length >= 12
    && buffer.toString('ascii', 0, 4) === 'RIFF'
    && buffer.toString('ascii', 8, 12) === 'WEBP';
}

function normalizeBase64Image(value) {
  return String(value || '')
    .replace(/^data:image\/webp;base64,/i, '')
    .replace(/\s/g, '');
}

function liquorImagePath(liquorId) {
  return `liquor-types/${liquorId}/${Date.now()}.webp`;
}

function storagePathFromPublicUrl(publicUrl) {
  if (!publicUrl) return null;
  const marker = `/storage/v1/object/public/${LIQUOR_IMAGE_BUCKET}/`;
  const markerIndex = String(publicUrl).indexOf(marker);
  if (markerIndex === -1) return null;
  const pathWithQuery = String(publicUrl).slice(markerIndex + marker.length);
  return decodeURIComponent(pathWithQuery.split('?')[0]);
}

async function removeStoredLiquorImage(publicUrl) {
  const oldPath = storagePathFromPublicUrl(publicUrl);
  if (!oldPath) return;
  await supabase.storage.from(LIQUOR_IMAGE_BUCKET).remove([oldPath]);
}

function friendlyLiquorError(message) {
  if (String(message || '').includes('liquor_types_name_key')) {
    return 'A liquor type with this name already exists.';
  }

  return message || 'Liquor request failed.';
}

liquorRouter.get('/liquors', requireArea('liquors'), async (_req, res) => {
  const data = await sb(
    supabase
      .from('liquor_types')
      .select('*')
      .order('display_order', { ascending: true })
      .order('name', { ascending: true }),
    res
  );

  if (data) res.json({ liquors: data });
});

liquorRouter.post('/liquors', requireArea('liquors'), async (req, res) => {
  const parsed = liquorCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid liquor type') });

  const payload = clean({
    name: parsed.data.name.trim(),
    image_url: parsed.data.image_url || null,
    display_order: parsed.data.display_order ?? 0,
    is_active: parsed.data.is_active ?? true
  });

  const created = await supabase.from('liquor_types').insert(payload).select().single();
  if (created.error) return res.status(400).json({ error: friendlyLiquorError(created.error.message) });

  res.json(created.data);
});

liquorRouter.patch('/liquors/:id', requireArea('liquors'), async (req, res) => {
  const parsed = liquorUpdateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid liquor update') });

  const payload = clean({
    ...parsed.data,
    name: parsed.data.name !== undefined ? parsed.data.name.trim() : undefined,
    image_url: parsed.data.image_url === '' ? null : parsed.data.image_url
  });

  if (!Object.keys(payload).length) {
    return res.status(400).json({ error: 'No liquor fields were provided to update.' });
  }

  const updated = await supabase.from('liquor_types').update(payload).eq('id', req.params.id).select().single();
  if (updated.error) return res.status(400).json({ error: friendlyLiquorError(updated.error.message) });

  res.json(updated.data);
});

liquorRouter.post('/liquors/:id/image', requireArea('liquors'), async (req, res) => {
  const parsed = z.object({
    file_name: z.string().min(1),
    content_type: z.string().optional(),
    data_base64: z.string().min(1)
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid liquor image upload') });

  const fileName = parsed.data.file_name.trim().toLowerCase();
  const contentType = String(parsed.data.content_type || '').toLowerCase();
  if (contentType !== 'image/webp' && !fileName.endsWith('.webp')) {
    return res.status(400).json({ error: 'Liquor images must be uploaded as .webp files.' });
  }

  const liquor = await supabase.from('liquor_types').select('id,image_url').eq('id', req.params.id).maybeSingle();
  if (liquor.error) return res.status(400).json({ error: liquor.error.message });
  if (!liquor.data) return res.status(404).json({ error: 'Liquor type not found.' });

  const base64 = normalizeBase64Image(parsed.data.data_base64);
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
    return res.status(400).json({ error: 'Image data is not valid base64.' });
  }

  const imageBuffer = Buffer.from(base64, 'base64');
  if (!imageBuffer.length) return res.status(400).json({ error: 'Image file is empty.' });
  if (imageBuffer.length > MAX_LIQUOR_IMAGE_BYTES) {
    return res.status(400).json({ error: 'Image file is too large. Maximum size is 3 MB.' });
  }
  if (!isWebpBuffer(imageBuffer)) {
    return res.status(400).json({ error: 'The selected file is not a valid WebP image.' });
  }

  const storagePath = liquorImagePath(req.params.id);
  const uploaded = await supabase.storage
    .from(LIQUOR_IMAGE_BUCKET)
    .upload(storagePath, imageBuffer, {
      contentType: 'image/webp',
      cacheControl: '31536000',
      upsert: false
    });

  if (uploaded.error) return res.status(400).json({ error: uploaded.error.message });

  const publicUrl = supabase.storage.from(LIQUOR_IMAGE_BUCKET).getPublicUrl(storagePath).data.publicUrl;

  const updated = await supabase
    .from('liquor_types')
    .update({ image_url: publicUrl })
    .eq('id', req.params.id)
    .select()
    .single();

  if (updated.error) {
    await supabase.storage.from(LIQUOR_IMAGE_BUCKET).remove([storagePath]);
    return res.status(400).json({ error: updated.error.message });
  }

  await removeStoredLiquorImage(liquor.data.image_url);

  res.json({ liquor: updated.data, image_url: publicUrl, storage_path: storagePath });
});

liquorRouter.delete('/liquors/:id/image', requireArea('liquors'), async (req, res) => {
  const liquor = await supabase.from('liquor_types').select('id,image_url').eq('id', req.params.id).maybeSingle();
  if (liquor.error) return res.status(400).json({ error: liquor.error.message });
  if (!liquor.data) return res.status(404).json({ error: 'Liquor type not found.' });

  await removeStoredLiquorImage(liquor.data.image_url);

  const updated = await supabase
    .from('liquor_types')
    .update({ image_url: null })
    .eq('id', req.params.id)
    .select()
    .single();

  if (updated.error) return res.status(400).json({ error: updated.error.message });
  res.json({ liquor: updated.data });
});

// Soft-delete only. Existing cocktails and past orders can still reference this liquor type.
liquorRouter.delete('/liquors/:id', requireArea('liquors'), async (req, res) => {
  const updated = await sb(
    supabase
      .from('liquor_types')
      .update({ is_active: false })
      .eq('id', req.params.id)
      .select()
      .single(),
    res
  );

  if (updated) res.json(updated);
});
