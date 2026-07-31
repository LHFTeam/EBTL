-- EBTL: allow orders.status = 'expired'
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
-- NOT verified against the live schema — unlike the earlier migrations here,
-- this was written without database access. It therefore handles every shape
-- orders.status might have (enum type, text + CHECK, or unconstrained text) and
-- reports what it found. Check the NOTICE output after applying.
--
-- Deliberately NOT wrapped in begin/commit: ALTER TYPE ... ADD VALUE cannot be
-- used in the same transaction that adds it, so the enum branch would fail.

do $$
declare
  enum_type_name text;
  status_constraint_name text;
  status_constraint_def text;
begin
  -- Case 1: status is an enum type. Widen the type itself.
  select t.typname
    into enum_type_name
  from pg_attribute a
  join pg_type t on t.oid = a.atttypid
  where a.attrelid = 'public.orders'::regclass
    and a.attname = 'status'
    and a.attnum > 0
    and t.typtype = 'e';

  if enum_type_name is not null then
    execute format('alter type public.%I add value if not exists %L', enum_type_name, 'expired');
    raise notice 'orders.status is enum %; ensured value ''expired''.', enum_type_name;
    return;
  end if;

  -- Case 2: status is text with a CHECK constraint enumerating the statuses.
  select c.conname, pg_get_constraintdef(c.oid)
    into status_constraint_name, status_constraint_def
  from pg_constraint c
  where c.conrelid = 'public.orders'::regclass
    and c.contype = 'c'
    and pg_get_constraintdef(c.oid) ilike '%pending_payment%'
  limit 1;

  -- Case 3: nothing constrains it, so nothing needs widening.
  if status_constraint_name is null then
    raise notice 'orders.status has no enumerating CHECK constraint; nothing to widen.';
    return;
  end if;

  if status_constraint_def ilike '%expired%' then
    raise notice 'Constraint % already allows ''expired''.', status_constraint_name;
    return;
  end if;

  execute format('alter table public.orders drop constraint %I', status_constraint_name);

  execute format(
    'alter table public.orders add constraint %I check (status in (%s))',
    status_constraint_name,
    $list$'draft','pending_payment','expired','confirmed','preparing','ready','out_for_delivery','completed','cancelled','refunded'$list$
  );

  raise notice 'Rebuilt constraint % to allow ''expired''. Previous definition: %',
    status_constraint_name, status_constraint_def;
end $$;

-- The sweep reads (status, payment_status, created_at) to find candidates.
create index if not exists orders_pending_payment_created_at_idx
  on public.orders (created_at)
  where status = 'pending_payment';

comment on index public.orders_pending_payment_created_at_idx is
  'Backs the abandoned-checkout sweep in server/lib/pendingOrderCleanup.js.';
