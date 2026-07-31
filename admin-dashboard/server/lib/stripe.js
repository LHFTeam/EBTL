import crypto from 'crypto';

const STRIPE_PROVIDER = 'stripe';
const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY || '';
const STRIPE_PUBLISHABLE_KEY = process.env.STRIPE_PUBLISHABLE_KEY || '';
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET || '';

const STRIPE_API_BASE = String(process.env.STRIPE_API_BASE || 'https://api.stripe.com').replace(/\/+$/, '');
// The ephemeral key must be created with the same Stripe API version the mobile
// SDK (flutter_stripe) speaks. Keep this in sync with the client SDK's version.
const STRIPE_API_VERSION = process.env.STRIPE_API_VERSION || '2024-06-20';

const STRIPE_MERCHANT_DISPLAY_NAME = process.env.STRIPE_MERCHANT_DISPLAY_NAME || 'EBTL';
const STRIPE_MERCHANT_COUNTRY = (process.env.STRIPE_MERCHANT_COUNTRY || 'US').toUpperCase();
const STRIPE_APPLE_PAY_MERCHANT_ID = process.env.STRIPE_APPLE_PAY_MERCHANT_ID || '';
const STRIPE_GOOGLE_PAY_ENABLED = String(process.env.STRIPE_GOOGLE_PAY_ENABLED || 'false').toLowerCase() === 'true';

// Zero-decimal currencies are charged in their major unit; everything else is
// charged in the minor unit (e.g. EGP -> piastres, USD -> cents).
const ZERO_DECIMAL_CURRENCIES = new Set([
  'bif', 'clp', 'djf', 'gnf', 'jpy', 'kmf', 'krw', 'mga', 'pyg',
  'rwf', 'ugx', 'vnd', 'vuv', 'xaf', 'xof', 'xpf'
]);

export function stripeIsConfigured() {
  return Boolean(STRIPE_SECRET_KEY && STRIPE_PUBLISHABLE_KEY && STRIPE_WEBHOOK_SECRET);
}

export function stripeIsTestMode() {
  return STRIPE_SECRET_KEY.startsWith('sk_test_') || STRIPE_PUBLISHABLE_KEY.startsWith('pk_test_');
}

export function stripeCheckoutConfig() {
  return {
    provider: STRIPE_PROVIDER,
    configured: stripeIsConfigured(),
    is_test: stripeIsTestMode(),
    publishable_key: STRIPE_PUBLISHABLE_KEY || null,
    merchant_display_name: STRIPE_MERCHANT_DISPLAY_NAME,
    merchant_country: STRIPE_MERCHANT_COUNTRY,
    apple_pay_merchant_id: STRIPE_APPLE_PAY_MERCHANT_ID || null,
    google_pay_enabled: STRIPE_GOOGLE_PAY_ENABLED
  };
}

export function stripeMinorUnits(value, currency) {
  const amount = Number(value || 0);
  if (!Number.isFinite(amount)) return 0;
  const code = String(currency || '').toLowerCase();
  if (ZERO_DECIMAL_CURRENCIES.has(code)) return Math.round(amount);
  return Math.round(amount * 100);
}

// Stripe's REST API is form-encoded and uses bracket notation for nested
// objects/arrays (e.g. metadata[order_id], payment_method_types[0]).
function appendFormValue(params, key, value) {
  if (value === null || value === undefined) return;

  if (Array.isArray(value)) {
    value.forEach((item, index) => appendFormValue(params, `${key}[${index}]`, item));
    return;
  }

  if (typeof value === 'object') {
    for (const [childKey, childValue] of Object.entries(value)) {
      appendFormValue(params, `${key}[${childKey}]`, childValue);
    }
    return;
  }

  if (typeof value === 'boolean') {
    params.append(key, value ? 'true' : 'false');
    return;
  }

  params.append(key, String(value));
}

function toFormBody(payload) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(payload || {})) {
    appendFormValue(params, key, value);
  }
  return params.toString();
}

