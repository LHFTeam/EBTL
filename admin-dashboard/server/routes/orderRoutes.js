import { Router } from 'express';
import { z } from 'zod';
import { orderStatuses, paymentStatuses } from '../config/appConfig.js';
import { requireArea } from '../middleware/auth.js';
import { pickupAttemptLimiter } from '../middleware/rateLimit.js';
import { clean } from '../lib/objectUtils.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';
import { decodePickupToken, verifyPickupShortCode } from '../lib/pickupToken.js';
import { notifyOrderReadyForPickup } from '../lib/notifications.js';

export const orderRouter = Router();

const CART_OPERATION_ROLES = ['prep', 'cart_operator', 'supervisor', 'manager', 'admin'];
const CART_LOCATION_SWITCH_ROLES = ['supervisor', 'manager', 'admin'];
const CART_OPERATION_STATUSES = ['confirmed', 'preparing', 'ready', 'completed'];
const ACTIVE_OPERATION_STATUSES = ['confirmed', 'preparing', 'ready'];
const PREP_VIEWABLE_STATUSES = ['confirmed', 'preparing', 'ready', 'completed'];
const STATUS_GROUPS = {
  active: ACTIVE_OPERATION_STATUSES,
  confirmed: ['confirmed'],
  preparing: ['preparing'],
  ready: ['ready'],
  picked_up: ['completed']
};
const OPERATION_TRANSITIONS = {
  confirmed: ['preparing'],
  preparing: ['ready'],
  ready: ['completed']
};

function userCanUseCartOperations(user) {
  return CART_OPERATION_ROLES.includes(user?.role);
}

function userCanSwitchCartLocations(user) {
  return CART_LOCATION_SWITCH_ROLES.includes(user?.role);
}

function paymentRows(order) {
  return Array.isArray(order?.payments) ? order.payments : [];
}

function paymentConfirmedAt(order) {
  if (order?.confirmed_at) return order.confirmed_at;

  const paidPayment = paymentRows(order)
    .filter((payment) => payment.status === 'paid')
    .sort((a, b) => new Date(a.updated_at || a.created_at || 0) - new Date(b.updated_at || b.created_at || 0))[0];

  if (paidPayment?.updated_at) return paidPayment.updated_at;
  if (paidPayment?.created_at) return paidPayment.created_at;
  if (order?.status === 'confirmed' && order?.payment_status === 'paid') return order.created_at;
  return order?.created_at || null;
}

function normalizeStatusList({ statusGroup, statuses }) {
  if (statusGroup && STATUS_GROUPS[statusGroup]) return STATUS_GROUPS[statusGroup];

  const parsedStatuses = String(statuses || '')
    .split(',')
    .map((status) => status.trim())
    .filter((status) => CART_OPERATION_STATUSES.includes(status));

  return parsedStatuses.length ? parsedStatuses : ACTIVE_OPERATION_STATUSES;
}

function orderById(rows = []) {
  return new Map(rows.map((row) => [row.id, row]));
}

function groupBy(rows = [], key) {
  const grouped = new Map();
  for (const row of rows) {
    const value = row[key];
    const list = grouped.get(value) || [];
    list.push(row);
    grouped.set(value, list);
  }
  return grouped;
}

function compactLocation(location) {
  if (!location) return null;
  return {
    id: location.id,
    name: location.name,
    type: location.type,
    compound_name: location.compound_name,
    beach_name: location.beach_name,
    is_active: Boolean(location.is_active)
  };
}

async function loadActiveCartLocations() {
  return supabase
    .from('locations')
    .select('id,name,type,compound_name,beach_name,is_active')
    .eq('type', 'beach_cart')
    .eq('is_active', true)
    .order('name', { ascending: true });
}

async function resolveCartOperationLocation({ req, res, requestedLocationId = null }) {
  if (!userCanUseCartOperations(req.user)) {
    res.status(403).json({ error: 'Not allowed' });
    return null;
  }

  const canSwitchLocations = userCanSwitchCartLocations(req.user);
  const locationsResult = await loadActiveCartLocations();
  if (locationsResult.error) {
    res.status(400).json({ error: locationsResult.error.message });
    return null;
  }

  const activeLocations = locationsResult.data || [];
  const activeById = orderById(activeLocations);
  const defaultLocationId = req.user?.location_id || '';

  if (!canSwitchLocations) {
    if (!defaultLocationId) {
      res.status(403).json({ error: 'This employee does not have a default cart location.' });
      return null;
    }

    const defaultLocation = activeById.get(defaultLocationId);
    if (!defaultLocation) {
      res.status(403).json({ error: 'This employee default location is not an active beach cart.' });
      return null;
    }

    if (requestedLocationId && requestedLocationId !== defaultLocationId) {
      res.status(403).json({ error: 'Not allowed to view orders for this cart location.' });
      return null;
    }

    return {
      canSwitchLocations: false,
      locations: [defaultLocation],
      selectedLocation: defaultLocation
    };
  }

  const requestedLocation = requestedLocationId ? activeById.get(requestedLocationId) : null;
  const defaultLocation = defaultLocationId ? activeById.get(defaultLocationId) : null;
  const selectedLocation = requestedLocation || defaultLocation || activeLocations[0] || null;

  if (requestedLocationId && !requestedLocation) {
    res.status(400).json({ error: 'Selected cart location is not active or does not exist.' });
    return null;
  }

  return {
    canSwitchLocations: true,
    locations: activeLocations,
    selectedLocation
  };
}

