import { Router } from 'express';
import { z } from 'zod';
import { productStatuses } from '../config/appConfig.js';
import { requireArea } from '../middleware/auth.js';
import { clean } from '../lib/objectUtils.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';

export const cocktailRouter = Router();

const uuid = z.string().uuid();
const nullableUuid = uuid.nullable();
const vatRate = z.coerce.number().min(0).max(1);

const shortDescription = z.string().max(40, 'Short description must be 40 characters or less.').nullable().optional();
const markdownDescription = z.string().max(6000, 'Description is too long.').nullable().optional();
const hexColor = z.string().regex(/^#[0-9A-Fa-f]{6}$/, 'Color must be a hex value like #F35F4B.');

function normalizeTagName(value) {
  return String(value || '').trim();
}

function normalizeTagNames(values = []) {
  return [...new Set((values || []).map(normalizeTagName).filter(Boolean))];
}

async function validateProductTagNames(tagNames, res) {
  const normalizedTags = normalizeTagNames(tagNames);
  if (!normalizedTags.length) return { ok: true, tags: [] };

  const result = await supabase
    .from('product_tags')
    .select('name,is_active')
    .in('name', normalizedTags);

  if (result.error) {
    res.status(400).json({ error: result.error.message });
    return { ok: false };
  }

  const activeNames = new Set(
    (result.data || [])
      .filter((tag) => tag.is_active)
      .map((tag) => tag.name)
  );

  const invalid = normalizedTags.filter((tagName) => !activeNames.has(tagName));

  if (invalid.length) {
    res.status(400).json({ error: `Unknown or inactive product tag: ${invalid.join(', ')}` });
    return { ok: false };
  }

  return { ok: true, tags: normalizedTags };
}

const COCKTAIL_IMAGE_BUCKET = 'cocktails';
const MAX_COCKTAIL_IMAGE_BYTES = 3 * 1024 * 1024;

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

function cocktailImagePath(productId) {
  return `products/${productId}/${Date.now()}.webp`;
}

function storagePathFromPublicUrl(publicUrl) {
  if (!publicUrl) return null;
  const marker = `/storage/v1/object/public/${COCKTAIL_IMAGE_BUCKET}/`;
  const markerIndex = String(publicUrl).indexOf(marker);
  if (markerIndex === -1) return null;
  const pathWithQuery = String(publicUrl).slice(markerIndex + marker.length);
  return decodeURIComponent(pathWithQuery.split('?')[0]);
}

async function removeStoredCocktailImage(publicUrl) {
  const oldPath = storagePathFromPublicUrl(publicUrl);
  if (!oldPath) return;
  await supabase.storage.from(COCKTAIL_IMAGE_BUCKET).remove([oldPath]);
}

function zodErrorMessage(error, fallback) {
  const first = error?.issues?.[0];
  if (!first) return fallback;
  const path = first.path?.length ? `${first.path.join('.')}: ` : '';
  return `${path}${first.message}`;
}

const recipePayloadSchema = z.object({
  status: z.enum(productStatuses).optional(),
  yield_servings: z.coerce.number().int().positive().optional(),
  notes: z.string().nullable().optional()
});

const recipeItemPayloadSchema = z.object({
  ingredient_id: uuid,
  quantity: z.coerce.number().nonnegative(),
  unit: z.string().min(1),
  is_optional: z.boolean().optional(),
  is_customer_supplied: z.boolean().optional()
});

const recipeItemPatchSchema = recipeItemPayloadSchema.partial();

async function validateRecipeItemPayloads(items, res) {
  if (!items.length) return true;

  const ingredientIds = [...new Set(items.map((item) => item.ingredient_id).filter(Boolean))];
  if (!ingredientIds.length) return true;

  const ingredients = await supabase.from('ingredients').select('id,name,base_unit').in('id', ingredientIds);
  if (ingredients.error) {
    res.status(400).json({ error: ingredients.error.message });
    return false;
  }

  const ingredientById = new Map((ingredients.data || []).map((ingredient) => [ingredient.id, ingredient]));

  for (const item of items) {
    if (!item.ingredient_id) continue;

    const ingredient = ingredientById.get(item.ingredient_id);
    if (!ingredient) {
      res.status(400).json({ error: `Ingredient ${item.ingredient_id} does not exist.` });
      return false;
    }

    if (item.unit && String(item.unit).toLowerCase() !== String(ingredient.base_unit).toLowerCase()) {
      res.status(400).json({ error: `${ingredient.name} must use ${ingredient.base_unit} as its recipe unit.` });
      return false;
    }
  }

  return true;
}

async function findCurrentRecipeForProduct(productId) {
  return supabase
    .from('recipes')
    .select('*')
    .eq('product_id', productId)
    .order('version', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
}

async function loadCocktailAdminData({ activeIngredientsOnly = true } = {}) {
  const ingredientQuery = supabase.from('ingredients').select('*').order('name');
  if (activeIngredientsOnly) ingredientQuery.eq('is_active', true);

  const [products, categories, variants, liquorTypes, compatibility, ingredients, recipes, recipeItems, productTags] = await Promise.all([
    supabase.from('products').select('*, product_categories(name)').order('name'),
    supabase.from('product_categories').select('*').order('sort_order').order('name'),
    supabase.from('product_variants').select('*').order('name'),
    supabase.from('liquor_types').select('*').order('name'),
    supabase.from('product_liquor_compatibility').select('*'),
    ingredientQuery,
    supabase.from('recipes').select('*').order('version', { ascending: false }).order('created_at', { ascending: false }),
    supabase.from('recipe_items').select('*, ingredients(name,base_unit,icon_key)').order('id'),
    supabase.from('product_tags').select('*').order('display_order').order('name')
  ]);
  
  return { products, categories, variants, liquorTypes, compatibility, ingredients, recipes, recipeItems, productTags };
}

function sendCocktailAdminData(resultMap, res) {
  const results = Object.values(resultMap);
  for (const result of results) if (result.error) return res.status(400).json({ error: result.error.message });
  return res.json({
    products: resultMap.products.data,
    categories: resultMap.categories.data,
    variants: resultMap.variants.data,
    liquorTypes: resultMap.liquorTypes.data,
    compatibility: resultMap.compatibility.data,
    ingredients: resultMap.ingredients.data,
    recipes: resultMap.recipes.data,
    recipeItems: resultMap.recipeItems.data,
    productTags: resultMap.productTags.data
  });
}

async function fetchVariantForProduct(productId, variantId) {
  const current = await supabase
    .from('product_variants')
    .select('*')
    .eq('id', variantId)
    .eq('product_id', productId)
    .maybeSingle();
  if (current.error) return { error: current.error.message };
  if (!current.data) return { error: 'Variant not found for this cocktail.' };
  return { data: current.data };
}

async function fetchRecipe(recipeId) {
  const current = await supabase.from('recipes').select('*').eq('id', recipeId).maybeSingle();
  if (current.error) return { error: current.error.message };
  if (!current.data) return { error: 'Recipe not found.' };
  return { data: current.data };
}

cocktailRouter.get('/cocktails', requireArea('cocktails'), async (_req, res) => {
  sendCocktailAdminData(await loadCocktailAdminData({ activeIngredientsOnly: false }), res);
});

// Backward-compatible old route name.
cocktailRouter.get('/products', requireArea('cocktails'), async (_req, res) => {
  sendCocktailAdminData(await loadCocktailAdminData({ activeIngredientsOnly: false }), res);
});

const productTagPayloadSchema = z.object({
  name: z.string().trim().min(1).max(40),
  color_hex: hexColor,
  display_order: z.coerce.number().int().optional(),
  is_active: z.boolean().optional()
});

const productTagPatchSchema = productTagPayloadSchema.partial();

cocktailRouter.get('/product-tags', requireArea('cocktails'), async (req, res) => {
  let query = supabase.from('product_tags').select('*').order('display_order').order('name');

  if (String(req.query.include_inactive || '').toLowerCase() !== 'true') {
    query = query.eq('is_active', true);
  }

  const data = await sb(query, res);
  if (data) res.json(data);
});

cocktailRouter.post('/product-tags', requireArea('cocktails'), async (req, res) => {
  const parsed = productTagPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid product tag') });
  }

  const data = await sb(
    supabase.from('product_tags').insert(clean(parsed.data)).select().single(),
    res
  );

  if (data) res.json(data);
});

cocktailRouter.patch('/product-tags/:id', requireArea('cocktails'), async (req, res) => {
  const parsed = productTagPatchSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid product tag update') });
  }

  const payload = clean(parsed.data);
  if (!Object.keys(payload).length) {
    return res.status(400).json({ error: 'No product tag fields were provided to update.' });
  }

  const data = await sb(
    supabase.from('product_tags').update(payload).eq('id', req.params.id).select().single(),
    res
  );

  if (data) res.json(data);
});

