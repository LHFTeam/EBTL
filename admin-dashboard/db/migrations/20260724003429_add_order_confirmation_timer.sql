-- Backfilled from supabase_migrations.schema_migrations (leading indentation
-- normalised; the SQL is otherwise unchanged).
-- Already applied to the live project; recorded here for history, not to run.
--
-- Superseded in part by 20260724003509, which makes confirmed_at immutable.

alter table public.orders
  add column if not exists confirmed_at timestamptz;

update public.orders as orders_row
set confirmed_at = coalesce(
  (
    select min(coalesce(payment_row.updated_at, payment_row.created_at))
    from public.payments as payment_row
    where payment_row.order_id = orders_row.id
      and payment_row.status::text = 'paid'
  ),
  orders_row.created_at,
  orders_row.updated_at
)
where orders_row.confirmed_at is null
  and orders_row.payment_status::text = 'paid'
  and orders_row.status::text in (
    'confirmed',
    'preparing',
    'ready',
    'out_for_delivery',
    'completed'
  );

create or replace function public.set_order_confirmed_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.confirmed_at is null
    and new.payment_status::text = 'paid'
    and new.status::text in (
      'confirmed',
      'preparing',
      'ready',
      'out_for_delivery',
      'completed'
    )
  then
    new.confirmed_at = clock_timestamp();
  end if;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'set_order_confirmed_at'
      and tgrelid = 'public.orders'::regclass
      and not tgisinternal
  ) then
    create trigger set_order_confirmed_at
      before insert or update of status, payment_status, confirmed_at
      on public.orders
      for each row
      execute function public.set_order_confirmed_at();
  end if;
end
$$;