async function loadRecipeContext({ itemRows, additionRows }) {
  const recipeIds = [
    ...itemRows.map((item) => item.recipe_id).filter(Boolean),
    ...additionRows.map((addition) => addition.addon_recipe_id).filter(Boolean)
  ];
  const uniqueRecipeIds = [...new Set(recipeIds)];

  if (!uniqueRecipeIds.length) {
    return {
      recipesById: new Map(),
      recipeItemsByRecipeId: new Map()
    };
  }

  const [recipes, recipeItems] = await Promise.all([
    supabase
      .from('recipes')
      .select('*')
      .in('id', uniqueRecipeIds),
    supabase
      .from('recipe_items')
      .select('*, ingredients(id,name,name_ar,base_unit,is_customer_supplied,allergen_flags)')
      .in('recipe_id', uniqueRecipeIds)
      .order('id', { ascending: true })
  ]);

  if (recipes.error) throw recipes.error;
  if (recipeItems.error) throw recipeItems.error;

  return {
    recipesById: orderById(recipes.data || []),
    recipeItemsByRecipeId: groupBy(recipeItems.data || [], 'recipe_id')
  };
}

function enrichOrderItem({ item, removedByItemId, additionsByItemId, componentsByItemId, recipesById, recipeItemsByRecipeId }) {
  const removed_ingredients = removedByItemId.get(item.id) || [];
  const additions = additionsByItemId.get(item.id) || [];
  const inventory_components = componentsByItemId.get(item.id) || [];
  const recipe = item.recipe_id ? recipesById.get(item.recipe_id) || null : null;

  return {
    ...item,
    product_image_url: item.products?.image_url || null,
    product_type: item.products?.product_type || null,
    serving_count: item.product_variants?.serving_count || 1,
    recipe,
    recipe_items: recipe ? (recipeItemsByRecipeId.get(recipe.id) || []) : [],
    removed_ingredients,
    additions: additions.map((addition) => ({
      ...addition,
      recipe: addition.addon_recipe_id ? recipesById.get(addition.addon_recipe_id) || null : null,
      recipe_items: addition.addon_recipe_id ? (recipeItemsByRecipeId.get(addition.addon_recipe_id) || []) : []
    })),
    inventory_components
  };
}

function prepRecipe(recipe) {
  if (!recipe) return null;
  return {
    id: recipe.id,
    yield_servings: recipe.yield_servings,
    notes: recipe.notes
  };
}

function prepRecipeItems(recipeItems = []) {
  return recipeItems.map((recipeItem) => ({
    id: recipeItem.id,
    ingredient_id: recipeItem.ingredient_id,
    quantity: recipeItem.quantity,
    unit: recipeItem.unit,
    is_optional: Boolean(recipeItem.is_optional),
    is_customer_supplied: Boolean(recipeItem.is_customer_supplied),
    ingredients: recipeItem.ingredients ? {
      id: recipeItem.ingredients.id,
      name: recipeItem.ingredients.name,
      name_ar: recipeItem.ingredients.name_ar,
      base_unit: recipeItem.ingredients.base_unit,
      is_customer_supplied: Boolean(recipeItem.ingredients.is_customer_supplied),
      allergen_flags: recipeItem.ingredients.allergen_flags
    } : null
  }));
}