cocktailRouter.delete('/product-tags/:id', requireArea('cocktails'), async (req, res) => {
  const data = await sb(
    supabase.from('product_tags').update({ is_active: false }).eq('id', req.params.id).select().single(),
    res
  );

  if (data) res.json(data);
});

cocktailRouter.post('/cocktails', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1),
    slug: z.string().min(1),
    description: markdownDescription,
    short_description: shortDescription,
    description: z.string().nullable().optional(),
    image_url: z.string().nullable().optional(),
    category_id: nullableUuid.optional(),
    status: z.enum(productStatuses).default('active'),
    is_featured: z.boolean().optional(),
    prep_time_minutes: z.coerce.number().int().nonnegative().optional(),
    tags: z.array(z.string()).optional(),
    variant_name: z.string().min(1).default('Standard'),
    serving_count: z.coerce.number().int().positive().default(1),
    price_ex_vat: z.coerce.number().nonnegative().default(0),
    vat_rate: vatRate.default(0.14),
    recipe_version: z.coerce.number().int().positive().default(1),
    yield_servings: z.coerce.number().int().positive().default(1),
    liquor_type_ids: z.array(uuid).optional(),
    recipe_items: z.array(recipeItemPayloadSchema).optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid cocktail') });

  const p = parsed.data;

  const validatedTags = await validateProductTagNames(p.tags || [], res);
  if (!validatedTags.ok) return;
  
  const productPayload = clean({
    category_id: p.category_id,
    name: p.name,
    slug: p.slug,
    description: p.description,
    short_description: p.short_description,
    image_url: p.image_url,
    status: p.status,
    is_featured: p.is_featured,
    prep_time_minutes: p.prep_time_minutes,
    tags: validatedTags.tags
  });

  const product = await supabase.from('products').insert(productPayload).select().single();
  if (product.error) return res.status(400).json({ error: product.error.message });

  const cleanup = async () => { await supabase.from('products').delete().eq('id', product.data.id); };

  const variant = await supabase.from('product_variants').insert({
    product_id: product.data.id,
    name: p.variant_name,
    serving_count: p.serving_count,
    price_ex_vat: p.price_ex_vat,
    vat_rate: p.vat_rate,
    is_active: true
  }).select().single();
  if (variant.error) { await cleanup(); return res.status(400).json({ error: variant.error.message }); }

  const recipe = await supabase.from('recipes').insert({
    product_id: product.data.id,
    version: p.recipe_version,
    status: p.status,
    yield_servings: p.yield_servings
  }).select().single();
  if (recipe.error) { await cleanup(); return res.status(400).json({ error: recipe.error.message }); }

  if (p.recipe_items?.length) {
    const validItems = await validateRecipeItemPayloads(p.recipe_items, res);
    if (!validItems) { await cleanup(); return; }
  
    const recipeItems = await supabase
      .from('recipe_items')
      .insert(p.recipe_items.map((item) => ({ ...clean(item), recipe_id: recipe.data.id })))
      .select();
    if (recipeItems.error) { await cleanup(); return res.status(400).json({ error: recipeItems.error.message }); }
  }
  
  if (p.liquor_type_ids?.length) {
    const compat = await supabase
      .from('product_liquor_compatibility')
      .insert(p.liquor_type_ids.map((liquor_type_id) => ({ product_id: product.data.id, liquor_type_id })))
      .select();
    if (compat.error) { await cleanup(); return res.status(400).json({ error: compat.error.message }); }
  }

  res.json({ product: product.data, variant: variant.data, recipe: recipe.data });
});

