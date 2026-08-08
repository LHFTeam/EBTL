// Every Supabase read and write the forecasting module makes. Isolated here so
// the model, the campaign algebra and the maths stay pure and testable, and so
// the module's entire database footprint is one file you can read end to end.
//
// Uses the shared service-role client from ../lib/supabase.js — per AGENTS.md
// there is exactly one, and this module does not create another.
//
// Rows come back as plain objects with numbers already coerced: Postgres numeric
// arrives over PostgREST as a string, and a single missed Number() turns a
// multiplication into string concatenation somewhere deep in the recursion.
// Coercing once, at the boundary, is the only reliable place to do it.

import { supabase } from '../lib/supabase.js';
import { MODEL_VERSION } from './config.js';
import { cairoDayBoundsUtc } from './businessDate.js';

// Orders that represent demand we actually served. Mirrors the definition in
// analyticsRoutes.js deliberately — if the two ever disagree, the dashboard and
// the forecast are describing different businesses.
//
// draft / pending_payment / expired / cancelled / refunded are all excluded:
// none of them is a kit that left a cart.
const REVENUE_STATUSES = ['confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed'];

const CHUNK = 500;

function num(value) {
  return Number(value || 0);
}

function numArray(value, length, fallback) {
  const source = Array.isArray(value) ? value : [];
  return Array.from({ length }, (_, i) => {
    const parsed = Number(source[i]);
    return Number.isFinite(parsed) ? parsed : fallback;
  });
}

// PostgREST has request-size limits and `.in()` builds a URL, so anything keyed
// by a list of ids is chunked rather than sent whole.
async function inChunks(items, size, handler) {
  const results = [];
  for (let i = 0; i < items.length; i += size) {
    results.push(await handler(items.slice(i, i + size)));
  }
  return results;
}

function unwrap(result, context) {
  if (result.error) throw new Error(`${context}: ${result.error.message}`);
  return result.data || [];
}

// --------------------------------------------------------------------------
// Catalogue
// --------------------------------------------------------------------------

export async function loadBeachCarts() {
  const rows = unwrap(
    await supabase
      .from('locations')
      .select('id,name,type,is_active')
      .eq('type', 'beach_cart')
      .order('name'),
    'load beach carts'
  );
  return rows;
}

export async function loadActiveProducts() {
  return unwrap(
    await supabase
      .from('products')
      .select('id,name,product_type,status')
      .eq('status', 'active')
      .order('name'),
    'load active products'
  );
}

// Which weekdays each cart is shut. cart_daily_openings would be the right
// source but is empty in production, so opening hours are the available proxy —
// see the `traded` note in ingest.js.
export async function loadClosedWeekdays() {
  const rows = unwrap(
    await supabase
      .from('location_opening_hours')
      .select('location_id,day_of_week,is_closed'),
    'load opening hours'
  );

  const closed = new Map();
  for (const row of rows) {
    if (!row.is_closed) continue;
    if (!closed.has(row.location_id)) closed.set(row.location_id, new Set());
    closed.get(row.location_id).add(Number(row.day_of_week));
  }
  return closed;
}

// --------------------------------------------------------------------------
// Source data for ingest
// --------------------------------------------------------------------------

