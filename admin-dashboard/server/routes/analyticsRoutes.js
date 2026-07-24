import { Router } from 'express';
import { z } from 'zod';
import { requireArea } from '../middleware/auth.js';
import { supabase } from '../lib/supabase.js';

export const analyticsRouter = Router();

const BUSINESS_TIME_ZONE = 'Africa/Cairo';
const DAY_MS = 24 * 60 * 60 * 1000;

// Presets the client segmented control offers. `days` is the number of Cairo
// calendar days the window spans (today counts as 1).
const RANGE_PRESETS = {
  today: { label: 'Today', days: 1 },
  '7d': { label: 'Last 7 days', days: 7 },
  '30d': { label: 'Last 30 days', days: 30 },
  '90d': { label: 'Last 90 days', days: 90 }
};

// Orders that represent real, collected revenue.
const REVENUE_STATUSES = new Set(['confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed']);

// Milliseconds to add to a UTC instant to get Cairo wall-clock time, honouring
// whatever offset (incl. DST) is in effect at that instant.
function cairoOffsetMs(date) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: BUSINESS_TIME_ZONE,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  }).formatToParts(date).reduce((acc, part) => {
    acc[part.type] = part.value;
    return acc;
  }, {});

  const asUTC = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(parts.hour === '24' ? '0' : parts.hour),
    Number(parts.minute),
    Number(parts.second)
  );
  return asUTC - date.getTime();
}

// UTC Date for 00:00 Cairo time of the day `date` falls on.
function startOfCairoDay(date) {
  const offset = cairoOffsetMs(date);
  const wall = new Date(date.getTime() + offset);
  const midnightWall = Date.UTC(wall.getUTCFullYear(), wall.getUTCMonth(), wall.getUTCDate());
  return new Date(midnightWall - offset);
}

// 'YYYY-MM-DD' key for the Cairo day an instant belongs to.
function cairoDateKey(date) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: BUSINESS_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).format(date);
}

function resolveRange(rangeKey) {
  const preset = RANGE_PRESETS[rangeKey] || RANGE_PRESETS['7d'];
  const now = new Date();
  const todayStart = startOfCairoDay(now);
  const start = new Date(todayStart.getTime() - (preset.days - 1) * DAY_MS);
  const previousStart = new Date(start.getTime() - preset.days * DAY_MS);

  return {
    key: RANGE_PRESETS[rangeKey] ? rangeKey : '7d',
    label: preset.label,
    days: preset.days,
    start,
    end: now,
    previousStart
  };
}

function isRevenueOrder(order) {
  return order.payment_status === 'paid' && REVENUE_STATUSES.has(order.status);
}

function num(value) {
  return Number(value || 0);
}

function deltaPct(current, previous) {
  if (!previous) return current ? null : 0; // null => "new" (no baseline)
  return ((current - previous) / previous) * 100;
}

function summarize(orders) {
  const revenueOrders = orders.filter(isRevenueOrder);
  const revenue = revenueOrders.reduce((sum, order) => sum + num(order.total_amount), 0);
  const paidOrders = revenueOrders.length;
  const activeCustomers = new Set(revenueOrders.map((order) => order.customer_id).filter(Boolean)).size;
  return {
    revenue,
    paidOrders,
    avgOrderValue: paidOrders ? revenue / paidOrders : 0,
    activeCustomers
  };
}

function averageMinutes(orders, fromKey, toKey) {
  let total = 0;
  let count = 0;
  for (const order of orders) {
    if (!order[fromKey] || !order[toKey]) continue;
    const deltaMs = new Date(order[toKey]).getTime() - new Date(order[fromKey]).getTime();
    if (deltaMs < 0) continue;
    total += deltaMs;
    count += 1;
  }
  return { minutes: count ? total / count / 60000 : null, sampleSize: count };
}