cocktailRouter.patch('/cocktails/:id', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1).optional(),
    slug: z.string().min(1).optional(),
    description: markdownDescription,
    short_description: shortDescription,
    image_url: z.string().nullable().optional(),
    category_id: nullableUuid.optional(),
    status: z.enum(productStatuses).optional(),
    is_featured: z.boolean().optional(),
    prep_time_minutes: z.coerce.number().int().nonnegative().optional(),
    tags: z.array(z.string()).optional(),
    display_order: z.coerce.number().int().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid cocktail update') });

  const validatedTags = parsed.data.tags === undefined
    ? null
    : await validateProductTagNames(parsed.data.tags || [], res);
  
  if (validatedTags && !validatedTags.ok) return;
  
  const payload = clean({
    ...parsed.data,
    ...(validatedTags ? { tags: validatedTags.tags } : {})
  });
  
  if (!Object.keys(payload).length) return res.status(400).json({ error: 'No cocktail fields were provided to update.' });

  const data = await sb(supabase.from('products').update(payload).eq('id', req.params.id).select().single(), res);
  if (data) res.json(data);
});

cocktailRouter.post('/cocktails/:id/image', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    file_name: z.string().min(1),
    content_type: z.string().optional(),
    data_base64: z.string().min(1)
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid cocktail image upload') });

  const fileName = parsed.data.file_name.trim().toLowerCase();
  const contentType = String(parsed.data.content_type || '').toLowerCase();
  if (contentType !== 'image/webp' && !fileName.endsWith('.webp')) {
    return res.status(400).json({ error: 'Cocktail images must be uploaded as .webp files.' });
  }

  const product = await supabase.from('products').select('id,image_url').eq('id', req.params.id).maybeSingle();
  if (product.error) return res.status(400).json({ error: product.error.message });
  if (!product.data) return res.status(404).json({ error: 'Cocktail not found.' });

  const base64 = normalizeBase64Image(parsed.data.data_base64);
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
    return res.status(400).json({ error: 'Image data is not valid base64.' });
  }

  const imageBuffer = Buffer.from(base64, 'base64');
  if (!imageBuffer.length) return res.status(400).json({ error: 'Image file is empty.' });
  if (imageBuffer.length > MAX_COCKTAIL_IMAGE_BYTES) {
    return res.status(400).json({ error: 'Image file is too large. Maximum size is 3 MB.' });
  }
  if (!isWebpBuffer(imageBuffer)) {
    return res.status(400).json({ error: 'The selected file is not a valid WebP image.' });
  }

  const storagePath = cocktailImagePath(req.params.id);
  const uploaded = await supabase.storage
    .from(COCKTAIL_IMAGE_BUCKET)
    .upload(storagePath, imageBuffer, {
      contentType: 'image/webp',
      cacheControl: '31536000',
      upsert: false
    });

  if (uploaded.error) return res.status(400).json({ error: uploaded.error.message });

  const publicUrl = supabase.storage.from(COCKTAIL_IMAGE_BUCKET).getPublicUrl(storagePath).data.publicUrl;

  const updated = await supabase
    .from('products')
    .update({ image_url: publicUrl })
    .eq('id', req.params.id)
    .select()
    .single();

  if (updated.error) {
    await supabase.storage.from(COCKTAIL_IMAGE_BUCKET).remove([storagePath]);
    return res.status(400).json({ error: updated.error.message });
  }

  await removeStoredCocktailImage(product.data.image_url);

  res.json({ product: updated.data, image_url: publicUrl, storage_path: storagePath });
});

