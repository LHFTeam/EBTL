-- Backfilled from supabase_migrations.schema_migrations (leading indentation
-- normalised; the SQL is otherwise unchanged).
-- Already applied to the live project; recorded here for history, not to run.
--
-- Fixes 20260724003429: once confirmed_at is set it must never move, so an
-- update that re-touches a confirmed order keeps the original timestamp.

create or replace function public.set_order_confirmed_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.confirmed_at is not null then
    new.confirmed_at = old.confirmed_at;
  elsif new.confirmed_at is null
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
