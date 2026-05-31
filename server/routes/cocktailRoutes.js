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

function priceIncVat(priceExVat, vatRateValue) {
  return Number((Number(priceExVat || 0) * (1 + Number(vatRateValue || 0))).toFixed(2));
}

function zodErrorMessage(error, fallback) {
  const first = error?.issues?.[0];
  if (!first) return fallback;
  const path = first.path?.length ? `${first.path.join('.')}: ` : '';
  return `${path}${first.message}`;
}

async function loadCocktailAdminData({ activeIngredientsOnly = true } = {}) {
  const ingredientQuery = supabase.from('ingredients').select('*').order('name');
  if (activeIngredientsOnly) ingredientQuery.eq('is_active', true);

  const [products, categories, variants, liquorTypes, compatibility, ingredients, recipes, recipeItems] = await Promise.all([
    supabase.from('products').select('*, product_categories(name)').order('name'),
    supabase.from('product_categories').select('*').order('sort_order').order('name'),
    supabase.from('product_variants').select('*').order('name'),
    supabase.from('liquor_types').select('*').order('name'),
    supabase.from('product_liquor_compatibility').select('*'),
    ingredientQuery,
    supabase.from('recipes').select('*').order('version', { ascending: false }).order('created_at', { ascending: false }),
    supabase.from('recipe_items').select('*, ingredients(name,base_unit)').order('id')
  ]);

  return { products, categories, variants, liquorTypes, compatibility, ingredients, recipes, recipeItems };
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
    recipeItems: resultMap.recipeItems.data
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

cocktailRouter.post('/cocktails', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1),
    slug: z.string().min(1),
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
    recipe_items: z.array(z.object({
      ingredient_id: uuid,
      quantity: z.coerce.number().nonnegative(),
      unit: z.string().min(1),
      is_optional: z.boolean().optional(),
      is_customer_supplied: z.boolean().optional()
    })).optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid cocktail') });

  const p = parsed.data;
  const productPayload = clean({
    category_id: p.category_id,
    name: p.name,
    slug: p.slug,
    description: p.description,
    image_url: p.image_url,
    status: p.status,
    is_featured: p.is_featured,
    prep_time_minutes: p.prep_time_minutes,
    tags: p.tags
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
    price_inc_vat: priceIncVat(p.price_ex_vat, p.vat_rate),
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
    description: z.string().nullable().optional(),
    image_url: z.string().nullable().optional(),
    category_id: nullableUuid.optional(),
    status: z.enum(productStatuses).optional(),
    is_featured: z.boolean().optional(),
    prep_time_minutes: z.coerce.number().int().nonnegative().optional(),
    tags: z.array(z.string()).optional(),
    display_order: z.coerce.number().int().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid cocktail update') });

  const payload = clean(parsed.data);
  if (!Object.keys(payload).length) return res.status(400).json({ error: 'No cocktail fields were provided to update.' });

  const data = await sb(supabase.from('products').update(payload).eq('id', req.params.id).select().single(), res);
  if (data) res.json(data);
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
  if (payload.price_ex_vat !== undefined || payload.vat_rate !== undefined) {
    const nextPriceExVat = payload.price_ex_vat !== undefined ? payload.price_ex_vat : current.data.price_ex_vat;
    const nextVatRate = payload.vat_rate !== undefined ? payload.vat_rate : current.data.vat_rate;
    payload.price_inc_vat = priceIncVat(nextPriceExVat, nextVatRate);
  }

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
    product_id: req.params.id,
    price_inc_vat: priceIncVat(parsed.data.price_ex_vat, parsed.data.vat_rate)
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
  const parsed = z.object({
    status: z.enum(productStatuses).optional(),
    yield_servings: z.coerce.number().int().positive().optional(),
    notes: z.string().nullable().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid recipe update') });

  const payload = clean(parsed.data);
  if (!Object.keys(payload).length) return res.status(400).json({ error: 'No recipe fields were provided to update.' });

  const data = await sb(supabase.from('recipes').update(payload).eq('id', req.params.recipeId).select().single(), res);
  if (data) res.json(data);
});

cocktailRouter.post('/recipes/:recipeId/items', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    ingredient_id: uuid,
    quantity: z.coerce.number().nonnegative(),
    unit: z.string().min(1),
    is_optional: z.boolean().optional(),
    is_customer_supplied: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid recipe item') });

  const recipe = await fetchRecipe(req.params.recipeId);
  if (recipe.error) return res.status(400).json({ error: recipe.error });

  const data = await sb(
    supabase
      .from('recipe_items')
      .insert({ ...clean(parsed.data), recipe_id: req.params.recipeId })
      .select('*, ingredients(name,base_unit)')
      .single(),
    res
  );
  if (data) res.json(data);
});

// Backward-compatible old route name.
cocktailRouter.post('/recipe-items', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    recipe_id: uuid,
    ingredient_id: uuid,
    quantity: z.coerce.number().nonnegative(),
    unit: z.string().min(1),
    is_optional: z.boolean().optional(),
    is_customer_supplied: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid recipe item') });

  const data = await sb(supabase.from('recipe_items').insert(clean(parsed.data)).select('*, ingredients(name,base_unit)').single(), res);
  if (data) res.json(data);
});

cocktailRouter.patch('/recipe-items/:itemId', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    ingredient_id: uuid.optional(),
    quantity: z.coerce.number().nonnegative().optional(),
    unit: z.string().min(1).optional(),
    is_optional: z.boolean().optional(),
    is_customer_supplied: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid recipe item update') });

  const payload = clean(parsed.data);
  if (!Object.keys(payload).length) return res.status(400).json({ error: 'No recipe item fields were provided to update.' });

  const data = await sb(
    supabase
      .from('recipe_items')
      .update(payload)
      .eq('id', req.params.itemId)
      .select('*, ingredients(name,base_unit)')
      .single(),
    res
  );
  if (data) res.json(data);
});

cocktailRouter.delete('/recipe-items/:itemId', requireArea('cocktails'), async (req, res) => {
  const data = await sb(supabase.from('recipe_items').delete().eq('id', req.params.itemId).select().single(), res);
  if (data) res.json(data);
});
