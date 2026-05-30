import 'dotenv/config';
import express from 'express';
import compression from 'compression';
import helmet from 'helmet';
import morgan from 'morgan';
import crypto from 'crypto';
import path from 'path';
import { fileURLToPath } from 'url';
import { createClient } from '@supabase/supabase-js';
import { z } from 'zod';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const app = express();
const PORT = Number(process.env.PORT || 10000);
const isProd = process.env.NODE_ENV === 'production';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SESSION_SECRET = process.env.SESSION_SECRET || 'dev-only-change-me';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
if (isProd && SESSION_SECRET === 'dev-only-change-me') throw new Error('Set SESSION_SECRET in production');

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});

const roleAccess = {
  admin: ['*'],
  manager: ['dashboard', 'orders', 'inventory', 'transfers', 'ingredients', 'cocktails', 'locations', 'employees'],
  supervisor: ['dashboard', 'orders', 'inventory', 'transfers', 'ingredients', 'cocktails', 'locations'],
  warehouse: ['dashboard', 'inventory', 'transfers', 'ingredients', 'locations'],
  cart_operator: ['dashboard', 'orders', 'inventory', 'transfers'],
  prep: ['dashboard', 'orders']
};

const employeeRoles = ['prep', 'cart_operator', 'warehouse', 'supervisor', 'manager', 'admin'];
const orderStatuses = ['draft', 'pending_payment', 'confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed', 'cancelled', 'refunded'];
const paymentStatuses = ['unpaid', 'pending', 'paid', 'failed', 'refunded', 'partially_refunded'];
const transferStatuses = ['draft', 'picked', 'in_transit', 'received', 'cancelled'];
const productStatuses = ['draft', 'active', 'archived'];
const locationTypes = ['central_warehouse', 'beach_cart'];
const roles = Object.keys(roleAccess);

function can(role, area) {
  const allowed = roleAccess[role] || [];
  return allowed.includes('*') || allowed.includes(area);
}

function envUsers() {
  try { return JSON.parse(process.env.ADMIN_USERS || '[]'); } catch { return []; }
}

function clean(obj = {}) {
  return Object.fromEntries(Object.entries(obj).filter(([, value]) => value !== undefined && value !== ''));
}

function sign(value) {
  return crypto.createHmac('sha256', SESSION_SECRET).update(value).digest('base64url');
}

function encodeSession(user) {
  const payload = Buffer.from(JSON.stringify({ user, exp: Date.now() + 12 * 60 * 60 * 1000 })).toString('base64url');
  return `${payload}.${sign(payload)}`;
}

function decodeSession(token) {
  try {
    if (!token || !token.includes('.')) return null;
    const [payload, signature] = token.split('.');
    const expected = sign(payload);
    if (signature.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (!data.exp || Date.now() > data.exp) return null;
    return data.user;
  } catch { return null; }
}

function getCookie(req, name) {
  const cookies = req.headers.cookie || '';
  return cookies.split(';').map((cookie) => cookie.trim()).find((cookie) => cookie.startsWith(`${name}=`))?.slice(name.length + 1);
}

function setSessionCookie(res, user) {
  const secure = isProd ? '; Secure' : '';
  res.setHeader('Set-Cookie', `ebtl_admin=${encodeSession(user)}; HttpOnly; Path=/; SameSite=Lax; Max-Age=43200${secure}`);
}

function clearSessionCookie(res) {
  res.setHeader('Set-Cookie', 'ebtl_admin=; HttpOnly; Path=/; SameSite=Lax; Max-Age=0');
}

function hashPassword(password, salt = crypto.randomBytes(16).toString('base64url')) {
  const hash = crypto.pbkdf2Sync(password, salt, 150000, 32, 'sha256').toString('base64url');
  return { salt, hash };
}

function verifyPassword(password, salt, expectedHash) {
  const { hash } = hashPassword(password, salt);
  if (!expectedHash || hash.length !== expectedHash.length) return false;
  return crypto.timingSafeEqual(Buffer.from(hash), Buffer.from(expectedHash));
}

function auth(req, _res, next) { req.user = decodeSession(getCookie(req, 'ebtl_admin')); next(); }
function requireAuth(req, res, next) { if (!req.user) return res.status(401).json({ error: 'Not logged in' }); next(); }
function requireArea(area) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'Not logged in' });
    if (!can(req.user.role, area)) return res.status(403).json({ error: 'Not allowed' });
    next();
  };
}

