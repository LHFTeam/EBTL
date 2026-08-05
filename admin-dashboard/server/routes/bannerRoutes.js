import { Router } from 'express';
import { z } from 'zod';
import { requireArea } from '../middleware/auth.js';
import { clean } from '../lib/objectUtils.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';
import {
  SHOP_ASSETS_BUCKET,
  imageUploadSchema,
  parseWebpUpload,
  removeStoredAsset,
  uploadWebpAsset,
  zodErrorMessage
} from '../lib/webpUploads.js';

export const bannerRouter = Router();

const uuid = z.string().uuid();

// Destinations a hero banner tap can resolve to in the customer app. The app
// parses the same set (`HomeHeroBanner.link`); anything else is rejected here
// so a typo cannot ship a slide that taps into nothing.
const staticDeepLinks = ['finder', 'explore', 'cart', 'orders'];
const cocktailDeepLink = /^cocktail\/[a-z0-9]+(?:-[a-z0-9]+)*$/;
const categoryDeepLink = /^category\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isSupportedDeepLink(value) {
  return staticDeepLinks.includes(value)
    || cocktailDeepLink.test(value)
    || categoryDeepLink.test(value);
}

// An optional column the dashboard clears by sending ''. Undefined keeps
// meaning "field not sent", which PATCH relies on to leave a column alone.
function optionalText(max) {
  return z
    .string()
    .trim()
    .max(max)
    .nullable()
    .optional()
    .transform((value) => (value === '' ? null : value));
}

const optionalDeepLink = z
  .string()
  .trim()
  .nullable()
  .optional()
  .transform((value) => (value === '' ? null : value))
  .refine((value) => value == null || isSupportedDeepLink(value), {
    message: 'Deep link must be finder, explore, cart, orders, cocktail/<slug> or category/<category id>.'
  });

// Only the image and the order are required. Everything else is optional
// decoration the slide renders when present.
const heroBannerFieldsSchema = z.object({
  headline: optionalText(80),
  body: optionalText(200),
  deep_link: optionalDeepLink,
  display_order: z.coerce.number().int().min(0),
  is_active: z.boolean().optional()
});

const heroBannerCreateSchema = heroBannerFieldsSchema.extend({
  image: imageUploadSchema
});

const heroBannerPatchSchema = heroBannerFieldsSchema.partial();

// Bounds match the check constraint on home_hero_settings: two seconds is the
// fastest a slide can be read, a minute the slowest that still reads as a
// carousel rather than a static image.
const heroSettingsPatchSchema = z.object({
  rotation_seconds: z.coerce.number().int().min(2).max(60)
});

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

// The migration seeds the singleton row, so this only has to stand one back up
// if it is ever deleted.
async function ensureHeroSettings() {
  const current = await supabase
    .from('home_hero_settings')
    .select('*')
    .eq('id', true)
    .maybeSingle();

  if (current.error) return current;
  if (current.data) return current;

  return supabase
    .from('home_hero_settings')
    .insert({ id: true })
    .select('*')
    .single();
}

// Everything the Banners tab needs in one call: the hero carousel rows and its
// rotation setting, the shop banner image, and the catalog rows behind the
// deep-link pickers.
bannerRouter.get('/banners', requireArea('banners'), async (_req, res) => {
  const [heroBanners, heroSettings, shopSettings, categories, cocktails] = await Promise.all([
    supabase.from('home_hero_banners').select('*').order('display_order').order('created_at'),
    ensureHeroSettings(),
    ensureShopSettings(),
    supabase.from('product_categories').select('id,name').eq('is_active', true).order('sort_order').order('name'),
    supabase.from('products').select('slug,name').eq('status', 'active').eq('product_type', 'cocktail').order('name')
  ]);

  for (const result of [heroBanners, heroSettings, shopSettings, categories, cocktails]) {
    if (result.error) return res.status(400).json({ error: result.error.message });
  }

  res.json({
    heroBanners: heroBanners.data || [],
    heroSettings: heroSettings.data,
    shopSettings: shopSettings.data,
    deepLinkOptions: {
      categories: categories.data || [],
      cocktails: (cocktails.data || []).filter((cocktail) => cocktail.slug)
    }
  });
});

bannerRouter.patch('/banners/hero-settings', requireArea('banners'), async (req, res) => {
  const parsed = heroSettingsPatchSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid hero carousel settings') });

  const settings = await ensureHeroSettings();
  if (settings.error) return res.status(400).json({ error: settings.error.message });

  const updated = await supabase
    .from('home_hero_settings')
    .update({ rotation_seconds: parsed.data.rotation_seconds })
    .eq('id', true)
    .select('*')
    .single();

  if (updated.error) return res.status(400).json({ error: updated.error.message });
  res.json({ settings: updated.data });
});

bannerRouter.post('/banners/hero', requireArea('banners'), async (req, res) => {
  const parsed = heroBannerCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid hero banner') });

  const imageBuffer = parseWebpUpload(parsed.data.image, res, 'Hero banner image');
  if (!imageBuffer) return;

  const uploaded = await uploadWebpAsset({ folder: 'banners/hero', ownerId: 'new', buffer: imageBuffer });
  if (uploaded.error) return res.status(400).json({ error: uploaded.error.message });

  const created = await supabase
    .from('home_hero_banners')
    .insert(clean({
      image_url: uploaded.publicUrl,
      headline: parsed.data.headline ?? null,
      body: parsed.data.body ?? null,
      deep_link: parsed.data.deep_link ?? null,
      display_order: parsed.data.display_order,
      is_active: parsed.data.is_active
    }))
    .select('*')
    .single();

  // The row is what makes the upload reachable, so a failed insert leaves an
  // orphan in storage — drop it rather than paying for it forever.
  if (created.error) {
    await supabase.storage.from(SHOP_ASSETS_BUCKET).remove([uploaded.storagePath]);
    return res.status(400).json({ error: created.error.message });
  }

  res.json({ banner: created.data });
});

