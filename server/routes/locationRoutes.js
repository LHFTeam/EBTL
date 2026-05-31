import { Router } from 'express';
import { z } from 'zod';
import { locationTypes } from '../config/appConfig.js';
import { clean } from '../lib/objectUtils.js';
import { requireArea } from '../middleware/auth.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';

export const locationRouter = Router();

const PROTECTED_CENTRAL_WAREHOUSE_NAME = 'central warehouse';

function trimText(value) {
  return typeof value === 'string' ? value.trim() : value;
}

function optionalText(value) {
  const trimmed = trimText(value);
  return trimmed === '' ? undefined : trimmed;
}

function nullableText(value) {
  const trimmed = trimText(value);
  return trimmed === '' ? null : trimmed;
}

function optionalNumber(value) {
  return value === '' || value === null ? undefined : value;
}

function nullableNumber(value) {
  return value === '' ? null : value;
}

function hasText(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function isProtectedCentralWarehouse(location) {
  return (
    location?.type === 'central_warehouse' &&
    String(location?.name || '').trim().toLowerCase() === PROTECTED_CENTRAL_WAREHOUSE_NAME
  );
}

function firstZodMessage(error, fallback) {
  return error?.issues?.[0]?.message || fallback;
}

function validateBeachCartCompound(location) {
  if (location.type === 'beach_cart' && !hasText(location.compound_name)) {
    return 'Beach cart locations require a compound name.';
  }
  return null;
}

async function loadLocation(id, res) {
  const result = await supabase.from('locations').select('*').eq('id', id).maybeSingle();

  if (result.error) {
    res.status(400).json({ error: result.error.message });
    return null;
  }

  if (!result.data) {
    res.status(404).json({ error: 'Location not found.' });
    return null;
  }

  return result.data;
}

const createLocationSchema = z.object({
  name: z.preprocess(trimText, z.string().min(1, 'Location name is required.')),
  type: z.enum(locationTypes),
  compound_name: z.preprocess(optionalText, z.string().optional()),
  beach_name: z.preprocess(optionalText, z.string().optional()),
  address: z.preprocess(optionalText, z.string().optional()),
  latitude: z.preprocess(optionalNumber, z.coerce.number().optional()),
  longitude: z.preprocess(optionalNumber, z.coerce.number().optional()),
  is_active: z.boolean().optional()
}).superRefine((location, ctx) => {
  if (location.type === 'beach_cart' && !hasText(location.compound_name)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['compound_name'],
      message: 'Beach cart locations require a compound name.'
    });
  }
});

const updateLocationSchema = z.object({
  name: z.preprocess(trimText, z.string().min(1, 'Location name is required.').optional()),
  type: z.enum(locationTypes).optional(),
  compound_name: z.preprocess(nullableText, z.string().nullable().optional()),
  beach_name: z.preprocess(nullableText, z.string().nullable().optional()),
  address: z.preprocess(nullableText, z.string().nullable().optional()),
  latitude: z.preprocess(nullableNumber, z.coerce.number().nullable().optional()),
  longitude: z.preprocess(nullableNumber, z.coerce.number().nullable().optional()),
  is_active: z.boolean().optional()
});

locationRouter.get('/locations', requireArea('locations'), async (_req, res) => {
  const data = await sb(
    supabase.from('locations').select('*').order('type').order('name'),
    res
  );

  if (data) res.json(data);
});

locationRouter.post('/locations', requireArea('locations'), async (req, res) => {
  const parsed = createLocationSchema.safeParse(req.body);

  if (!parsed.success) {
    return res.status(400).json({
      error: firstZodMessage(parsed.error, 'Invalid location.')
    });
  }

  const data = await sb(
    supabase.from('locations').insert(clean(parsed.data)).select().single(),
    res
  );

  if (data) res.json(data);
});

locationRouter.patch('/locations/:id/deactivate', requireArea('locations'), async (req, res) => {
  const current = await loadLocation(req.params.id, res);
  if (!current) return;

  if (isProtectedCentralWarehouse(current)) {
    return res.status(400).json({
      error: 'Central Warehouse is protected and cannot be deactivated.'
    });
  }

  const data = await sb(
    supabase
      .from('locations')
      .update({ is_active: false })
      .eq('id', req.params.id)
      .select()
      .single(),
    res
  );

  if (data) res.json(data);
});

locationRouter.patch('/locations/:id', requireArea('locations'), async (req, res) => {
  const parsed = updateLocationSchema.safeParse(req.body);

  if (!parsed.success) {
    return res.status(400).json({
      error: firstZodMessage(parsed.error, 'Invalid location update.')
    });
  }

  const current = await loadLocation(req.params.id, res);
  if (!current) return;

  const payload = clean(parsed.data);

  if (!Object.keys(payload).length) {
    return res.json(current);
  }

  if (isProtectedCentralWarehouse(current)) {
    if (payload.is_active === false) {
      return res.status(400).json({
        error: 'Central Warehouse is protected and cannot be deactivated.'
      });
    }

    if (payload.type && payload.type !== current.type) {
      return res.status(400).json({
        error: 'Central Warehouse type is protected and cannot be changed.'
      });
    }

    if (payload.name && payload.name !== current.name) {
      return res.status(400).json({
        error: 'Central Warehouse name is protected and cannot be changed.'
      });
    }
  }

  const nextLocation = { ...current, ...payload };
  const beachCartError = validateBeachCartCompound(nextLocation);

  if (beachCartError) {
    return res.status(400).json({ error: beachCartError });
  }

  const data = await sb(
    supabase
      .from('locations')
      .update(payload)
      .eq('id', req.params.id)
      .select()
      .single(),
    res
  );

  if (data) res.json(data);
});
