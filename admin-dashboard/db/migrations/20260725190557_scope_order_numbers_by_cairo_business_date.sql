-- Backfilled from supabase_migrations.schema_migrations (leading indentation
-- normalised; the SQL is otherwise unchanged).
-- Already applied to the live project; recorded here for history, not to run.
--
-- Creates the `private` schema and moves order-number generation into it, so
-- the counter cannot be reached over PostgREST and burned. Order numbers become
-- unique per Cairo business date rather than globally.

create schema if not exists private;
revoke all on schema private from public;

alter table public.orders
  add column if not exists business_date date;

update public.orders
set business_date = (created_at at time zone 'Africa/Cairo')::date
where business_date is null;

alter table public.orders
  alter column business_date
    set default ((now() at time zone 'Africa/Cairo')::date),
  alter column business_date set not null,
  alter column order_number set not null;

comment on column public.orders.business_date is
  'Cairo business date used with order_number; resets at Africa/Cairo midnight.';

alter table public.orders
  drop constraint if exists orders_order_number_key;

alter table public.orders
  add constraint orders_business_date_order_number_key
  unique (business_date, order_number);

create or replace function private.generate_order_number()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_today date := (clock_timestamp() at time zone 'Africa/Cairo')::date;
  v_next integer;
  v_request_role text := coalesce(
    auth.jwt() ->> 'role',
    nullif(current_setting('role', true), 'none'),
    session_user
  );
begin
  if tg_op <> 'INSERT' or tg_relid <> 'public.orders'::regclass then
    raise exception 'generate_order_number may only run for inserts on public.orders';
  end if;

  if v_request_role = 'authenticated' and auth.uid() is null then
    raise exception 'authenticated order insert requires a valid user identity';
  end if;

  new.business_date := v_today;

  if new.order_number is null then
    insert into public.order_number_counters as c
      (order_date, last_number, updated_at)
    values
      (v_today, 100, clock_timestamp())
    on conflict (order_date)
    do update
      set last_number = c.last_number + 1,
          updated_at = clock_timestamp()
    returning c.last_number into v_next;

    new.order_number := v_next::text;
  end if;

  return new;
end;
$function$;

revoke all on function private.generate_order_number() from public;

drop trigger if exists trg_generate_order_number on public.orders;
create trigger trg_generate_order_number
  before insert on public.orders
  for each row
  execute function private.generate_order_number();

drop function if exists public.generate_order_number();

revoke all privileges on table public.order_number_counters from anon, authenticated;
alter table public.order_number_counters enable row level security;

comment on table public.order_number_counters is
  'Private per-day counter backing orders.order_number. Numbering starts at 100 and resets each Africa/Cairo business date.';