bannerRouter.patch('/banners/hero/:id', requireArea('banners'), async (req, res) => {
  const bannerId = uuid.safeParse(req.params.id);
  if (!bannerId.success) return res.status(400).json({ error: 'Invalid hero banner id.' });

  const parsed = heroBannerPatchSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid hero banner update') });

  // Optional text columns are cleared with an explicit null, which `clean()`
  // keeps and `undefined` (field not sent) drops.
  const payload = clean(parsed.data);
  if (!Object.keys(payload).length) return res.status(400).json({ error: 'No hero banner fields were provided to update.' });

  const data = await sb(
    supabase.from('home_hero_banners').update(payload).eq('id', req.params.id).select('*').single(),
    res
  );

  if (data) res.json({ banner: data });
});

bannerRouter.post('/banners/hero/:id/image', requireArea('banners'), async (req, res) => {
  const bannerId = uuid.safeParse(req.params.id);
  if (!bannerId.success) return res.status(400).json({ error: 'Invalid hero banner id.' });

  const imageBuffer = parseWebpUpload(req.body, res, 'Hero banner image');
  if (!imageBuffer) return;

  const banner = await supabase
    .from('home_hero_banners')
    .select('id,image_url')
    .eq('id', req.params.id)
    .maybeSingle();

  if (banner.error) return res.status(400).json({ error: banner.error.message });
  if (!banner.data) return res.status(404).json({ error: 'Hero banner not found.' });

  const uploaded = await uploadWebpAsset({ folder: 'banners/hero', ownerId: req.params.id, buffer: imageBuffer });
  if (uploaded.error) return res.status(400).json({ error: uploaded.error.message });

  const updated = await supabase
    .from('home_hero_banners')
    .update({ image_url: uploaded.publicUrl })
    .eq('id', req.params.id)
    .select('*')
    .single();

  if (updated.error) {
    await supabase.storage.from(SHOP_ASSETS_BUCKET).remove([uploaded.storagePath]);
    return res.status(400).json({ error: updated.error.message });
  }

  await removeStoredAsset(banner.data.image_url);

  res.json({ banner: updated.data, image_url: uploaded.publicUrl, storage_path: uploaded.storagePath });
});

// A hero banner has no history worth keeping and nothing references it, so
// removing one is a real delete — `is_active` is the soft "hide it for now".
bannerRouter.delete('/banners/hero/:id', requireArea('banners'), async (req, res) => {
  const bannerId = uuid.safeParse(req.params.id);
  if (!bannerId.success) return res.status(400).json({ error: 'Invalid hero banner id.' });

  const banner = await supabase
    .from('home_hero_banners')
    .select('id,image_url')
    .eq('id', req.params.id)
    .maybeSingle();

  if (banner.error) return res.status(400).json({ error: banner.error.message });
  if (!banner.data) return res.status(404).json({ error: 'Hero banner not found.' });

  const deleted = await supabase.from('home_hero_banners').delete().eq('id', req.params.id);
  if (deleted.error) return res.status(400).json({ error: deleted.error.message });

  await removeStoredAsset(banner.data.image_url);

  res.json({ deleted: true, id: req.params.id });
});

// The shop banner lives on the same tab as the hero carousel, so its upload
// endpoints moved here from shopRoutes with the UI section.
bannerRouter.post('/banners/shop-image', requireArea('banners'), async (req, res) => {
  const imageBuffer = parseWebpUpload(req.body, res, 'Shop banner image');
  if (!imageBuffer) return;

  const settings = await ensureShopSettings();
  if (settings.error) return res.status(400).json({ error: settings.error.message });

  const uploaded = await uploadWebpAsset({ folder: 'banners', ownerId: 'shop', buffer: imageBuffer });
  if (uploaded.error) return res.status(400).json({ error: uploaded.error.message });

  const updated = await supabase
    .from('shop_settings')
    .update({ banner_image_url: uploaded.publicUrl })
    .eq('id', true)
    .select('*')
    .single();

  if (updated.error) {
    await supabase.storage.from(SHOP_ASSETS_BUCKET).remove([uploaded.storagePath]);
    return res.status(400).json({ error: updated.error.message });
  }

  await removeStoredAsset(settings.data?.banner_image_url);

  res.json({ settings: updated.data, image_url: uploaded.publicUrl, storage_path: uploaded.storagePath });
});

bannerRouter.delete('/banners/shop-image', requireArea('banners'), async (_req, res) => {
  const settings = await ensureShopSettings();
  if (settings.error) return res.status(400).json({ error: settings.error.message });

  await removeStoredAsset(settings.data?.banner_image_url);

  const updated = await supabase
    .from('shop_settings')
    .update({ banner_image_url: null })
    .eq('id', true)
    .select('*')
    .single();

  if (updated.error) return res.status(400).json({ error: updated.error.message });
  res.json({ settings: updated.data });
});
