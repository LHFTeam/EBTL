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

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}

if (isProd && SESSION_SECRET === 'dev-only-change-me') {
  throw new Error('Set SESSION_SECRET in production');
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});

const roleAccess = {
  admin: ['*'],
  manager: ['dashboard', 'orders', 'inventory', 'transfers', 'products', 'locations', 'employees'],
  supervisor: ['dashboard', 'orders', 'inventory', 'transfers', 'products', 'locations'],
  warehouse: ['dashboard', 'inventory', 'transfers', 'locations'],
  cart_operator: ['dashboard', 'orders', 'inventory', 'transfers'],
  prep: ['dashboard', 'orders']
};

const orderStatuses = [
  'draft',
  'pending_payment',
  'confirmed',
  'preparing',
  'ready',
  'out_for_delivery',
  'completed',
  'cancelled',
  'refunded'
];

const transferStatuses = ['draft', 'picked', 'in_transit', 'received', 'cancelled'];
const productStatuses = ['draft', 'active', 'archived'];
const roles = Object.keys(roleAccess);

function can(role, area) {
  const allowed = roleAccess[role] || [];
  return allowed.includes('*') || allowed.includes(area);
}

function users() {
  try {
    return JSON.parse(process.env.ADMIN_USERS || '[]');
  } catch {
    return [];
  }
}

function clean(obj = {}) {
  return Object.fromEntries(
    Object.entries(obj).filter(([, value]) => value !== undefined && value !== '')
  );
}

function sign(value) {
  return crypto.createHmac('sha256', SESSION_SECRET).update(value).digest('base64url');
}

function encodeSession(user) {
  const payload = Buffer.from(
    JSON.stringify({
      user,
      exp: Date.now() + 12 * 60 * 60 * 1000
    })
  ).toString('base64url');

  return `${payload}.${sign(payload)}`;
}

function decodeSession(token) {
  try {
    if (!token || !token.includes('.')) return null;

    const [payload, signature] = token.split('.');
    const expected = sign(payload);

    if (
      signature.length !== expected.length ||
      !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))
    ) {
      return null;
    }

    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));

    if (!data.exp || Date.now() > data.exp) return null;

    return data.user;
  } catch {
    return null;
  }
}

function getCookie(req, name) {
  const cookies = req.headers.cookie || '';
  return cookies
    .split(';')
    .map((cookie) => cookie.trim())
    .find((cookie) => cookie.startsWith(`${name}=`))
    ?.slice(name.length + 1);
}

function setSessionCookie(res, user) {
  const secure = isProd ? '; Secure' : '';

  res.setHeader(
    'Set-Cookie',
    `ebtl_admin=${encodeSession(user)}; HttpOnly; Path=/; SameSite=Lax; Max-Age=43200${secure}`
  );
}

function clearSessionCookie(res) {
  res.setHeader('Set-Cookie', 'ebtl_admin=; HttpOnly; Path=/; SameSite=Lax; Max-Age=0');
}

function auth(req, _res, next) {
  req.user = decodeSession(getCookie(req, 'ebtl_admin'));
  next();
}

function requireAuth(req, res, next) {
  if (!req.user) return res.status(401).json({ error: 'Not logged in' });
  next();
}

function requireArea(area) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'Not logged in' });
    if (!can(req.user.role, area)) return res.status(403).json({ error: 'Not allowed' });
    next();
  };
}

async function sb(promise, res) {
  const { data, error } = await promise;

  if (error) {
    console.error(error);
    res.status(400).json({ error: error.message });
    return null;
  }

  return data;
}

app.set('trust proxy', 1);
app.use(helmet({ contentSecurityPolicy: false }));
app.use(compression());
app.use(morgan('tiny'));
app.use(express.json({ limit: '1mb' }));
app.use(auth);

app.get('/api/health', (_req, res) => res.json({ ok: true }));

app.post('/api/login', (req, res) => {
  const parsed = z
    .object({
      username: z.string().min(1),
      password: z.string().min(1)
    })
    .safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid login payload' });

  const found = users().find(
    (user) => user.username === parsed.data.username && user.password === parsed.data.password
  );

  if (!found || !roles.includes(found.role)) {
    return res.status(401).json({ error: 'Invalid username or password' });
  }

  const user = {
    username: found.username,
    name: found.name || found.username,
    role: found.role
  };

  setSessionCookie(res, user);

  res.json({
    user,
    access: roleAccess[user.role] || []
  });
});