// Revenue orders across a range of Cairo business dates, with their line items
// and any promo redemptions.
//
// business_date is filtered on directly (it is a real column, defaulted to the
// Cairo date) rather than reconstructed from created_at — an order placed at
// 00:30 Cairo belongs to the day the business says it does.
//
// Loaded as a range rather than per day so a rebuild over months is three
// queries plus chunking, not three per date.
export async function loadOrdersForRange(from, to) {
  const orders = unwrap(
    await supabase
      .from('orders')
      .select('id,location_id,business_date,status,payment_status,total_amount,discount_amount,subtotal_ex_vat')
      .gte('business_date', from)
      .lte('business_date', to)
      .eq('payment_status', 'paid')
      .in('status', REVENUE_STATUSES)
      .order('business_date', { ascending: true }),
    `load orders ${from}..${to}`
  );

  if (!orders.length) return { orders: [], itemsByOrder: new Map(), redeemedOrderIds: new Set() };

  const orderIds = orders.map((order) => order.id);

  const itemChunks = await inChunks(orderIds, CHUNK, (chunk) =>
    supabase
      .from('order_items')
      .select('order_id,product_id,quantity,line_total')
      .in('order_id', chunk));

  const itemsByOrder = new Map();
  for (const result of itemChunks) {
    for (const item of unwrap(result, 'load order items')) {
      if (!itemsByOrder.has(item.order_id)) itemsByOrder.set(item.order_id, []);
      itemsByOrder.get(item.order_id).push({
        product_id: item.product_id,
        quantity: num(item.quantity),
        line_total: num(item.line_total)
      });
    }
  }

  const redemptionChunks = await inChunks(orderIds, CHUNK, (chunk) =>
    supabase
      .from('promotion_redemptions')
      .select('order_id')
      .in('order_id', chunk));

  const redeemedOrderIds = new Set();
  for (const result of redemptionChunks) {
    for (const row of unwrap(result, 'load redemptions')) redeemedOrderIds.add(row.order_id);
  }

  return { orders, itemsByOrder, redeemedOrderIds };
}

// Earliest date each cart has ever sold anything, read from the facts already
// ingested. An incremental run only loads a day or two of orders, so it cannot
// work this out from the range alone — and getting it wrong would mark a
// genuine zero-demand day at an established cart as "not trading" and throw the
// evidence away.
export async function loadFirstSaleDates() {
  const rows = unwrap(
    await supabase
      .from('forecast_demand_daily_cart')
      .select('location_id,business_date')
      .gt('units', 0)
      .order('business_date', { ascending: true }),
    'load first sale dates'
  );

  const first = new Map();
  for (const row of rows) {
    if (!first.has(row.location_id)) first.set(row.location_id, row.business_date);
  }
  return first;
}

// The earliest business date with any revenue order — where a full rebuild
// starts from.
export async function firstBusinessDate() {
  const rows = unwrap(
    await supabase
      .from('orders')
      .select('business_date')
      .eq('payment_status', 'paid')
      .in('status', REVENUE_STATUSES)
      .order('business_date', { ascending: true })
      .limit(1),
    'find first business date'
  );
  return rows.length ? rows[0].business_date : null;
}

// --------------------------------------------------------------------------
// Demand facts
// --------------------------------------------------------------------------

export async function upsertCartFacts(rows) {
  if (!rows.length) return;
  await inChunks(rows, CHUNK, async (chunk) => {
    const result = await supabase
      .from('forecast_demand_daily_cart')
      .upsert(chunk, { onConflict: 'location_id,business_date' });
    if (result.error) throw new Error(`upsert cart facts: ${result.error.message}`);
    return result;
  });
}

export async function upsertProductFacts(rows) {
  if (!rows.length) return;
  await inChunks(rows, CHUNK, async (chunk) => {
    const result = await supabase
      .from('forecast_demand_daily_product')
      .upsert(chunk, { onConflict: 'location_id,business_date,product_id' });
    if (result.error) throw new Error(`upsert product facts: ${result.error.message}`);
    return result;
  });
}

export async function loadCartFacts({ from, to } = {}) {
  let query = supabase
    .from('forecast_demand_daily_cart')
    .select('location_id,business_date,units,orders,revenue,traded,promo_order_share,mean_discount_pct,applied_uplift,baseline_units')
    .order('business_date', { ascending: true });

  if (from) query = query.gte('business_date', from);
  if (to) query = query.lte('business_date', to);

  return unwrap(await query, 'load cart facts').map((row) => ({
    ...row,
    units: num(row.units),
    orders: num(row.orders),
    revenue: num(row.revenue),
    promo_order_share: num(row.promo_order_share),
    mean_discount_pct: num(row.mean_discount_pct),
    applied_uplift: num(row.applied_uplift) || 1,
    baseline_units: num(row.baseline_units)
  }));
}

