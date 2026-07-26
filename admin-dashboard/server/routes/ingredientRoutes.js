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

const iconKey = z.string()
  .trim()
  .regex(/^[a-z0-9]+([_-][a-z0-9]+)*$/, 'Icon key must use lowercase letters, numbers, underscores, or hyphens.')
  .nullable()
  .optional();

const ingredientCreateSchema = z.object({
  name: z.string().min(1),
  name_ar: z.string().nullable().optional(),
  category: z.string().nullable().optional(),
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
  const data = await sb(supabase.from('ingredients').select('*').order('name'), res);
  if (data) res.json(data);
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