function prepOperationalItem(item) {
  return {
    id: item.id,
    product_name_snapshot: item.product_name_snapshot,
    variant_name_snapshot: item.variant_name_snapshot,
    quantity: item.quantity,
    prep_status: item.prep_status,
    customization_summary: item.customization_summary,
    product_image_url: item.product_image_url,
    product_type: item.product_type,
    serving_count: item.serving_count,
    products: item.products ? {
      name: item.products.name,
      name_ar: item.products.name_ar,
      product_type: item.products.product_type,
      image_url: item.products.image_url,
      prep_time_minutes: item.products.prep_time_minutes
    } : null,
    product_variants: item.product_variants ? {
      name: item.product_variants.name,
      name_ar: item.product_variants.name_ar
    } : null,
    recipe: prepRecipe(item.recipe),
    recipe_items: prepRecipeItems(item.recipe_items),
    removed_ingredients: (item.removed_ingredients || []).map((removed) => ({
      id: removed.id,
      recipe_item_id: removed.recipe_item_id,
      ingredient_id: removed.ingredient_id,
      ingredient_name_snapshot: removed.ingredient_name_snapshot,
      quantity_snapshot: removed.quantity_snapshot,
      unit_snapshot: removed.unit_snapshot
    })),
    additions: (item.additions || []).map((addition) => ({
      id: addition.id,
      quantity_per_parent: addition.quantity_per_parent,
      product_name_snapshot: addition.product_name_snapshot,
      variant_name_snapshot: addition.variant_name_snapshot,
      serving_count_snapshot: addition.serving_count_snapshot,
      recipe: prepRecipe(addition.recipe),
      recipe_items: prepRecipeItems(addition.recipe_items)
    }))
  };
}

function publicOperationalOrder({ order, items, isPrep = false }) {
  const confirmedAt = paymentConfirmedAt(order);
  const customerName = order.customers?.full_name || null;
  const customerPhone = order.customer_phone_snapshot || order.customers?.phone || null;

  const operationalOrder = {
    id: order.id,
    order_number: order.order_number,
    location_id: order.location_id,
    location: compactLocation(order.locations),
    order_channel: order.order_channel,
    fulfillment_type: order.fulfillment_type,
    status: order.status,
    payment_status: order.payment_status,
    customer_notes: order.customer_notes,
    customer_address_snapshot: order.customer_address_snapshot,
    created_at: order.created_at,
    updated_at: order.updated_at,
    confirmed_at: confirmedAt,
    preparing_at: order.preparing_at || null,
    ready_at: order.ready_at || null,
    completed_at: order.completed_at || null,
    customer: {
      name: customerName || 'Walk-in Customer'
    },
    item_count: items.reduce((sum, item) => sum + Number(item.quantity || 0), 0),
    items: isPrep ? items.map(prepOperationalItem) : items
  };

  if (!isPrep) {
    operationalOrder.requested_fulfillment_at = order.requested_fulfillment_at;
    operationalOrder.subtotal_ex_vat = order.subtotal_ex_vat;
    operationalOrder.vat_amount = order.vat_amount;
    operationalOrder.discount_amount = order.discount_amount;
    operationalOrder.delivery_fee = order.delivery_fee;
    operationalOrder.total_amount = order.total_amount;
    operationalOrder.internal_notes = order.internal_notes;
    operationalOrder.customer_phone_snapshot = order.customer_phone_snapshot;
    operationalOrder.customer.phone = customerPhone;
  }

  return operationalOrder;
}

function operationTransitionsFor(user, currentStatus) {
  if (user?.role === 'prep') {
    if (currentStatus === 'confirmed') return ['preparing'];
    if (currentStatus === 'preparing') return ['ready'];
    if (currentStatus === 'ready') return ['completed'];
    return [];
  }

  return OPERATION_TRANSITIONS[currentStatus] || [];
}

function requireGlobalOrderAccess(req, res, next) {
  if (req.user?.role === 'prep') {
    return res.status(403).json({ error: 'Prep employees can only access orders for their assigned cart location.' });
  }
  next();
}

orderRouter.get('/cart-operations/locations', requireArea('orders'), async (req, res) => {
  const resolved = await resolveCartOperationLocation({ req, res });
  if (!resolved) return;

  res.json({
    locations: resolved.locations.map(compactLocation),
    selected_location_id: resolved.selectedLocation?.id || null,
    can_switch_locations: resolved.canSwitchLocations,
    server_time: new Date().toISOString()
  });
});

