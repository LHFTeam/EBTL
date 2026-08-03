-- Backfilled from supabase_migrations.schema_migrations (leading indentation
-- normalised; the SQL is otherwise unchanged).
-- Already applied to the live project; recorded here for history, not to run.
--
-- Moves the "advance an order and its items" step into one statement so two
-- staff acting at once cannot interleave. Execute is granted to service_role
-- only: anon and authenticated are revoked explicitly.

create or replace function public.transition_cart_order_status(
  p_order_id uuid,
  p_expected_status public.order_status,
  p_next_status public.order_status
)
returns setof public.orders
language plpgsql
security invoker
set search_path = ''
as $$
declare
  changed_order public.orders%rowtype;
begin
  update public.orders
  set status = p_next_status
  where id = p_order_id
    and status = p_expected_status
    and payment_status = 'paid'::public.payment_status
  returning * into changed_order;

  if not found then
    return;
  end if;

  if p_next_status = 'preparing'::public.order_status then
    update public.order_items
    set prep_status = 'in_progress'::public.prep_status
    where order_id = p_order_id
      and prep_status in (
        'queued'::public.prep_status,
        'blocked'::public.prep_status
      );
  elsif p_next_status in (
    'ready'::public.order_status,
    'completed'::public.order_status
  ) then
    update public.order_items
    set prep_status = 'packed'::public.prep_status
    where order_id = p_order_id
      and prep_status in (
        'queued'::public.prep_status,
        'in_progress'::public.prep_status,
        'blocked'::public.prep_status
      );
  end if;

  return next changed_order;
end;
$$;

revoke all on function public.transition_cart_order_status(
  uuid,
  public.order_status,
  public.order_status
) from public, anon, authenticated;

grant execute on function public.transition_cart_order_status(
  uuid,
  public.order_status,
  public.order_status
) to service_role;
