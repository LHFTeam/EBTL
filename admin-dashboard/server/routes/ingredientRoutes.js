import { Router } from 'express';
import { z } from 'zod';
import { requireArea } from '../middleware/auth.js';
import { clean } from '../lib/objectUtils.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';

export const ingredientRouter = Router();

function hasOwn(obj, key) {
  return Object.prototype.hasOwnProperty.call(obj, key);
}

function isNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function canCalculateCostPerBaseUnit(payload) {
  return isNumber(payload.purchase_unit_cost) && isNumber(payload.purchase_unit_size) && payload.purchase_unit_size > 0;
}

function calculateCostPerBaseUnit(payload) {
  return payload.purchase_unit_cost / payload.purchase_unit_size;
}

function sameNullableNumber(a, b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return Number(a) === Number(b);
}

function isDuplicateIngredientNameError(error) {
  return (
    error?.code === '23505' &&
    (
      error?.message?.includes('ingredients_name_key') ||
      error?.details?.includes('ingredients_name_key') ||
      error?.details?.includes('name')
    )
  );
}

function sendIngredientError(error, res) {
  console.error(error);

  if (isDuplicateIngredientNameError(error)) {
    return res.status(409).json({
      error: 'An ingredient with this name already exists. Use a different name, or edit/reactivate the existing ingredient.'
    });
  }

  return res.status(400).json({ error: error?.message || 'Ingredient request failed' });
}

async function findLinkedProduct(ingredientId) {
  const recipeItems = await supabase
    .from('recipe_items')
    .select('recipe_id')
    .eq('ingredient_id', ingredientId);

  if (recipeItems.error) return recipeItems;
  if (!recipeItems.data?.length) return { data: null };

  const recipeIds = [...new Set(recipeItems.data.map((item) => item.recipe_id))];
  const recipes = await supabase
    .from('recipes')
    .select('product_id')
    .in('id', recipeIds);

  if (recipes.error) return recipes;
  if (!recipes.data?.length) return { data: null };

  const productIds = [...new Set(recipes.data.map((recipe) => recipe.product_id))];
  return supabase
    .from('products')
    .select('id,name,product_type')
    .in('id', productIds)
    .order('name')
    .limit(1)
    .maybeSingle();
}

function isNewerRecipe(recipe, other) {
  if (!other) return true;
  if (recipe.version !== other.version) return recipe.version > other.version;
  return String(recipe.created_at) > String(other.created_at);
}

// The products whose recipes call for this ingredient. An ingredient can sit in
// an older recipe version that the product no longer serves, and that still
// blocks archiving and deleting, so those rows are listed too and marked as not
// current rather than hidden.
async function loadProductsUsingIngredient(ingredientId) {
  const recipeItems = await supabase
    .from('recipe_items')
    .select('recipe_id,quantity,unit,is_optional,is_customer_supplied')
    .eq('ingredient_id', ingredientId);

  if (recipeItems.error) return recipeItems;
  if (!recipeItems.data.length) return { data: [] };

  const usageByRecipeId = new Map(recipeItems.data.map((item) => [item.recipe_id, item]));
  const usedRecipes = await supabase
    .from('recipes')
    .select('id,product_id,version,status,yield_servings,created_at')
    .in('id', [...usageByRecipeId.keys()]);

  if (usedRecipes.error) return usedRecipes;
  if (!usedRecipes.data.length) return { data: [] };

  const productIds = [...new Set(usedRecipes.data.map((recipe) => recipe.product_id).filter(Boolean))];
  if (!productIds.length) return { data: [] };

  const [products, allRecipes] = await Promise.all([
    supabase
      .from('products')
      .select('id,name,name_ar,product_type,status,image_url,short_description')
      .in('id', productIds)
      .order('name'),
    supabase
      .from('recipes')
      .select('id,product_id,version,created_at')
      .in('product_id', productIds)
  ]);

  if (products.error) return products;
  if (allRecipes.error) return allRecipes;

  // The product's live recipe is its highest version, newest first on a tie —
  // the same ordering the catalog uses to pick a product's current recipe.
  const currentRecipeIdByProduct = new Map();
  const newestRecipeByProduct = new Map();
  for (const recipe of allRecipes.data) {
    if (isNewerRecipe(recipe, newestRecipeByProduct.get(recipe.product_id))) {
      newestRecipeByProduct.set(recipe.product_id, recipe);
      currentRecipeIdByProduct.set(recipe.product_id, recipe.id);
    }
  }

  // One row per product: the current recipe when it uses the ingredient,
  // otherwise the newest version that does.
  const recipeByProduct = new Map();
  for (const recipe of usedRecipes.data) {
    const chosen = recipeByProduct.get(recipe.product_id);
    const isCurrent = currentRecipeIdByProduct.get(recipe.product_id) === recipe.id;
    if (!chosen || isCurrent || (!chosen.isCurrent && isNewerRecipe(recipe, chosen.recipe))) {
      recipeByProduct.set(recipe.product_id, { recipe, isCurrent });
    }
  }

  const rows = products.data
    .filter((product) => recipeByProduct.has(product.id))
    .map((product) => {
      const { recipe, isCurrent } = recipeByProduct.get(product.id);
      const usage = usageByRecipeId.get(recipe.id) || {};

      return {
        ...product,
        quantity: usage.quantity ?? null,
        unit: usage.unit || null,
        is_optional: Boolean(usage.is_optional),
        is_customer_supplied: Boolean(usage.is_customer_supplied),
        recipe_id: recipe.id,
        recipe_version: recipe.version,
        recipe_status: recipe.status,
        yield_servings: recipe.yield_servings,
        is_current_recipe: isCurrent
      };
    });

  return { data: rows };
}