cocktailRouter.delete('/cocktails/:id/image', requireArea('cocktails'), async (req, res) => {
  const product = await supabase.from('products').select('id,image_url').eq('id', req.params.id).maybeSingle();
  if (product.error) return res.status(400).json({ error: product.error.message });
  if (!product.data) return res.status(404).json({ error: 'Cocktail not found.' });

  await removeStoredCocktailImage(product.data.image_url);

  const updated = await supabase
    .from('products')
    .update({ image_url: null })
    .eq('id', req.params.id)
    .select()
    .single();

  if (updated.error) return res.status(400).json({ error: updated.error.message });
  res.json({ product: updated.data });
});

cocktailRouter.delete('/cocktails/:id', requireArea('cocktails'), async (req, res) => {
  const product = await supabase.from('products').select('id,name,status').eq('id', req.params.id).maybeSingle();
  if (product.error) return res.status(400).json({ error: product.error.message });
  if (!product.data) return res.status(404).json({ error: 'Cocktail not found.' });

  const variants = await supabase.from('product_variants').update({ is_active: false }).eq('product_id', req.params.id).select('id');
  if (variants.error) return res.status(400).json({ error: variants.error.message });

  const recipes = await supabase.from('recipes').update({ status: 'archived' }).eq('product_id', req.params.id).select('id');
  if (recipes.error) return res.status(400).json({ error: recipes.error.message });

  const archived = await supabase
    .from('products')
    .update({ status: 'archived' })
    .eq('id', req.params.id)
    .select('id,name,status')
    .single();
  if (archived.error) return res.status(400).json({ error: archived.error.message });

  res.json({ product: archived.data, deactivated_variants: variants.data || [], archived_recipes: recipes.data || [] });
});