async function stripeRequest(pathname, { method = 'POST', body = null, idempotencyKey = null, apiVersion = null } = {}) {
  if (!STRIPE_SECRET_KEY) {
    throw new Error('Stripe is not configured. Set STRIPE_SECRET_KEY.');
  }

  const headers = {
    Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
    'Content-Type': 'application/x-www-form-urlencoded'
  };

  if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;
  if (apiVersion) headers['Stripe-Version'] = apiVersion;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25000);

  let response;
  let responseText = '';

  try {
    response = await fetch(`${STRIPE_API_BASE}${pathname}`, {
      method,
      headers,
      body: body ? toFormBody(body) : undefined,
      signal: controller.signal
    });

    responseText = await response.text();
  } finally {
    clearTimeout(timeout);
  }

  let responseBody = null;

  try {
    responseBody = responseText ? JSON.parse(responseText) : null;
  } catch {
    responseBody = { raw: responseText };
  }

  if (!response.ok) {
    const message = responseBody?.error?.message
      || responseBody?.error
      || `Stripe request failed with HTTP ${response.status}.`;
    const error = new Error(typeof message === 'string' ? message : JSON.stringify(message));
    error.stripeStatus = response.status;
    error.stripeBody = responseBody;
    throw error;
  }

  return responseBody;
}

async function createStripeCustomer({ customer }) {
  const fullName = String(customer?.full_name || '').trim();

  const created = await stripeRequest('/v1/customers', {
    body: {
      name: fullName || undefined,
      email: customer?.email || undefined,
      phone: customer?.phone || undefined,
      metadata: {
        ebtl_customer_id: customer?.id || ''
      }
    }
  });

  return created?.id || null;
}

// Reuse the Stripe customer id previously stored on one of the shopper's saved
// payment methods so saved cards remain reusable across orders; otherwise make
// a fresh Stripe customer. Returns the customer id string.
export async function resolveStripeCustomerId({ customer, existingCustomerId = null }) {
  if (existingCustomerId) return existingCustomerId;
  return createStripeCustomer({ customer });
}

export async function createStripeEphemeralKey(customerId) {
  const key = await stripeRequest('/v1/ephemeral_keys', {
    body: { customer: customerId },
    apiVersion: STRIPE_API_VERSION
  });

  return {
    id: key?.id || null,
    secret: key?.secret || null,
    api_version: STRIPE_API_VERSION
  };
}

export async function createStripePaymentIntent({
  order,
  payment,
  customer,
  customerId,
  saveCard = false
}) {
  if (!stripeIsConfigured()) {
    throw new Error('Stripe is not configured. Set STRIPE_SECRET_KEY, STRIPE_PUBLISHABLE_KEY, and STRIPE_WEBHOOK_SECRET.');
  }

  const currency = String(payment.currency || 'EGP').toLowerCase();
  const amount = stripeMinorUnits(order.total_amount ?? payment.amount, currency);

  if (amount <= 0) {
    throw new Error('Stripe payment amount must be greater than zero.');
  }

  const body = {
    amount,
    currency,
    customer: customerId,
    // Let the Dashboard-configured automatic payment methods decide which
    // options (cards, Apple Pay, Google Pay, ...) are surfaced in the sheet.
    'automatic_payment_methods[enabled]': true,
    description: `EBTL order ${order.order_number || order.id}`,
    metadata: {
      ebtl_order_id: order.id,
      ebtl_order_number: order.order_number || '',
      ebtl_payment_id: payment.id,
      ebtl_customer_id: customer?.id || ''
    }
  };

  if (saveCard) {
    body.setup_future_usage = 'off_session';
  }

  const intent = await stripeRequest('/v1/payment_intents', {
    body,
    // The EBTL payment row id is a stable idempotency key for this checkout.
    idempotencyKey: `pi_${payment.id}`
  });

  return {
    payment_intent_id: intent?.id || null,
    client_secret: intent?.client_secret || null,
    status: intent?.status || null,
    amount,
    currency,
    raw_response: intent
  };
}

// Intent states that mean money is either already ours or still moving. Stripe
// refuses to cancel these, and so should we — an intent in one of these states
// is not an abandoned checkout.
const MONEY_IN_FLIGHT_INTENT_STATUSES = new Set(['succeeded', 'processing', 'requires_capture']);