const iconKey = z.string()
  .trim()
  .regex(/^[a-z0-9]+([_-][a-z0-9]+)*$/, 'Icon key must use lowercase letters, numbers, underscores, or hyphens.')
  .nullable()
  .optional();

const ingredientCreateSchema = z.object({
  name: z.string().min(1),
  name_ar: z.string().nullable().optional(),
  category_id: z.string().uuid().nullable().optional(),
  icon_key: iconKey,
  base_unit: z.string().min(1),
  purchase_unit_name: z.string().nullable().optional(),
  purchase_unit_size: z.coerce.number().positive().nullable().optional(),
  purchase_unit_cost: z.coerce.number().nonnegative().nullable().optional(),
  cost_per_base_unit: z.coerce.number().nonnegative().nullable().optional(),
  is_perishable: z.boolean().optional(),
  shelf_life_days: z.coerce.number().int().nonnegative().nullable().optional(),
  allergen_flags: z.array(z.string()).optional(),
  is_customer_supplied: z.boolean().optional(),
  is_searchable: z.boolean().optional(),
  is_active: z.boolean().optional()
});

const ingredientUpdateSchema = ingredientCreateSchema.partial().extend({
  confirm_base_unit_change: z.boolean().optional()
});

ingredientRouter.get('/ingredients', requireArea('ingredients'), async (_req, res) => {
  const data = await sb(supabase.from('ingredients').select('*, ingredient_categories(name)').order('name'), res);
  if (data) res.json(data.map(({ ingredient_categories, ...ingredient }) => ({
    ...ingredient,
    category: ingredient_categories?.name || null
  })));
});

const ingredientCategorySchema = z.object({
  name: z.string().trim().min(1).max(80),
  is_active: z.boolean().optional()
});

function sendCategoryError(error, res) {
  console.error(error);
  if (error?.code === '23505') return res.status(409).json({ error: 'An ingredient category with this name already exists.' });
  return res.status(400).json({ error: error?.message || 'Ingredient category request failed' });
}

ingredientRouter.get('/ingredient-categories', requireArea('ingredients'), async (_req, res) => {
  const data = await sb(supabase.from('ingredient_categories').select('*').order('name'), res);
  if (data) res.json(data);
});

ingredientRouter.post('/ingredient-categories', requireArea('ingredients'), async (req, res) => {
  const parsed = ingredientCategorySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid ingredient category' });
  const { data, error } = await supabase.from('ingredient_categories').insert(parsed.data).select().single();
  if (error) return sendCategoryError(error, res);
  return res.json(data);
});

