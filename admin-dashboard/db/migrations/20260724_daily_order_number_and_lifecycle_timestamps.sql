-- EBTL: daily-resetting order numbers + order lifecycle timestamps
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is a hand-written migration meant to be
-- applied to the Supabase project (dashboard SQL editor, `supabase db push`,
-- or the Supabase MCP `apply_migration`). It is written to be idempotent and
-- safe to re-run.
--
-- What it does:
--   1. Order number becomes a plain integer that starts at 100 each day and
--      increments per order, resetting the next day (business day is in the
--      Africa/Cairo time zone, matching BUSINESS_TIME_ZONE in the API).
--   2. Adds lifecycle timestamp columns and stamps them automatically when an
--      order moves to preparing / ready / completed. `created_at` already
--      exists and covers "created".
--
-- Both status-change paths in the API (the `transition_cart_order_status` RPC
-- used by cart operations, and the admin `PATCH /api/orders/:id` route) issue a
-- normal UPDATE on `orders`, so a BEFORE UPDATE trigger captures every path
-- without touching either code path.

begin;

-- ---------------------------------------------------------------------------
-- 1. Daily-resetting order number
-- ---------------------------------------------------------------------------

-- Per-day counter. One row per Cairo calendar day; `last_number` is the most
-- recently assigned order number for that day.
create table if not exists public.order_number_counters (
  order_date  date    primary key,
  last_number integer not null,
  updated_at  timestamptz not null default now()
);

comment on table public.order_number_counters is
  'Per-day sequence backing orders.order_number. Numbering starts at 100 and resets each Africa/Cairo calendar day.';

-- The order number is now the daily counter value, so it is intentionally NOT
-- globally unique anymore (100 recurs every day). Remove any pre-existing
-- default and any unique constraint/index that is exactly (order_number),
-- otherwise the second day of inserts would collide.
alter table public.orders alter column order_number drop default;

do $$
declare
  r record;
begin
  -- Drop UNIQUE CONSTRAINTS defined on exactly (order_number).
  for r in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'orders'
      and con.contype = 'u'
      and (
        select array_agg(att.attname order by att.attnum)
        from unnest(con.conkey) as k(attnum)
        join pg_attribute att
          on att.attrelid = con.conrelid and att.attnum = k.attnum
      ) = array['order_number']
  loop
    execute format('alter table public.orders drop constraint %I', r.conname);
  end loop;

  -- Drop standalone UNIQUE INDEXES on exactly (order_number) not backing a constraint.
  for r in
    select i.relname
    from pg_index idx
    join pg_class i on i.oid = idx.indexrelid
    join pg_class t on t.oid = idx.indrelid
    join pg_namespace nsp on nsp.oid = t.relnamespace
    where nsp.nspname = 'public'
      and t.relname = 'orders'
      and idx.indisunique
      and not exists (select 1 from pg_constraint c where c.conindid = idx.indexrelid)
      and (
        select array_agg(att.attname order by att.attnum)
        from unnest(idx.indkey) as k(attnum)
        join pg_attribute att
          on att.attrelid = idx.indrelid and att.attnum = k.attnum
      ) = array['order_number']
  loop
    execute format('drop index public.%I', r.relname);
  end loop;
end $$;

-- Assigns the next daily order number. Runs on INSERT. The upsert + RETURNING
-- takes a row lock on the counter row, serializing concurrent inserts for the
-- same day so numbers are gap-free and collision-free.
create or replace function public.assign_daily_order_number()
returns trigger
language plpgsql
as $$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_next  integer;
begin
  insert into public.order_number_counters as c (order_date, last_number, updated_at)
  values (v_today, 100, now())
  on conflict (order_date)
  do update set last_number = c.last_number + 1,
                updated_at  = now()
  returning c.last_number into v_next;

  -- Assign unconditionally so a leftover legacy default/trigger cannot win.
  new.order_number := v_next;
  return new;
end;
$$;

-- Named to sort last so it wins over any legacy BEFORE INSERT trigger that may
-- still set order_number (BEFORE triggers fire in trigger-name order).
drop trigger if exists zz_orders_assign_daily_number on public.orders;
create trigger zz_orders_assign_daily_number
  before insert on public.orders
  for each row
  execute function public.assign_daily_order_number();

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
as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'preparing' and new.preparing_at is null then
      new.preparing_at := now();
    elsif new.status = 'ready' and new.ready_at is null then
      new.ready_at := now();
    elsif new.status = 'completed' and new.completed_at is null then
      new.completed_at := now();
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_stamp_order_status_timestamps on public.orders;
create trigger trg_stamp_order_status_timestamps
  before update on public.orders
  for each row
  execute function public.stamp_order_status_timestamps();

-- Backfill: seed the timestamps we can reasonably infer for existing rows so
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