// Closes the payment window on an abandoned checkout, so a customer who left
// the sheet open cannot pay for an order we have already given up on.
//
// Never throws. The return value distinguishes the three outcomes that matter:
// cancelled (or already cancelled), `moneyInFlight` — Stripe refused because
// the intent is succeeding or has succeeded, which means the order must NOT be
// expired — and a plain failure, which is safe to retry on the next sweep.
export async function cancelStripePaymentIntent(paymentIntentId, { reason = 'abandoned' } = {}) {
  if (!paymentIntentId) return { cancelled: false, skipped: 'no_payment_intent' };
  if (!stripeIsConfigured()) return { cancelled: false, skipped: 'stripe_not_configured' };

  try {
    const intent = await stripeRequest(`/v1/payment_intents/${encodeURIComponent(paymentIntentId)}/cancel`, {
      body: { cancellation_reason: reason }
    });

    return { cancelled: true, status: intent?.status || 'canceled' };
  } catch (error) {
    const status = error?.stripeBody?.error?.payment_intent?.status || null;

    // Cancelling an already-cancelled intent is an error to Stripe but a
    // success to us — the window is shut either way.
    if (status === 'canceled') return { cancelled: true, status };

    if (status && MONEY_IN_FLIGHT_INTENT_STATUSES.has(status)) {
      return { cancelled: false, status, moneyInFlight: true };
    }

    return { cancelled: false, status, error };
  }
}

export function extractStripeAmount(paymentIntent) {
  const obj = paymentIntent && typeof paymentIntent === 'object' ? paymentIntent : {};
  return {
    amount: Number(obj.amount_received ?? obj.amount ?? 0),
    currency: String(obj.currency || '').toLowerCase()
  };
}

// Pulls saved-card details out of a succeeded PaymentIntent so they can be
// stored the same shape the Geidea flow uses for customer_payment_methods.
export function extractStripeSavedCard(paymentIntent) {
  const obj = paymentIntent && typeof paymentIntent === 'object' ? paymentIntent : {};
  const charge = Array.isArray(obj.charges?.data) && obj.charges.data.length
    ? obj.charges.data[obj.charges.data.length - 1]
    : (obj.latest_charge && typeof obj.latest_charge === 'object' ? obj.latest_charge : {});

  const card = charge?.payment_method_details?.card || {};
  const billing = charge?.billing_details || {};

  const paymentMethodId = typeof obj.payment_method === 'string'
    ? obj.payment_method
    : (charge?.payment_method || obj.payment_method?.id || null);

  const customerId = typeof obj.customer === 'string' ? obj.customer : (obj.customer?.id || null);

  if (!paymentMethodId) return null;

  const last4 = card.last4 || null;

  return {
    payment_method_id: String(paymentMethodId),
    customer_id: customerId,
    card_brand: card.brand || null,
    cardholder_name: billing.name || null,
    masked_card_number: last4 ? `•••• ${last4}` : null,
    expiry_month: card.exp_month ? Number(card.exp_month) : null,
    expiry_year: card.exp_year ? Number(card.exp_year) : null,
    last4
  };
}

// Verifies a Stripe webhook signature (scheme: t=timestamp,v1=hmac) without the
// Stripe SDK, mirroring how geidea.js verifies its callback with crypto.
export function constructStripeEvent(rawBody, signatureHeader, { toleranceSeconds = 300 } = {}) {
  if (!STRIPE_WEBHOOK_SECRET) {
    return { ok: false, reason: 'Stripe webhook secret is not configured.', event: null };
  }

  if (!signatureHeader) {
    return { ok: false, reason: 'Missing Stripe-Signature header.', event: null };
  }

  const payload = Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : String(rawBody || '');

  const parts = String(signatureHeader).split(',').reduce((acc, part) => {
    const [key, value] = part.split('=');
    if (key === 't') acc.timestamp = value;
    if (key === 'v1') acc.signatures.push(value);
    return acc;
  }, { timestamp: null, signatures: [] });

  if (!parts.timestamp || !parts.signatures.length) {
    return { ok: false, reason: 'Malformed Stripe-Signature header.', event: null };
  }

  const expected = crypto
    .createHmac('sha256', STRIPE_WEBHOOK_SECRET)
    .update(`${parts.timestamp}.${payload}`, 'utf8')
    .digest('hex');

  const matched = parts.signatures.some((candidate) => {
    if (candidate.length !== expected.length) return false;
    return crypto.timingSafeEqual(Buffer.from(candidate), Buffer.from(expected));
  });

  if (!matched) {
    return { ok: false, reason: 'Stripe signature verification failed.', event: null };
  }

  const age = Math.floor(Date.now() / 1000) - Number(parts.timestamp);
  if (Number.isFinite(age) && Math.abs(age) > toleranceSeconds) {
    return { ok: false, reason: 'Stripe webhook timestamp is outside the tolerance window.', event: null };
  }

  let event = null;
  try {
    event = JSON.parse(payload);
  } catch {
    return { ok: false, reason: 'Stripe webhook payload is not valid JSON.', event: null };
  }

  return { ok: true, reason: null, event };
}

export { STRIPE_PROVIDER };