export async function loadProductFacts({ from, to } = {}) {
  let query = supabase
    .from('forecast_demand_daily_product')
    .select('location_id,business_date,product_id,units,revenue,applied_uplift,baseline_units')
    .order('business_date', { ascending: true });

  if (from) query = query.gte('business_date', from);
  if (to) query = query.lte('business_date', to);

  return unwrap(await query, 'load product facts').map((row) => ({
    ...row,
    units: num(row.units),
    revenue: num(row.revenue),
    applied_uplift: num(row.applied_uplift) || 1,
    baseline_units: num(row.baseline_units)
  }));
}

// --------------------------------------------------------------------------
// Model state
// --------------------------------------------------------------------------

export async function loadCartStates() {
  const rows = unwrap(
    await supabase.from('forecast_cart_state').select('*'),
    'load cart state'
  );

  const states = new Map();
  for (const row of rows) {
    states.set(row.location_id, {
      location_id: row.location_id,
      level: num(row.level),
      dispersion: num(row.dispersion),
      dow_index: numArray(row.dow_index, 7, 1),
      dow_obs_count: numArray(row.dow_obs_count, 7, 0),
      observations: num(row.observations),
      residual_sum_sq: num(row.residual_sum_sq),
      residual_count: num(row.residual_count),
      last_business_date: row.last_business_date
    });
  }
  return states;
}

export async function saveCartStates(states) {
  const rows = [...states.values()].map((state) => ({
    location_id: state.location_id,
    level: Number(state.level.toFixed(4)),
    dispersion: Number(state.dispersion.toFixed(5)),
    dow_index: state.dow_index.map((value) => Number(value.toFixed(5))),
    dow_obs_count: state.dow_obs_count,
    observations: state.observations,
    residual_sum_sq: Number(state.residual_sum_sq.toFixed(5)),
    residual_count: state.residual_count,
    last_business_date: state.last_business_date,
    updated_at: new Date().toISOString()
  }));

  if (!rows.length) return;
  const result = await supabase.from('forecast_cart_state').upsert(rows, { onConflict: 'location_id' });
  if (result.error) throw new Error(`save cart state: ${result.error.message}`);
}

export async function loadProductStates() {
  const rows = unwrap(
    await supabase.from('forecast_product_state').select('*'),
    'load product state'
  );

  const byLocation = new Map();
  for (const row of rows) {
    if (!byLocation.has(row.location_id)) byLocation.set(row.location_id, new Map());
    byLocation.get(row.location_id).set(row.product_id, {
      alpha: num(row.alpha),
      units_ewma: num(row.units_ewma),
      observations: num(row.observations),
      last_sold_date: row.last_sold_date
    });
  }
  return byLocation;
}

export async function saveProductStates(byLocation) {
  const rows = [];
  for (const [locationId, states] of byLocation) {
    for (const [productId, state] of states) {
      // Products whose evidence has decayed to nothing are dropped rather than
      // stored as a row of zeros — the prior supplies their share anyway, and
      // this keeps the table proportional to what has actually sold.
      if (!(state.alpha > 0.0001)) continue;
      rows.push({
        location_id: locationId,
        product_id: productId,
        alpha: Number(state.alpha.toFixed(5)),
        units_ewma: Number(state.units_ewma.toFixed(5)),
        observations: state.observations,
        last_sold_date: state.last_sold_date,
        updated_at: new Date().toISOString()
      });
    }
  }

  if (!rows.length) return;
  await inChunks(rows, CHUNK, async (chunk) => {
    const result = await supabase
      .from('forecast_product_state')
      .upsert(chunk, { onConflict: 'location_id,product_id' });
    if (result.error) throw new Error(`save product state: ${result.error.message}`);
    return result;
  });
}

