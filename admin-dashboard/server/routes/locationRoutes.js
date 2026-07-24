import { Router } from 'express';
import { z } from 'zod';
import { locationTypes } from '../config/appConfig.js';
import { clean } from '../lib/objectUtils.js';
import { requireArea } from '../middleware/auth.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';

export const locationRouter = Router();

const PROTECTED_CENTRAL_WAREHOUSE_NAME = 'central warehouse';
const LOCATION_BANNER_BUCKET = 'locations';
const MAX_LOCATION_BANNER_BYTES = 3 * 1024 * 1024;

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

function zodErrorMessage(error, fallback) {
  const first = error?.issues?.[0];
  if (!first) return fallback;
  const path = first.path?.length ? `${first.path.join('.')}: ` : '';
  return `${path}${first.message}`;
}

function isWebpBuffer(buffer) {
  return buffer.length >= 12
    && buffer.toString('ascii', 0, 4) === 'RIFF'
    && buffer.toString('ascii', 8, 12) === 'WEBP';
}

function normalizeBase64Image(value) {
  return String(value || '')
    .replace(/^data:image\/webp;base64,/i, '')
    .replace(/\s/g, '');
}

function locationBannerPath(locationId) {
  return `location-banners/${locationId}/${Date.now()}.webp`;
}

function storagePathFromPublicUrl(publicUrl) {
  if (!publicUrl) return null;
  const marker = `/storage/v1/object/public/${LOCATION_BANNER_BUCKET}/`;
  const markerIndex = String(publicUrl).indexOf(marker);
  if (markerIndex === -1) return null;
  const pathWithQuery = String(publicUrl).slice(markerIndex + marker.length);
  return decodeURIComponent(pathWithQuery.split('?')[0]);
}

async function removeStoredLocationBanner(publicUrl) {
  const oldPath = storagePathFromPublicUrl(publicUrl);
  if (!oldPath) return;
  await supabase.storage.from(LOCATION_BANNER_BUCKET).remove([oldPath]);
}

function normalizeTime(value) {
  if (!value) return null;
  const parts = String(value).split(':');
  if (parts.length < 2) return value;
  return `${parts[0].padStart(2, '0')}:${parts[1].padStart(2, '0')}:00`;
}

const timeString = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/, 'Use HH:MM or HH:MM:SS time.');

const locationOpeningHourSchema = z.object({
  day_of_week: z.coerce.number().int().min(0).max(6),
  is_closed: z.boolean().optional().default(false),
  opens_at: timeString.nullable().optional(),
  closes_at: timeString.nullable().optional()
}).superRefine((row, ctx) => {
  if (row.is_closed) return;

  if (!row.opens_at) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['opens_at'],
      message: 'Open time is required unless the day is closed.'
    });
  }

  if (!row.closes_at) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['closes_at'],
      message: 'Close time is required unless the day is closed.'
    });
  }
});

const openingHoursPayloadSchema = z.object({
  hours: z.array(locationOpeningHourSchema).min(1).max(7)
}).superRefine((data, ctx) => {
  const seen = new Set();

  for (const row of data.hours) {
    if (seen.has(row.day_of_week)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['hours'],
        message: 'Each day_of_week can only be sent once.'
      });
      return;
    }

    seen.add(row.day_of_week);
  }
});

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

async function activePrepAssignmentCount(locationId, res) {
  const result = await supabase
    .from('employees')
    .select('id', { count: 'exact', head: true })
    .eq('role', 'prep')
    .eq('is_active', true)
    .eq('default_location_id', locationId);

  if (result.error) {
    res.status(400).json({ error: result.error.message });
    return null;
  }

  return result.count || 0;
}

async function blockInvalidPrepLocationChange({ locationId, nextLocation, res }) {
  if (nextLocation.is_active && nextLocation.type === 'beach_cart') return false;

  const assignedPrepCount = await activePrepAssignmentCount(locationId, res);
  if (assignedPrepCount === null) return true;
  if (!assignedPrepCount) return false;

  res.status(409).json({
    error: `Reassign or deactivate ${assignedPrepCount} active prep employee${assignedPrepCount === 1 ? '' : 's'} before changing this kitchen location.`
  });
  return true;
}

