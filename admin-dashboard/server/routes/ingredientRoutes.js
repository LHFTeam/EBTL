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

// Every table that keeps a non-nullable foreign key on ingredients(id). Postgres
// would refuse the delete anyway; checking first turns that into a message that
// says which record is holding the ingredient. `order_item_removed_ingredients`
// is deliberately absent: its key is ON DELETE SET NULL next to a name snapshot,
// so that history survives the delete on its own.
const ingredientReferences = [
  ['recipe_items', 'it is used in a product recipe'],
  ['order_item_inventory_components', 'it appears in past order history'],
  ['cart_item_removed_ingredients', 'a customer cart still references it'],
  ['stock_movements', 'it has stock movement history'],
  ['stock_transfer_items', 'it appears on a stock transfer'],
  ['purchase_order_items', 'it appears on a purchase order']
];

async function findIngredientReference(ingredientId) {
  for (const [table, reason] of ingredientReferences) {
    const { data, error } = await supabase
      .from(table)
      .select('ingredient_id')
      .eq('ingredient_id', ingredientId)
      .limit(1);

    if (error) return { error };
    if (data?.length) return { reason };
  }

  return {};
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

// Permanent delete, archived ingredients only. Archiving stays the normal way to
// retire an ingredient; this exists for rows that were never really used (typos,
// duplicates) and should not sit in the Archived view forever.
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

  const linkedProduct = await findLinkedProduct(existing.id);
  if (linkedProduct.error) return sendIngredientError(linkedProduct.error, res);
  if (linkedProduct.data) {
    const productLabel = linkedProduct.data.product_type === 'cocktail' ? 'cocktail' : 'product';
    return res.status(409).json({
      error: `"${existing.name}" cannot be deleted because it is linked to the ${productLabel} "${linkedProduct.data.name}". Remove it from the ${productLabel} recipe first.`
    });
  }

  const reference = await findIngredientReference(existing.id);
  if (reference.error) return sendIngredientError(reference.error, res);
  if (reference.reason) {
    return res.status(409).json({
      error: `"${existing.name}" cannot be deleted because ${reference.reason}. It stays archived so those records keep their ingredient.`
    });
  }

  // Inventory balances are derived state, not history: the stock movement trigger
  // maintains them. Anything with real movements was already refused above, so a
  // surviving row here is an empty leftover and is cleared with the ingredient.
  const balances = await supabase
    .from('inventory_balances')
    .select('quantity_on_hand,reserved_quantity')
    .eq('ingredient_id', existing.id);

  if (balances.error) return sendIngredientError(balances.error, res);

  const hasStock = (balances.data || []).some(
    (balance) => Number(balance.quantity_on_hand) !== 0 || Number(balance.reserved_quantity) !== 0
  );

  if (hasStock) {
    return res.status(409).json({
      error: `"${existing.name}" cannot be deleted because it still has stock on hand. Adjust its balances to zero first.`
    });
  }

  if (balances.data?.length) {
    const clearedBalances = await supabase.from('inventory_balances').delete().eq('ingredient_id', existing.id);
    if (clearedBalances.error) return sendIngredientError(clearedBalances.error, res);
  }

  const { data, error } = await supabase
    .from('ingredients')
    .delete()
    .eq('id', existing.id)
    .select('id,name')
    .single();

  if (error) return sendIngredientError(error, res);
  return res.json(data);
});
