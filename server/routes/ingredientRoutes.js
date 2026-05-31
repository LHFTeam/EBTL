import { Router } from 'express';
import { z } from 'zod';
import { requireArea } from '../middleware/auth.js';
import { clean } from '../lib/objectUtils.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';

export const ingredientRouter = Router();

ingredientRouter.get('/ingredients', requireArea('ingredients'), async (_req, res) => {
  const data = await sb(supabase.from('ingredients').select('*').order('name'), res);
  if (data) res.json(data);
});

ingredientRouter.post('/ingredients', requireArea('ingredients'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1),
    category: z.string().optional(),
    base_unit: z.string().min(1),
    purchase_unit_name: z.string().optional(),
    purchase_unit_size: z.coerce.number().positive().optional(),
    purchase_unit_cost: z.coerce.number().nonnegative().optional(),
    cost_per_base_unit: z.coerce.number().nonnegative().optional(),
    is_perishable: z.boolean().optional(),
    shelf_life_days: z.coerce.number().int().nonnegative().optional(),
    allergen_flags: z.array(z.string()).optional(),
    is_customer_supplied: z.boolean().optional(),
    is_active: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid ingredient' });
  const payload = parsed.data;
  if (!payload.cost_per_base_unit && payload.purchase_unit_cost && payload.purchase_unit_size) payload.cost_per_base_unit = payload.purchase_unit_cost / payload.purchase_unit_size;
  const data = await sb(supabase.from('ingredients').insert(clean(payload)).select().single(), res);
  if (data) res.json(data);
});

ingredientRouter.patch('/ingredients/:id', requireArea('ingredients'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1).optional(),
    category: z.string().nullable().optional(),
    base_unit: z.string().min(1).optional(),
    purchase_unit_name: z.string().nullable().optional(),
    purchase_unit_size: z.coerce.number().positive().nullable().optional(),
    purchase_unit_cost: z.coerce.number().nonnegative().nullable().optional(),
    cost_per_base_unit: z.coerce.number().nonnegative().nullable().optional(),
    is_perishable: z.boolean().optional(),
    shelf_life_days: z.coerce.number().int().nonnegative().nullable().optional(),
    allergen_flags: z.array(z.string()).optional(),
    is_customer_supplied: z.boolean().optional(),
    is_active: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid ingredient update' });
  const data = await sb(supabase.from('ingredients').update(clean(parsed.data)).eq('id', req.params.id).select().single(), res);
  if (data) res.json(data);
});
