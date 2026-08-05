import { z } from 'zod';
import { supabase } from './supabase.js';

// Image uploads for the dashboard's merchandising tabs. Every one of them works
// the same way: the browser posts a base64 WebP, the server checks it really is
// a WebP and small enough, drops it in the `shop-assets` bucket, and stores the
// public URL on a row. This module is that shared machinery — it was written
// for the hero banners and moved here when Golden Hour needed the same thing.
//
// WebP-only is a deliberate constraint carried over from the shop assets: the
// app renders these over other artwork on a phone, and asking marketing to
// convert once beats shipping PNGs to every customer forever.

export const SHOP_ASSETS_BUCKET = 'shop-assets';
export const MAX_UPLOAD_BYTES = 3 * 1024 * 1024;

export const imageUploadSchema = z.object({
  file_name: z.string().min(1),
  content_type: z.string().optional(),
  data_base64: z.string().min(1)
});

// zod reports a path and a message; callers want one sentence to put in a
// response body.
export function zodErrorMessage(error, fallback) {
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

function assetPath(folder, ownerId = 'global') {
  return `${folder}/${ownerId}/${Date.now()}.webp`;
}

export function storagePathFromPublicUrl(publicUrl) {
  if (!publicUrl) return null;
  const marker = `/storage/v1/object/public/${SHOP_ASSETS_BUCKET}/`;
  const markerIndex = String(publicUrl).indexOf(marker);
  if (markerIndex === -1) return null;
  const pathWithQuery = String(publicUrl).slice(markerIndex + marker.length);
  return decodeURIComponent(pathWithQuery.split('?')[0]);
}

export async function removeStoredAsset(publicUrl) {
  const oldPath = storagePathFromPublicUrl(publicUrl);
  if (!oldPath) return;
  await supabase.storage.from(SHOP_ASSETS_BUCKET).remove([oldPath]);
}

/**
 * Validates an upload payload and returns its bytes, or answers the request
 * with the reason it was rejected and returns null.
 */
export function parseWebpUpload(payload, res, fallbackErrorLabel = 'Image') {
  const parsed = imageUploadSchema.safeParse(payload);
  if (!parsed.success) {
    res.status(400).json({ error: zodErrorMessage(parsed.error, `Invalid ${fallbackErrorLabel.toLowerCase()} upload`) });
    return null;
  }

  const fileName = parsed.data.file_name.trim().toLowerCase();
  const contentType = String(parsed.data.content_type || '').toLowerCase();

  if (contentType !== 'image/webp' && !fileName.endsWith('.webp')) {
    res.status(400).json({ error: `${fallbackErrorLabel} must be uploaded as a .webp file.` });
    return null;
  }

  const base64 = normalizeBase64Image(parsed.data.data_base64);
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
    res.status(400).json({ error: 'Image data is not valid base64.' });
    return null;
  }

  const imageBuffer = Buffer.from(base64, 'base64');
  if (!imageBuffer.length) {
    res.status(400).json({ error: 'Image file is empty.' });
    return null;
  }

  if (imageBuffer.length > MAX_UPLOAD_BYTES) {
    res.status(400).json({ error: 'Image file is too large. Maximum size is 3 MB.' });
    return null;
  }

  if (!isWebpBuffer(imageBuffer)) {
    res.status(400).json({ error: 'The selected file is not a valid WebP image.' });
    return null;
  }

  return imageBuffer;
}

export async function uploadWebpAsset({ folder, ownerId, buffer }) {
  const storagePath = assetPath(folder, ownerId);
  const uploaded = await supabase.storage
    .from(SHOP_ASSETS_BUCKET)
    .upload(storagePath, buffer, {
      contentType: 'image/webp',
      cacheControl: '31536000',
      upsert: false
    });

  if (uploaded.error) return { error: uploaded.error };

  const publicUrl = supabase.storage.from(SHOP_ASSETS_BUCKET).getPublicUrl(storagePath).data.publicUrl;
  return { publicUrl, storagePath };
}
