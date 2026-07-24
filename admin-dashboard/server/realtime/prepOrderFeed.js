import { supabase } from '../lib/supabase.js';

const INVALIDATION_DEBOUNCE_MS = 150;
const LOOKUP_RETRY_MIN_MS = 2_000;
const LOOKUP_RETRY_MAX_MS = 30_000;
const LOCATION_CACHE_TTL_MS = 24 * 60 * 60 * 1_000;
const LOCATION_CACHE_PRUNE_INTERVAL_MS = 60 * 60 * 1_000;

function eventRow(payload) {
  return payload?.new && Object.keys(payload.new).length ? payload.new : payload?.old || {};
}

function chunks(values, size = 100) {
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

export function createPrepOrderFeed({ onInvalidate, onStatus }) {
  let channel = null;
  let stopped = false;
  let channelHealthy = false;
  let lookupHealthy = true;
  let flushTimer = null;
  let flushing = false;
  let retryDelay = LOOKUP_RETRY_MIN_MS;
  let status = {
    status: 'connecting',
    updated_at: new Date().toISOString()
  };

  const pending = new Map();
  const orderLocations = new Map();
  let lastLocationCachePruneAt = 0;

  function publishStatus(nextStatus) {
    if (status.status === nextStatus) return;
    status = {
      status: nextStatus,
      updated_at: new Date().toISOString()
    };
    onStatus(status);
  }

  function refreshStatus() {
    if (stopped) return publishStatus('stopped');
    if (channelHealthy && lookupHealthy) return publishStatus('live');
    if (!channel && lookupHealthy) return publishStatus('connecting');
    return publishStatus('degraded');
  }

  function pruneLocationCache(now = Date.now()) {
    if (now - lastLocationCachePruneAt < LOCATION_CACHE_PRUNE_INTERVAL_MS) return;
    lastLocationCachePruneAt = now;
    for (const [orderId, cached] of orderLocations) {
      if (now - cached.seenAt > LOCATION_CACHE_TTL_MS) orderLocations.delete(orderId);
    }
  }

  function rememberLocation(orderId, locationId) {
    if (!orderId || !locationId) return;
    const now = Date.now();
    pruneLocationCache(now);
    orderLocations.set(orderId, {
      locationId,
      seenAt: now
    });
  }

  function cachedLocation(orderId) {
    const cached = orderLocations.get(orderId);
    if (!cached) return null;
    if (Date.now() - cached.seenAt > LOCATION_CACHE_TTL_MS) {
      orderLocations.delete(orderId);
      return null;
    }
    return cached.locationId;
  }

  function scheduleFlush(delay = INVALIDATION_DEBOUNCE_MS) {
    if (stopped || flushTimer) return;
    flushTimer = setTimeout(() => {
      flushTimer = null;
      void flush();
    }, delay);
    flushTimer.unref?.();
  }

  function queueOrder(orderId, locationId = null) {
    if (!orderId || stopped) return;
    const existing = pending.get(orderId);
    pending.set(orderId, locationId || existing || cachedLocation(orderId) || null);
    scheduleFlush();
  }

  function handleOrderChange(payload) {
    const row = eventRow(payload);
    const orderId = row.id;
    if (!orderId) return;

    const locationId = row.location_id || cachedLocation(orderId);
    if (row.location_id) rememberLocation(orderId, row.location_id);
    queueOrder(orderId, locationId);
  }

  function handleOrderItemChange(payload) {
    const row = eventRow(payload);
    if (row.order_id) queueOrder(row.order_id);
  }

  async function loadOrderLocations(orderIds) {
    const locations = new Map();
    for (const batch of chunks(orderIds)) {
      const result = await supabase
        .from('orders')
        .select('id,location_id')
        .in('id', batch);
      if (result.error) throw result.error;

      for (const order of result.data || []) {
        if (!order.id || !order.location_id) continue;
        locations.set(order.id, order.location_id);
        rememberLocation(order.id, order.location_id);
      }
    }
    return locations;
  }

  async function flush() {
    if (stopped || !pending.size) return;
    if (flushing) {
      scheduleFlush();
      return;
    }
    flushing = true;

    try {
      const queued = new Map(pending);
      pending.clear();

      const missingOrderIds = [...queued]
        .filter(([, locationId]) => !locationId)
        .map(([orderId]) => orderId);

      if (missingOrderIds.length) {
        try {
          const loadedLocations = await loadOrderLocations(missingOrderIds);
          for (const [orderId, locationId] of loadedLocations) {
            queued.set(orderId, locationId);
          }
          lookupHealthy = true;
          retryDelay = LOOKUP_RETRY_MIN_MS;
          refreshStatus();
        } catch (error) {
          console.error('Prep order realtime location lookup failed:', error?.message || 'Unknown Supabase error');
          lookupHealthy = false;
          refreshStatus();
          for (const orderId of missingOrderIds) {
            if (!queued.get(orderId)) pending.set(orderId, null);
          }
          scheduleFlush(retryDelay);
          retryDelay = Math.min(retryDelay * 2, LOOKUP_RETRY_MAX_MS);
        }
      }

      const orderIdsByLocation = new Map();
      for (const [orderId, locationId] of queued) {
        if (!locationId) continue;
        const orderIds = orderIdsByLocation.get(locationId) || [];
        orderIds.push(orderId);
        orderIdsByLocation.set(locationId, orderIds);
      }

      if (stopped) return;
      for (const [locationId, orderIds] of orderIdsByLocation) {
        onInvalidate({
          locationId,
          payload: {
            order_ids: [...new Set(orderIds)]
          }
        });
      }
    } finally {
      flushing = false;
      if (pending.size) scheduleFlush();
    }
  }

  function start() {
    if (channel || stopped) return;

    channel = supabase
      .channel(`prep-order-feed-${process.pid}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'orders' },
        handleOrderChange
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'order_items' },
        handleOrderItemChange
      )
      .subscribe((subscriptionStatus, error) => {
        if (stopped) return;
        channelHealthy = subscriptionStatus === 'SUBSCRIBED';
        if (error) {
          console.error('Prep order realtime feed error:', error.message || 'Unknown Supabase Realtime error');
        }
        refreshStatus();
      });
  }

  async function stop() {
    if (stopped) return;
    stopped = true;
    if (flushTimer) clearTimeout(flushTimer);
    flushTimer = null;
    pending.clear();
    publishStatus('stopped');

    if (channel) {
      const currentChannel = channel;
      channel = null;
      await currentChannel.unsubscribe(250);
      currentChannel.teardown();
      await supabase.realtime.disconnect();
      return;
    }
    await supabase.realtime.disconnect();
  }

  return {
    getStatus: () => status,
    start,
    stop
  };
}