const createLocationSchema = z.object({
  name: z.preprocess(trimText, z.string().min(1, 'Location name is required.')),
  type: z.enum(locationTypes),
  compound_name: z.preprocess(optionalText, z.string().optional()),
  beach_name: z.preprocess(optionalText, z.string().optional()),
  address: z.preprocess(optionalText, z.string().optional()),
  banner_image_url: z.preprocess(optionalText, z.string().optional()),
  delivery_fee: z.preprocess(optionalNumber, z.coerce.number().min(0).optional()),
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
  banner_image_url: z.preprocess(nullableText, z.string().nullable().optional()),
  delivery_fee: z.preprocess(optionalNumber, z.coerce.number().min(0).optional()),
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

locationRouter.get('/locations/:id/opening-hours', requireArea('locations'), async (req, res) => {
  const current = await loadLocation(req.params.id, res);
  if (!current) return;

  const data = await sb(
    supabase
      .from('location_opening_hours')
      .select('*')
      .eq('location_id', req.params.id)
      .order('day_of_week', { ascending: true }),
    res
  );

  if (data) res.json({ location_id: req.params.id, hours: data });
});

locationRouter.put('/locations/:id/opening-hours', requireArea('locations'), async (req, res) => {
  const parsed = openingHoursPayloadSchema.safeParse(req.body);

  if (!parsed.success) {
    return res.status(400).json({
      error: firstZodMessage(parsed.error, 'Invalid opening hours.')
    });
  }

  const current = await loadLocation(req.params.id, res);
  if (!current) return;

  const deleted = await supabase
    .from('location_opening_hours')
    .delete()
    .eq('location_id', req.params.id);

  if (deleted.error) return res.status(400).json({ error: deleted.error.message });

  const payload = parsed.data.hours.map((row) => ({
    location_id: req.params.id,
    day_of_week: row.day_of_week,
    is_closed: Boolean(row.is_closed),
    opens_at: row.is_closed ? null : normalizeTime(row.opens_at),
    closes_at: row.is_closed ? null : normalizeTime(row.closes_at)
  }));

  const saved = await sb(
    supabase
      .from('location_opening_hours')
      .insert(payload)
      .select()
      .order('day_of_week', { ascending: true }),
    res
  );

  if (saved) res.json({ location_id: req.params.id, hours: saved });
});

locationRouter.post('/locations/:id/banner', requireArea('locations'), async (req, res) => {
  const parsed = z.object({
    file_name: z.string().min(1),
    content_type: z.string().optional(),
    data_base64: z.string().min(1)
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid location banner upload') });

  const fileName = parsed.data.file_name.trim().toLowerCase();
  const contentType = String(parsed.data.content_type || '').toLowerCase();

  if (contentType !== 'image/webp' && !fileName.endsWith('.webp')) {
    return res.status(400).json({ error: 'Location banners must be uploaded as .webp files.' });
  }

  const location = await loadLocation(req.params.id, res);
  if (!location) return;

  const base64 = normalizeBase64Image(parsed.data.data_base64);
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
    return res.status(400).json({ error: 'Image data is not valid base64.' });
  }

  const imageBuffer = Buffer.from(base64, 'base64');
  if (!imageBuffer.length) return res.status(400).json({ error: 'Image file is empty.' });

  if (imageBuffer.length > MAX_LOCATION_BANNER_BYTES) {
    return res.status(400).json({ error: 'Image file is too large. Maximum size is 3 MB.' });
  }

  if (!isWebpBuffer(imageBuffer)) {
    return res.status(400).json({ error: 'The selected file is not a valid WebP image.' });
  }

  const storagePath = locationBannerPath(req.params.id);
  const uploaded = await supabase.storage
    .from(LOCATION_BANNER_BUCKET)
    .upload(storagePath, imageBuffer, {
      contentType: 'image/webp',
      cacheControl: '31536000',
      upsert: false
    });

  if (uploaded.error) return res.status(400).json({ error: uploaded.error.message });

  const publicUrl = supabase.storage.from(LOCATION_BANNER_BUCKET).getPublicUrl(storagePath).data.publicUrl;

  const updated = await supabase
    .from('locations')
    .update({ banner_image_url: publicUrl })
    .eq('id', req.params.id)
    .select()
    .single();

  if (updated.error) {
    await supabase.storage.from(LOCATION_BANNER_BUCKET).remove([storagePath]);
    return res.status(400).json({ error: updated.error.message });
  }

  await removeStoredLocationBanner(location.banner_image_url);

  res.json({ location: updated.data, banner_image_url: publicUrl, storage_path: storagePath });
});

locationRouter.delete('/locations/:id/banner', requireArea('locations'), async (req, res) => {
  const location = await loadLocation(req.params.id, res);
  if (!location) return;

  await removeStoredLocationBanner(location.banner_image_url);

  const updated = await supabase
    .from('locations')
    .update({ banner_image_url: null })
    .eq('id', req.params.id)
    .select()
    .single();

  if (updated.error) return res.status(400).json({ error: updated.error.message });
  res.json({ location: updated.data });
});

locationRouter.patch('/locations/:id/deactivate', requireArea('locations'), async (req, res) => {
  const current = await loadLocation(req.params.id, res);
  if (!current) return;

  if (isProtectedCentralWarehouse(current)) {
    return res.status(400).json({
      error: 'Central Warehouse is protected and cannot be deactivated.'
    });
  }

  if (await blockInvalidPrepLocationChange({
    locationId: req.params.id,
    nextLocation: { ...current, is_active: false },
    res
  })) return;

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

  if (await blockInvalidPrepLocationChange({
    locationId: req.params.id,
    nextLocation,
    res
  })) return;

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