const variantCreateSchema = z.object({
  name: z.string().min(1),
  serving_count: z.coerce.number().int().positive(),
  price_ex_vat: z.coerce.number().nonnegative(),
  vat_rate: vatRate.default(0.14),
  is_active: z.boolean().optional()
});

const variantUpdateSchema = z.object({
  name: z.string().min(1).optional(),
  serving_count: z.coerce.number().int().positive().optional(),
  price_ex_vat: z.coerce.number().nonnegative().optional(),
  vat_rate: vatRate.optional(),
  is_active: z.boolean().optional()
});

async function updateVariant({ variantId, productId, patch, res }) {
  const currentQuery = supabase.from('product_variants').select('*').eq('id', variantId);
  if (productId) currentQuery.eq('product_id', productId);

  const current = await currentQuery.maybeSingle();
  if (current.error) return res.status(400).json({ error: current.error.message });
  if (!current.data) return res.status(404).json({ error: 'Variant not found.' });

  const payload = clean(patch);
  
  if (!Object.keys(payload).length) return res.status(400).json({ error: 'No variant fields were provided to update.' });

  const updateQuery = supabase.from('product_variants').update(payload).eq('id', variantId);
  if (productId) updateQuery.eq('product_id', productId);

  const data = await sb(updateQuery.select().single(), res);
  if (data) return res.json(data);
}

async function deactivateVariant({ variantId, productId, res }) {
  const updateQuery = supabase.from('product_variants').update({ is_active: false }).eq('id', variantId);
  if (productId) updateQuery.eq('product_id', productId);

  const data = await sb(updateQuery.select().single(), res);
  if (data) return res.json(data);
}

cocktailRouter.post('/cocktails/:id/variants', requireArea('cocktails'), async (req, res) => {
  const parsed = variantCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid variant') });

  const payload = {
    ...parsed.data,
    product_id: req.params.id
  };
  
  const data = await sb(supabase.from('product_variants').insert(payload).select().single(), res);
  if (data) res.json(data);
});