analyticsRouter.get('/analytics', requireArea('analytics'), async (req, res) => {
  const parsed = z.object({
    range: z.enum(['today', '7d', '30d', '90d']).optional()
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid analytics range.' });

  const range = resolveRange(parsed.data.range);

  // Pull orders across the current AND previous window (for deltas) in one query.
  const ordersResult = await supabase
    .from('orders')
    .select('id,status,payment_status,fulfillment_type,total_amount,location_id,customer_id,created_at,confirmed_at,preparing_at,ready_at,completed_at, locations(id,name,type)')
    .gte('created_at', range.previousStart.toISOString())
    .order('created_at', { ascending: true })
    .limit(10000);

  if (ordersResult.error) return res.status(400).json({ error: ordersResult.error.message });

  const allOrders = ordersResult.data || [];
  const startMs = range.start.getTime();
  const current = allOrders.filter((order) => new Date(order.created_at).getTime() >= startMs);
  const previous = allOrders.filter((order) => new Date(order.created_at).getTime() < startMs);

  const currentSummary = summarize(current);
  const previousSummary = summarize(previous);

  // New customers (signups) in each window.
  const customersResult = await supabase
    .from('customers')
    .select('id,created_at')
    .gte('created_at', range.previousStart.toISOString())
    .limit(10000);

  if (customersResult.error) return res.status(400).json({ error: customersResult.error.message });

  const newCustomersCurrent = (customersResult.data || []).filter((c) => new Date(c.created_at).getTime() >= startMs).length;
  const newCustomersPrevious = (customersResult.data || []).length - newCustomersCurrent;

  // Daily revenue/orders trend across the current window.
  const buckets = new Map();
  for (let i = 0; i < range.days; i += 1) {
    const dayStart = new Date(range.start.getTime() + i * DAY_MS);
    const key = cairoDateKey(dayStart);
    buckets.set(key, { date: key, revenue: 0, orders: 0 });
  }
  for (const order of current) {
    if (!isRevenueOrder(order)) continue;
    const key = cairoDateKey(new Date(order.created_at));
    const bucket = buckets.get(key);
    if (!bucket) continue;
    bucket.revenue += num(order.total_amount);
    bucket.orders += 1;
  }
  const revenueTrend = [...buckets.values()];

  // Order status breakdown (all current orders, any payment state).
  const statusCounts = new Map();
  for (const order of current) {
    statusCounts.set(order.status, (statusCounts.get(order.status) || 0) + 1);
  }
  const statusBreakdown = [...statusCounts.entries()]
    .map(([status, count]) => ({ status, count }))
    .sort((a, b) => b.count - a.count);

  // Fulfillment type split (revenue orders only).
  const typeSplitMap = new Map();
  for (const order of current.filter(isRevenueOrder)) {
    const type = order.fulfillment_type || 'unknown';
    const entry = typeSplitMap.get(type) || { type, orders: 0, revenue: 0 };
    entry.orders += 1;
    entry.revenue += num(order.total_amount);
    typeSplitMap.set(type, entry);
  }
  const fulfillmentTypeSplit = [...typeSplitMap.values()].sort((a, b) => b.orders - a.orders);

  // Fulfillment speed, using the lifecycle timestamps.
  const speed = {
    queueWait: averageMinutes(current, 'confirmed_at', 'preparing_at'),
    prepTime: averageMinutes(current, 'preparing_at', 'ready_at'),
    handoff: averageMinutes(current, 'ready_at', 'completed_at'),
    total: averageMinutes(current, 'confirmed_at', 'completed_at')
  };

  // Revenue by location (revenue orders only).
  const locationMap = new Map();
  for (const order of current.filter(isRevenueOrder)) {
    const id = order.location_id || 'unknown';
    const entry = locationMap.get(id) || {
      location: order.locations?.name || 'Unassigned',
      type: order.locations?.type || null,
      orders: 0,
      revenue: 0
    };
    entry.orders += 1;
    entry.revenue += num(order.total_amount);
    locationMap.set(id, entry);
  }
  const revenueByLocation = [...locationMap.values()].sort((a, b) => b.revenue - a.revenue);

  // Top products, from the line items of the current revenue orders.
  const currentRevenueOrderIds = current.filter(isRevenueOrder).map((order) => order.id);
  let topProducts = [];
  if (currentRevenueOrderIds.length) {
    const itemsResult = await supabase
      .from('order_items')
      .select('product_id,product_name_snapshot,quantity,line_total,order_id')
      .in('order_id', currentRevenueOrderIds)
      .limit(20000);

    if (itemsResult.error) return res.status(400).json({ error: itemsResult.error.message });

    const productMap = new Map();
    for (const item of itemsResult.data || []) {
      const key = item.product_id || item.product_name_snapshot || 'unknown';
      const entry = productMap.get(key) || {
        name: item.product_name_snapshot || 'Unknown item',
        quantity: 0,
        revenue: 0
      };
      entry.quantity += num(item.quantity);
      entry.revenue += num(item.line_total);
      productMap.set(key, entry);
    }
    topProducts = [...productMap.values()]
      .sort((a, b) => b.revenue - a.revenue)
      .slice(0, 8);
  }

  // Operational / payment health across current orders.
  const totalCurrent = current.length;
  const cancelledOrders = current.filter((order) => order.status === 'cancelled').length;
  const refundedOrders = current.filter((order) => order.status === 'refunded').length;
  const completedOrders = current.filter((order) => order.status === 'completed').length;
  const paymentCounts = current.reduce((acc, order) => {
    acc[order.payment_status] = (acc[order.payment_status] || 0) + 1;
    return acc;
  }, {});

  const buildKpi = (currentValue, previousValue) => ({
    value: currentValue,
    previous: previousValue,
    deltaPct: deltaPct(currentValue, previousValue)
  });

  res.json({
    range: {
      key: range.key,
      label: range.label,
      days: range.days,
      start: range.start.toISOString(),
      end: range.end.toISOString(),
      previousStart: range.previousStart.toISOString(),
      time_zone: BUSINESS_TIME_ZONE
    },
    presets: Object.entries(RANGE_PRESETS).map(([key, value]) => ({ key, label: value.label })),
    kpis: {
      revenue: buildKpi(currentSummary.revenue, previousSummary.revenue),
      paidOrders: buildKpi(currentSummary.paidOrders, previousSummary.paidOrders),
      avgOrderValue: buildKpi(currentSummary.avgOrderValue, previousSummary.avgOrderValue),
      newCustomers: buildKpi(newCustomersCurrent, newCustomersPrevious),
      activeCustomers: buildKpi(currentSummary.activeCustomers, previousSummary.activeCustomers)
    },
    revenueTrend,
    statusBreakdown,
    fulfillment: {
      typeSplit: fulfillmentTypeSplit,
      speed
    },
    topProducts,
    revenueByLocation,
    health: {
      totalOrders: totalCurrent,
      completedOrders,
      cancelledOrders,
      refundedOrders,
      completionRate: totalCurrent ? (completedOrders / totalCurrent) * 100 : 0,
      cancellationRate: totalCurrent ? (cancelledOrders / totalCurrent) * 100 : 0,
      payments: paymentCounts
    },
    server_time: new Date().toISOString()
  });
});