export async function loadNetworkState() {
  const rows = unwrap(
    await supabase.from('forecast_network_state').select('*').eq('id', true).limit(1),
    'load network state'
  );
  if (!rows.length) return null;

  const row = rows[0];
  return {
    dow_index: numArray(row.dow_index, 7, 1),
    dow_obs_count: numArray(row.dow_obs_count, 7, 0),
    mean_level: num(row.mean_level),
    dispersion: num(row.dispersion),
    product_mix: row.product_mix || {},
    observations: num(row.observations)
  };
}

export async function saveNetworkState(state) {
  const result = await supabase.from('forecast_network_state').upsert({
    id: true,
    dow_index: state.dow_index.map((value) => Number(value.toFixed(5))),
    dow_obs_count: state.dow_obs_count,
    mean_level: Number(state.mean_level.toFixed(4)),
    dispersion: Number(state.dispersion.toFixed(5)),
    product_mix: state.product_mix,
    observations: state.observations,
    updated_at: new Date().toISOString()
  }, { onConflict: 'id' });

  if (result.error) throw new Error(`save network state: ${result.error.message}`);
}

// --------------------------------------------------------------------------
// Assumptions
// --------------------------------------------------------------------------

export async function loadAssumptions() {
  const rows = unwrap(
    await supabase.from('forecast_cart_assumptions').select('*'),
    'load assumptions'
  );

  const byLocation = new Map();
  for (const row of rows) {
    if (!byLocation.has(row.location_id)) byLocation.set(row.location_id, new Map());
    byLocation.get(row.location_id).set(Number(row.day_of_week), {
      expected_units: row.expected_units === null ? null : num(row.expected_units),
      expected_orders: row.expected_orders === null ? null : num(row.expected_orders),
      prior_strength_days: num(row.prior_strength_days),
      notes: row.notes
    });
  }
  return byLocation;
}

// --------------------------------------------------------------------------
// Campaigns
// --------------------------------------------------------------------------

// Campaigns with their scope sets attached. An empty location or product list
// means "all" — see campaigns.js.
export async function loadCampaigns({ activeOnly = false } = {}) {
  let query = supabase.from('forecast_campaigns').select('*').order('starts_on', { ascending: false });
  if (activeOnly) query = query.eq('is_active', true);

  const campaigns = unwrap(await query, 'load campaigns');
  if (!campaigns.length) return [];

  const [locations, products] = await Promise.all([
    supabase.from('forecast_campaign_locations').select('campaign_id,location_id'),
    supabase.from('forecast_campaign_products').select('campaign_id,product_id')
  ]);

  const locationsByCampaign = new Map();
  for (const row of unwrap(locations, 'load campaign locations')) {
    if (!locationsByCampaign.has(row.campaign_id)) locationsByCampaign.set(row.campaign_id, []);
    locationsByCampaign.get(row.campaign_id).push(row.location_id);
  }

  const productsByCampaign = new Map();
  for (const row of unwrap(products, 'load campaign products')) {
    if (!productsByCampaign.has(row.campaign_id)) productsByCampaign.set(row.campaign_id, []);
    productsByCampaign.get(row.campaign_id).push(row.product_id);
  }

  return campaigns.map((campaign) => ({
    ...campaign,
    discount_pct: campaign.discount_pct === null ? null : num(campaign.discount_pct),
    expected_uplift_pct: num(campaign.expected_uplift_pct),
    learned_log_uplift: campaign.learned_log_uplift === null ? null : num(campaign.learned_log_uplift),
    learned_observations: num(campaign.learned_observations),
    location_ids: locationsByCampaign.get(campaign.id) || [],
    product_ids: productsByCampaign.get(campaign.id) || []
  }));
}

export async function createCampaign(payload, { locationIds = [], productIds = [] } = {}) {
  const result = await supabase.from('forecast_campaigns').insert(payload).select('*').limit(1);
  if (result.error) throw new Error(`create campaign: ${result.error.message}`);

  const campaign = result.data[0];
  await replaceCampaignScope(campaign.id, { locationIds, productIds });
  return campaign;
}

