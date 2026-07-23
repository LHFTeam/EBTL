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

// Which live gateway backs the customer checkout. Defaults to geidea so existing
// deployments are unaffected; set PAYMENT_PROVIDER=stripe to switch to Stripe.
export const ACTIVE_PAYMENT_PROVIDER = normalizeEnvValue(process.env.PAYMENT_PROVIDER) === 'stripe'
  ? 'stripe'
  : 'geidea';

// Marketing/analytics pixel IDs for the public landing page. Each is null when
// unset; the client only initializes the platforms that have an ID. Served via
// GET /api/public-config and consumed by public/landing-assets/tracking.js.
export const LANDING_TRACKING = {
  metaPixelId: process.env.META_PIXEL_ID || null,
  tiktokPixelId: process.env.TIKTOK_PIXEL_ID || null,
  snapchatPixelId: process.env.SNAPCHAT_PIXEL_ID || null,
  ga4MeasurementId: process.env.GA4_MEASUREMENT_ID || null
};

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

if (isProd && SESSION_SECRET === 'dev-only-change-me') {
  throw new Error('Set SESSION_SECRET in production');
}

export const roleAccess = {
  admin: ['*'],
  manager: ['dashboard', 'orders', 'inventory', 'transfers', 'ingredients', 'cocktails', 'additional-products', 'liquors', 'shop', 'locations', 'employees'],
  supervisor: ['dashboard', 'orders', 'inventory', 'transfers', 'ingredients', 'cocktails', 'additional-products', 'liquors', 'shop', 'locations'],
  warehouse: ['dashboard', 'inventory', 'transfers', 'ingredients', 'locations'],
  cart_operator: ['dashboard', 'orders', 'inventory', 'transfers'],
  prep: ['dashboard', 'orders']
};

export const employeeRoles = ['prep', 'cart_operator', 'warehouse', 'supervisor', 'manager', 'admin'];
export const orderStatuses = ['draft', 'pending_payment', 'confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed', 'cancelled', 'refunded'];
export const paymentStatuses = ['unpaid', 'pending', 'paid', 'failed', 'refunded', 'partially_refunded'];
export const transferStatuses = ['draft', 'picked', 'in_transit', 'received', 'cancelled'];
export const productStatuses = ['draft', 'active', 'archived'];
export const productTypes = ['cocktail', 'snack', 'essential', 'bundle', 'add_on'];
export const locationTypes = ['central_warehouse', 'beach_cart'];
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
