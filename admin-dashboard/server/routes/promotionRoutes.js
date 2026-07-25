import { Router } from 'express';
import { z } from 'zod';
import { promotionDiscountTypes, promotionFulfillmentTypes } from '../config/appConfig.js';
import { clean } from '../lib/objectUtils.js';
import { supabase } from '../lib/supabase.js';
import { sb } from '../lib/supabaseResponse.js';
import { requireArea } from '../middleware/auth.js';

export const promotionRouter = Router();

// Columns the admin form controls. Kept explicit so a promotions row can carry
// extra internal columns without leaking into create/update payloads.
const PROMOTION_COLUMNS = [
  'id',
  'code',
  'name',
  'description',
  'discount_type',
  'discount_value',
  'max_discount_amount',
  'min_order_value',
  'usage_limit',
  'per_customer_limit',
  'first_order_only',
  'allowed_fulfillment_type',
  'starts_at',
  'ends_at',
  'is_active',
  'created_at',
  'updated_at'
].join(',');

function zodErrorMessage(error, fallback) {
  const first = error?.issues?.[0];
  if (!first) return fallback;
  const path = first.path?.length ? `${first.path.join('.')}: ` : '';
  return `${path}${first.message}`;
}

function friendlyPromotionError(message) {
  const text = String(message || '');
  if (text.includes('promotions_code_key') || text.includes('promotions_code') || text.toLowerCase().includes('duplicate key')) {
    return 'A promo code with this code already exists.';
  }
  return message || 'Promo code request failed.';
}

// A timestamptz column accepts an ISO string; the form sends 'YYYY-MM-DDTHH:mm'
// (datetime-local) or '' to clear. Normalize '' -> null so update routes can
// clear the window.
const optionalTimestamp = z.preprocess(
  (value) => (value === '' || value === null ? null : value),
  z.string().min(1).nullable().optional()
);

const optionalPositiveInt = z.preprocess(
  (value) => (value === '' || value === null ? null : value),
  z.coerce.number().int().min(0).nullable().optional()
);

const optionalMoney = z.preprocess(
  (value) => (value === '' || value === null ? null : value),
  z.coerce.number().min(0).nullable().optional()
);

const promotionCreateSchema = z.object({
  code: z.string().trim().min(2).max(40),
  name: z.string().trim().min(1).max(120),
  description: z.preprocess(
    (value) => (value === '' ? null : value),
    z.string().trim().max(500).nullable().optional()
  ),
  discount_type: z.enum(promotionDiscountTypes),
  discount_value: z.coerce.number().min(0).default(0),
  max_discount_amount: optionalMoney,
  min_order_value: z.coerce.number().min(0).optional(),
  usage_limit: optionalPositiveInt,
  per_customer_limit: optionalPositiveInt,
  first_order_only: z.boolean().optional(),
  allowed_fulfillment_type: z.preprocess(
    (value) => (value === '' || value === null ? null : value),
    z.enum(promotionFulfillmentTypes).nullable().optional()
  ),
  starts_at: optionalTimestamp,
  ends_at: optionalTimestamp,
  is_active: z.boolean().optional()
}).refine(
  (data) => data.discount_type === 'free_delivery' || data.discount_value > 0,
  { path: ['discount_value'], message: 'Discount value must be greater than 0.' }
).refine(
  (data) => data.discount_type !== 'percentage' || data.discount_value <= 100,
  { path: ['discount_value'], message: 'Percentage discount cannot exceed 100.' }
).refine(
  (data) => !data.starts_at || !data.ends_at || new Date(data.ends_at) > new Date(data.starts_at),
  { path: ['ends_at'], message: 'End date must be after the start date.' }
);

// Update: every field optional; validate the same cross-field rules only when
// both sides of a comparison are present.
const promotionUpdateSchema = z.object({
  code: z.string().trim().min(2).max(40).optional(),
  name: z.string().trim().min(1).max(120).optional(),
  description: z.preprocess(
    (value) => (value === '' ? null : value),
    z.string().trim().max(500).nullable().optional()
  ),
  discount_type: z.enum(promotionDiscountTypes).optional(),
  discount_value: z.coerce.number().min(0).optional(),
  max_discount_amount: optionalMoney,
  min_order_value: z.coerce.number().min(0).optional(),
  usage_limit: optionalPositiveInt,
  per_customer_limit: optionalPositiveInt,
  first_order_only: z.boolean().optional(),
  allowed_fulfillment_type: z.preprocess(
    (value) => (value === '' || value === null ? null : value),
    z.enum(promotionFulfillmentTypes).nullable().optional()
  ),
  starts_at: optionalTimestamp,
  ends_at: optionalTimestamp,
  is_active: z.boolean().optional()
}).refine(
  (data) => data.discount_type !== 'percentage' || data.discount_value === undefined || data.discount_value <= 100,
  { path: ['discount_value'], message: 'Percentage discount cannot exceed 100.' }
).refine(
  (data) => !data.starts_at || !data.ends_at || new Date(data.ends_at) > new Date(data.starts_at),
  { path: ['ends_at'], message: 'End date must be after the start date.' }
);

function buildPayload(data) {
  const payload = { ...data };

  if (typeof payload.code === 'string') payload.code = payload.code.trim().toUpperCase();
  if (typeof payload.name === 'string') payload.name = payload.name.trim();

  // free_delivery ignores a discount value; store 0 for consistency.
  if (payload.discount_type === 'free_delivery') payload.discount_value = 0;

  return payload;
}

