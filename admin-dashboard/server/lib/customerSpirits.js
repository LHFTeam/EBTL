// Customer spirit profile.
//
// "Spirits" are rows in `liquor_types` — the bottles a customer brings to the
// beach. The customer profile carries two spirit lists, and this module owns
// both:
//
//   * Favorite spirits (`customer_favorite_liquor_types`) — curated by the
//     customer from the profile screen. Add/remove, nothing computed.
//
//   * Most-ordered spirits (`customer_top_liquor_types`) — computed from the
//     customer's order history and refreshed on every order confirmation.
//
// A product's spirits come from `product_liquor_compatibility`: the liquor
// types a cocktail can be made with. A cocktail compatible with more than one
// spirit counts for each of them — that table is the only record of what a
// cocktail is based on, since neither cart items nor order items pin a bottle.
//
// The schema lives in db/migrations/20260804_customer_spirit_profile.sql.

import { supabase } from './supabase.js';

// How many *counts* the most-ordered list keeps — not how many spirits. See
// pickTopSpirits: ties share a place, so two kept counts can yield more than
// two spirits.
export const TOP_SPIRIT_PLACES = 2;

// Order statuses that count as a genuinely-placed order. Mirrors
// PLACED_ORDER_STATUSES in lib/referrals.js: draft, pending_payment, expired
// and cancelled are checkouts that never became orders, so they must not shape
// what the customer is told they drink. A refunded order still happened.
const PLACED_ORDER_STATUSES = [
  'confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed', 'refunded'
];

// Supabase caps a single `.in()` list, and an order history is unbounded, so
// id lists are fetched in chunks.
const ID_CHUNK_SIZE = 200;

// PostgREST caps a response at its configured max rows (1000 by default) and
// says nothing when it truncates, so every read here pages explicitly. A
// silently short page would drop orders and skew the counts.
const PAGE_SIZE = 500;

function chunk(values, size) {
  const chunks = [];
  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }
  return chunks;
}

// Reads every row a query matches, a page at a time. `buildQuery` must return a
// fresh, deterministically-ordered query — paging an unordered result can
// repeat or skip rows between pages.
async function fetchAllRows(buildQuery) {
  const rows = [];

  for (let from = 0; ; from += PAGE_SIZE) {
    const page = await buildQuery().range(from, from + PAGE_SIZE - 1);
    if (page.error) return { error: page.error };

    const data = page.data || [];
    rows.push(...data);

    if (data.length < PAGE_SIZE) return { data: rows };
  }
}

/**
 * Turn per-spirit order counts into the rows we keep.
 *
 * The rule is "the two most-used spirits", counted per order, with ties kept
 * whole: we keep the top TOP_SPIRIT_PLACES *distinct counts* and every spirit
 * holding one of them. So 10 gin / 6 rum / 4 vodka keeps gin and rum; a single
 * order with gin, rum, tequila and red wine (1 each) keeps all four, because
 * they share first place and there is no second place to fall to.
 *
 * @param {Map<string, number>} countsByLiquorTypeId
 * @returns {Array<{liquor_type_id: string, order_count: number, rank: number}>}
 */
export function pickTopSpirits(countsByLiquorTypeId) {
  const counts = [...countsByLiquorTypeId.entries()].filter(([, count]) => count > 0);
  if (!counts.length) return [];

  const keptCounts = [...new Set(counts.map(([, count]) => count))]
    .sort((a, b) => b - a)
    .slice(0, TOP_SPIRIT_PLACES);

  return counts
    .filter(([, count]) => keptCounts.includes(count))
    .map(([liquorTypeId, count]) => ({
      liquor_type_id: liquorTypeId,
      order_count: count,
      rank: keptCounts.indexOf(count) + 1
    }))
    .sort((a, b) => b.order_count - a.order_count);
}

// The spirits behind a set of products, as product_id -> Set(liquor_type_id).
// Inactive liquor types are dropped, the same way the catalog drops them.
async function spiritsByProductId(productIds) {
  const byProductId = new Map();
  if (!productIds.length) return { data: byProductId };

  for (const productIdChunk of chunk(productIds, ID_CHUNK_SIZE)) {
    const compatibility = await fetchAllRows(() => supabase
      .from('product_liquor_compatibility')
      .select('product_id,liquor_type_id,liquor_types(is_active)')
      .in('product_id', productIdChunk)
      .order('product_id')
      .order('liquor_type_id'));

    if (compatibility.error) return { error: compatibility.error };

    for (const row of compatibility.data) {
      if (row.liquor_types?.is_active === false) continue;
      if (!row.liquor_type_id) continue;

      const spirits = byProductId.get(row.product_id) || new Set();
      spirits.add(row.liquor_type_id);
      byProductId.set(row.product_id, spirits);
    }
  }

  return { data: byProductId };
}

/**
 * Count, per spirit, how many of the customer's placed orders used it. A spirit
 * counts once per order however many of its cocktails that order contains.
 */