cocktailRouter.patch('/cocktails/:id/variants/:variantId', requireArea('cocktails'), async (req, res) => {
  const parsed = variantUpdateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid variant update') });

  await updateVariant({ variantId: req.params.variantId, productId: req.params.id, patch: parsed.data, res });
});

cocktailRouter.delete('/cocktails/:id/variants/:variantId', requireArea('cocktails'), async (req, res) => {
  await deactivateVariant({ variantId: req.params.variantId, productId: req.params.id, res });
});

// Generic variant routes for screens/tools that know the variant id but not the cocktail id.
// These are intentionally soft-delete routes because historical carts/orders can reference variants.
cocktailRouter.patch('/product-variants/:variantId', requireArea('cocktails'), async (req, res) => {
  const parsed = variantUpdateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid variant update') });

  await updateVariant({ variantId: req.params.variantId, patch: parsed.data, res });
});

cocktailRouter.delete('/product-variants/:variantId', requireArea('cocktails'), async (req, res) => {
  await deactivateVariant({ variantId: req.params.variantId, res });
});

cocktailRouter.post('/cocktails/:id/liquors', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({ liquor_type_ids: z.array(uuid) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid liquor compatibility') });

  const deleted = await supabase.from('product_liquor_compatibility').delete().eq('product_id', req.params.id);
  if (deleted.error) return res.status(400).json({ error: deleted.error.message });

  if (!parsed.data.liquor_type_ids.length) return res.json([]);

  const data = await sb(
    supabase
      .from('product_liquor_compatibility')
      .insert(parsed.data.liquor_type_ids.map((liquor_type_id) => ({ product_id: req.params.id, liquor_type_id })))
      .select(),
    res
  );
  if (data) res.json(data);
});

cocktailRouter.put('/cocktails/:id/recipe-items', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    recipe_id: uuid.optional(),
    recipe: recipePayloadSchema.optional(),
    items: z.array(recipeItemPayloadSchema).default([])
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid recipe replacement') });

  const productId = req.params.id;
  const product = await supabase.from('products').select('id,status').eq('id', productId).maybeSingle();
  if (product.error) return res.status(400).json({ error: product.error.message });
  if (!product.data) return res.status(404).json({ error: 'Cocktail not found.' });

  const validItems = await validateRecipeItemPayloads(parsed.data.items, res);
  if (!validItems) return;

  let recipe;
  if (parsed.data.recipe_id) {
    recipe = await supabase.from('recipes').select('*').eq('id', parsed.data.recipe_id).eq('product_id', productId).maybeSingle();
  } else {
    recipe = await findCurrentRecipeForProduct(productId);
  }

  if (recipe.error) return res.status(400).json({ error: recipe.error.message });

  if (!recipe.data) {
    recipe = await supabase
      .from('recipes')
      .insert({
        product_id: productId,
        status: parsed.data.recipe?.status || product.data.status || 'draft',
        yield_servings: parsed.data.recipe?.yield_servings || 1,
        notes: parsed.data.recipe?.notes ?? null,
        version: 1
      })
      .select()
      .single();

    if (recipe.error) return res.status(400).json({ error: recipe.error.message });
  } else if (parsed.data.recipe && Object.keys(clean(parsed.data.recipe)).length) {
    const updatedRecipe = await supabase
      .from('recipes')
      .update(clean(parsed.data.recipe))
      .eq('id', recipe.data.id)
      .select()
      .single();

    if (updatedRecipe.error) return res.status(400).json({ error: updatedRecipe.error.message });
    recipe = updatedRecipe;
  }

  const deleted = await supabase.from('recipe_items').delete().eq('recipe_id', recipe.data.id);
  if (deleted.error) return res.status(400).json({ error: deleted.error.message });

  if (!parsed.data.items.length) return res.json({ recipe: recipe.data, items: [] });

  const inserted = await supabase
    .from('recipe_items')
    .insert(parsed.data.items.map((item) => ({ ...clean(item), recipe_id: recipe.data.id })))
    .select('*, ingredients(name,base_unit,icon_key)');

  if (inserted.error) return res.status(400).json({ error: inserted.error.message });

  res.json({ recipe: recipe.data, items: inserted.data });
});