// Aggregate redemption count + total discount per promotion. Redemption volume
// for a promo engine is modest, so a single fetch + JS reduce is fine and keeps
// us to the app's no-RPC convention.
async function redemptionStatsByPromotion() {
  const rows = await supabase
    .from('promotion_redemptions')
    .select('promotion_id,discount_amount');

  if (rows.error) throw rows.error;

  const stats = new Map();
  for (const row of rows.data || []) {
    const current = stats.get(row.promotion_id) || { redemption_count: 0, total_discount: 0 };
    current.redemption_count += 1;
    current.total_discount += Number(row.discount_amount || 0);
    stats.set(row.promotion_id, current);
  }
  return stats;
}

promotionRouter.get('/promotions', requireArea('promotions'), async (_req, res) => {
  const promotions = await sb(
    supabase
      .from('promotions')
      .select(PROMOTION_COLUMNS)
      .order('created_at', { ascending: false }),
    res
  );

  if (!promotions) return;

  let stats;
  try {
    stats = await redemptionStatsByPromotion();
  } catch (error) {
    return res.status(400).json({ error: error.message });
  }

  const withStats = promotions.map((promotion) => {
    const stat = stats.get(promotion.id) || { redemption_count: 0, total_discount: 0 };
    return {
      ...promotion,
      redemption_count: stat.redemption_count,
      total_discount: Math.round(stat.total_discount * 100) / 100
    };
  });

  res.json({ promotions: withStats });
});

promotionRouter.get('/promotions/:id', requireArea('promotions'), async (req, res) => {
  const promotion = await supabase
    .from('promotions')
    .select(PROMOTION_COLUMNS)
    .eq('id', req.params.id)
    .maybeSingle();

  if (promotion.error) return res.status(400).json({ error: promotion.error.message });
  if (!promotion.data) return res.status(404).json({ error: 'Promo code not found.' });

  const redemptions = await supabase
    .from('promotion_redemptions')
    .select('id,customer_id,order_id,discount_amount,created_at')
    .eq('promotion_id', req.params.id)
    .order('created_at', { ascending: false })
    .limit(100);

  if (redemptions.error) return res.status(400).json({ error: redemptions.error.message });

  const rows = redemptions.data || [];
  const totalDiscount = rows.reduce((sum, row) => sum + Number(row.discount_amount || 0), 0);

  res.json({
    promotion: promotion.data,
    redemptions: rows,
    stats: {
      redemption_count: rows.length,
      total_discount: Math.round(totalDiscount * 100) / 100
    }
  });
});

promotionRouter.post('/promotions', requireArea('promotions'), async (req, res) => {
  const parsed = promotionCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid promo code.') });

  const payload = clean(buildPayload({
    code: parsed.data.code,
    name: parsed.data.name,
    description: parsed.data.description ?? null,
    discount_type: parsed.data.discount_type,
    discount_value: parsed.data.discount_value ?? 0,
    max_discount_amount: parsed.data.max_discount_amount ?? null,
    min_order_value: parsed.data.min_order_value ?? 0,
    usage_limit: parsed.data.usage_limit ?? null,
    per_customer_limit: parsed.data.per_customer_limit ?? null,
    first_order_only: parsed.data.first_order_only ?? false,
    allowed_fulfillment_type: parsed.data.allowed_fulfillment_type ?? null,
    starts_at: parsed.data.starts_at ?? null,
    ends_at: parsed.data.ends_at ?? null,
    is_active: parsed.data.is_active ?? true
  }));

  const created = await supabase.from('promotions').insert(payload).select(PROMOTION_COLUMNS).single();
  if (created.error) return res.status(400).json({ error: friendlyPromotionError(created.error.message) });

  res.json(created.data);
});

promotionRouter.patch('/promotions/:id', requireArea('promotions'), async (req, res) => {
  const parsed = promotionUpdateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid promo code update.') });

  // Nullable columns must survive clean() (which drops undefined only), so
  // build the payload from parsed data and update timestamp bookkeeping.
  const payload = buildPayload({ ...parsed.data, updated_at: new Date().toISOString() });

  // Remove keys that were not provided at all (undefined) so a partial update
  // never clobbers unspecified columns. Explicit nulls are kept to clear a value.
  for (const key of Object.keys(payload)) {
    if (payload[key] === undefined) delete payload[key];
  }

  if (Object.keys(payload).length <= 1) {
    return res.status(400).json({ error: 'No promo code fields were provided to update.' });
  }

  const updated = await supabase.from('promotions').update(payload).eq('id', req.params.id).select(PROMOTION_COLUMNS).single();
  if (updated.error) return res.status(400).json({ error: friendlyPromotionError(updated.error.message) });

  res.json(updated.data);
});

// Soft-delete only. Past redemptions keep referencing this promo code.
promotionRouter.delete('/promotions/:id', requireArea('promotions'), async (req, res) => {
  const updated = await sb(
    supabase
      .from('promotions')
      .update({ is_active: false, updated_at: new Date().toISOString() })
      .eq('id', req.params.id)
      .select(PROMOTION_COLUMNS)
      .single(),
    res
  );

  if (updated) res.json(updated);
});
