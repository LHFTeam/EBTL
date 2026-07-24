-- EBTL: daily-resetting order numbers + order lifecycle timestamps
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is a hand-written migration meant to be
-- applied to the Supabase project (dashboard SQL editor, `supabase db push`,
-- or the Supabase MCP `apply_migration`). It is written to be idempotent and
-- safe to re-run.
--
-- Verified against the live schema before writing:
--   * orders.order_number is TEXT, nullable, no default.
--   * It is populated by BEFORE INSERT trigger trg_generate_order_number
--     -> generate_order_number(), which today builds 'EBTL-YYYYMMDD-000001'
--     from the global sequence public.order_number_seq (never resets).
--   * There is NO unique constraint/index on order_number, so a daily-repeating
--     number is safe.
--   * orders already has created_at and confirmed_at; the status-change RPC
--     transition_cart_order_status() and admin PATCH /api/orders/:id both issue
--     a plain UPDATE, so a BEFORE UPDATE trigger captures every path.
--
-- What this migration does:
--   1. Order number becomes a plain integer (stored as text) that starts at 100
--      each Africa/Cairo day and increments per order, resetting the next day.
--      Implemented by REPLACING generate_order_number()'s body (its trigger is
--      left in place). order_number_seq is left intact but is now unused.
--   2. Adds preparing_at / ready_at / completed_at and stamps them the first
--      time an order reaches each status. created_at already covers "created".

begin;

-- ---------------------------------------------------------------------------
-- 1. Daily-resetting order number
-- ---------------------------------------------------------------------------

-- Per-day counter. One row per Cairo calendar day; last_number is the most
-- recently assigned order number for that day.
create table if not exists public.order_number_counters (
  order_date  date        primary key,
  last_number integer     not null,
  updated_at  timestamptz not null default now()
);

comment on table public.order_number_counters is
  'Per-day counter backing orders.order_number. Numbering starts at 100 and resets each Africa/Cairo calendar day.';

-- Replace the existing generator (trigger trg_generate_order_number keeps
-- calling this function). The upsert + RETURNING takes a row lock on the
-- counter row, serializing concurrent inserts for the same day so numbers are
-- gap-free and collision-free.
create or replace function public.generate_order_number()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_next  integer;
begin
  if new.order_number is null then
    insert into public.order_number_counters as c (order_date, last_number, updated_at)
    values (v_today, 100, now())
    on conflict (order_date)
    do update set last_number = c.last_number + 1,
                  updated_at  = now()
    returning c.last_number into v_next;

    new.order_number := v_next::text;
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Lifecycle timestamps
-- ---------------------------------------------------------------------------

alter table public.orders
  add column if not exists preparing_at timestamptz,
  add column if not exists ready_at     timestamptz,
  add column if not exists completed_at timestamptz;

comment on column public.orders.preparing_at is 'When the order first moved to status = preparing.';
comment on column public.orders.ready_at     is 'When the order first moved to status = ready.';
comment on column public.orders.completed_at is 'When the order was marked completed / picked up.';

-- Stamp the timestamp the first time the order reaches each status. Only sets a
-- column when it is still null, so re-entering a status (or an idempotent
-- update) never overwrites the original time.
create or replace function public.stamp_order_status_timestamps()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.status is distinct from old.status then
    if new.status = 'preparing'::public.order_status and new.preparing_at is null then
      new.preparing_at := now();
    elsif new.status = 'ready'::public.order_status and new.ready_at is null then
      new.ready_at := now();
    elsif new.status = 'completed'::public.order_status and new.completed_at is null then
      new.completed_at := now();
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_stamp_order_status_timestamps on public.orders;
create trigger trg_stamp_order_status_timestamps
  before update on public.orders
  for each row
  execute function public.stamp_order_status_timestamps();

-- Backfill: seed timestamps we can reasonably infer for existing rows so
-- historical orders aren't left blank. Orders already at/after a stage get the
-- best available timestamp (falls back to updated_at, then created_at).
update public.orders
set preparing_at = coalesce(preparing_at, updated_at, created_at)
where preparing_at is null
  and status in ('preparing', 'ready', 'out_for_delivery', 'completed');

update public.orders
set ready_at = coalesce(ready_at, updated_at, created_at)
where ready_at is null
  and status in ('ready', 'out_for_delivery', 'completed');

update public.orders
set completed_at = coalesce(completed_at, updated_at, created_at)
where completed_at is null
  and status = 'completed';

commit;
