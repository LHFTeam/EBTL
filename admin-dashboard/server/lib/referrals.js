// Referral program engine.
//
// A double-sided referral loop layered on top of the existing promo-code
// engine (see server/routes/customerRoutes.js). There is no customer login —
// a customer is an anonymous session token mapped to a row in `customers`.
//
//   * Every customer has a unique, shareable `referral_code`.
//   * A new customer who applies someone's code is *attributed* to that
//     referrer (a `pending` row in `referrals`) and earns a first-order
//     discount (the "referee reward", computed live at checkout).
//   * When that referee completes a qualifying paid first order, the referrer
//     earns store credit (the "referrer reward"), recorded in the append-only
//     `customer_credit_ledger` and auto-applied at the referrer's next checkout.
//
// The schema lives in db/migrations/20260726_referral_program_engine.sql.

import { supabase } from './supabase.js';
import { createCustomerNotification } from './notifications.js';

// Order statuses that count as a genuinely-placed order. Mirrors the
// "first order" logic in resolvePromotion (customerRoutes.js) — draft,
// pending_payment and cancelled are ignored so an abandoned checkout never
// disqualifies a real first purchase.
const PLACED_ORDER_STATUSES = [
  'confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed', 'refunded'
];

const REFERRAL_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I/O/0/1
const REFERRAL_CODE_PREFIX = 'EBTL-';
const REFERRAL_CODE_LENGTH = 5;

const SETTINGS_CACHE_TTL_MS = 30_000;
let settingsCache = { value: null, expiresAt: 0 };

function money(value) {
  return Number(Number(value || 0).toFixed(2));
}

function normalizeCode(value) {
  return String(value || '').trim().toUpperCase();
}

function normalizePhone(value) {
  return String(value || '').replace(/\D/g, '');
}

