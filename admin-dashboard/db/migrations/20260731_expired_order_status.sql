-- EBTL: add orders.status = 'expired'
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is a hand-written migration meant to be
-- applied to the Supabase project (dashboard SQL editor, `supabase db push`,
-- or the Supabase MCP `apply_migration`). It is idempotent and safe to re-run.
--
-- Why: an order is created at `pending_payment` and only leaves that state when
-- the gateway's payment-success webhook lands. A customer who opens the payment
-- sheet and walks away leaves one behind permanently. The server now sweeps
-- those (server/lib/pendingOrderCleanup.js) and marks them `expired` — a
-- terminal state meaning "checkout was never paid for". They are deliberately
-- NOT deleted: if a payment settles late, the row must still be there for the
-- webhook to find and flag, otherwise the money cannot be reconciled.
--
-- Verified against the live schema (project pfcncajijvtvsdwgwbjl) before
-- writing:
--   * orders.status is enum public.order_status, values (draft,
--     pending_payment, confirmed, preparing, ready, out_for_delivery,
--     completed, cancelled, refunded). No 'expired' yet.
--   * No CHECK constraint, RLS policy or function enumerates order statuses,
--     so widening the enum is the only schema change needed.
--   * The three triggers on orders are all inert for 'expired':
--     set_order_confirmed_at only stamps confirmed_at for status in
--     (confirmed, preparing, ready, out_for_delivery, completed), so a late
--     payment marking an expired order paid does NOT confirm it;
--     stamp_order_status_timestamps has no branch for it; and
--     consume_inventory_when_order_completed only fires on 'completed', so
--     expiring never touches stock.
--   * v_daily_sales_by_location and v_product_sales filter to 'completed',
--     v_order_prep_queue to (confirmed, preparing, ready) — none is affected.
--   * transition_cart_order_status() requires payment_status = 'paid', so
--     staff cannot walk an unpaid expired order back into the prep queue.
--   * idx_orders_status_created is btree (status, created_at DESC), which
--     already serves the sweep's lookup. No new index is needed.
--
-- ALTER TYPE ... ADD VALUE is allowed inside a transaction on PG 12+ as long as
-- the new value is not *used* in the same transaction. This migration only adds
-- it; the first use is a later UPDATE from the application.

alter type public.order_status add value if not exists 'expired' after 'pending_payment';

comment on type public.order_status is
  'Order lifecycle. `expired` is terminal and set only by the abandoned-checkout sweep in server/lib/pendingOrderCleanup.js; it means the checkout was never paid for.';
