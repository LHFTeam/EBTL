import { cancelStripePaymentIntent } from './stripe.js';
import { supabase } from './supabase.js';

// An order is created at `pending_payment` and only leaves that state when the
// gateway's payment-success webhook lands. A customer who opens the payment
// sheet and walks away leaves one behind permanently: no money moved, no stock
// was reserved, and the cart it came from is untouched (see
// convertCartAfterPayment in customerRoutes.js).
//
// The sweep marks those `expired` rather than deleting them. The row has to
// survive: if a payment settles late — a slow 3-D Secure flow, a retried
// webhook after an outage — the webhook must still find the order so the money
// can be flagged and reconciled. A deleted order means an unattributable
// payment nobody notices.
//
// Thirty minutes is the payment window, not a grace period for the webhook.
// Webhooks land in seconds; a customer who has not paid in half an hour is not
// coming back, and the Stripe intent is cancelled as the order expires so they
// cannot pay against it afterwards.
export const PENDING_ORDER_MAX_AGE_MINUTES = Number(process.env.PENDING_ORDER_MAX_AGE_MINUTES || 30);
export const PENDING_ORDER_SWEEP_INTERVAL_MINUTES = Number(process.env.PENDING_ORDER_SWEEP_INTERVAL_MINUTES || 10);

// Payment states that mean "no money reached us". Listed explicitly rather than
// filtering on `!= paid`, so an unexpected state is never assumed to be unpaid.
const UNPAID_PAYMENT_STATUSES = ['unpaid', 'pending', 'failed'];

const STRIPE_PROVIDER = 'stripe';

// A sweep is a safety net, not a batch job — cap it so one run can never turn
// into a long series of gateway calls. Anything left over is picked up next run.
const SWEEP_BATCH_LIMIT = 200;

const FIRST_SWEEP_DELAY_MS = 60_000;

function cutoffIso(maxAgeMinutes) {
  return new Date(Date.now() - maxAgeMinutes * 60 * 1000).toISOString();
}

async function paymentsForOrders(orderIds) {
  return supabase
    .from('payments')
    .select('id,order_id,provider,provider_payment_id,status,raw_payload')
    .in('order_id', orderIds);
}

// Best-effort breadcrumb so "did we close the payment window on this order?" is
// answerable later from our own data, not just from Stripe.
async function recordIntentCancellation(payment, outcome) {
  const updated = await supabase
    .from('payments')
    .update({
      raw_payload: {
        ...(payment.raw_payload || {}),
        stripe_intent_cancelled_at: new Date().toISOString(),
        stripe_intent_cancelled_status: outcome.status || 'canceled'
      }
    })
    .eq('id', payment.id);

  if (updated.error) {
    console.error('Could not record intent cancellation', { paymentId: payment.id, error: updated.error });
  }
}

// Shuts the gateway's payment window for one order. Returns false only when the
// money is already in flight, which means the order must be left alone.
async function closePaymentWindow(payments) {
  for (const payment of payments) {
    if (payment.provider !== STRIPE_PROVIDER || !payment.provider_payment_id) continue;

    const outcome = await cancelStripePaymentIntent(payment.provider_payment_id);

    if (outcome.moneyInFlight) {
      console.warn('Kept a pending order whose Stripe intent is still live', {
        orderId: payment.order_id,
        paymentIntentId: payment.provider_payment_id,
        intentStatus: outcome.status
      });
      return false;
    }

    if (outcome.cancelled) {
      await recordIntentCancellation(payment, outcome);
      continue;
    }

    if (outcome.error) {
      // Leave the order pending and try again next sweep rather than expiring
      // an order whose payment window we failed to close.
      console.error('Could not cancel Stripe intent', {
        orderId: payment.order_id,
        paymentIntentId: payment.provider_payment_id,
        error: outcome.error.message
      });
      return false;
    }
  }

  return true;
}

// Expires orders that have been sitting unpaid past the cutoff, cancelling the
// gateway's payment intent first so the window is genuinely shut.
//
// Returns a summary; never throws. Orders are handled one at a time so a single
// failure skips itself instead of failing the whole sweep.
export async function expireStalePendingOrders({
  maxAgeMinutes = PENDING_ORDER_MAX_AGE_MINUTES,
  limit = SWEEP_BATCH_LIMIT
} = {}) {
  const stale = await supabase
    .from('orders')
    .select('id,order_number,created_at')
    .eq('status', 'pending_payment')
    .in('payment_status', UNPAID_PAYMENT_STATUSES)
    .lt('created_at', cutoffIso(maxAgeMinutes))
    .order('created_at', { ascending: true })
    .limit(limit);

  if (stale.error) {
    console.error('expireStalePendingOrders could not list stale orders', stale.error);
    return { expired: 0, skipped: 0, failed: 0, error: stale.error };
  }

  const candidates = stale.data || [];
  if (!candidates.length) return { expired: 0, skipped: 0, failed: 0 };

  const payments = await paymentsForOrders(candidates.map((order) => order.id));

  if (payments.error) {
    console.error('expireStalePendingOrders could not load payments', payments.error);
    return { expired: 0, skipped: 0, failed: 0, error: payments.error };
  }

  const paymentsByOrderId = new Map();
  for (const payment of payments.data || []) {
    if (!paymentsByOrderId.has(payment.order_id)) paymentsByOrderId.set(payment.order_id, []);
    paymentsByOrderId.get(payment.order_id).push(payment);
  }

  let expired = 0;
  let skipped = 0;
  let failed = 0;

  for (const order of candidates) {
    const orderPayments = paymentsByOrderId.get(order.id) || [];

    // A payment record that says paid, on an order that does not, means a
    // webhook updated one and not the other — exactly the case where expiring
    // would bury a real, paid order.
    if (orderPayments.some((payment) => payment.status === 'paid')) {
      skipped += 1;
      console.warn('Kept a pending order whose payment is paid', {
        orderId: order.id,
        orderNumber: order.order_number
      });
      continue;
    }

    if (!(await closePaymentWindow(orderPayments))) {
      skipped += 1;
      continue;
    }

    // Re-assert both status filters: an order paid between the read above and
    // this write is left alone.
    const updated = await supabase
      .from('orders')
      .update({ status: 'expired' })
      .eq('id', order.id)
      .eq('status', 'pending_payment')
      .in('payment_status', UNPAID_PAYMENT_STATUSES);

    if (updated.error) {
      failed += 1;
      console.error('Could not expire order', {
        orderId: order.id,
        orderNumber: order.order_number,
        error: updated.error
      });
      continue;
    }

    expired += 1;
  }

  return { expired, skipped, failed };
}

// Runs the sweep shortly after boot and then on an interval. The delay keeps it
// out of the way of a cold start, and the timers are unref'd so they never hold
// the process open during shutdown.
export function startPendingOrderCleanup({
  maxAgeMinutes = PENDING_ORDER_MAX_AGE_MINUTES,
  intervalMinutes = PENDING_ORDER_SWEEP_INTERVAL_MINUTES
} = {}) {
  let sweepInProgress = false;

  async function sweep() {
    if (sweepInProgress) return;
    sweepInProgress = true;

    try {
      const result = await expireStalePendingOrders({ maxAgeMinutes });

      if (result.expired || result.skipped || result.failed) {
        console.log('Expired abandoned checkouts', {
          older_than_minutes: maxAgeMinutes,
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