orderRouter.get('/cart-operations/orders', requireArea('orders'), async (req, res) => {
  const parsed = z.object({
    location_id: z.string().uuid().optional(),
    status_group: z.enum(['active', 'confirmed', 'preparing', 'ready', 'picked_up']).optional(),
    statuses: z.string().optional()
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid cart operations order filters.' });

  const resolved = await resolveCartOperationLocation({
    req,
    res,
    requestedLocationId: parsed.data.location_id || null
  });
  if (!resolved) return;

  if (!resolved.selectedLocation) {
    return res.json({
      orders: [],
      location: null,
      available_locations: [],
      can_switch_locations: resolved.canSwitchLocations,
      server_time: new Date().toISOString()
    });
  }

  const statuses = normalizeStatusList({
    statusGroup: parsed.data.status_group,
    statuses: parsed.data.statuses
  });

  if (req.user.role === 'prep' && statuses.some((status) => !PREP_VIEWABLE_STATUSES.includes(status))) {
    return res.status(403).json({ error: 'Prep employees can only view active and completed orders for their assigned cart.' });
  }

  // Completed tickets are read newest-first (so the limit captures the most
  // recent orders for the "Completed" filter); active tickets keep the
  // received order so cards stay in place as they advance.
  const completedOnly = statuses.length > 0 && statuses.every((status) => status === 'completed');

  const orderQuery = supabase
    .from('orders')
    .select('id,order_number,customer_id,location_id,order_channel,fulfillment_type,status,payment_status,requested_fulfillment_at,subtotal_ex_vat,vat_amount,discount_amount,delivery_fee,total_amount,customer_notes,internal_notes,customer_address_snapshot,customer_phone_snapshot,created_at,confirmed_at,preparing_at,ready_at,completed_at,updated_at, customers(full_name,phone), locations(id,name,type,compound_name,beach_name,is_active), payments(id,status,created_at,updated_at)')
    .eq('location_id', resolved.selectedLocation.id)
    .eq('payment_status', 'paid')
    .in('status', statuses);

  const orderResult = await (completedOnly
    ? orderQuery.order('completed_at', { ascending: false, nullsFirst: false }).limit(200)
    : orderQuery.order('created_at', { ascending: true }).limit(200));

  if (orderResult.error) return res.status(400).json({ error: orderResult.error.message });

  const orders = orderResult.data || [];
  const orderIds = orders.map((order) => order.id);

  if (!orderIds.length) {
    return res.json({
      orders: [],
      location: compactLocation(resolved.selectedLocation),
      available_locations: resolved.locations.map(compactLocation),
      selected_location_id: resolved.selectedLocation.id,
      can_switch_locations: resolved.canSwitchLocations,
      server_time: new Date().toISOString()
    });
  }

  const itemResult = await supabase
    .from('order_items')
    .select('*, products(id,name,name_ar,product_type,image_url,prep_time_minutes), product_variants(id,name,name_ar,serving_count)')
    .in('order_id', orderIds)
    .order('created_at', { ascending: true });

  if (itemResult.error) return res.status(400).json({ error: itemResult.error.message });

  const itemRows = itemResult.data || [];
  const itemIds = itemRows.map((item) => item.id);

  let removedRows = [];
  let additionRows = [];
  let componentRows = [];

  if (itemIds.length) {
    const [removedResult, additionsResult, componentsResult] = await Promise.all([
      supabase
        .from('order_item_removed_ingredients')
        .select('*')
        .in('order_item_id', itemIds)
        .order('created_at', { ascending: true }),
      supabase
        .from('order_item_additions')
        .select('*')
        .in('order_item_id', itemIds)
        .order('created_at', { ascending: true }),
      supabase
        .from('order_item_inventory_components')
        .select('*')
        .in('order_item_id', itemIds)
        .order('created_at', { ascending: true })
    ]);

    if (removedResult.error) return res.status(400).json({ error: removedResult.error.message });
    if (additionsResult.error) return res.status(400).json({ error: additionsResult.error.message });
    if (componentsResult.error) return res.status(400).json({ error: componentsResult.error.message });

    removedRows = removedResult.data || [];
    additionRows = additionsResult.data || [];
    componentRows = componentsResult.data || [];
  }

  let recipesById;
  let recipeItemsByRecipeId;
  try {
    const recipeContext = await loadRecipeContext({ itemRows, additionRows });
    recipesById = recipeContext.recipesById;
    recipeItemsByRecipeId = recipeContext.recipeItemsByRecipeId;
  } catch (error) {
    return res.status(400).json({ error: error.message });
  }

  const removedByItemId = groupBy(removedRows, 'order_item_id');
  const additionsByItemId = groupBy(additionRows, 'order_item_id');
  const componentsByItemId = groupBy(componentRows, 'order_item_id');
  const itemsByOrderId = groupBy(itemRows.map((item) => enrichOrderItem({
    item,
    removedByItemId,
    additionsByItemId,
    componentsByItemId,
    recipesById,
    recipeItemsByRecipeId
  })), 'order_id');

  const publicOrders = orders
    .map((order) => publicOperationalOrder({
      order,
      items: itemsByOrderId.get(order.id) || [],
      isPrep: req.user.role === 'prep'
    }))
    .sort((a, b) => new Date(a.confirmed_at || a.created_at || 0) - new Date(b.confirmed_at || b.created_at || 0));

  res.json({
    orders: publicOrders,
    location: compactLocation(resolved.selectedLocation),
    available_locations: resolved.locations.map(compactLocation),
    selected_location_id: resolved.selectedLocation.id,
    can_switch_locations: resolved.canSwitchLocations,
    server_time: new Date().toISOString()
  });
});

orderRouter.patch('/cart-operations/orders/:id/status', requireArea('orders'), async (req, res) => {
  const parsed = z.object({
    status: z.enum(['preparing', 'ready', 'completed'])
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid order status update.' });

  const existing = await sb(
    supabase
      .from('orders')
      .select('id,order_number,status,payment_status,customer_id,location_id,fulfillment_type')
      .eq('id', req.params.id)
      .single(),
    res
  );
  if (!existing) return;

  const resolved = await resolveCartOperationLocation({
    req,
    res,
    requestedLocationId: existing.location_id
  });
  if (!resolved) return;

  if (existing.payment_status !== 'paid') {
    return res.status(409).json({
      error: `Order ${existing.order_number || existing.id} cannot be prepared until payment is complete.`
    });
  }

  const allowedNextStatuses = operationTransitionsFor(req.user, existing.status);
  if (!allowedNextStatuses.includes(parsed.data.status)) {
    return res.status(409).json({
      error: `Order ${existing.order_number || existing.id} cannot move from ${existing.status} to ${parsed.data.status}.`
    });
  }

  // A cart pickup is released by the customer's code, not by a button — see the
  // pickup handoff routes below. Everything up to `ready` still moves from
  // here, and admins keep PATCH /orders/:id as break-glass.
  if (parsed.data.status === 'completed' && existing.fulfillment_type === 'pickup_at_cart') {
    return res.status(409).json({
      code: 'scan_required',
      error: `Order ${existing.order_number || existing.id} is collected by scanning the customer's pickup code.`
    });
  }

  const updatedOrder = await supabase
    .rpc('transition_cart_order_status', {
      p_order_id: req.params.id,
      p_expected_status: existing.status,
      p_next_status: parsed.data.status
    })
    .maybeSingle();

  if (updatedOrder.error) return res.status(400).json({ error: updatedOrder.error.message });
  if (!updatedOrder.data) {
    return res.status(409).json({
      error: `Order ${existing.order_number || existing.id} was already updated on another screen.`
    });
  }

  const data = updatedOrder.data;

  await notifyOrderReadyForPickup({
    order: data,
    previousStatus: existing.status
  });

  res.json({
    id: data.id,
    order_number: data.order_number,
    status: data.status,
    updated_at: data.updated_at
  });
});

// ---------------------------------------------------------------------------
// Pickup handoff — the scan gate on `ready` → `completed`
//
// A pickup order is released by proving the customer is the one collecting it:
// the app shows a short-lived code (lib/pickupToken.js), the attendant scans it
// or types its six digits, reviews the bag against what comes back, and
// confirms. `PATCH /cart-operations/orders/:id/status` no longer accepts
// `completed` for a pickup order, so this is the only routine way through.
//
// Scanning and completing are two calls on purpose. The scan proves the right
// *customer*; only a human looking in the bag proves the right *order*, and
// collapsing them into one tap would close the order before anyone had looked.
// ---------------------------------------------------------------------------

const PICKUP_OVERRIDE_ROLES = ['supervisor', 'manager', 'admin'];
const PICKUP_OVERRIDE_REASONS = ['dead_phone', 'no_app', 'app_error', 'staff_error', 'other'];

// Answers the request and returns null, so every guard below reads as
// `if (!x) return;` at the call site. `code` is what the scanner switches on;
// `error` is what the attendant reads.
function pickupProblem(res, { status, code, error, ...rest }) {
  res.status(status).json({ ok: false, code, error, ...rest });
  return null;
}

function staffLabelFor(user) {
  return user?.name || user?.username || 'Unknown staff';
}

async function loadPickupOrder(orderId) {
  return supabase
    .from('orders')
    .select('id,order_number,status,payment_status,fulfillment_type,location_id,customer_id,customer_notes,customer_phone_snapshot,ready_at,completed_at,customers(full_name,phone),locations(id,name,type,compound_name,beach_name,is_active)')
    .eq('id', orderId)
    .maybeSingle();
}

// Deliberately lighter than publicOperationalOrder: this is the "is this the
// right bag" panel, so it carries what an attendant reads off a phone in one
// glance and none of the recipe detail the prep screens need.
async function pickupOrderCard(order) {
  // `serving_count` and `product_image_url` are not columns on `order_items` —
  // they are derived from the joined variant and product, the same way
  // `enrichOrderItem` does it for the operational feed. Asking for them as
  // columns is a 42703 from Postgres, which reaches the attendant as an
  // untranslatable `lookup_failed` in the middle of a handover.
  const items = await supabase
    .from('order_items')
    .select('id,product_name_snapshot,variant_name_snapshot,quantity,customization_summary,products(image_url),product_variants(serving_count)')
    .eq('order_id', order.id)
    .order('created_at', { ascending: true });

  if (items.error) throw items.error;

  const rows = items.data || [];

  return {
    id: order.id,
    order_number: order.order_number,
    status: order.status,
    fulfillment_type: order.fulfillment_type,
    location: compactLocation(order.locations),
    customer: {
      name: order.customers?.full_name || 'Walk-in Customer',
      phone_last4: String(order.customer_phone_snapshot || order.customers?.phone || '').replace(/\D/g, '').slice(-4) || null
    },
    customer_notes: order.customer_notes || null,
    ready_at: order.ready_at || null,
    completed_at: order.completed_at || null,
    item_count: rows.reduce((sum, item) => sum + Number(item.quantity || 0), 0),
    items: rows.map((item) => ({
      id: item.id,
      product_name_snapshot: item.product_name_snapshot,
      variant_name_snapshot: item.variant_name_snapshot,
      quantity: item.quantity,
      serving_count: item.product_variants?.serving_count || 1,
      customization_summary: item.customization_summary,
      product_image_url: item.products?.image_url || null
    }))
  };
}

// Who released an order, for the "already collected" message. Best effort: the
// handoff log is young, and an order completed before this feature shipped has
// no row.
async function lastHandoffFor(orderId) {
  const handoff = await supabase
    .from('order_handoffs')
    .select('staff_label,method,created_at')
    .eq('order_id', orderId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  return handoff.error ? null : handoff.data;
}

/**
 * Turns whatever the attendant presented — a scanned token, or an order number
 * plus six digits — into the order it names, or sends the error and returns
 * null. Shared by verify and confirm so the two can never disagree about what
 * a code means.
 */
async function resolvePresentedPickup({ res, body, location }) {
  if (body.token) {
    const decoded = decodePickupToken(body.token);

    if (!decoded.ok) {
      return pickupProblem(res, decoded.reason === 'expired'
        ? {
          status: 409,
          code: 'expired',
          error: 'That code has expired. Ask the customer to refresh their screen, then scan again.'
        }
        : {
          status: 400,
          code: 'unrecognized',
          error: 'That is not an EBTL pickup code.'
        });
    }

    return { orderId: decoded.order_id, nonce: decoded.nonce, method: 'qr' };
  }

  // The typed fallback. The digits alone do not name an order, so the attendant
  // supplies the order number too, and it is looked up at their own cart only.
  const orderNumber = String(body.order_number || '').trim().replace(/^#/, '');

  const candidates = await supabase
    .from('orders')
    .select('id')
    .eq('order_number', orderNumber)
    .eq('location_id', location.id)
    .eq('fulfillment_type', 'pickup_at_cart')
    .in('status', ['ready', 'completed']);

  if (candidates.error) {
    return pickupProblem(res, { status: 400, code: 'lookup_failed', error: candidates.error.message });
  }

  const rows = candidates.data || [];

  if (rows.length !== 1) {
    // Order numbers reset every Cairo business date, so a stale one from
    // yesterday finds nothing and a repeat finds two. Neither is safe to guess.
    return pickupProblem(res, {
      status: 404,
      code: 'unknown_order',
      error: rows.length
        ? `More than one order at this cart is numbered ${orderNumber}. Scan the code instead.`
        : `No order numbered ${orderNumber} is waiting at this cart.`
    });
  }

  const verified = verifyPickupShortCode({ orderId: rows[0].id, shortCode: body.short_code });

  if (!verified) {
    return pickupProblem(res, {
      status: 409,
      code: 'code_mismatch',
      error: 'Those digits do not match a current code for that order. Ask the customer to refresh their screen.'
    });
  }

  return { orderId: rows[0].id, nonce: verified.nonce, method: 'short_code' };
}

/**
 * Everything that has to be true before an order can be released, in the order
 * an attendant would ask it. Returns the order, or sends the error and null.
 */
async function pickupOrderReadyForHandoff({ res, orderId, location }) {
  const order = await loadPickupOrder(orderId);

  if (order.error) {
    return pickupProblem(res, { status: 400, code: 'lookup_failed', error: order.error.message });
  }

  if (!order.data) {
    return pickupProblem(res, { status: 404, code: 'unknown_order', error: 'That order no longer exists.' });
  }

  if (order.data.fulfillment_type !== 'pickup_at_cart') {
    return pickupProblem(res, {
      status: 409,
      code: 'not_pickup',
      error: `Order ${order.data.order_number} is a delivery, not a cart pickup.`
    });
  }

  if (order.data.location_id !== location.id) {
    return pickupProblem(res, {
      status: 409,
      code: 'wrong_location',
      error: `Order ${order.data.order_number} belongs to ${order.data.locations?.name || 'another cart'}.`
    });
  }

  if (order.data.status === 'completed') {
    const handoff = await lastHandoffFor(order.data.id);
    return pickupProblem(res, {
      status: 409,
      code: 'already_collected',
      error: handoff
        ? `Order ${order.data.order_number} was already collected — released by ${handoff.staff_label}.`
        : `Order ${order.data.order_number} has already been collected.`,
      handoff: handoff || null
    });
  }

  if (order.data.payment_status !== 'paid') {
    return pickupProblem(res, {
      status: 409,
      code: 'unpaid',
      error: `Order ${order.data.order_number} is not paid for yet.`
    });
  }

  if (order.data.status !== 'ready') {
    return pickupProblem(res, {
      status: 409,
      code: 'not_ready',
      error: `Order ${order.data.order_number} is still ${String(order.data.status).replaceAll('_', ' ')}.`
    });
  }

  return order.data;
}

/**
 * Completes the order and writes the handoff row.
 *
 * The transition runs first: its compare-and-swap is the real guard against a
 * double handoff, and it is the thing that must not happen twice. The log
 * follows. If the log write fails the order is still legitimately collected —
 * refusing at that point would leave a customer holding their kit and an
 * attendant looking at an error — so it answers `logged: false` and says so
 * rather than pretending either way.
 */
async function releasePickupOrder({ res, order, user, location, method, nonce = null, reasonCode = null }) {
  const transitioned = await supabase
    .rpc('transition_cart_order_status', {
      p_order_id: order.id,
      p_expected_status: 'ready',
      p_next_status: 'completed'
    })
    .maybeSingle();

  if (transitioned.error) {
    return pickupProblem(res, { status: 400, code: 'transition_failed', error: transitioned.error.message });
  }

  if (!transitioned.data) {
    return pickupProblem(res, {
      status: 409,
      code: 'already_collected',
      error: `Order ${order.order_number} was released on another screen a moment ago.`
    });
  }

  const logged = await supabase.from('order_handoffs').insert({
    order_id: order.id,
    location_id: location.id,
    employee_id: user?.employee_id || null,
    staff_label: staffLabelFor(user),
    method,
    reason_code: reasonCode,
    token_nonce: nonce
  });

  if (logged.error) console.error('Handed over order without writing the handoff log', logged.error);

  return { order: transitioned.data, logged: !logged.error };
}

const presentedPickupSchema = z.union([
  z.object({ token: z.string().min(1).max(200) }),
  z.object({
    order_number: z.string().min(1).max(20),
    short_code: z.string().min(1).max(12)
  })
]);

orderRouter.post('/cart-operations/pickups/verify', requireArea('orders'), pickupAttemptLimiter, async (req, res) => {
  const parsed = presentedPickupSchema.safeParse(req.body);
  if (!parsed.success) {
    return pickupProblem(res, { status: 400, code: 'invalid_request', error: 'Scan a code, or enter an order number and its six digits.' });
  }

  const resolved = await resolveCartOperationLocation({ req, res });
  if (!resolved) return;

  const presented = await resolvePresentedPickup({ res, body: parsed.data, location: resolved.selectedLocation });
  if (!presented) return;

  const order = await pickupOrderReadyForHandoff({
    res,
    orderId: presented.orderId,
    location: resolved.selectedLocation
  });
  if (!order) return;

  try {
    res.json({
      ok: true,
      method: presented.method,
      order: await pickupOrderCard(order)
    });
  } catch (error) {
    pickupProblem(res, { status: 400, code: 'lookup_failed', error: error.message });
  }
});

orderRouter.post('/cart-operations/pickups/confirm', requireArea('orders'), pickupAttemptLimiter, async (req, res) => {
  const parsed = presentedPickupSchema.safeParse(req.body);
  if (!parsed.success) {
    return pickupProblem(res, { status: 400, code: 'invalid_request', error: 'Scan a code, or enter an order number and its six digits.' });
  }

  const resolved = await resolveCartOperationLocation({ req, res });
  if (!resolved) return;

  // Re-checked rather than trusted from the verify call: the code may have
  // expired, and the order may have moved, in the seconds the attendant spent
  // looking in the bag.
  const presented = await resolvePresentedPickup({ res, body: parsed.data, location: resolved.selectedLocation });
  if (!presented) return;

  const order = await pickupOrderReadyForHandoff({
    res,
    orderId: presented.orderId,
    location: resolved.selectedLocation
  });
  if (!order) return;

  const released = await releasePickupOrder({
    res,
    order,
    user: req.user,
    location: resolved.selectedLocation,
    method: presented.method,
    nonce: presented.nonce
  });
  if (!released) return;

  res.json({
    ok: true,
    method: presented.method,
    logged: released.logged,
    order: {
      id: released.order.id,
      order_number: released.order.order_number,
      status: released.order.status,
      completed_at: released.order.completed_at || null,
      updated_at: released.order.updated_at
    }
  });
});

// The last resort: a customer who cannot produce a code at all — a dead
// battery, or an app reinstalled since they ordered, which wipes the anonymous
// session the order lives on. The reason is mandatory because the rate of these
// is the number that says whether the whole process is working.
orderRouter.post('/cart-operations/pickups/override', requireArea('orders'), pickupAttemptLimiter, async (req, res) => {
  const parsed = z.object({
    order_id: z.string().uuid(),
    reason_code: z.enum(PICKUP_OVERRIDE_REASONS),
    phone_last4: z.string().regex(/^\d{4}$/).optional()
  }).safeParse(req.body);

  if (!parsed.success) {
    return pickupProblem(res, { status: 400, code: 'invalid_request', error: 'Pick an order and a reason for the override.' });
  }

  const resolved = await resolveCartOperationLocation({ req, res });
  if (!resolved) return;

  const isPrivileged = PICKUP_OVERRIDE_ROLES.includes(req.user?.role);
  if (!isPrivileged && req.user?.role !== 'cart_operator') {
    return pickupProblem(res, {
      status: 403,
      code: 'not_allowed',
      error: 'Overrides are for cart operators and supervisors.'
    });
  }

  const order = await pickupOrderReadyForHandoff({
    res,
    orderId: parsed.data.order_id,
    location: resolved.selectedLocation
  });
  if (!order) return;

  // Checking the phone is what keeps an override an identity check rather than
  // a free pass. It is skipped only when the order has no phone to check.
  const expectedLast4 = String(order.customer_phone_snapshot || order.customers?.phone || '').replace(/\D/g, '').slice(-4);

  if (expectedLast4 && parsed.data.phone_last4 !== expectedLast4) {
    return pickupProblem(res, {
      status: 409,
      code: 'phone_mismatch',
      error: parsed.data.phone_last4
        ? 'Those last four digits do not match the phone on this order.'
        : 'Confirm the last four digits of the phone on this order.'
    });
  }

  const released = await releasePickupOrder({
    res,
    order,
    user: req.user,
    location: resolved.selectedLocation,
    method: 'override',
    reasonCode: parsed.data.reason_code
  });
  if (!released) return;

  res.json({
    ok: true,
    method: 'override',
    logged: released.logged,
    order: {
      id: released.order.id,
      order_number: released.order.order_number,
      status: released.order.status,
      completed_at: released.order.completed_at || null,
      updated_at: released.order.updated_at
    }
  });
});

orderRouter.get('/orders', requireArea('orders'), requireGlobalOrderAccess, async (_req, res) => {
  const [orders, items, removedIngredients, additions, locations] = await Promise.all([
    supabase.from('orders').select('*, customers(full_name,phone), locations(name,type,compound_name)').order('created_at', { ascending: false }).limit(100),
    supabase.from('order_items').select('*').order('id'),
    supabase.from('order_item_removed_ingredients').select('*').order('created_at'),
    supabase.from('order_item_additions').select('*').order('created_at'),
    supabase.from('locations').select('*').order('name')
  ]);
  for (const result of [orders, items, removedIngredients, additions, locations]) if (result.error) return res.status(400).json({ error: result.error.message });
  res.json({
    orders: orders.data,
    items: items.data,
    removedIngredients: removedIngredients.data,
    additions: additions.data,
    locations: locations.data
  });
});

orderRouter.patch('/orders/:id', requireArea('orders'), requireGlobalOrderAccess, async (req, res) => {
  const parsed = z.object({ status: z.enum(orderStatuses).optional(), payment_status: z.enum(paymentStatuses).optional(), internal_notes: z.string().optional() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid order update' });

  const existing = await sb(
    supabase
      .from('orders')
      .select('id,order_number,status,customer_id')
      .eq('id', req.params.id)
      .single(),
    res
  );
  if (!existing) return;

  const data = await sb(
    supabase
      .from('orders')
      .update(clean(parsed.data))
      .eq('id', req.params.id)
      .select()
      .single(),
    res
  );

  if (!data) return;

  if (parsed.data.status && parsed.data.status !== existing.status) {
    await notifyOrderReadyForPickup({
      order: data,
      previousStatus: existing.status
    });
  }

  res.json(data);
});