async function sb(promise, res) {
  const { data, error } = await promise;
  if (error) { console.error(error); res.status(400).json({ error: error.message }); return null; }
  return data;
}

app.set('trust proxy', 1);
app.use(helmet({ contentSecurityPolicy: false }));
app.use(compression());
app.use(morgan('tiny'));
app.use(express.json({ limit: '2mb' }));
app.use(auth);

app.get('/api/health', (_req, res) => res.json({ ok: true }));

app.post('/api/login', async (req, res) => {
  const parsed = z.object({ username: z.string().min(1), password: z.string().min(1) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid login payload' });
  const { username, password } = parsed.data;

  const foundEnv = envUsers().find((user) => user.username === username && user.password === password);
  if (foundEnv && roles.includes(foundEnv.role)) {
    const user = { username: foundEnv.username, name: foundEnv.name || foundEnv.username, role: foundEnv.role, source: 'env' };
    setSessionCookie(res, user);
    return res.json({ user, access: roleAccess[user.role] || [] });
  }

  const { data, error } = await supabase
    .from('employee_credentials')
    .select('username,password_hash,password_salt,is_active, employees(id,full_name,role,is_active,default_location_id)')
    .eq('username', username)
    .maybeSingle();

  if (error && !String(error.message || '').includes('employee_credentials')) {
    console.error(error);
  }

  if (!data || !data.is_active || !data.employees?.is_active || !verifyPassword(password, data.password_salt, data.password_hash)) {
    return res.status(401).json({ error: 'Invalid username or password' });
  }

  const user = {
    username: data.username,
    name: data.employees.full_name,
    role: data.employees.role,
    employee_id: data.employees.id,
    location_id: data.employees.default_location_id,
    source: 'employee'
  };
  setSessionCookie(res, user);
  res.json({ user, access: roleAccess[user.role] || [] });
});

app.post('/api/logout', requireAuth, (_req, res) => { clearSessionCookie(res); res.json({ ok: true }); });
app.get('/api/me', requireAuth, (req, res) => res.json({ user: req.user, access: roleAccess[req.user.role] || [] }));

app.get('/api/dashboard', requireArea('dashboard'), async (_req, res) => {
  const [orders, sales, lowStock, locations, transfers] = await Promise.all([
    supabase.from('orders').select('id,order_number,status,payment_status,total_amount,created_at,location_id').order('created_at', { ascending: false }).limit(200),
    supabase.from('v_daily_sales_by_location').select('*').order('sales_date', { ascending: false }).limit(30),
    supabase.from('v_inventory_low_stock').select('*').limit(100),
    supabase.from('locations').select('*').order('name'),
    supabase.from('stock_transfers').select('id,status,requested_at').in('status', ['draft', 'picked', 'in_transit']).limit(100)
  ]);
  for (const result of [orders, sales, lowStock, locations, transfers]) if (result.error) return res.status(400).json({ error: result.error.message });
  const completed = orders.data.filter((order) => order.status === 'completed');
  res.json({
    kpis: {
      recentOrders: orders.data.length,
      completedOrders: completed.length,
      recentRevenue: completed.reduce((sum, order) => sum + Number(order.total_amount || 0), 0),
      lowStockItems: lowStock.data.length,
      activeLocations: locations.data.filter((location) => location.is_active).length,
      openTransfers: transfers.data.length
    },
    recentOrders: orders.data.slice(0, 20),
    dailySales: sales.data,
    lowStock: lowStock.data,
    locations: locations.data
  });
});

// LOCATIONS
app.get('/api/locations', requireArea('locations'), async (_req, res) => {
  const data = await sb(supabase.from('locations').select('*').order('type').order('name'), res);
  if (data) res.json(data);
});

app.post('/api/locations', requireArea('locations'), async (req, res) => {
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

app.patch('/api/locations/:id', requireArea('locations'), async (req, res) => {
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

// EMPLOYEES + SIMPLE DASHBOARD CREDENTIALS
app.get('/api/employees', requireArea('employees'), async (_req, res) => {
  const [employees, locations, credentials] = await Promise.all([
    supabase.from('employees').select('*, locations(name,type,compound_name)').order('full_name'),
    supabase.from('locations').select('*').order('name'),
    supabase.from('employee_credentials').select('employee_id,username,is_active')
  ]);
  for (const result of [employees, locations]) if (result.error) return res.status(400).json({ error: result.error.message });
  if (credentials.error) console.warn(credentials.error.message);
  const credentialMap = new Map((credentials.data || []).map((c) => [c.employee_id, c]));
  res.json({ employees: employees.data.map((e) => ({ ...e, credential: credentialMap.get(e.id) || null })), locations: locations.data, roles: employeeRoles });
});

app.post('/api/employees', requireArea('employees'), async (req, res) => {
  const parsed = z.object({
    full_name: z.string().min(1),
    username: z.string().min(3).regex(/^[a-zA-Z0-9._-]+$/),
    password: z.string().min(6),
    phone: z.string().optional(),
    role: z.enum(employeeRoles),
    default_location_id: z.string().uuid().optional(),
    is_active: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid employee. Username must be at least 3 characters; password at least 6 characters.' });

  const { username, password, ...employeePayload } = parsed.data;
  const created = await supabase.from('employees').insert(clean(employeePayload)).select().single();
  if (created.error) return res.status(400).json({ error: created.error.message });

  const { salt, hash } = hashPassword(password);
  const cred = await supabase.from('employee_credentials').insert({
    employee_id: created.data.id,
    username,
    password_hash: hash,
    password_salt: salt,
    is_active: employeePayload.is_active ?? true
  }).select('employee_id,username,is_active').single();

  if (cred.error) {
    await supabase.from('employees').delete().eq('id', created.data.id);
    return res.status(400).json({ error: cred.error.message });
  }

  res.json({ ...created.data, credential: cred.data });
});

app.patch('/api/employees/:id', requireArea('employees'), async (req, res) => {
  const parsed = z.object({
    full_name: z.string().min(1).optional(),
    phone: z.string().nullable().optional(),
    role: z.enum(employeeRoles).optional(),
    default_location_id: z.string().uuid().nullable().optional(),
    is_active: z.boolean().optional(),
    username: z.string().min(3).regex(/^[a-zA-Z0-9._-]+$/).optional(),
    password: z.string().min(6).optional(),
    credential_is_active: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid employee update' });

  const { username, password, credential_is_active, ...employeePayload } = parsed.data;
  const updates = clean(employeePayload);
  let employee = null;
  if (Object.keys(updates).length) {
    const updated = await supabase.from('employees').update(updates).eq('id', req.params.id).select().single();
    if (updated.error) return res.status(400).json({ error: updated.error.message });
    employee = updated.data;
  }

  if (username || password || credential_is_active !== undefined) {
    const current = await supabase.from('employee_credentials').select('*').eq('employee_id', req.params.id).maybeSingle();
    if (current.error) return res.status(400).json({ error: current.error.message });
    const credentialPayload = {};
    if (username) credentialPayload.username = username;
    if (credential_is_active !== undefined) credentialPayload.is_active = credential_is_active;
    if (password) {
      const { salt, hash } = hashPassword(password);
      credentialPayload.password_salt = salt;
      credentialPayload.password_hash = hash;
    }
    if (current.data) {
      const cred = await supabase.from('employee_credentials').update(credentialPayload).eq('employee_id', req.params.id).select('employee_id,username,is_active').single();
      if (cred.error) return res.status(400).json({ error: cred.error.message });
    } else {
      if (!username || !password) return res.status(400).json({ error: 'Username and password are required when creating credentials for an existing employee.' });
      const { salt, hash } = hashPassword(password);
      const cred = await supabase.from('employee_credentials').insert({ employee_id: req.params.id, username, password_hash: hash, password_salt: salt, is_active: credential_is_active ?? true }).select('employee_id,username,is_active').single();
      if (cred.error) return res.status(400).json({ error: cred.error.message });
    }
  }

  if (!employee) {
    const fetched = await supabase.from('employees').select('*').eq('id', req.params.id).single();
    if (fetched.error) return res.status(400).json({ error: fetched.error.message });
    employee = fetched.data;
  }
  res.json(employee);
});

// INGREDIENTS
app.get('/api/ingredients', requireArea('ingredients'), async (_req, res) => {
  const data = await sb(supabase.from('ingredients').select('*').order('name'), res);
  if (data) res.json(data);
});

app.post('/api/ingredients', requireArea('ingredients'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1),
    category: z.string().optional(),
    base_unit: z.string().min(1),
    purchase_unit_name: z.string().optional(),
    purchase_unit_size: z.coerce.number().positive().optional(),
    purchase_unit_cost: z.coerce.number().nonnegative().optional(),
    cost_per_base_unit: z.coerce.number().nonnegative().optional(),
    is_perishable: z.boolean().optional(),
    shelf_life_days: z.coerce.number().int().nonnegative().optional(),
    allergen_flags: z.array(z.string()).optional(),
    is_customer_supplied: z.boolean().optional(),
    is_active: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid ingredient' });
  const payload = parsed.data;
  if (!payload.cost_per_base_unit && payload.purchase_unit_cost && payload.purchase_unit_size) payload.cost_per_base_unit = payload.purchase_unit_cost / payload.purchase_unit_size;
  const data = await sb(supabase.from('ingredients').insert(clean(payload)).select().single(), res);
  if (data) res.json(data);
});

app.patch('/api/ingredients/:id', requireArea('ingredients'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1).optional(),
    category: z.string().nullable().optional(),
    base_unit: z.string().min(1).optional(),
    purchase_unit_name: z.string().nullable().optional(),
    purchase_unit_size: z.coerce.number().positive().nullable().optional(),
    purchase_unit_cost: z.coerce.number().nonnegative().nullable().optional(),
    cost_per_base_unit: z.coerce.number().nonnegative().nullable().optional(),
    is_perishable: z.boolean().optional(),
    shelf_life_days: z.coerce.number().int().nonnegative().nullable().optional(),
    allergen_flags: z.array(z.string()).optional(),
    is_customer_supplied: z.boolean().optional(),
    is_active: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid ingredient update' });
  const data = await sb(supabase.from('ingredients').update(clean(parsed.data)).eq('id', req.params.id).select().single(), res);
  if (data) res.json(data);
});

// COCKTAILS / PRODUCTS / RECIPES
app.get('/api/cocktails', requireArea('cocktails'), async (_req, res) => {
  const [products, categories, variants, liquorTypes, compatibility, ingredients, recipes, recipeItems] = await Promise.all([
    supabase.from('products').select('*, product_categories(name)').order('name'),
    supabase.from('product_categories').select('*').order('sort_order'),
    supabase.from('product_variants').select('*').order('name'),
    supabase.from('liquor_types').select('*').order('name'),
    supabase.from('product_liquor_compatibility').select('*'),
    supabase.from('ingredients').select('*').eq('is_active', true).order('name'),
    supabase.from('recipes').select('*').order('created_at', { ascending: false }),
    supabase.from('recipe_items').select('*, ingredients(name,base_unit)').order('id')
  ]);
  for (const result of [products, categories, variants, liquorTypes, compatibility, ingredients, recipes, recipeItems]) if (result.error) return res.status(400).json({ error: result.error.message });
  res.json({ products: products.data, categories: categories.data, variants: variants.data, liquorTypes: liquorTypes.data, compatibility: compatibility.data, ingredients: ingredients.data, recipes: recipes.data, recipeItems: recipeItems.data });
});

// Backward compatible old route name
app.get('/api/products', requireArea('cocktails'), async (_req, res) => {
  const [products, categories, variants, liquorTypes, compatibility, ingredients, recipes, recipeItems] = await Promise.all([
    supabase.from('products').select('*, product_categories(name)').order('name'),
    supabase.from('product_categories').select('*').order('sort_order'),
    supabase.from('product_variants').select('*').order('name'),
    supabase.from('liquor_types').select('*').order('name'),
    supabase.from('product_liquor_compatibility').select('*'),
    supabase.from('ingredients').select('*').order('name'),
    supabase.from('recipes').select('*').order('created_at', { ascending: false }),
    supabase.from('recipe_items').select('*, ingredients(name,base_unit)').order('id')
  ]);
  for (const result of [products, categories, variants, liquorTypes, compatibility, ingredients, recipes, recipeItems]) if (result.error) return res.status(400).json({ error: result.error.message });
  res.json({ products: products.data, categories: categories.data, variants: variants.data, liquorTypes: liquorTypes.data, compatibility: compatibility.data, ingredients: ingredients.data, recipes: recipes.data, recipeItems: recipeItems.data });
});

app.post('/api/cocktails', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1),
    slug: z.string().min(1),
    description: z.string().optional(),
    image_url: z.string().optional(),
    category_id: z.string().uuid().optional(),
    status: z.enum(productStatuses).default('active'),
    is_featured: z.boolean().optional(),
    prep_time_minutes: z.coerce.number().int().nonnegative().optional(),
    tags: z.array(z.string()).optional(),
    variant_name: z.string().min(1).default('Standard'),
    serving_count: z.coerce.number().int().positive().default(1),
    price_ex_vat: z.coerce.number().nonnegative().default(0),
    vat_rate: z.coerce.number().nonnegative().default(0.14),
    recipe_version: z.coerce.number().int().positive().default(1),
    yield_servings: z.coerce.number().int().positive().default(1),
    liquor_type_ids: z.array(z.string().uuid()).optional(),
    recipe_items: z.array(z.object({ ingredient_id: z.string().uuid(), quantity: z.coerce.number().nonnegative(), unit: z.string().min(1), is_optional: z.boolean().optional(), is_customer_supplied: z.boolean().optional() })).optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid cocktail' });

  const p = parsed.data;
  const productPayload = clean({ category_id: p.category_id, name: p.name, slug: p.slug, description: p.description, image_url: p.image_url, status: p.status, is_featured: p.is_featured, prep_time_minutes: p.prep_time_minutes, tags: p.tags });
  const product = await supabase.from('products').insert(productPayload).select().single();
  if (product.error) return res.status(400).json({ error: product.error.message });

  const cleanup = async () => { await supabase.from('products').delete().eq('id', product.data.id); };

  const variant = await supabase.from('product_variants').insert({ product_id: product.data.id, name: p.variant_name, serving_count: p.serving_count, price_ex_vat: p.price_ex_vat, vat_rate: p.vat_rate, is_active: true }).select().single();
  if (variant.error) { await cleanup(); return res.status(400).json({ error: variant.error.message }); }

  const recipe = await supabase.from('recipes').insert({ product_id: product.data.id, version: p.recipe_version, status: p.status, yield_servings: p.yield_servings }).select().single();
  if (recipe.error) { await cleanup(); return res.status(400).json({ error: recipe.error.message }); }

  if (p.recipe_items?.length) {
    const recipeItems = await supabase.from('recipe_items').insert(p.recipe_items.map((item) => ({ ...clean(item), recipe_id: recipe.data.id }))).select();
    if (recipeItems.error) { await cleanup(); return res.status(400).json({ error: recipeItems.error.message }); }
  }

  if (p.liquor_type_ids?.length) {
    const compat = await supabase.from('product_liquor_compatibility').insert(p.liquor_type_ids.map((liquor_type_id) => ({ product_id: product.data.id, liquor_type_id }))).select();
    if (compat.error) { await cleanup(); return res.status(400).json({ error: compat.error.message }); }
  }

  res.json({ product: product.data, variant: variant.data, recipe: recipe.data });
});

app.patch('/api/cocktails/:id', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({
    name: z.string().min(1).optional(),
    slug: z.string().min(1).optional(),
    description: z.string().nullable().optional(),
    image_url: z.string().nullable().optional(),
    category_id: z.string().uuid().nullable().optional(),
    status: z.enum(productStatuses).optional(),
    is_featured: z.boolean().optional(),
    prep_time_minutes: z.coerce.number().int().nonnegative().optional(),
    tags: z.array(z.string()).optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid cocktail update' });
  const data = await sb(supabase.from('products').update(clean(parsed.data)).eq('id', req.params.id).select().single(), res);
  if (data) res.json(data);
});

app.post('/api/cocktails/:id/variants', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({ name: z.string().min(1), serving_count: z.coerce.number().int().positive(), price_ex_vat: z.coerce.number().nonnegative(), vat_rate: z.coerce.number().nonnegative().default(0.14), is_active: z.boolean().optional() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid variant' });
  const data = await sb(supabase.from('product_variants').insert({ ...parsed.data, product_id: req.params.id }).select().single(), res);
  if (data) res.json(data);
});

app.post('/api/cocktails/:id/liquors', requireArea('cocktails'), async (req, res) => {
  const parsed = z.object({ liquor_type_ids: z.array(z.string().uuid()) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid liquor compatibility' });
  await supabase.from('product_liquor_compatibility').delete().eq('product_id', req.params.id);
  if (!parsed.data.liquor_type_ids.length) return res.json([]);
  const data = await sb(supabase.from('product_liquor_compatibility').insert(parsed.data.liquor_type_ids.map((liquor_type_id) => ({ product_id: req.params.id, liquor_type_id }))).select(), res);
  if (data) res.json(data);
});

app.post('/api/recipes', requireArea('cocktails'), async (req, res) => {
  const data = await sb(supabase.from('recipes').insert(clean(req.body)).select().single(), res);
  if (data) res.json(data);
});

app.post('/api/recipe-items', requireArea('cocktails'), async (req, res) => {
  const data = await sb(supabase.from('recipe_items').insert(clean(req.body)).select().single(), res);
  if (data) res.json(data);
});

// INVENTORY
app.get('/api/inventory', requireArea('inventory'), async (_req, res) => {
  const [balances, movements, ingredients, locations] = await Promise.all([
    supabase.from('inventory_balances').select('*, ingredients(name,base_unit), locations(name,type,compound_name)').order('updated_at', { ascending: false }),
    supabase.from('stock_movements').select('*, ingredients(name), locations(name)').order('created_at', { ascending: false }).limit(100),
    supabase.from('ingredients').select('*').order('name'),
    supabase.from('locations').select('*').order('name')
  ]);
  for (const result of [balances, movements, ingredients, locations]) if (result.error) return res.status(400).json({ error: result.error.message });
  res.json({ balances: balances.data, movements: movements.data, ingredients: ingredients.data, locations: locations.data });
});

app.post('/api/inventory/adjust', requireArea('inventory'), async (req, res) => {
  const parsed = z.object({ ingredient_id: z.string().uuid(), location_id: z.string().uuid(), quantity_delta: z.coerce.number(), reason: z.string().optional() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid adjustment' });
  const data = await sb(supabase.from('stock_movements').insert({ ...parsed.data, movement_type: 'adjustment' }).select().single(), res);
  if (data) res.json(data);
});

// TRANSFERS
app.get('/api/transfers', requireArea('transfers'), async (_req, res) => {
  const [transfers, items, ingredients, locations] = await Promise.all([
    supabase.from('stock_transfers').select('*, from:locations!stock_transfers_from_location_id_fkey(name,type), to:locations!stock_transfers_to_location_id_fkey(name,type)').order('requested_at', { ascending: false }).limit(100),
    supabase.from('stock_transfer_items').select('*, ingredients(name,base_unit)').order('id'),
    supabase.from('ingredients').select('*').order('name'),
    supabase.from('locations').select('*').order('name')
  ]);
  for (const result of [transfers, items, ingredients, locations]) if (result.error) return res.status(400).json({ error: result.error.message });
  res.json({ transfers: transfers.data, items: items.data, ingredients: ingredients.data, locations: locations.data });
});

app.post('/api/transfers', requireArea('transfers'), async (req, res) => {
  const parsed = z.object({
    from_location_id: z.string().uuid(),
    to_location_id: z.string().uuid(),
    notes: z.string().optional(),
    items: z.array(z.object({ ingredient_id: z.string().uuid(), requested_qty: z.coerce.number().nonnegative().default(0), dispatched_qty: z.coerce.number().nonnegative().default(0), received_qty: z.coerce.number().nonnegative().default(0) })).optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid transfer' });
  const { items = [], ...transfer } = parsed.data;
  const created = await supabase.from('stock_transfers').insert(clean(transfer)).select().single();
  if (created.error) return res.status(400).json({ error: created.error.message });
  if (items.length) {
    const inserted = await supabase.from('stock_transfer_items').insert(items.map((item) => ({ ...clean(item), transfer_id: created.data.id }))).select();
    if (inserted.error) return res.status(400).json({ error: inserted.error.message });
  }
  res.json(created.data);
});

app.patch('/api/transfers/:id', requireArea('transfers'), async (req, res) => {
  const parsed = z.object({ status: z.enum(transferStatuses).optional(), dispatched_at: z.string().optional(), received_at: z.string().optional(), notes: z.string().optional() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid transfer update' });
  const data = await sb(supabase.from('stock_transfers').update(clean(parsed.data)).eq('id', req.params.id).select().single(), res);
  if (data) res.json(data);
});

app.post('/api/transfers/:id/items', requireArea('transfers'), async (req, res) => {
  const data = await sb(supabase.from('stock_transfer_items').insert({ ...clean(req.body), transfer_id: req.params.id }).select().single(), res);
  if (data) res.json(data);
});

// ORDERS
app.get('/api/orders', requireArea('orders'), async (_req, res) => {
  const [orders, items, locations] = await Promise.all([
    supabase.from('orders').select('*, customers(full_name,phone), locations(name,type,compound_name)').order('created_at', { ascending: false }).limit(100),
    supabase.from('order_items').select('*').order('id'),
    supabase.from('locations').select('*').order('name')
  ]);
  for (const result of [orders, items, locations]) if (result.error) return res.status(400).json({ error: result.error.message });
  res.json({ orders: orders.data, items: items.data, locations: locations.data });
});

app.patch('/api/orders/:id', requireArea('orders'), async (req, res) => {
  const parsed = z.object({ status: z.enum(orderStatuses).optional(), payment_status: z.enum(paymentStatuses).optional(), internal_notes: z.string().optional() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid order update' });
  const data = await sb(supabase.from('orders').update(clean(parsed.data)).eq('id', req.params.id).select().single(), res);
  if (data) res.json(data);
});

if (isProd) {
  const distPath = path.join(__dirname, '..', 'dist');
  app.use(express.static(distPath));
  app.get('*', (_req, res) => res.sendFile(path.join(distPath, 'index.html')));
}

app.listen(PORT, () => console.log(`EBTL Admin running on port ${PORT}`));
