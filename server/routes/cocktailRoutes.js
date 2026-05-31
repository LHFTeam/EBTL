import { Router } from 'express';
import { z } from 'zod';
import { productStatuses } from '../config/appConfig.js';
import { requireArea } from '../middleware/auth.js';
import { clean } from '../lib/objectUtils.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';

export const cocktailRouter = Router();

async function loadCocktailAdminData({ activeIngredientsOnly = true } = {}) {
  const ingredientQuery = supabase.from('ingredients').select('*').order('name');
  if (activeIngredientsOnly) ingredientQuery.eq('is_active', true);

  const [products, categories, variants, liquorTypes, compatibility, ingredients, recipes, recipeItems] = await Promise.all([
    supabase.from('products').select('*, product_categories(name)').order('name'),
    supabase.from('product_categories').select('*').order('sort_order'),
    supabase.from('product_variants').select('*').order('name'),
    supabase.from('liquor_types').select('*').order('name'),
    supabase.from('product_liquor_compatibility').select('*'),
    ingredientQuery,
    supabase.from('recipes').select('*').order('created_at', { ascending: false }),
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

cocktailRouter.get('/cocktails', requireArea('cocktails'), async (_req, res) => {
  sendCocktailAdminData(await loadCocktailAdminData({ activeIngredientsOnly: true }), res);
});

// Backward-compatible old route name.
cocktailRouter.get('/products', requireArea('cocktails'), async (_req, res) => {
  sendCocktailAdminData(await loadCocktailAdminData({ activeIngredientsOnly: false }), res);
});

cocktailRouter.post('/cocktails', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1),
    slug: z.string().min(1),
    description: z.string().optional(),
    image_url: z.string().optional(),
    category_id: z.string().uuid().optional(),
    status: z.enum(productStatuses).default('active'),
    is_featured: z.boolean().optional(),
    prep_time_minutes: z.coerce.number().int().nonnegative().optional(),
    tags: z.array(z.string()).optional(),
    variant_name: z.string().min(1).default('Standard'),
    serving_count: z.coerce.number().int().positive().default(1),
    price_ex_vat: z.coerce.number().nonnegative().default(0),
    vat_rate: z.coerce.number().nonnegative().default(0.14),
    recipe_version: z.coerce.number().int().positive().default(1),
    yield_servings: z.coerce.number().int().positive().default(1),
    liquor_type_ids: z.array(z.string().uuid()).optional(),
    recipe_items: z.array(z.object({ ingredient_id: z.string().uuid(), quantity: z.coerce.number().nonnegative(), unit: z.string().min(1), is_optional: z.boolean().optional(), is_customer_supplied: z.boolean().optional() })).optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid cocktail' });

  const p = parsed.data;
  const productPayload = clean({ category_id: p.category_id, name: p.name, slug: p.slug, description: p.description, image_url: p.image_url, status: p.status, is_featured: p.is_featured, prep_time_minutes: p.prep_time_minutes, tags: p.tags });
  const product = await supabase.from('products').insert(productPayload).select().single();
  if (product.error) return res.status(400).json({ error: product.error.message });

  const cleanup = async () => { await supabase.from('products').delete().eq('id', product.data.id); };

  const variant = await supabase.from('product_variants').insert({ product_id: product.data.id, name: p.variant_name, serving_count: p.serving_count, price_ex_vat: p.price_ex_vat, vat_rate: p.vat_rate, is_active: true }).select().single();
  if (variant.error) { await cleanup(); return res.status(400).json({ error: variant.error.message }); }

  const recipe = await supabase.from('recipes').insert({ product_id: product.data.id, version: p.recipe_version, status: p.status, yield_servings: p.yield_servings }).select().single();
  if (recipe.error) { await cleanup(); return res.status(400).json({ error: recipe.error.message }); }

  if (p.recipe_items?.length) {
    const recipeItems = await supabase.from('recipe_items').insert(p.recipe_items.map((item) => ({ ...clean(item), recipe_id: recipe.data.id }))).select();
    if (recipeItems.error) { await cleanup(); return res.status(400).json({ error: recipeItems.error.message }); }
  }

  if (p.liquor_type_ids?.length) {
    const compat = await supabase.from('product_liquor_compatibility').insert(p.liquor_type_ids.map((liquor_type_id) => ({ product_id: product.data.id, liquor_type_id }))).select();
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
    category_id: z.string().uuid().nullable().optional(),
    status: z.enum(productStatuses).optional(),
    is_featured: z.boolean().optional(),
    prep_time_minutes: z.coerce.number().int().nonnegative().optional(),
    tags: z.array(z.string()).optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid cocktail update' });
  const data = await sb(supabase.from('products').update(clean(parsed.data)).eq('id', req.params.id).select().single(), res);
  if (data) res.json(data);
});

cocktailRouter.post('/cocktails/:id/variants', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({ name: z.string().min(1), serving_count: z.coerce.number().int().positive(), price_ex_vat: z.coerce.number().nonnegative(), vat_rate: z.coerce.number().nonnegative().default(0.14), is_active: z.boolean().optional() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid variant' });
  const data = await sb(supabase.from('product_variants').insert({ ...parsed.data, product_id: req.params.id }).select().single(), res);
  if (data) res.json(data);
});

cocktailRouter.post('/cocktails/:id/liquors', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({ liquor_type_ids: z.array(z.string().uuid()) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid liquor compatibility' });
  await supabase.from('product_liquor_compatibility').delete().eq('product_id', req.params.id);
  if (!parsed.data.liquor_type_ids.length) return res.json([]);
  const data = await sb(supabase.from('product_liquor_compatibility').insert(parsed.data.liquor_type_ids.map((liquor_type_id) => ({ product_id: req.params.id, liquor_type_id }))).select(), res);
  if (data) res.json(data);
});

cocktailRouter.post('/recipes', requireArea('cocktails'), async (req, res) => {
  const data = await sb(supabase.from('recipes').insert(clean(req.body)).select().single(), res);
  if (data) res.json(data);
});

cocktailRouter.post('/recipe-items', requireArea('cocktails'), async (req, res) => {
  const data = await sb(supabase.from('recipe_items').insert(clean(req.body)).select().single(), res);
  if (data) res.json(data);
});