async function countOrdersBySpirit(customerId) {
  const orders = await fetchAllRows(() => supabase
    .from('orders')
    .select('id')
    .eq('customer_id', customerId)
    .in('status', PLACED_ORDER_STATUSES)
    .order('id'));

  if (orders.error) return { error: orders.error };

  const orderIds = orders.data.map((order) => order.id);
  if (!orderIds.length) return { data: new Map() };

  const itemRows = [];

  for (const orderIdChunk of chunk(orderIds, ID_CHUNK_SIZE)) {
    const items = await fetchAllRows(() => supabase
      .from('order_items')
      .select('id,order_id,product_id')
      .in('order_id', orderIdChunk)
      .not('product_id', 'is', null)
      .order('id'));

    if (items.error) return { error: items.error };
    itemRows.push(...items.data);
  }

  const productIds = [...new Set(itemRows.map((item) => item.product_id))];
  const spirits = await spiritsByProductId(productIds);
  if (spirits.error) return { error: spirits.error };

  // Per order, the distinct spirits it used — that is what makes the count
  // "once per order" rather than once per cocktail.
  const spiritsByOrderId = new Map();

  for (const item of itemRows) {
    const productSpirits = spirits.data.get(item.product_id);
    if (!productSpirits) continue;

    const orderSpirits = spiritsByOrderId.get(item.order_id) || new Set();
    for (const liquorTypeId of productSpirits) orderSpirits.add(liquorTypeId);
    spiritsByOrderId.set(item.order_id, orderSpirits);
  }

  const countsByLiquorTypeId = new Map();

  for (const orderSpirits of spiritsByOrderId.values()) {
    for (const liquorTypeId of orderSpirits) {
      countsByLiquorTypeId.set(liquorTypeId, (countsByLiquorTypeId.get(liquorTypeId) || 0) + 1);
    }
  }

  return { data: countsByLiquorTypeId };
}

/**
 * Rebuild `customer_top_liquor_types` for one customer from their whole order
 * history. Recomputing rather than incrementing keeps this idempotent: a
 * replayed webhook, or a backfill, lands on the same answer.
 */
export async function recomputeCustomerTopSpirits(customerId) {
  if (!customerId) return { data: [] };

  const counts = await countOrdersBySpirit(customerId);
  if (counts.error) return { error: counts.error };

  const topSpirits = pickTopSpirits(counts.data);
  const computedAt = new Date().toISOString();

  const cleared = await supabase
    .from('customer_top_liquor_types')
    .delete()
    .eq('customer_id', customerId);

  if (cleared.error) return { error: cleared.error };
  if (!topSpirits.length) return { data: [] };

  const inserted = await supabase
    .from('customer_top_liquor_types')
    .insert(topSpirits.map((spirit) => ({
      customer_id: customerId,
      liquor_type_id: spirit.liquor_type_id,
      order_count: spirit.order_count,
      rank: spirit.rank,
      computed_at: computedAt
    })));

  if (inserted.error) return { error: inserted.error };

  return { data: topSpirits };
}

/**
 * Called from each payment-success path once an order actually reached
 * `confirmed`. Never throws and never reports: a spirit profile that failed to
 * refresh must not fail a payment webhook, and the next confirmation rebuilds
 * it from scratch anyway.
 */
export async function refreshTopSpiritsAfterOrderConfirmed(order) {
  if (!order?.customer_id) return;

  try {
    const result = await recomputeCustomerTopSpirits(order.customer_id);

    if (result.error) {
      console.error('recomputeCustomerTopSpirits failed', {
        orderId: order.id,
        customerId: order.customer_id,
        error: result.error
      });
    }
  } catch (error) {
    console.error('recomputeCustomerTopSpirits threw', {
      orderId: order.id,
      customerId: order.customer_id,
      error
    });
  }
}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

const LIQUOR_TYPE_COLUMNS = 'id,name,image_url,display_order,is_active';

export async function loadCustomerFavoriteSpirits(customerId) {
  if (!customerId) return { data: [] };

  const favorites = await supabase
    .from('customer_favorite_liquor_types')
    .select(`customer_id,liquor_type_id,created_at,liquor_types(${LIQUOR_TYPE_COLUMNS})`)
    .eq('customer_id', customerId)
    .order('created_at', { ascending: false });

  if (favorites.error) return { error: favorites.error };

  return {
    data: (favorites.data || []).filter((row) => row.liquor_types?.is_active !== false)
  };
}

export async function loadCustomerTopSpirits(customerId) {
  if (!customerId) return { data: [] };

  const top = await supabase
    .from('customer_top_liquor_types')
    .select(`customer_id,liquor_type_id,order_count,rank,computed_at,liquor_types(${LIQUOR_TYPE_COLUMNS})`)
    .eq('customer_id', customerId)
    .order('order_count', { ascending: false });

  if (top.error) return { error: top.error };

  return {
    data: (top.data || []).filter((row) => row.liquor_types?.is_active !== false)
  };
}

export async function loadActiveSpirits() {
  const liquorTypes = await supabase
    .from('liquor_types')
    .select('*')
    .eq('is_active', true)
    .order('display_order')
    .order('name');

  if (liquorTypes.error) return { error: liquorTypes.error };

  return { data: liquorTypes.data || [] };
}

// ---------------------------------------------------------------------------
// Writes (favorites only — the computed list is never edited by hand)
// ---------------------------------------------------------------------------

export async function findActiveSpirit(liquorTypeId) {
  const liquorType = await supabase
    .from('liquor_types')
    .select(LIQUOR_TYPE_COLUMNS)
    .eq('id', liquorTypeId)
    .eq('is_active', true)
    .maybeSingle();

  if (liquorType.error) return { error: liquorType.error };
  if (!liquorType.data) return { notFound: true };

  return { data: liquorType.data };
}

export async function addCustomerFavoriteSpirit({ customerId, liquorTypeId }) {
  const favorite = await supabase
    .from('customer_favorite_liquor_types')
    .upsert({
      customer_id: customerId,
      liquor_type_id: liquorTypeId
    }, { onConflict: 'customer_id,liquor_type_id' })
    .select('customer_id,liquor_type_id,created_at')
    .single();

  if (favorite.error) return { error: favorite.error };

  return { data: favorite.data };
}

export async function removeCustomerFavoriteSpirit({ customerId, liquorTypeId }) {
  const deleted = await supabase
    .from('customer_favorite_liquor_types')
    .delete()
    .eq('customer_id', customerId)
    .eq('liquor_type_id', liquorTypeId);

  if (deleted.error) return { error: deleted.error };

  return { data: true };
}