ingredientRouter.patch('/ingredient-categories/:id', requireArea('ingredients'), async (req, res) => {
  const parsed = ingredientCategorySchema.partial().safeParse(req.body);
  if (!parsed.success || !Object.keys(parsed.data).length) return res.status(400).json({ error: 'Invalid ingredient category update' });

  if (parsed.data.is_active === false) {
    const linked = await supabase.from('ingredients').select('id').eq('category_id', req.params.id).eq('is_active', true).limit(1);
    if (linked.error) return sendCategoryError(linked.error, res);
    if (linked.data?.length) return res.status(409).json({ error: 'This category cannot be archived while it is assigned to an active ingredient.' });
  }

  const { data, error } = await supabase.from('ingredient_categories').update(parsed.data).eq('id', req.params.id).select().single();
  if (error) return sendCategoryError(error, res);
  return res.json(data);
});

ingredientRouter.delete('/ingredient-categories/:id', requireArea('ingredients'), async (req, res) => {
  const category = await supabase
    .from('ingredient_categories')
    .select('id,name')
    .eq('id', req.params.id)
    .maybeSingle();

  if (category.error) return sendCategoryError(category.error, res);
  if (!category.data) return res.status(404).json({ error: 'Ingredient category not found.' });

  // Archiving a category only has to clear the active ingredients; deleting it
  // has to clear every one, because the foreign key does not care whether the
  // ingredient holding the category is archived.
  const linked = await supabase
    .from('ingredients')
    .select('name,is_active', { count: 'exact' })
    .eq('category_id', category.data.id)
    .order('name')
    .limit(1);

  if (linked.error) return sendCategoryError(linked.error, res);

  if (linked.data?.length) {
    const [blocker] = linked.data;
    // Name one ingredient rather than all of them, and say when it is archived —
    // otherwise the ingredient blocking the delete is nowhere to be seen in the
    // Active view the admin is most likely looking at.
    const blockerLabel = `"${blocker.name}"${blocker.is_active ? '' : ' (archived)'}`;
    const others = (linked.count ?? linked.data.length) - 1;
    const assigned = others > 0
      ? `${blockerLabel} and ${others} other ${others === 1 ? 'ingredient' : 'ingredients'}`
      : blockerLabel;

    return res.status(409).json({
      error: `"${category.data.name}" cannot be deleted because it is still assigned to ${assigned}. ` +
        `Move ${others > 0 ? 'those ingredients' : 'that ingredient'} to another category first.`
    });
  }

  const { data, error } = await supabase
    .from('ingredient_categories')
    .delete()
    .eq('id', category.data.id)
    .select('id,name')
    .single();

  if (error) return sendCategoryError(error, res);
  return res.json(data);
});

ingredientRouter.post('/ingredients', requireArea('ingredients'), async (req, res) => {
  const parsed = ingredientCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid ingredient' });

  const payload = parsed.data;

  if ((payload.cost_per_base_unit == null) && canCalculateCostPerBaseUnit(payload)) {
    payload.cost_per_base_unit = calculateCostPerBaseUnit(payload);
  }

  const { data, error } = await supabase
    .from('ingredients')
    .insert(clean(payload))
    .select()
    .single();

  if (error) return sendIngredientError(error, res);
  return res.json(data);
});