cocktailRouter.post('/recipes', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    product_id: uuid,
    version: z.coerce.number().int().positive().optional(),
    status: z.enum(productStatuses).default('draft'),
    yield_servings: z.coerce.number().int().positive().default(1),
    notes: z.string().nullable().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid recipe') });

  let payload = clean(parsed.data);
  if (!payload.version) {
    const existing = await supabase
      .from('recipes')
      .select('version')
      .eq('product_id', payload.product_id)
      .order('version', { ascending: false })
      .limit(1);
    if (existing.error) return res.status(400).json({ error: existing.error.message });
    payload = { ...payload, version: Number(existing.data?.[0]?.version || 0) + 1 };
  }

  const data = await sb(supabase.from('recipes').insert(payload).select().single(), res);
  if (data) res.json(data);
});

cocktailRouter.patch('/recipes/:recipeId', requireArea('cocktails'), async (req, res) => {
  const parsed = recipePayloadSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid recipe update') });

  const payload = clean(parsed.data);
  if (!Object.keys(payload).length) return res.status(400).json({ error: 'No recipe fields were provided to update.' });

  const data = await sb(supabase.from('recipes').update(payload).eq('id', req.params.recipeId).select().single(), res);
  if (data) res.json(data);
});

cocktailRouter.post('/recipes/:recipeId/items', requireArea('cocktails'), async (req, res) => {
  const parsed = recipeItemPayloadSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid recipe item') });

  const recipe = await fetchRecipe(req.params.recipeId);
  if (recipe.error) return res.status(400).json({ error: recipe.error });

  const validItems = await validateRecipeItemPayloads([parsed.data], res);
  if (!validItems) return;

  const data = await sb(
    supabase
      .from('recipe_items')
      .insert({ ...clean(parsed.data), recipe_id: req.params.recipeId })
      .select('*, ingredients(name,base_unit,icon_key)')
      .single(),
    res
  );
  if (data) res.json(data);
});

// Backward-compatible old route name.
cocktailRouter.post('/recipe-items', requireArea('cocktails'), async (req, res) => {
  const parsed = recipeItemPayloadSchema.extend({ recipe_id: uuid }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid recipe item') });

  const validItems = await validateRecipeItemPayloads([parsed.data], res);
  if (!validItems) return;

  const data = await sb(supabase.from('recipe_items').insert(clean(parsed.data)).select('*, ingredients(name,base_unit,icon_key)').single(), res);
  if (data) res.json(data);
});

cocktailRouter.patch('/recipe-items/:itemId', requireArea('cocktails'), async (req, res) => {
  const parsed = recipeItemPatchSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid recipe item update') });

  const payload = clean(parsed.data);
  if (!Object.keys(payload).length) return res.status(400).json({ error: 'No recipe item fields were provided to update.' });

  if (payload.ingredient_id || payload.unit) {
    const current = await supabase.from('recipe_items').select('ingredient_id,unit').eq('id', req.params.itemId).maybeSingle();
    if (current.error) return res.status(400).json({ error: current.error.message });
    if (!current.data) return res.status(404).json({ error: 'Recipe item not found.' });

    const validItems = await validateRecipeItemPayloads([{
      ingredient_id: payload.ingredient_id || current.data.ingredient_id,
      unit: payload.unit || current.data.unit
    }], res);
    if (!validItems) return;
  }

  const data = await sb(
    supabase
      .from('recipe_items')
      .update(payload)
      .eq('id', req.params.itemId)
      .select('*, ingredients(name,base_unit,icon_key)')
      .single(),
    res
  );
  if (data) res.json(data);
});

cocktailRouter.delete('/recipe-items/:itemId', requireArea('cocktails'), async (req, res) => {
  const data = await sb(supabase.from('recipe_items').delete().eq('id', req.params.itemId).select().single(), res);
  if (data) res.json(data);
});
