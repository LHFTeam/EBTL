import { supabase } from './supabase.js';

// An order is created at `pending_payment` and only leaves that state when the
// gateway's payment-success webhook lands. A customer who opens the payment
// sheet and walks away leaves one behind permanently: no money moved, no stock
// was reserved, and the cart it came from is untouched (see
// convertCartAfterPayment in customerRoutes.js). They are not real orders, so
// they are swept instead of accumulating forever.
//
// Two days is deliberately generous — far longer than any webhook delay, and
// long enough that a payment which somehow settles late has already been
// reconciled before its order becomes a candidate.
export const PENDING_ORDER_MAX_AGE_HOURS = Number(process.env.PENDING_ORDER_MAX_AGE_HOURS || 48);
export const PENDING_ORDER_SWEEP_INTERVAL_MINUTES = Number(process.env.PENDING_ORDER_SWEEP_INTERVAL_MINUTES || 60);

// Payment states that mean "no money reached us". Listed explicitly rather than
// filtering on `!= paid`, so an unexpected state is never assumed to be unpaid.
const UNPAID_PAYMENT_STATUSES = ['unpaid', 'pending', 'failed'];

// A sweep is a safety net, not a batch job — cap it so one run can never turn
// into a long-running delete storm. Anything left over is picked up next hour.
const SWEEP_BATCH_LIMIT = 200;

const FIRST_SWEEP_DELAY_MS = 60_000;

function cutoffIso(maxAgeHours) {
  return new Date(Date.now() - maxAgeHours * 60 * 60 * 1000).toISOString();
}

// Orders whose payment record says paid, even though the order row does not.
// That only happens if a webhook updated the payment and then failed partway,
// which is exactly the case where deleting would destroy a real, paid order.
async function orderIdsWithAPaidPayment(orderIds) {
  const paidPayments = await supabase
    .from('payments')
    .select('order_id')
    .in('order_id', orderIds)
    .eq('status', 'paid');

  if (paidPayments.error) return { error: paidPayments.error };

  return {
    data: new Set((paidPayments.data || []).map((row) => row.order_id))
  };
}

// Deletes orders that have been sitting unpaid past the cutoff. Order items,
// their customizations, and the payment rows go with them via the schema's
// cascades — the same cascade the place-order rollback path relies on.
//
// Returns a summary; never throws. Deleting one order at a time is slower than
// one bulk statement, but a single row the database refuses to drop (an order
// referenced by a referral or credit-ledger entry, neither of which a *pending*
// order should ever have) then skips itself instead of failing the whole sweep.
export async function deleteStalePendingOrders({
  maxAgeHours = PENDING_ORDER_MAX_AGE_HOURS,
  limit = SWEEP_BATCH_LIMIT
} = {}) {
  const stale = await supabase
    .from('orders')
    .select('id,order_number,created_at')
    .eq('status', 'pending_payment')
    .in('payment_status', UNPAID_PAYMENT_STATUSES)
    .lt('created_at', cutoffIso(maxAgeHours))
    .order('created_at', { ascending: true })
    .limit(limit);

  if (stale.error) {
    console.error('deleteStalePendingOrders could not list stale orders', stale.error);
    return { deleted: 0, skipped: 0, failed: 0, error: stale.error };
  }

  const candidates = stale.data || [];
  if (!candidates.length) return { deleted: 0, skipped: 0, failed: 0 };

  const paidOrderIds = await orderIdsWithAPaidPayment(candidates.map((order) => order.id));

  if (paidOrderIds.error) {
    console.error('deleteStalePendingOrders could not check payments', paidOrderIds.error);
    return { deleted: 0, skipped: 0, failed: 0, error: paidOrderIds.error };
  }

  let deleted = 0;
  let skipped = 0;
  let failed = 0;

  for (const order of candidates) {
    if (paidOrderIds.data.has(order.id)) {
      skipped += 1;
      console.warn('deleteStalePendingOrders kept an order whose payment is paid', {
        orderId: order.id,
        orderNumber: order.order_number
      });
      continue;
    }

    const removed = await supabase
      .from('orders')
      .delete()
      .eq('id', order.id)
      .eq('status', 'pending_payment')
      .in('payment_status', UNPAID_PAYMENT_STATUSES);

    if (removed.error) {
      failed += 1;
      console.error('deleteStalePendingOrders could not delete order', {
        orderId: order.id,
        orderNumber: order.order_number,
        error: removed.error
      });
      continue;
    }

    deleted += 1;
  }

  return { deleted, skipped, failed };
}

// Runs the sweep shortly after boot and then on an interval. The delay keeps it
// out of the way of a cold start, and the timers are unref'd so they never hold
// the process open during shutdown.
export function startPendingOrderCleanup({
  maxAgeHours = PENDING_ORDER_MAX_AGE_HOURS,
  intervalMinutes = PENDING_ORDER_SWEEP_INTERVAL_MINUTES
} = {}) {
  let sweepInProgress = false;

  async function sweep() {
    if (sweepInProgress) return;
    sweepInProgress = true;

    try {
      const result = await deleteStalePendingOrders({ maxAgeHours });

      if (result.deleted || result.skipped || result.failed) {
        console.log('Swept stale pending_payment orders', {
          older_than_hours: maxAgeHours,
          ...result
        });
      }
    } catch (error) {
      console.error('Pending-order sweep failed', error);
    } finally {
      sweepInProgress = false;
    }
  }

  const firstSweepTimer = setTimeout(() => void sweep(), FIRST_SWEEP_DELAY_MS);
  firstSweepTimer.unref?.();

  const sweepTimer = setInterval(() => void sweep(), intervalMinutes * 60 * 1000);
  sweepTimer.unref?.();

  return {
    stop() {
      clearTimeout(firstSweepTimer);
      clearInterval(sweepTimer);
    }
  };
}