ingredientRouter.patch('/ingredients/:id', requireArea('ingredients'), async (req, res) => {
  const parsed = ingredientUpdateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid ingredient update' });

  const { confirm_base_unit_change, ...payload } = parsed.data;

  const { data: existing, error: readError } = await supabase
    .from('ingredients')
    .select('*')
    .eq('id', req.params.id)
    .single();

  if (readError) return sendIngredientError(readError, res);

  if (existing.is_active && payload.is_active === false) {
    const linkedProduct = await findLinkedProduct(existing.id);
    if (linkedProduct.error) return sendIngredientError(linkedProduct.error, res);
    if (linkedProduct.data) {
      const productLabel = linkedProduct.data.product_type === 'cocktail' ? 'cocktail' : 'product';
      return res.status(409).json({
        error: `This ingredient cannot be archived because it is linked to the ${productLabel} "${linkedProduct.data.name}". Remove it from the ${productLabel} recipe first.`
      });
    }
  }

  if (
    hasOwn(payload, 'base_unit') &&
    payload.base_unit &&
    existing.base_unit !== payload.base_unit &&
    !confirm_base_unit_change
  ) {
    return res.status(409).json({
      error: 'Changing the base unit can affect recipes and inventory quantities. Confirm the base unit change before saving.'
    });
  }

  const purchaseUnitCostChanged =
    hasOwn(payload, 'purchase_unit_cost') && !sameNullableNumber(payload.purchase_unit_cost, existing.purchase_unit_cost);
  const purchaseUnitSizeChanged =
    hasOwn(payload, 'purchase_unit_size') && !sameNullableNumber(payload.purchase_unit_size, existing.purchase_unit_size);
  const purchaseInputsChanged = purchaseUnitCostChanged || purchaseUnitSizeChanged;
  const merged = { ...existing, ...payload };

  if (!hasOwn(payload, 'cost_per_base_unit') && purchaseInputsChanged) {
    payload.cost_per_base_unit = canCalculateCostPerBaseUnit(merged)
      ? calculateCostPerBaseUnit(merged)
      : null;
  } else if (hasOwn(payload, 'cost_per_base_unit') && payload.cost_per_base_unit == null && canCalculateCostPerBaseUnit(merged)) {
    payload.cost_per_base_unit = calculateCostPerBaseUnit(merged);
  }

  const { data, error } = await supabase
    .from('ingredients')
    .update(clean(payload))
    .eq('id', req.params.id)
    .select()
    .single();

  if (error) return sendIngredientError(error, res);
  return res.json(data);
});

ingredientRouter.get('/ingredients/:id/products', requireArea('ingredients'), async (req, res) => {
  const ingredient = await supabase
    .from('ingredients')
    .select('id,name,name_ar,base_unit,is_active')
    .eq('id', req.params.id)
    .maybeSingle();

  if (ingredient.error) return sendIngredientError(ingredient.error, res);
  if (!ingredient.data) return res.status(404).json({ error: 'Ingredient not found.' });

  const products = await loadProductsUsingIngredient(ingredient.data.id);
  if (products.error) return sendIngredientError(products.error, res);

  return res.json({ ingredient: ingredient.data, products: products.data });
});

// Permanent delete, archived ingredients only. Archiving stays the normal way to
// retire an ingredient; this exists for rows that were never really used (typos,
// duplicates) and should not sit in the Archived view forever.
//
// The delete cascades: inventory balances, stock movements, transfer and
// purchase order lines, order inventory components and cart removals all go with
// the ingredient. Recipes are the exception — a product or cocktail that calls
// for the ingredient blocks the delete instead of losing its recipe line.
ingredientRouter.delete('/ingredients/:id', requireArea('ingredients'), async (req, res) => {
  const { data: existing, error: readError } = await supabase
    .from('ingredients')
    .select('id,name,is_active')
    .eq('id', req.params.id)
    .maybeSingle();

  if (readError) return sendIngredientError(readError, res);
  if (!existing) return res.status(404).json({ error: 'Ingredient not found.' });

  if (existing.is_active) {
    return res.status(409).json({
      error: 'Only archived ingredients can be deleted permanently. Archive this ingredient first.'
    });
  }

  // One transaction in Postgres: the recipe check and every dependent delete
  // commit together, so a failure part-way cannot strip an ingredient of its
  // inventory and then leave it on the books. Doing the same thing here would
  // take one round trip per table with no way to roll the earlier ones back.
  const { data, error } = await supabase.rpc('delete_ingredient_cascade', { p_ingredient_id: existing.id });

  if (error) return sendIngredientError(error, res);
  if (data?.status === 'not_found') return res.status(404).json({ error: 'Ingredient not found.' });

  if (data?.status === 'in_recipe') {
    const productLabel = data.product_type === 'cocktail' ? 'cocktail' : 'product';
    return res.status(409).json({
      error: `"${existing.name}" cannot be deleted because it is linked to the ${productLabel} "${data.product_name}". Remove it from the ${productLabel} recipe first.`
    });
  }

  return res.json({ id: data.id, name: data.name });
});
