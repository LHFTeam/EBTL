import 'dotenv/config';

export const PORT = Number(process.env.PORT || 10000);
export const isProd = process.env.NODE_ENV === 'production';

export const SUPABASE_URL = process.env.SUPABASE_URL;
export const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
export const SESSION_SECRET = process.env.SESSION_SECRET || 'dev-only-change-me';

function normalizeEnvValue(value) {
  return String(value || '')
    .trim()
    .replace(/^['"]+|['"]+$/g, '')
    .trim()
    .toLowerCase();
}

export const RAW_PAYMENT_MODE = process.env.PAYMENT_MODE || '';
export const PAYMENT_MODE = normalizeEnvValue(RAW_PAYMENT_MODE) === 'demo' ? 'demo' : 'live';
export const isDemoPaymentMode = PAYMENT_MODE === 'demo';

// Stripe is the primary checkout gateway. Geidea remains available as an
// explicit rollback option.
export const ACTIVE_PAYMENT_PROVIDER = normalizeEnvValue(process.env.PAYMENT_PROVIDER) === 'geidea'
  ? 'geidea'
  : 'stripe';

// Google Tag Manager is the single loader for marketing/analytics tags on the
// public landing page. The ID is public (it is present in every GTM snippet),
// so the production container is a safe default while still being overridable
// for preview/staging deployments. The employee SPA never consumes this config.
export const LANDING_TRACKING = {
  gtmContainerId: process.env.GTM_CONTAINER_ID || 'GTM-WN6DZGBS'
};

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

if (isProd && SESSION_SECRET === 'dev-only-change-me') {
  throw new Error('Set SESSION_SECRET in production');
}

export const roleAccess = {
  admin: ['*'],
  manager: ['dashboard', 'analytics', 'orders', 'inventory', 'transfers', 'ingredients', 'cocktails', 'additional-products', 'liquors', 'shop', 'promotions', 'referrals', 'locations', 'employees'],
  supervisor: ['dashboard', 'orders', 'inventory', 'transfers', 'ingredients', 'cocktails', 'additional-products', 'liquors', 'shop', 'promotions', 'referrals', 'locations'],
  warehouse: ['dashboard', 'inventory', 'transfers', 'ingredients', 'locations'],
  cart_operator: ['dashboard', 'orders', 'inventory', 'transfers'],
  prep: ['orders']
};

export const employeeRoles = ['prep', 'cart_operator', 'warehouse', 'supervisor', 'manager', 'admin'];
// `expired` is terminal and is only ever set by the pending-order sweep
// (lib/pendingOrderCleanup.js): a checkout that was never paid for. It is not a
// state staff can move an order into or out of.
export const orderStatuses = ['draft', 'pending_payment', 'expired', 'confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed', 'cancelled', 'refunded'];
export const paymentStatuses = ['unpaid', 'pending', 'paid', 'failed', 'refunded', 'partially_refunded'];
export const transferStatuses = ['draft', 'picked', 'in_transit', 'received', 'cancelled'];
export const productStatuses = ['draft', 'active', 'archived'];
export const productTypes = ['cocktail', 'snack', 'essential', 'bundle', 'add_on'];
export const locationTypes = ['central_warehouse', 'beach_cart'];
export const promotionDiscountTypes = ['percentage', 'fixed_amount', 'free_delivery'];
export const promotionFulfillmentTypes = ['pickup_at_cart', 'delivery_to_unit'];
export const roles = Object.keys(roleAccess);

export function can(role, area) {
  const allowed = roleAccess[role] || [];
  return allowed.includes('*') || allowed.includes(area);
}

export function envUsers() {
  try {
    return JSON.parse(process.env.ADMIN_USERS || '[]');
  } catch {
    return [];
  }
}