function randomCode() {
  let suffix = '';
  for (let i = 0; i < REFERRAL_CODE_LENGTH; i += 1) {
    suffix += REFERRAL_CODE_ALPHABET[Math.floor(Math.random() * REFERRAL_CODE_ALPHABET.length)];
  }
  return `${REFERRAL_CODE_PREFIX}${suffix}`;
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

function defaultSettings() {
  return {
    is_active: true,
    referrer_reward_amount: 100,
    referee_discount_type: 'fixed_amount',
    referee_discount_value: 75,
    referee_max_discount_amount: null,
    min_qualifying_order_value: 0,
    reward_cap_per_referrer: null,
    terms: null
  };
}

export function invalidateReferralSettingsCache() {
  settingsCache = { value: null, expiresAt: 0 };
}

// Reads the single-row referral_settings config, with a short in-memory cache.
// Falls back to sensible defaults if the row/table is missing so checkout never
// hard-fails on a partially-migrated environment.
export async function getReferralSettings({ fresh = false } = {}) {
  if (!fresh && settingsCache.value && settingsCache.expiresAt > Date.now()) {
    return settingsCache.value;
  }

  const result = await supabase
    .from('referral_settings')
    .select('*')
    .eq('id', true)
    .maybeSingle();

  const value = result.error || !result.data ? defaultSettings() : result.data;
  settingsCache = { value, expiresAt: Date.now() + SETTINGS_CACHE_TTL_MS };
  return value;
}

// ---------------------------------------------------------------------------
// Referral codes
// ---------------------------------------------------------------------------

// Returns the customer's referral code, lazily generating and persisting a
// unique one on first use. Retries on the (rare) unique-collision.
export async function ensureReferralCode(customer) {
  if (customer?.referral_code) return customer.referral_code;
  if (!customer?.id) return null;

  for (let attempt = 0; attempt < 6; attempt += 1) {
    const code = randomCode();
    const updated = await supabase
      .from('customers')
      .update({ referral_code: code })
      .eq('id', customer.id)
      .is('referral_code', null)
      .select('referral_code')
      .maybeSingle();

    if (!updated.error && updated.data?.referral_code) {
      customer.referral_code = updated.data.referral_code;
      return updated.data.referral_code;
    }

    // Another writer set it first, or the code collided. Re-read; keep whatever
    // code now exists, otherwise retry with a fresh code.
    const current = await supabase
      .from('customers')
      .select('referral_code')
      .eq('id', customer.id)
      .maybeSingle();

    if (!current.error && current.data?.referral_code) {
      customer.referral_code = current.data.referral_code;
      return current.data.referral_code;
    }
  }

  return null;
}

export function referralShareMessage(code) {
  return `I'm loving EBTL — you bring the bottle, they bring the magic. 🍹\n`
    + `Use my code ${code} for a discount on your first order!`;
}

function refereeRewardLabel(settings) {
  const value = money(settings.referee_discount_value);
  return settings.referee_discount_type === 'percentage'
    ? `${value}% off`
    : `EGP ${value} off`;
}

// Assembles the full referral hub payload for a customer: their code, share
// text, store-credit balance, referral stats, and the current program terms.
// Used by GET /customer/referrals and (trimmed) by the profile summary.
export async function buildReferralHub(customer) {
  const settings = await getReferralSettings();
  const code = await ensureReferralCode(customer);

  const [balanceResult, referralRows, earnedRows] = await Promise.all([
    getCreditBalance(customer.id),
    supabase
      .from('referrals')
      .select('status')
      .eq('referrer_customer_id', customer.id),
    supabase
      .from('customer_credit_ledger')
      .select('delta_amount')
      .eq('customer_id', customer.id)
      .eq('reason', 'referral_reward')
  ]);

  const rows = referralRows.error ? [] : (referralRows.data || []);
  const pending = rows.filter((row) => row.status === 'pending').length;
  const rewarded = rows.filter((row) => row.status === 'rewarded').length;
  const creditEarned = earnedRows.error
    ? 0
    : money((earnedRows.data || []).reduce((sum, row) => sum + Number(row.delta_amount || 0), 0));

  return {
    program_active: Boolean(settings.is_active),
    code,
    share_message: code ? referralShareMessage(code) : null,
    credit: {
      balance: balanceResult.error ? 0 : money(balanceResult.data),
      currency: 'EGP'
    },
    stats: {
      invited: rows.length,
      pending,
      rewarded,
      credit_earned: creditEarned
    },
    rewards: {
      referrer_reward_amount: money(settings.referrer_reward_amount),
      referee_reward_label: refereeRewardLabel(settings),
      min_qualifying_order_value: money(settings.min_qualifying_order_value),
      currency: 'EGP'
    },
    how_it_works: [
      'Share your code with friends.',
      `They get ${refereeRewardLabel(settings)} their first order.`,
      `You get EGP ${money(settings.referrer_reward_amount)} store credit once they complete it.`
    ],
    terms: settings.terms || null
  };
}

// ---------------------------------------------------------------------------
// Attribution
// ---------------------------------------------------------------------------

async function hasPlacedOrder(customerId) {
  const result = await supabase
    .from('orders')
    .select('id', { count: 'exact', head: true })
    .eq('customer_id', customerId)
    .in('status', PLACED_ORDER_STATUSES);

  if (result.error) return { error: result.error };
  return { data: Number(result.count || 0) > 0 };
}

// Attributes `referee` (a full customers row) to the owner of `code`.
// Returns { data } on success, or { badRequest } / { error } like resolvePromotion.
export async function attributeReferral({ referee, code }) {
  const normalized = normalizeCode(code);
  if (!normalized) return { badRequest: 'Enter a referral code.' };
  if (!referee?.id) return { badRequest: 'Referral could not be applied.' };

  const settings = await getReferralSettings();
  if (!settings.is_active) {
    return { badRequest: 'The referral program is not active right now.' };
  }

  if (referee.referred_by_customer_id || referee.referral_attributed_at) {
    return { badRequest: 'You have already applied a referral code.' };
  }

  if (referee.referral_code && normalizeCode(referee.referral_code) === normalized) {
    return { badRequest: "You can't use your own referral code." };
  }

  const priorOrder = await hasPlacedOrder(referee.id);
  if (priorOrder.error) return { error: priorOrder.error };
  if (priorOrder.data) {
    return { badRequest: 'Referral codes can only be applied before your first order.' };
  }

  const referrer = await supabase
    .from('customers')
    .select('id, phone, referral_code')
    .ilike('referral_code', normalized)
    .maybeSingle();

  if (referrer.error) return { error: referrer.error };
  if (!referrer.data) return { badRequest: 'That referral code was not found.' };
  if (referrer.data.id === referee.id) {
    return { badRequest: "You can't use your own referral code." };
  }

  const refereePhone = normalizePhone(referee.phone);
  if (refereePhone && refereePhone === normalizePhone(referrer.data.phone)) {
    return { badRequest: 'That referral code cannot be applied to this account.' };
  }

  const referralInsert = await supabase
    .from('referrals')
    .insert({
      referrer_customer_id: referrer.data.id,
      referee_customer_id: referee.id,
      referral_code: normalizeCode(referrer.data.referral_code),
      status: 'pending',
      referrer_reward_amount: money(settings.referrer_reward_amount)
    })
    .select()
    .single();

  if (referralInsert.error) {
    // Unique violation on referee_customer_id => already attributed by a race.
    if (referralInsert.error.code === '23505') {
      return { badRequest: 'You have already applied a referral code.' };
    }
    return { error: referralInsert.error };
  }

  const customerUpdate = await supabase
    .from('customers')
    .update({
      referred_by_customer_id: referrer.data.id,
      referral_attributed_at: new Date().toISOString()
    })
    .eq('id', referee.id);

  if (customerUpdate.error) return { error: customerUpdate.error };

  referee.referred_by_customer_id = referrer.data.id;

  return { data: { referral: referralInsert.data } };
}

// ---------------------------------------------------------------------------
// Referee discount (checkout quote)
// ---------------------------------------------------------------------------

function calculateRefereeDiscount(settings, subtotalIncVat) {
  const value = Number(settings.referee_discount_value || 0);
  const max = settings.referee_max_discount_amount == null
    ? null
    : Number(settings.referee_max_discount_amount);
  const cap = (amount) => (max == null ? amount : Math.min(amount, max));

  if (settings.referee_discount_type === 'percentage') {
    return money(Math.min(subtotalIncVat, cap(subtotalIncVat * (value / 100))));
  }
  return money(Math.min(subtotalIncVat, cap(value)));
}

// If `customer` has a pending referral (they were referred and haven't had a
// qualifying order yet), returns the first-order discount they should receive.
// Returns { data: { referral_id, discount_amount, label } } or { data: null }.
export async function resolveReferralDiscount({ customer, subtotalIncVat }) {
  if (!customer?.id) return { data: null };
  if (!customer.referred_by_customer_id) return { data: null };

  const settings = await getReferralSettings();
  if (!settings.is_active) return { data: null };

  const referral = await supabase
    .from('referrals')
    .select('id, status')
    .eq('referee_customer_id', customer.id)
    .eq('status', 'pending')
    .maybeSingle();

  if (referral.error) return { error: referral.error };
  if (!referral.data) return { data: null };

  const discountAmount = calculateRefereeDiscount(settings, money(subtotalIncVat));
  if (discountAmount <= 0) return { data: null };

  return {
    data: {
      referral_id: referral.data.id,
      discount_amount: discountAmount,
      label: 'Referral discount',
      description: 'A little welcome gift from the friend who referred you.'
    }
  };
}

// ---------------------------------------------------------------------------
// Store credit (wallet)
// ---------------------------------------------------------------------------

export async function getCreditBalance(customerId) {
  if (!customerId) return { data: 0 };

  const result = await supabase
    .from('customer_credit_ledger')
    .select('delta_amount')
    .eq('customer_id', customerId);

  if (result.error) return { error: result.error };

  const balance = money((result.data || []).reduce((sum, row) => sum + Number(row.delta_amount || 0), 0));
  return { data: Math.max(balance, 0) };
}

// Amount of store credit to apply to an order, capped at the amount still due.
export async function computeCreditToApply({ customerId, amountDue }) {
  const balance = await getCreditBalance(customerId);
  if (balance.error) return { error: balance.error };
  return { data: money(Math.max(Math.min(balance.data, money(amountDue)), 0)) };
}

// Records the credit spent on an order (a negative ledger entry). Idempotent —
// a unique index guards one order_redemption row per order, so re-runs across
// the COD / Geidea / Stripe payment-success paths are safe.
export async function redeemCreditForOrder({ order, creditApplied }) {
  const amount = money(creditApplied);
  if (!order?.id || !order?.customer_id || amount <= 0) return null;

  const insert = await supabase
    .from('customer_credit_ledger')
    .insert({
      customer_id: order.customer_id,
      delta_amount: -amount,
      reason: 'order_redemption',
      order_id: order.id
    })
    .select()
    .maybeSingle();

  // 23505 = the redemption was already recorded for this order.
  if (insert.error && insert.error.code !== '23505') throw insert.error;
  return insert.data || null;
}

// ---------------------------------------------------------------------------
// Referrer reward (order confirmation hook)
// ---------------------------------------------------------------------------

async function rewardedCountForReferrer(referrerId) {
  const result = await supabase
    .from('referrals')
    .select('id', { count: 'exact', head: true })
    .eq('referrer_customer_id', referrerId)
    .eq('status', 'rewarded');

  if (result.error) return { error: result.error };
  return { data: Number(result.count || 0) };
}

// Called from each payment-success path alongside recordPromotionRedemptionIfNeeded.
// If `order` is the referee's first qualifying paid order, flips their pending
// referral to `rewarded`, grants the referrer store credit, and notifies them.
// Idempotent (guards on referral status + a unique reward ledger row).
export async function grantReferralRewardIfNeeded({ order }) {
  if (!order?.id || !order?.customer_id) return null;

  const referral = await supabase
    .from('referrals')
    .select('*')
    .eq('referee_customer_id', order.customer_id)
    .eq('status', 'pending')
    .maybeSingle();

  if (referral.error || !referral.data) return null;

  const settings = await getReferralSettings();
  if (!settings.is_active) return null;

  // Qualifying order value = subtotal (inc VAT) before discounts/credit.
  const subtotalIncVat = money(Number(order.subtotal_ex_vat || 0) + Number(order.vat_amount || 0));
  if (subtotalIncVat < money(settings.min_qualifying_order_value || 0)) return null;

  // Per-referrer reward cap.
  if (settings.reward_cap_per_referrer != null) {
    const rewarded = await rewardedCountForReferrer(referral.data.referrer_customer_id);
    if (rewarded.error) return null;
    if (rewarded.data >= Number(settings.reward_cap_per_referrer)) {
      // Cap reached — close the referral out without a reward.
      await supabase
        .from('referrals')
        .update({ status: 'void', qualifying_order_id: order.id, qualified_at: new Date().toISOString() })
        .eq('id', referral.data.id)
        .eq('status', 'pending');
      return null;
    }
  }

  const rewardAmount = money(referral.data.referrer_reward_amount || settings.referrer_reward_amount);

  // Grant the credit first — the unique index on (referral_id) makes this the
  // idempotency gate and guarantees at most one reward per referral. Doing this
  // before the status flip means a transient failure here leaves the referral
  // `pending`, so the next payment-success hook retries instead of stranding it.
  if (rewardAmount > 0) {
    const ledger = await supabase
      .from('customer_credit_ledger')
      .insert({
        customer_id: referral.data.referrer_customer_id,
        delta_amount: rewardAmount,
        reason: 'referral_reward',
        referral_id: referral.data.id,
        order_id: order.id
      })
      .select()
      .maybeSingle();

    // 23505 => reward ledger row already exists for this referral; the reward
    // was already granted, so fall through to make sure the status is settled.
    if (ledger.error && ledger.error.code !== '23505') throw ledger.error;

    if (!ledger.error) {
      await createCustomerNotification({
        customerId: referral.data.referrer_customer_id,
        type: 'referral_reward',
        title: 'You earned store credit! 🎉',
        body: `A friend you referred just placed their first order. EGP ${rewardAmount} credit is now in your account.`,
        data: {
          kind: 'referral_reward',
          amount: String(rewardAmount),
          referral_id: referral.data.id
        },
        dedupeKey: `referral_reward:${referral.data.id}`
      });
    }
  }

  // Settle the referral status (idempotent — only flips a still-pending row).
  await supabase
    .from('referrals')
    .update({
      status: 'rewarded',
      qualifying_order_id: order.id,
      qualified_at: new Date().toISOString(),
      rewarded_at: new Date().toISOString()
    })
    .eq('id', referral.data.id)
    .eq('status', 'pending');

  return { referralId: referral.data.id, rewardAmount };
}
