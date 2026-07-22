import { Router } from 'express';
import { z } from 'zod';
import { requireArea } from '../middleware/auth.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';

export const inventoryRouter = Router();

inventoryRouter.get('/inventory', requireArea('inventory'), async (_req, res) => {
  const [balances, movements, ingredients, locations] = await Promise.all([
    supabase.from('inventory_balances').select('*, ingredients(name,base_unit), locations(name,type,compound_name)').order('updated_at', { ascending: false }),
    supabase.from('stock_movements').select('*, ingredients(name), locations(name)').order('created_at', { ascending: false }).limit(100),
    supabase.from('ingredients').select('*').order('name'),
    supabase.from('locations').select('*').order('name')
  ]);
  for (const result of [balances, movements, ingredients, locations]) if (result.error) return res.status(400).json({ error: result.error.message });
  res.json({ balances: balances.data, movements: movements.data, ingredients: ingredients.data, locations: locations.data });
});

inventoryRouter.post('/inventory/adjust', requireArea('inventory'), async (req, res) => {
  const parsed = z.object({ ingredient_id: z.string().uuid(), location_id: z.string().uuid(), quantity_delta: z.coerce.number(), reason: z.string().optional() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid adjustment' });
  const data = await sb(supabase.from('stock_movements').insert({ ...parsed.data, movement_type: 'adjustment' }).select().single(), res);
  if (data) res.json(data);
});
