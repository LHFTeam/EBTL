// Turns orders into the demand facts the model learns from.
//
// The model never reads `orders` directly. Everything it knows comes from
// forecast_demand_daily_* , which means: one definition of "a sale" (here, in
// one place), a rebuild that replays deterministically, and no risk that a
// future change to order-status semantics silently rewrites history the model
// has already learned from.

import { cartUplift, deflateToBaseline, productUplifts } from './campaigns.js';
import { dateRange, dayOfWeek } from './businessDate.js';
import { loadOrdersForRange } from './store.js';

// Whether a cart was open on a date.
//
// This is the least satisfying judgement in the module, and it matters: a
// closed day treated as zero demand drags the level down for every cart that
// takes a day off, while a genuine zero-demand day ignored pushes it up.
//
// cart_daily_openings is the table that should answer this and is empty in
// production, so the rule is:
//
//   - the weekday is marked closed in location_opening_hours  -> not trading
//   - the date precedes the cart's first ever sale            -> not trading
//   - otherwise                                                -> trading
//
// The first-sale cutoff is the standard treatment for intermittent demand
// series: leading zeros before an item was ever stocked are absence of a
// product, not absence of demand, and counting them would put every new cart in
// a hole it climbs out of for months. Once a cart has sold something, a zero day
// inside its operating span is real evidence and is kept.
//
// Populating cart_daily_openings would remove the guess entirely; the
// cart-operations flow already has the concept.
export function wasTrading({ dateKey, locationId, closedWeekdays, firstSaleByLocation }) {
  const closed = closedWeekdays.get(locationId);
  if (closed && closed.has(dayOfWeek(dateKey))) return false;

  const firstSale = firstSaleByLocation.get(locationId);
  if (!firstSale || dateKey < firstSale) return false;

  return true;
}

// Build one date's facts for every cart.
//
// `applied_uplift` is the campaign lift divided back out to get baseline_units.
// Storing both the raw and the deflated figure keeps the base/lift split of any
// past day inspectable rather than implicit in a state number nobody can see.
export function buildFactsForDate({
  dateKey,
  carts,
  ordersByCartDate,
  campaigns,
  effects,
  closedWeekdays,
  firstSaleByLocation
}) {
  const cartRows = [];
  const productRows = [];

  for (const cart of carts) {
    const bucket = ordersByCartDate.get(`${cart.id}::${dateKey}`) || {
      units: 0,
      orders: 0,
      revenue: 0,
      promoOrders: 0,
      discountPctSum: 0,
      unitsByProduct: new Map(),
      revenueByProduct: new Map()
    };

    const traded = wasTrading({ dateKey, locationId: cart.id, closedWeekdays, firstSaleByLocation });

    const { uplift } = cartUplift(campaigns, cart.id, dateKey, effects);
    const perProductUplift = productUplifts(campaigns, cart.id, dateKey, effects);

    cartRows.push({
      location_id: cart.id,
      business_date: dateKey,
      units: bucket.units,
      orders: bucket.orders,
      revenue: Number(bucket.revenue.toFixed(2)),
      traded,
      promo_orders: bucket.promoOrders,
      promo_order_share: bucket.orders ? Number((bucket.promoOrders / bucket.orders).toFixed(4)) : 0,
      mean_discount_pct: bucket.orders ? Number((bucket.discountPctSum / bucket.orders).toFixed(3)) : 0,
      applied_uplift: Number(uplift.toFixed(4)),
      baseline_units: Number(deflateToBaseline(bucket.units, uplift).toFixed(3)),
      ingested_at: new Date().toISOString()
    });

    for (const [productId, units] of bucket.unitsByProduct) {
      // A product-targeted campaign lifts the mix; a cart-wide one lifts volume.
      // Both have to come out of a product's baseline, or the product keeps an
      // inflated share after the campaign ends.
      const productLift = uplift * (perProductUplift.get(productId) || 1);
      productRows.push({
        location_id: cart.id,
        business_date: dateKey,
        product_id: productId,
        units,
        revenue: Number((bucket.revenueByProduct.get(productId) || 0).toFixed(2)),
        applied_uplift: Number(productLift.toFixed(4)),
        baseline_units: Number(deflateToBaseline(units, productLift).toFixed(3)),
        ingested_at: new Date().toISOString()
      });
    }
  }

  return { cartRows, productRows };
}

// Group raw orders into per-cart-per-date buckets.
//
// Discount depth is measured per order as a share of what the order would have
// cost undiscounted, so a 50 EGP discount on a 100 EGP order and on a 1000 EGP
// order are not treated as the same promotional pressure.
export function groupOrders({ orders, itemsByOrder, redeemedOrderIds }) {
  const buckets = new Map();
  const firstSaleByLocation = new Map();

  for (const order of orders) {
    const key = `${order.location_id}::${order.business_date}`;
    if (!buckets.has(key)) {
      buckets.set(key, {
        units: 0,
        orders: 0,
        revenue: 0,
        promoOrders: 0,
        discountPctSum: 0,
        unitsByProduct: new Map(),
        revenueByProduct: new Map()
      });
    }
    const bucket = buckets.get(key);

    const items = itemsByOrder.get(order.id) || [];
    const units = items.reduce((sum, item) => sum + item.quantity, 0);

    bucket.orders += 1;
    bucket.units += units;
    bucket.revenue += Number(order.total_amount) || 0;

    const discount = Number(order.discount_amount) || 0;
    const total = Number(order.total_amount) || 0;
    const gross = total + discount;
    if (gross > 0) bucket.discountPctSum += (discount / gross) * 100;

    // A code that was redeemed is the signal, not a code that merely existed:
    // orders.discount_amount catches promotions applied without a redemption row.
    if (redeemedOrderIds.has(order.id) || discount > 0) bucket.promoOrders += 1;

    for (const item of items) {
      if (!item.product_id) continue;
      bucket.unitsByProduct.set(item.product_id, (bucket.unitsByProduct.get(item.product_id) || 0) + item.quantity);
      bucket.revenueByProduct.set(item.product_id, (bucket.revenueByProduct.get(item.product_id) || 0) + item.line_total);
    }

    const seen = firstSaleByLocation.get(order.location_id);
    if (!seen || order.business_date < seen) firstSaleByLocation.set(order.location_id, order.business_date);
  }

  return { buckets, firstSaleByLocation };
}

// Ingest a whole range. Returns the facts rather than writing them, so job.js
// controls transaction-shaped ordering and the pure part stays testable.
export async function ingestRange({ from, to, carts, campaigns, effects, closedWeekdays, knownFirstSales }) {
  const raw = await loadOrdersForRange(from, to);
  const { buckets, firstSaleByLocation: inRange } = groupOrders(raw);

  // Merge what this range revealed with what was already known. An incremental
  // run sees only a day or two of orders, so without the known dates every
  // established cart would look like it had just opened.
  const firstSaleByLocation = new Map(knownFirstSales || []);
  for (const [locationId, dateKey] of inRange) {
    const known = firstSaleByLocation.get(locationId);
    if (!known || dateKey < known) firstSaleByLocation.set(locationId, dateKey);
  }

  const cartRows = [];
  const productRows = [];

  for (const dateKey of dateRange(from, to)) {
    const built = buildFactsForDate({
      dateKey,
      carts,
      ordersByCartDate: buckets,
      campaigns,
      effects,
      closedWeekdays,
      firstSaleByLocation
    });
    cartRows.push(...built.cartRows);
    productRows.push(...built.productRows);
  }

  return { cartRows, productRows, firstSaleByLocation };
}
