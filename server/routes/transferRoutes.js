import { Router } from 'express';
import { z } from 'zod';
import { transferStatuses } from '../config/appConfig.js';
import { requireArea } from '../middleware/auth.js';
import { clean } from '../lib/objectUtils.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';

export const transferRouter = Router();

transferRouter.get('/transfers', requireArea('transfers'), async (_req, res) => {
  const [transfers, items, ingredients, locations] = await Promise.all([
    supabase.from('stock_transfers').select('*, from:locations!stock_transfers_from_location_id_fkey(name,type), to:locations!stock_transfers_to_location_id_fkey(name,type)').order('requested_at', { ascending: false }).limit(100),
    supabase.from('stock_transfer_items').select('*, ingredients(name,base_unit)').order('id'),
    supabase.from('ingredients').select('*').order('name'),
    supabase.from('locations').select('*').order('name')
  ]);
  for (const result of [transfers, items, ingredients, locations]) if (result.error) return res.status(400).json({ error: result.error.message });
  res.json({ transfers: transfers.data, items: items.data, ingredients: ingredients.data, locations: locations.data });
});

transferRouter.post('/transfers', requireArea('transfers'), async (req, res) => {
  const parsed = z.object({
    from_location_id: z.string().uuid(),
    to_location_id: z.string().uuid(),
    notes: z.string().optional(),
    items: z.array(z.object({ ingredient_id: z.string().uuid(), requested_qty: z.coerce.number().nonnegative().default(0), dispatched_qty: z.coerce.number().nonnegative().default(0), received_qty: z.coerce.number().nonnegative().default(0) })).optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid transfer' });
  const { items = [], ...transfer } = parsed.data;
  const created = await supabase.from('stock_transfers').insert(clean(transfer)).select().single();
  if (created.error) return res.status(400).json({ error: created.error.message });
  if (items.length) {
    const inserted = await supabase.from('stock_transfer_items').insert(items.map((item) => ({ ...clean(item), transfer_id: created.data.id }))).select();
    if (inserted.error) return res.status(400).json({ error: inserted.error.message });
  }
  res.json(created.data);
});

transferRouter.patch('/transfers/:id', requireArea('transfers'), async (req, res) => {
  const parsed = z.object({ status: z.enum(transferStatuses).optional(), dispatched_at: z.string().optional(), received_at: z.string().optional(), notes: z.string().optional() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid transfer update' });
  const data = await sb(supabase.from('stock_transfers').update(clean(parsed.data)).eq('id', req.params.id).select().single(), res);
  if (data) res.json(data);
});

transferRouter.post('/transfers/:id/items', requireArea('transfers'), async (req, res) => {
  const data = await sb(supabase.from('stock_transfer_items').insert({ ...clean(req.body), transfer_id: req.params.id }).select().single(), res);
  if (data) res.json(data);
});