export async function updateCampaign(id, patch) {
  const result = await supabase.from('forecast_campaigns').update(patch).eq('id', id).select('*').limit(1);
  if (result.error) throw new Error(`update campaign: ${result.error.message}`);
  return result.data?.[0] || null;
}

// Scope sets are replaced wholesale rather than diffed: they are small, and a
// partial update is how a campaign ends up targeting a product nobody meant.
export async function replaceCampaignScope(campaignId, { locationIds, productIds }) {
  if (Array.isArray(locationIds)) {
    const cleared = await supabase.from('forecast_campaign_locations').delete().eq('campaign_id', campaignId);
    if (cleared.error) throw new Error(`clear campaign locations: ${cleared.error.message}`);

    if (locationIds.length) {
      const inserted = await supabase
        .from('forecast_campaign_locations')
        .insert(locationIds.map((location_id) => ({ campaign_id: campaignId, location_id })));
      if (inserted.error) throw new Error(`set campaign locations: ${inserted.error.message}`);
    }
  }

  if (Array.isArray(productIds)) {
    const cleared = await supabase.from('forecast_campaign_products').delete().eq('campaign_id', campaignId);
    if (cleared.error) throw new Error(`clear campaign products: ${cleared.error.message}`);

    if (productIds.length) {
      const inserted = await supabase
        .from('forecast_campaign_products')
        .insert(productIds.map((product_id) => ({ campaign_id: campaignId, product_id })));
      if (inserted.error) throw new Error(`set campaign products: ${inserted.error.message}`);
    }
  }
}

export async function deleteCampaign(id) {
  const result = await supabase.from('forecast_campaigns').delete().eq('id', id);
  if (result.error) throw new Error(`delete campaign: ${result.error.message}`);
}

export async function upsertAssumptions(rows) {
  if (!rows.length) return;
  const result = await supabase
    .from('forecast_cart_assumptions')
    .upsert(rows, { onConflict: 'location_id,day_of_week' });
  if (result.error) throw new Error(`save assumptions: ${result.error.message}`);
}

export async function loadCampaignEffects() {
  const rows = unwrap(
    await supabase.from('forecast_campaign_effects').select('*'),
    'load campaign effects'
  );

  const effects = new Map();
  for (const row of rows) {
    effects.set(`${row.campaign_type}::${row.discount_bucket}`, {
      log_uplift_mean: num(row.log_uplift_mean),
      observations: num(row.observations),
      pull_forward_ratio: num(row.pull_forward_ratio)
    });
  }
  return effects;
}

export async function saveCampaignEffects(effects) {
  if (!effects.length) return;
  const result = await supabase
    .from('forecast_campaign_effects')
    .upsert(effects.map((effect) => ({ ...effect, updated_at: new Date().toISOString() })), {
      onConflict: 'campaign_type,discount_bucket'
    });
  if (result.error) throw new Error(`save campaign effects: ${result.error.message}`);
}

export async function upsertCampaignObservations(rows) {
  if (!rows.length) return;
  await inChunks(rows, CHUNK, async (chunk) => {
    const result = await supabase
      .from('forecast_campaign_observations')
      .upsert(chunk, { onConflict: 'campaign_id,location_id,business_date' });
    if (result.error) throw new Error(`save campaign observations: ${result.error.message}`);
    return result;
  });
}

export async function loadCampaignObservations() {
  const rows = unwrap(
    await supabase.from('forecast_campaign_observations').select('campaign_id,location_id,business_date,ratio,actual_units,baseline_forecast'),
    'load campaign observations'
  );

  const byCampaign = new Map();
  for (const row of rows) {
    if (!byCampaign.has(row.campaign_id)) byCampaign.set(row.campaign_id, []);
    byCampaign.get(row.campaign_id).push({ ...row, ratio: num(row.ratio) });
  }
  return byCampaign;
}

