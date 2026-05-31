import { Router } from 'express';
import { z } from 'zod';
import { orderStatuses, paymentStatuses } from '../config/appConfig.js';
import { requireArea } from '../middleware/auth.js';
import { clean } from '../lib/objectUtils.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';

export const orderRouter = Router();

orderRouter.get('/orders', requireArea('orders'), async (_req, res) => {
  const [orders, items, locations] = await Promise.all([
    supabase.from('orders').select('*, customers(full_name,phone), locations(name,type,compound_name)').order('created_at', { ascending: false }).limit(100),
    supabase.from('order_items').select('*').order('id'),
    supabase.from('locations').select('*').order('name')
  ]);
  for (const result of [orders, items, locations]) if (result.error) return res.status(400).json({ error: result.error.message });
  res.json({ orders: orders.data, items: items.data, locations: locations.data });
});

orderRouter.patch('/orders/:id', requireArea('orders'), async (req, res) => {
  const parsed = z.object({ status: z.enum(orderStatuses).optional(), payment_status: z.enum(paymentStatuses).optional(), internal_notes: z.string().optional() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid order update' });
  const data = await sb(supabase.from('orders').update(clean(parsed.data)).eq('id', req.params.id).select().single(), res);
  if (data) res.json(data);
});