app.post('/api/logout', requireAuth, (_req, res) => {
  clearSessionCookie(res);
  res.json({ ok: true });
});

app.get('/api/me', requireAuth, (req, res) => {
  res.json({
    user: req.user,
    access: roleAccess[req.user.role] || []
  });
});

app.get('/api/dashboard', requireArea('dashboard'), async (_req, res) => {
  const [orders, sales, lowStock, locations, transfers] = await Promise.all([
    supabase
      .from('orders')
      .select('id,order_number,status,total_amount,created_at,location_id')
      .order('created_at', { ascending: false })
      .limit(200),

    supabase
      .from('v_daily_sales_by_location')
      .select('*')
      .order('sales_date', { ascending: false })
      .limit(30),

    supabase.from('v_inventory_low_stock').select('*').limit(100),

    supabase.from('locations').select('*').order('name'),

    supabase
      .from('stock_transfers')
      .select('id,status,requested_at')
      .in('status', ['draft', 'picked', 'in_transit'])
      .limit(100)
  ]);

  for (const result of [orders, sales, lowStock, locations, transfers]) {
    if (result.error) return res.status(400).json({ error: result.error.message });
  }

  const completed = orders.data.filter((order) => order.status === 'completed');

  res.json({
    kpis: {
      recentOrders: orders.data.length,
      completedOrders: completed.length,
      recentRevenue: completed.reduce(
        (sum, order) => sum + Number(order.total_amount || 0),
        0
      ),
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

app.get('/api/locations', requireArea('locations'), async (_req, res) => {
  const data = await sb(
    supabase.from('locations').select('*').order('type').order('name'),
    res
  );

  if (data) res.json(data);
});

app.post('/api/locations', requireArea('locations'), async (req, res) => {
  const parsed = z
    .object({
      name: z.string().min(1),
      type: z.enum(['central_warehouse', 'beach_cart']),
      compound_name: z.string().optional(),
      beach_name: z.string().optional(),
      address: z.string().optional(),
      latitude: z.coerce.number().optional(),
      longitude: z.coerce.number().optional(),
      is_active: z.boolean().optional()
    })
    .safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid location' });

  const data = await sb(
    supabase.from('locations').insert(clean(parsed.data)).select().single(),
    res
  );

  if (data) res.json(data);
});

app.patch('/api/locations/:id', requireArea('locations'), async (req, res) => {
  const data = await sb(
    supabase.from('locations').update(clean(req.body)).eq('id', req.params.id).select().single(),
    res
  );

  if (data) res.json(data);
});

app.get('/api/employees', requireArea('employees'), async (_req, res) => {
  const data = await sb(
    supabase.from('employees').select('*, locations(name)').order('full_name'),
    res
  );

  if (data) res.json(data);
});

app.post('/api/employees', requireArea('employees'), async (req, res) => {
  const parsed = z
    .object({
      full_name: z.string().min(1),
      phone: z.string().optional(),
      role: z.enum(['prep', 'cart_operator', 'warehouse', 'supervisor', 'manager', 'admin']),
      default_location_id: z.string().uuid().optional(),
      is_active: z.boolean().optional()
    })
    .safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid employee' });

  const data = await sb(
    supabase.from('employees').insert(clean(parsed.data)).select().single(),
    res
  );

  if (data) res.json(data);
});

app.patch('/api/employees/:id', requireArea('employees'), async (req, res) => {
  const data = await sb(
    supabase.from('employees').update(clean(req.body)).eq('id', req.params.id).select().single(),
    res
  );

  if (data) res.json(data);
});

app.get('/api/products', requireArea('products'), async (_req, res) => {
  const [
    products,
    categories,
    variants,
    liquorTypes,
    compatibility,
    ingredients,
    recipes,
    recipeItems
  ] = await Promise.all([
    supabase.from('products').select('*, product_categories(name)').order('name'),
    supabase.from('product_categories').select('*').order('sort_order'),
    supabase.from('product_variants').select('*').order('name'),
    supabase.from('liquor_types').select('*').order('name'),
    supabase.from('product_liquor_compatibility').select('*'),
    supabase.from('ingredients').select('*').order('name'),
    supabase.from('recipes').select('*').order('created_at', { ascending: false }),
    supabase.from('recipe_items').select('*, ingredients(name,base_unit)').order('id')
  ]);

  for (const result of [
    products,
    categories,
    variants,
    liquorTypes,
    compatibility,
    ingredients,
    recipes,
    recipeItems
  ]) {
    if (result.error) return res.status(400).json({ error: result.error.message });
  }

  res.json({
    products: products.data,
    categories: categories.data,
    variants: variants.data,
    liquorTypes: liquorTypes.data,
    compatibility: compatibility.data,
    ingredients: ingredients.data,
    recipes: recipes.data,
    recipeItems: recipeItems.data
  });
});

app.post('/api/products', requireArea('products'), async (req, res) => {
  const parsed = z
    .object({
      category_id: z.string().uuid().optional(),
      name: z.string().min(1),
      slug: z.string().min(1),
      description: z.string().optional(),
      image_url: z.string().optional(),
      status: z.enum(productStatuses).default('draft'),
      is_featured: z.boolean().optional(),
      prep_time_minutes: z.coerce.number().int().nonnegative().optional(),
      tags: z.array(z.string()).optional()
    })
    .safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid product' });

  const data = await sb(
    supabase.from('products').insert(clean(parsed.data)).select().single(),
    res
  );

  if (data) res.json(data);
});

app.patch('/api/products/:id', requireArea('products'), async (req, res) => {
  const data = await sb(
    supabase.from('products').update(clean(req.body)).eq('id', req.params.id).select().single(),
    res
  );

  if (data) res.json(data);
});

app.post('/api/product-variants', requireArea('products'), async (req, res) => {
  const data = await sb(
    supabase.from('product_variants').insert(clean(req.body)).select().single(),
    res
  );

  if (data) res.json(data);
});

app.post('/api/ingredients', requireArea('products'), async (req, res) => {
  const parsed = z
    .object({
      name: z.string().min(1),
      category: z.string().optional(),
      base_unit: z.string().min(1),
      purchase_unit_name: z.string().optional(),
      purchase_unit_size: z.coerce.number().positive().optional(),
      purchase_unit_cost: z.coerce.number().nonnegative().optional(),
      cost_per_base_unit: z.coerce.number().nonnegative().optional(),
      is_perishable: z.boolean().optional(),
      shelf_life_days: z.coerce.number().int().optional(),
      allergen_flags: z.array(z.string()).optional(),
      is_customer_supplied: z.boolean().optional(),
      is_active: z.boolean().optional()
    })
    .safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid ingredient' });

  const data = await sb(
    supabase.from('ingredients').insert(clean(parsed.data)).select().single(),
    res
  );

  if (data) res.json(data);
});

app.post('/api/recipes', requireArea('products'), async (req, res) => {
  const data = await sb(
    supabase.from('recipes').insert(clean(req.body)).select().single(),
    res
  );

  if (data) res.json(data);
});

app.post('/api/recipe-items', requireArea('products'), async (req, res) => {
  const data = await sb(
    supabase.from('recipe_items').insert(clean(req.body)).select().single(),
    res
  );

  if (data) res.json(data);
});

app.post('/api/product-liquor-compatibility', requireArea('products'), async (req, res) => {
  const data = await sb(
    supabase.from('product_liquor_compatibility').upsert(clean(req.body)).select(),
    res
  );

  if (data) res.json(data);
});

app.get('/api/inventory', requireArea('inventory'), async (_req, res) => {
  const [balances, movements, ingredients, locations] = await Promise.all([
    supabase
      .from('inventory_balances')
      .select('*, ingredients(name,base_unit), locations(name,type,compound_name)')
      .order('updated_at', { ascending: false }),

    supabase
      .from('stock_movements')
      .select('*, ingredients(name), locations(name)')
      .order('created_at', { ascending: false })
      .limit(100),

    supabase.from('ingredients').select('*').order('name'),
    supabase.from('locations').select('*').order('name')
  ]);

  for (const result of [balances, movements, ingredients, locations]) {
    if (result.error) return res.status(400).json({ error: result.error.message });
  }

  res.json({
    balances: balances.data,
    movements: movements.data,
    ingredients: ingredients.data,
    locations: locations.data
  });
});

app.post('/api/inventory/adjust', requireArea('inventory'), async (req, res) => {
  const parsed = z
    .object({
      ingredient_id: z.string().uuid(),
      location_id: z.string().uuid(),
      quantity_delta: z.coerce.number(),
      reason: z.string().optional()
    })
    .safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid adjustment' });

  const data = await sb(
    supabase
      .from('stock_movements')
      .insert({
        ...parsed.data,
        movement_type: 'adjustment'
      })
      .select()
      .single(),
    res
  );

  if (data) res.json(data);
});

app.get('/api/transfers', requireArea('transfers'), async (_req, res) => {
  const [transfers, items, ingredients, locations] = await Promise.all([
    supabase
      .from('stock_transfers')
      .select(
        '*, from:locations!stock_transfers_from_location_id_fkey(name,type), to:locations!stock_transfers_to_location_id_fkey(name,type)'
      )
      .order('requested_at', { ascending: false })
      .limit(100),

    supabase
      .from('stock_transfer_items')
      .select('*, ingredients(name,base_unit)')
      .order('id'),

    supabase.from('ingredients').select('*').order('name'),
    supabase.from('locations').select('*').order('name')
  ]);

  for (const result of [transfers, items, ingredients, locations]) {
    if (result.error) return res.status(400).json({ error: result.error.message });
  }

  res.json({
    transfers: transfers.data,
    items: items.data,
    ingredients: ingredients.data,
    locations: locations.data
  });
});

app.post('/api/transfers', requireArea('transfers'), async (req, res) => {
  const parsed = z
    .object({
      from_location_id: z.string().uuid(),
      to_location_id: z.string().uuid(),
      notes: z.string().optional(),
      items: z
        .array(
          z.object({
            ingredient_id: z.string().uuid(),
            requested_qty: z.coerce.number().nonnegative().default(0),
            dispatched_qty: z.coerce.number().nonnegative().default(0),
            received_qty: z.coerce.number().nonnegative().default(0)
          })
        )
        .optional()
    })
    .safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid transfer' });

  const { items = [], ...transfer } = parsed.data;

  const created = await supabase.from('stock_transfers').insert(clean(transfer)).select().single();

  if (created.error) return res.status(400).json({ error: created.error.message });

  if (items.length) {
    const inserted = await supabase
      .from('stock_transfer_items')
      .insert(
        items.map((item) => ({
          ...clean(item),
          transfer_id: created.data.id
        }))
      )
      .select();

    if (inserted.error) return res.status(400).json({ error: inserted.error.message });
  }

  res.json(created.data);
});

app.patch('/api/transfers/:id', requireArea('transfers'), async (req, res) => {
  const parsed = z
    .object({
      status: z.enum(transferStatuses).optional(),
      dispatched_at: z.string().optional(),
      received_at: z.string().optional(),
      notes: z.string().optional()
    })
    .safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid transfer update' });

  const data = await sb(
    supabase
      .from('stock_transfers')
      .update(clean(parsed.data))
      .eq('id', req.params.id)
      .select()
      .single(),
    res
  );

  if (data) res.json(data);
});

app.post('/api/transfers/:id/items', requireArea('transfers'), async (req, res) => {
  const data = await sb(
    supabase
      .from('stock_transfer_items')
      .insert({
        ...clean(req.body),
        transfer_id: req.params.id
      })
      .select()
      .single(),
    res
  );

  if (data) res.json(data);
});

app.get('/api/orders', requireArea('orders'), async (_req, res) => {
  const [orders, items, locations] = await Promise.all([
    supabase
      .from('orders')
      .select('*, customers(full_name,phone), locations(name,type,compound_name)')
      .order('created_at', { ascending: false })
      .limit(100),

    supabase.from('order_items').select('*').order('id'),

    supabase.from('locations').select('*').order('name')
  ]);

  for (const result of [orders, items, locations]) {
    if (result.error) return res.status(400).json({ error: result.error.message });
  }

  res.json({
    orders: orders.data,
    items: items.data,
    locations: locations.data
  });
});

app.patch('/api/orders/:id', requireArea('orders'), async (req, res) => {
  const parsed = z
    .object({
      status: z.enum(orderStatuses).optional(),
      payment_status: z
        .enum(['unpaid', 'pending', 'paid', 'failed', 'refunded', 'partially_refunded'])
        .optional(),
      internal_notes: z.string().optional()
    })
    .safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid order update' });

  const data = await sb(
    supabase.from('orders').update(clean(parsed.data)).eq('id', req.params.id).select().single(),
    res
  );

  if (data) res.json(data);
});

if (isProd) {
  const distPath = path.join(__dirname, '..', 'dist');
  app.use(express.static(distPath));
  app.get('*', (_req, res) => res.sendFile(path.join(distPath, 'index.html')));
}

app.listen(PORT, () => console.log(`EBTL Admin running on port ${PORT}`));
