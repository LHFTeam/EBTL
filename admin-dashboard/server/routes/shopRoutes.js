import { Router } from 'express';
import { z } from 'zod';
import { requireArea } from '../middleware/auth.js';
import { clean } from '../lib/objectUtils.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';

export const shopRouter = Router();

const SHOP_ASSETS_BUCKET = 'shop-assets';
const MAX_SHOP_ASSET_BYTES = 3 * 1024 * 1024;

const uuid = z.string().uuid();
const hexColor = z.string().regex(/^#[0-9A-Fa-f]{6}$/, 'Color must be a hex value like #F35F4B.');
const imageUploadSchema = z.object({
  file_name: z.string().min(1),
  content_type: z.string().optional(),
  data_base64: z.string().min(1)
});

const categoryPayloadSchema = z.object({
  name: z.string().trim().min(1),
  slug: z.string().trim().min(1).nullable().optional(),
  sort_order: z.coerce.number().int().optional(),
  is_active: z.boolean().optional(),
  image_url: z.string().trim().url().nullable().optional()
});

const categoryPatchSchema = categoryPayloadSchema.partial();

const productTagPayloadSchema = z.object({
  name: z.string().trim().min(1).max(40),
  color_hex: hexColor,
  display_order: z.coerce.number().int().optional(),
  is_active: z.boolean().optional()
});

const productTagPatchSchema = productTagPayloadSchema.partial();

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

function assetPath(folder, ownerId = 'global') {
  return `${folder}/${ownerId}/${Date.now()}.webp`;
}

function storagePathFromPublicUrl(publicUrl) {
  if (!publicUrl) return null;
  const marker = `/storage/v1/object/public/${SHOP_ASSETS_BUCKET}/`;
  const markerIndex = String(publicUrl).indexOf(marker);
  if (markerIndex === -1) return null;
  const pathWithQuery = String(publicUrl).slice(markerIndex + marker.length);
  return decodeURIComponent(pathWithQuery.split('?')[0]);
}

async function removeStoredAsset(publicUrl) {
  const oldPath = storagePathFromPublicUrl(publicUrl);
  if (!oldPath) return;
  await supabase.storage.from(SHOP_ASSETS_BUCKET).remove([oldPath]);
}

function parseWebpUpload(req, res, fallbackErrorLabel = 'Image') {
  const parsed = imageUploadSchema.safeParse(req.body);
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

  if (imageBuffer.length > MAX_SHOP_ASSET_BYTES) {
    res.status(400).json({ error: 'Image file is too large. Maximum size is 3 MB.' });
    return null;
  }

  if (!isWebpBuffer(imageBuffer)) {
    res.status(400).json({ error: 'The selected file is not a valid WebP image.' });
    return null;
  }

  return imageBuffer;
}

async function uploadWebpAsset({ folder, ownerId, buffer }) {
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

async function ensureShopSettings() {
  const current = await supabase
    .from('shop_settings')
    .select('*')
    .eq('id', true)
    .maybeSingle();

  if (current.error) return current;
  if (current.data) return current;

  return supabase
    .from('shop_settings')
    .insert({ id: true })
    .select('*')
    .single();
}

async function loadCategoryProductCounts() {
  const activeProducts = await supabase
    .from('products')
    .select('category_id')
    .eq('status', 'active')
    .not('category_id', 'is', null);

  if (activeProducts.error) return { error: activeProducts.error };

  const countsByCategoryId = new Map();
  for (const product of activeProducts.data || []) {
    countsByCategoryId.set(product.category_id, (countsByCategoryId.get(product.category_id) || 0) + 1);
  }

  return { data: countsByCategoryId };
}

shopRouter.get('/shop', requireArea('shop'), async (_req, res) => {
  const [settings, categories, productTags, counts] = await Promise.all([
    ensureShopSettings(),
    supabase.from('product_categories').select('*').order('sort_order').order('name'),
    supabase.from('product_tags').select('*').order('display_order').order('name'),
    loadCategoryProductCounts()
  ]);

  for (const result of [settings, categories, productTags, counts]) {
    if (result.error) return res.status(400).json({ error: result.error.message });
  }

  res.json({
    settings: settings.data,
    categories: (categories.data || []).map((category) => ({
      ...category,
      active_product_count: counts.data.get(category.id) || 0
    })),
    productTags: productTags.data || []
  });
});

// The shop banner image is edited from Marketing → Banners alongside the home
// hero carousel; its upload/remove endpoints live in bannerRoutes.js.

shopRouter.post('/shop/categories', requireArea('shop'), async (req, res) => {
  const parsed = categoryPayloadSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid category') });

  const data = await sb(
    supabase.from('product_categories').insert(clean(parsed.data)).select().single(),
    res
  );

  if (data) res.json(data);
});

shopRouter.patch('/shop/categories/:id', requireArea('shop'), async (req, res) => {
  const parsed = categoryPatchSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid category update') });

  const payload = clean(parsed.data);
  if (!Object.keys(payload).length) return res.status(400).json({ error: 'No category fields were provided to update.' });

  const data = await sb(
    supabase.from('product_categories').update(payload).eq('id', req.params.id).select().single(),
    res
  );

  if (data) res.json(data);
});

shopRouter.delete('/shop/categories/:id', requireArea('shop'), async (req, res) => {
  const data = await sb(
    supabase.from('product_categories').update({ is_active: false }).eq('id', req.params.id).select().single(),
    res
  );

  if (data) res.json(data);
});

shopRouter.post('/shop/categories/:id/image', requireArea('shop'), async (req, res) => {
  const categoryId = uuid.safeParse(req.params.id);
  if (!categoryId.success) return res.status(400).json({ error: 'Invalid category id.' });

  const imageBuffer = parseWebpUpload(req, res, 'Category image');
  if (!imageBuffer) return;

  const category = await supabase
    .from('product_categories')
    .select('id,image_url')
    .eq('id', req.params.id)
    .maybeSingle();

  if (category.error) return res.status(400).json({ error: category.error.message });
  if (!category.data) return res.status(404).json({ error: 'Category not found.' });

  const uploaded = await uploadWebpAsset({ folder: 'categories', ownerId: req.params.id, buffer: imageBuffer });
  if (uploaded.error) return res.status(400).json({ error: uploaded.error.message });

  const updated = await supabase
    .from('product_categories')
    .update({ image_url: uploaded.publicUrl })
    .eq('id', req.params.id)
    .select()
    .single();

  if (updated.error) {
    await supabase.storage.from(SHOP_ASSETS_BUCKET).remove([uploaded.storagePath]);
    return res.status(400).json({ error: updated.error.message });
  }

  await removeStoredAsset(category.data.image_url);

  res.json({ category: updated.data, image_url: uploaded.publicUrl, storage_path: uploaded.storagePath });
});

shopRouter.delete('/shop/categories/:id/image', requireArea('shop'), async (req, res) => {
  const category = await supabase
    .from('product_categories')
    .select('id,image_url')
    .eq('id', req.params.id)
    .maybeSingle();

  if (category.error) return res.status(400).json({ error: category.error.message });
  if (!category.data) return res.status(404).json({ error: 'Category not found.' });

  await removeStoredAsset(category.data.image_url);

  const updated = await supabase
    .from('product_categories')
    .update({ image_url: null })
    .eq('id', req.params.id)
    .select()
    .single();

  if (updated.error) return res.status(400).json({ error: updated.error.message });
  res.json({ category: updated.data });
});

shopRouter.post('/shop/product-tags', requireArea('shop'), async (req, res) => {
  const parsed = productTagPayloadSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid product tag') });

  const data = await sb(
    supabase.from('product_tags').insert(clean(parsed.data)).select().single(),
    res
  );

  if (data) res.json(data);
});

shopRouter.patch('/shop/product-tags/:id', requireArea('shop'), async (req, res) => {
  const parsed = productTagPatchSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid product tag update') });

  const payload = clean(parsed.data);
  if (!Object.keys(payload).length) return res.status(400).json({ error: 'No product tag fields were provided to update.' });

  const data = await sb(
    supabase.from('product_tags').update(payload).eq('id', req.params.id).select().single(),
    res
  );

  if (data) res.json(data);
});

shopRouter.delete('/shop/product-tags/:id', requireArea('shop'), async (req, res) => {
  const data = await sb(
    supabase.from('product_tags').update({ is_active: false }).eq('id', req.params.id).select().single(),
    res
  );

  if (data) res.json(data);
});
