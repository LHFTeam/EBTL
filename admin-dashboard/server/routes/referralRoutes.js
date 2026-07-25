import { Router } from 'express';
import { z } from 'zod';
import { supabase } from '../lib/supabase.js';
import { sb } from '../lib/supabaseResponse.js';
import { requireArea } from '../middleware/auth.js';
import { invalidateReferralSettingsCache } from '../lib/referrals.js';

export const referralRouter = Router();

// Access area for the referral admin API. Granted to admin / manager /
// supervisor in server/config/appConfig.js (roleAccess) and mirrored by the
// 'referrals' nav tab in the dashboard.
const REFERRAL_AREA = 'referrals';

const SETTINGS_COLUMNS = [
  'is_active',
  'referrer_reward_amount',
  'referee_discount_type',
  'referee_discount_value',
  'referee_max_discount_amount',
  'min_qualifying_order_value',
  'reward_cap_per_referrer',
  'terms',
  'updated_at'
].join(',');

const refereeDiscountTypes = ['percentage', 'fixed_amount'];

function zodErrorMessage(error, fallback) {
  const first = error?.issues?.[0];
  if (!first) return fallback;
  const path = first.path?.length ? `${first.path.join('.')}: ` : '';
  return `${path}${first.message}`;
}

const optionalMoney = z.preprocess(
  (value) => (value === '' || value === null ? null : value),
  z.coerce.number().min(0).nullable().optional()
);

const optionalPositiveInt = z.preprocess(
  (value) => (value === '' || value === null ? null : value),
  z.coerce.number().int().min(0).nullable().optional()
);

// Every field optional — the settings row is a singleton edited in place.
const settingsUpdateSchema = z.object({
  is_active: z.boolean().optional(),
  referrer_reward_amount: z.coerce.number().min(0).optional(),
  referee_discount_type: z.enum(refereeDiscountTypes).optional(),
  referee_discount_value: z.coerce.number().min(0).optional(),
  referee_max_discount_amount: optionalMoney,
  min_qualifying_order_value: z.coerce.number().min(0).optional(),
  reward_cap_per_referrer: optionalPositiveInt,
  terms: z.preprocess(
    (value) => (value === '' ? null : value),
    z.string().trim().max(2000).nullable().optional()
  )
}).refine(
  (data) => data.referee_discount_type !== 'percentage'
    || data.referee_discount_value === undefined
    || data.referee_discount_value <= 100,
  { path: ['referee_discount_value'], message: 'Percentage discount cannot exceed 100.' }
);

async function loadSettings(res) {
  const existing = await supabase
    .from('referral_settings')
    .select(SETTINGS_COLUMNS)
    .eq('id', true)
    .maybeSingle();

  if (existing.error) {
    res.status(400).json({ error: existing.error.message });
    return null;
  }

  if (existing.data) return existing.data;

  // Seed the singleton row on first access (no-op elsewhere).
  return sb(
    supabase
      .from('referral_settings')
      .upsert({ id: true }, { onConflict: 'id' })
      .select(SETTINGS_COLUMNS)
      .single(),
    res
  );
}

referralRouter.get('/referral-settings', requireArea(REFERRAL_AREA), async (_req, res) => {
  const settings = await loadSettings(res);
  if (!settings) return;
  res.json({ settings });
});

referralRouter.patch('/referral-settings', requireArea(REFERRAL_AREA), async (req, res) => {
  const parsed = settingsUpdateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: zodErrorMessage(parsed.error, 'Invalid referral settings.') });
  }

  const payload = { id: true, ...parsed.data, updated_at: new Date().toISOString() };
  for (const key of Object.keys(payload)) {
    if (payload[key] === undefined) delete payload[key];
  }

  const updated = await sb(
    supabase
      .from('referral_settings')
      .upsert(payload, { onConflict: 'id' })
      .select(SETTINGS_COLUMNS)
      .single(),
    res
  );

  if (!updated) return;

  invalidateReferralSettingsCache();
  res.json({ settings: updated });
});

// Paginated referrals list + program-wide summary stats.
referralRouter.get('/referrals', requireArea(REFERRAL_AREA), async (req, res) => {
  const parsed = z.object({
    limit: z.coerce.number().int().positive().max(200).optional(),
    offset: z.coerce.number().int().min(0).optional(),
    status: z.enum(['pending', 'qualified', 'rewarded', 'void']).optional()
  }).safeParse(req.query);

  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid referrals query.' });
  }

  const limit = parsed.data.limit || 50;
  const offset = parsed.data.offset || 0;

  let query = supabase
    .from('referrals')
    .select(
      'id,status,referral_code,referee_discount_amount,referrer_reward_amount,'
      + 'qualifying_order_id,created_at,qualified_at,rewarded_at,'
      + 'referrer:referrer_customer_id(id,full_name,phone),'
      + 'referee:referee_customer_id(id,full_name,phone)',
      { count: 'exact' }
    )
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  if (parsed.data.status) query = query.eq('status', parsed.data.status);

  const result = await query;
  if (result.error) return res.status(400).json({ error: result.error.message });

  // Program-wide stats (modest volume, single fetch + JS reduce per the app's
  // no-RPC convention).
  const statusRows = await supabase.from('referrals').select('status,referrer_reward_amount');
  if (statusRows.error) return res.status(400).json({ error: statusRows.error.message });

  const stats = { total: 0, pending: 0, rewarded: 0, void: 0, credit_issued: 0 };
  for (const row of statusRows.data || []) {
    stats.total += 1;
    if (row.status === 'pending') stats.pending += 1;
    if (row.status === 'void') stats.void += 1;
    if (row.status === 'rewarded') {
      stats.rewarded += 1;
      stats.credit_issued += Number(row.referrer_reward_amount || 0);
    }
  }
  stats.credit_issued = Math.round(stats.credit_issued * 100) / 100;

  res.json({
    referrals: result.data || [],
    total: result.count || 0,
    limit,
    offset,
    stats
  });
});
