import 'dotenv/config';

export const PORT = Number(process.env.PORT || 10000);
export const isProd = process.env.NODE_ENV === 'production';

export const SUPABASE_URL = process.env.SUPABASE_URL;
export const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
export const SESSION_SECRET = process.env.SESSION_SECRET || 'dev-only-change-me';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

if (isProd && SESSION_SECRET === 'dev-only-change-me') {
  throw new Error('Set SESSION_SECRET in production');
}

export const roleAccess = {
  admin: ['*'],
  manager: ['dashboard', 'orders', 'inventory', 'transfers', 'ingredients', 'cocktails', 'liquors', 'shop', 'locations', 'employees'],
  supervisor: ['dashboard', 'orders', 'inventory', 'transfers', 'ingredients', 'cocktails', 'liquors', 'shop', 'locations'],
  warehouse: ['dashboard', 'inventory', 'transfers', 'ingredients', 'locations'],
  cart_operator: ['dashboard', 'orders', 'inventory', 'transfers'],
  prep: ['dashboard', 'orders']
};

export const employeeRoles = ['prep', 'cart_operator', 'warehouse', 'supervisor', 'manager', 'admin'];
export const orderStatuses = ['draft', 'pending_payment', 'confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed', 'cancelled', 'refunded'];
export const paymentStatuses = ['unpaid', 'pending', 'paid', 'failed', 'refunded', 'partially_refunded'];
export const transferStatuses = ['draft', 'picked', 'in_transit', 'received', 'cancelled'];
export const productStatuses = ['draft', 'active', 'archived'];
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
