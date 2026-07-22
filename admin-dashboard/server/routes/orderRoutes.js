import { Router } from 'express';
import { z } from 'zod';
import { orderStatuses, paymentStatuses } from '../config/appConfig.js';
import { requireArea } from '../middleware/auth.js';
import { clean } from '../lib/objectUtils.js';
import { sb } from '../lib/supabaseResponse.js';
import { supabase } from '../lib/supabase.js';
import { notifyOrderReadyForPickup } from '../lib/notifications.js';

export const orderRouter = Router();

const CART_OPERATION_ROLES = ['prep', 'cart_operator', 'supervisor', 'manager', 'admin'];
const CART_LOCATION_SWITCH_ROLES = ['supervisor', 'manager', 'admin'];
const CART_OPERATION_STATUSES = ['confirmed', 'preparing', 'ready', 'completed'];
const ACTIVE_OPERATION_STATUSES = ['confirmed', 'preparing', 'ready'];
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
const ORDER_PREP_STATUS_BY_ORDER_STATUS = {
  preparing: 'in_progress',
  ready: 'packed',
  completed: 'packed'
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
  const paidPayment = paymentRows(order)
    .filter((payment) => payment.status === 'paid')
    .sort((a, b) => new Date(a.updated_at || a.created_at || 0) - new Date(b.updated_at || b.created_at || 0))[0];

  if (paidPayment?.raw_payload?.demo_confirmed_at) return paidPayment.raw_payload.demo_confirmed_at;
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
      .select('*, ingredients(id,name,base_unit,is_customer_supplied,allergen_flags)')
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

function publicOperationalOrder({ order, items }) {
  const confirmedAt = paymentConfirmedAt(order);
  const customerName = order.customers?.full_name || null;
  const customerPhone = order.customer_phone_snapshot || order.customers?.phone || null;
  const payments = paymentRows(order).sort((a, b) => new Date(b.updated_at || b.created_at || 0) - new Date(a.updated_at || a.created_at || 0));

  return {
    id: order.id,
    order_number: order.order_number,
    location_id: order.location_id,
    location: compactLocation(order.locations),
    order_channel: order.order_channel,
    fulfillment_type: order.fulfillment_type,
    status: order.status,
    payment_status: order.payment_status,
    requested_fulfillment_at: order.requested_fulfillment_at,
    subtotal_ex_vat: order.subtotal_ex_vat,
    vat_amount: order.vat_amount,
    discount_amount: order.discount_amount,
    delivery_fee: order.delivery_fee,
    total_amount: order.total_amount,
    customer_notes: order.customer_notes,
    internal_notes: order.internal_notes,
    customer_address_snapshot: order.customer_address_snapshot,
    customer_phone_snapshot: order.customer_phone_snapshot,
    created_at: order.created_at,
    updated_at: order.updated_at,
    confirmed_at: confirmedAt,
    customer: {
      name: customerName || 'Walk-in Customer',
      phone: customerPhone
    },
    latest_payment: payments[0] || null,
    item_count: items.reduce((sum, item) => sum + Number(item.quantity || 0), 0),
    items
  };
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

  const orderResult = await supabase
    .from('orders')
    .select('*, customers(full_name,phone), locations(id,name,type,compound_name,beach_name,is_active), payments(id,status,provider,amount,currency,created_at,updated_at,raw_payload)')
    .eq('location_id', resolved.selectedLocation.id)
    .in('status', statuses)
    .order('created_at', { ascending: true })
    .limit(200);

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
    .select('*, products(id,name,product_type,image_url,prep_time_minutes), product_variants(id,name,serving_count)')
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
    .map((order) => publicOperationalOrder({ order, items: itemsByOrderId.get(order.id) || [] }))
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
      .select('id,order_number,status,customer_id,location_id')
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

  const allowedNextStatuses = OPERATION_TRANSITIONS[existing.status] || [];
  if (!allowedNextStatuses.includes(parsed.data.status)) {
    return res.status(409).json({
      error: `Order ${existing.order_number || existing.id} cannot move from ${existing.status} to ${parsed.data.status}.`
    });
  }

  const data = await sb(
    supabase
      .from('orders')
      .update({ status: parsed.data.status })
      .eq('id', req.params.id)
      .eq('status', existing.status)
      .select()
      .single(),
    res
  );

  if (!data) return;

  const nextPrepStatus = ORDER_PREP_STATUS_BY_ORDER_STATUS[parsed.data.status];
  if (nextPrepStatus) {
    const itemUpdate = await supabase
      .from('order_items')
      .update({ prep_status: nextPrepStatus })
      .eq('order_id', req.params.id)
      .neq('prep_status', 'cancelled');

    if (itemUpdate.error) return res.status(400).json({ error: itemUpdate.error.message });
  }

  await notifyOrderReadyForPickup({
    order: data,
    previousStatus: existing.status
  });

  res.json(data);
});

orderRouter.get('/orders', requireArea('orders'), async (_req, res) => {
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

orderRouter.patch('/orders/:id', requireArea('orders'), async (req, res) => {
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
