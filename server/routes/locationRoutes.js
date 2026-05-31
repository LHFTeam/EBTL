import { Router } from 'express';
import { z } from 'zod';
import { locationTypes } from '../config/appConfig.js';
import { requireArea } from '../middleware/auth.js';
import { clean } from '../lib/objectUtils.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';

export const locationRouter = Router();

locationRouter.get('/locations', requireArea('locations'), async (_req, res) => {
  const data = await sb(supabase.from('locations').select('*').order('type').order('name'), res);
  if (data) res.json(data);
});

locationRouter.post('/locations', requireArea('locations'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1),
    type: z.enum(locationTypes),
    compound_name: z.string().optional(),
    beach_name: z.string().optional(),
    address: z.string().optional(),
    latitude: z.coerce.number().optional(),
    longitude: z.coerce.number().optional(),
    is_active: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid location' });
  const data = await sb(supabase.from('locations').insert(clean(parsed.data)).select().single(), res);
  if (data) res.json(data);
});

locationRouter.patch('/locations/:id', requireArea('locations'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1).optional(),
    type: z.enum(locationTypes).optional(),
    compound_name: z.string().nullable().optional(),
    beach_name: z.string().nullable().optional(),
    address: z.string().nullable().optional(),
    latitude: z.coerce.number().nullable().optional(),
    longitude: z.coerce.number().nullable().optional(),
    is_active: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid location update' });
  const data = await sb(supabase.from('locations').update(clean(parsed.data)).eq('id', req.params.id).select().single(), res);
  if (data) res.json(data);
});