export async function updateCampaignLearning(campaignId, logUplift, observations) {
  const result = await supabase
    .from('forecast_campaigns')
    .update({
      learned_log_uplift: logUplift === null ? null : Number(logUplift.toFixed(6)),
      learned_observations: observations
    })
    .eq('id', campaignId);
  if (result.error) throw new Error(`update campaign learning: ${result.error.message}`);
}

// --------------------------------------------------------------------------
// Forecast output
// --------------------------------------------------------------------------

export async function writeCartForecasts(rows) {
  if (!rows.length) return 0;
  const payload = rows.map((row) => ({
    location_id: row.location_id,
    business_date: row.business_date,
    horizon_days: row.horizon_days,
    expected_units: Number(row.expected_units.toFixed(4)),
    p50: row.p50,
    p90: row.p90,
    expected_orders: Number((row.expected_orders || 0).toFixed(4)),
    expected_revenue: Number((row.expected_revenue || 0).toFixed(2)),
    campaign_uplift: Number(row.campaign_uplift.toFixed(4)),
    campaign_ids: row.campaign_ids,
    confidence: row.confidence,
    sample_size: row.sample_size,
    model_version: MODEL_VERSION,
    generated_at: new Date().toISOString()
  }));

  await inChunks(payload, CHUNK, async (chunk) => {
    const result = await supabase
      .from('forecast_daily_cart')
      .upsert(chunk, { onConflict: 'location_id,business_date' });
    if (result.error) throw new Error(`write cart forecasts: ${result.error.message}`);
    return result;
  });
  return payload.length;
}

export async function writeProductForecasts(rows) {
  if (!rows.length) return 0;
  const payload = rows.map((row) => ({
    location_id: row.location_id,
    business_date: row.business_date,
    product_id: row.product_id,
    horizon_days: row.horizon_days,
    mix_share: Number(row.mix_share.toFixed(6)),
    expected_units: Number(row.expected_units.toFixed(4)),
    p50: row.p50,
    p90: row.p90,
    expected_revenue: Number(row.expected_revenue.toFixed(2)),
    campaign_uplift: Number(row.campaign_uplift.toFixed(4)),
    confidence: row.confidence,
    sample_size: row.sample_size,
    model_version: MODEL_VERSION,
    generated_at: new Date().toISOString()
  }));

  await inChunks(payload, CHUNK, async (chunk) => {
    const result = await supabase
      .from('forecast_daily_product')
      .upsert(chunk, { onConflict: 'location_id,business_date,product_id' });
    if (result.error) throw new Error(`write product forecasts: ${result.error.message}`);
    return result;
  });
  return payload.length;
}

// Forecasts for dates now in the past are kept as the accuracy record's
// counterpart, but stale future rows beyond the horizon are cleared so a
// shortened horizon does not leave orphans on screen.
export async function pruneForecastsAfter(dateKey) {
  await supabase.from('forecast_daily_cart').delete().gt('business_date', dateKey);
  await supabase.from('forecast_daily_product').delete().gt('business_date', dateKey);
}

export async function loadCartForecast(locationId, dateKey) {
  const rows = unwrap(
    await supabase
      .from('forecast_daily_cart')
      .select('*')
      .eq('location_id', locationId)
      .eq('business_date', dateKey)
      .limit(1),
    'load cart forecast'
  );
  if (!rows.length) return null;
  return { ...rows[0], expected_units: num(rows[0].expected_units), campaign_uplift: num(rows[0].campaign_uplift) };
}

export async function loadForecastRange({ from, to, locationId }) {
  let cartQuery = supabase
    .from('forecast_daily_cart')
    .select('*')
    .gte('business_date', from)
    .lte('business_date', to)
    .order('business_date', { ascending: true });

  let productQuery = supabase
    .from('forecast_daily_product')
    .select('*')
    .gte('business_date', from)
    .lte('business_date', to)
    .order('expected_units', { ascending: false });

  if (locationId) {
    cartQuery = cartQuery.eq('location_id', locationId);
    productQuery = productQuery.eq('location_id', locationId);
  }

  const [carts, products] = await Promise.all([cartQuery, productQuery]);
  return {
    carts: unwrap(carts, 'load cart forecasts'),
    products: unwrap(products, 'load product forecasts')
  };
}

// --------------------------------------------------------------------------
// Accuracy
// --------------------------------------------------------------------------

export async function writeCartAccuracy(rows) {
  if (!rows.length) return;
  const result = await supabase
    .from('forecast_accuracy_cart')
    .upsert(rows, { onConflict: 'location_id,business_date,horizon_days' });
  if (result.error) throw new Error(`write cart accuracy: ${result.error.message}`);
}

export async function loadCartAccuracy({ from, to, locationId } = {}) {
  let query = supabase
    .from('forecast_accuracy_cart')
    .select('*')
    .order('business_date', { ascending: true });

  if (from) query = query.gte('business_date', from);
  if (to) query = query.lte('business_date', to);
  if (locationId) query = query.eq('location_id', locationId);

  return unwrap(await query, 'load cart accuracy').map((row) => ({
    ...row,
    abs_error: num(row.abs_error),
    naive_abs_error: row.naive_abs_error === null ? null : num(row.naive_abs_error),
    pinball_loss: num(row.pinball_loss),
    expected_units: num(row.expected_units)
  }));
}

// --------------------------------------------------------------------------
// Run log
// --------------------------------------------------------------------------

export async function startRun(trigger) {
  const result = await supabase
    .from('forecast_runs')
    .insert({ trigger, status: 'running', model_version: MODEL_VERSION })
    .select('id')
    .limit(1);

  if (result.error) throw new Error(`start run: ${result.error.message}`);
  return result.data?.[0]?.id || null;
}

export async function finishRun(runId, patch) {
  if (!runId) return;
  const result = await supabase
    .from('forecast_runs')
    .update({ ...patch, finished_at: new Date().toISOString() })
    .eq('id', runId);
  if (result.error) console.error('Could not finish forecast run', result.error);
}

export async function latestRun() {
  const rows = unwrap(
    await supabase.from('forecast_runs').select('*').order('started_at', { ascending: false }).limit(1),
    'load latest run'
  );
  return rows[0] || null;
}

// --------------------------------------------------------------------------
// Rebuild
// --------------------------------------------------------------------------

// Wipe derived state so it can be replayed from the facts. Facts themselves are
// NOT deleted — they are re-derived from orders by the ingest pass, and keeping
// them means a rebuild that fails midway has not destroyed the inputs.
//
// A recursive model you cannot replay is a model you cannot audit, which is why
// this exists at all.
export async function clearDerivedState() {
  // PostgREST refuses an unfiltered delete, so each table is cleared through a
  // predicate on a NOT NULL column, which is always true.
  const tables = [
    ['forecast_cart_state', 'location_id'],
    ['forecast_product_state', 'location_id'],
    ['forecast_campaign_observations', 'campaign_id'],
    ['forecast_campaign_effects', 'campaign_type'],
    ['forecast_daily_cart', 'location_id'],
    ['forecast_daily_product', 'location_id'],
    ['forecast_accuracy_cart', 'location_id'],
    ['forecast_accuracy_product', 'location_id']
  ];

  for (const [table, column] of tables) {
    const result = await supabase.from(table).delete().not(column, 'is', null);
    if (result.error) throw new Error(`clear ${table}: ${result.error.message}`);
  }

  await supabase.from('forecast_campaigns').update({ learned_log_uplift: null, learned_observations: 0 }).not('id', 'is', null);
  await supabase.from('forecast_network_state').update({
    dow_index: [1, 1, 1, 1, 1, 1, 1],
    dow_obs_count: [0, 0, 0, 0, 0, 0, 0],
    mean_level: 0,
    dispersion: 0,
    product_mix: {},
    observations: 0
  }).eq('id', true);
}
