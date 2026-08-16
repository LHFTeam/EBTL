-- ============================================================================
-- EBTL — Supabase schema backup: functions
-- Includes trigger functions and the RLS helper functions used by policies.
-- ============================================================================

SET search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- private schema — server-side helpers not exposed through PostgREST
-- ---------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.generate_order_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

-- ---------------------------------------------------------------------------
-- public schema functions
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.current_employee_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select e.id
  from public.employees e
  where e.auth_user_id = (select auth.uid())
    and e.is_active = true
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.current_employee_role()
 RETURNS public.employee_role
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select e.role
  from public.employees e
  where e.auth_user_id = (select auth.uid())
    and e.is_active = true
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.is_manager_or_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.current_employee_role() in ('manager', 'admin', 'supervisor');
$function$;

CREATE OR REPLACE FUNCTION public.is_staff()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.current_employee_role() is not null;
$function$;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_stock_movement_to_balance()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  insert into public.inventory_balances (
    ingredient_id,
    location_id,
    quantity_on_hand,
    updated_at
  )
  values (
    new.ingredient_id,
    new.location_id,
    new.quantity_delta,
    now()
  )
  on conflict (ingredient_id, location_id)
  do update set
    quantity_on_hand = public.inventory_balances.quantity_on_hand + excluded.quantity_on_hand,
    updated_at = now();

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.consume_inventory_when_order_completed()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
 if new.status = 'completed'
 and old.status is distinct from 'completed'
 and not exists (
   select 1 from public.order_inventory_consumptions where order_id = new.id
 )
 then
   insert into public.order_inventory_consumptions(order_id)
   values (new.id);

   if exists (
     select 1
     from public.order_items oi
     join public.order_item_inventory_components c on c.order_item_id = oi.id
     where oi.order_id = new.id
   ) then
     insert into public.stock_movements (
       ingredient_id,
       location_id,
       movement_type,
       quantity_delta,
       related_order_id,
       reason,
       created_at
     )
     select
       c.ingredient_id,
       new.location_id,
       'sale_consumption',
       -1 * oi.quantity * c.quantity_per_order_item_unit,
       new.id,
       'Configured cocktail consumption for completed order',
       now()
     from public.order_items oi
     join public.order_item_inventory_components c on c.order_item_id = oi.id
     where oi.order_id = new.id
       and c.quantity_per_order_item_unit > 0;
   else
     insert into public.stock_movements (
       ingredient_id,
       location_id,
       movement_type,
       quantity_delta,
       related_order_id,
       reason,
       created_at
     )
     select
       ri.ingredient_id,
       new.location_id,
       'sale_consumption',
       -1 * oi.quantity * coalesce(pv.serving_count, 1) * (ri.quantity / r.yield_servings),
       new.id,
       'Recipe consumption for completed order',
       now()
     from public.order_items oi
     join public.recipes r on r.id = oi.recipe_id
     left join public.product_variants pv on pv.id = oi.variant_id
     join public.recipe_items ri on ri.recipe_id = r.id
     join public.ingredients ing on ing.id = ri.ingredient_id
     where oi.order_id = new.id
       and coalesce(ri.is_customer_supplied, false) = false
       and coalesce(ing.is_customer_supplied, false) = false
       and ri.quantity > 0;
   end if;
 end if;
 return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.generate_transfer_number()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.transfer_number is null then
    new.transfer_number :=
      'TRF-' ||
      to_char(now(), 'YYYYMMDD') ||
      '-' ||
      lpad(nextval('public.transfer_number_seq')::text, 6, '0');
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.post_stock_transfer_movements()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.status = 'in_transit'
     and old.status is distinct from 'in_transit'
     and not exists (
       select 1
       from public.stock_transfer_movement_events
       where transfer_id = new.id
         and event_type = 'transfer_out'
     )
  then
    insert into public.stock_transfer_movement_events(transfer_id, event_type)
    values (new.id, 'transfer_out');

    insert into public.stock_movements (
      ingredient_id,
      location_id,
      movement_type,
      quantity_delta,
      related_transfer_id,
      reason,
      created_by
    )
    select
      ingredient_id,
      new.from_location_id,
      'transfer_out',
      -1 * dispatched_qty,
      new.id,
      'Stock dispatched to another location',
      new.dispatched_by
    from public.stock_transfer_items
    where transfer_id = new.id
      and dispatched_qty > 0;
  end if;

  if new.status = 'received'
     and old.status is distinct from 'received'
     and not exists (
       select 1
       from public.stock_transfer_movement_events
       where transfer_id = new.id
         and event_type = 'transfer_in'
     )
  then
    insert into public.stock_transfer_movement_events(transfer_id, event_type)
    values (new.id, 'transfer_in');

    insert into public.stock_movements (
      ingredient_id,
      location_id,
      movement_type,
      quantity_delta,
      related_transfer_id,
      reason,
      created_by
    )
    select
      ingredient_id,
      new.to_location_id,
      'transfer_in',
      received_qty,
      new.id,
      'Stock received from another location',
      new.received_by
    from public.stock_transfer_items
    where transfer_id = new.id
      and received_qty > 0;
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_order_confirmed_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
    $function$;

CREATE OR REPLACE FUNCTION public.stamp_order_status_timestamps()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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

CREATE OR REPLACE FUNCTION public.validate_recipe_item_unit()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  ingredient_unit text;
begin
  select base_unit into ingredient_unit
  from public.ingredients
  where id = new.ingredient_id;

  if ingredient_unit is null then
    raise exception 'Ingredient % does not exist', new.ingredient_id;
  end if;

  if lower(new.unit) <> lower(ingredient_unit) then
    raise exception 'Recipe item unit (%) must match ingredient base unit (%)', new.unit, ingredient_unit;
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.transition_cart_order_status(p_order_id uuid, p_expected_status public.order_status, p_next_status public.order_status)
 RETURNS SETOF public.orders
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
    $function$;

CREATE OR REPLACE FUNCTION public.delete_ingredient_cascade(p_ingredient_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_name         text;
  v_product_name text;
  v_product_type text;
begin
  select name into v_name from ingredients where id = p_ingredient_id;
  if v_name is null then
    return jsonb_build_object('status', 'not_found');
  end if;

  -- The one hard stop. An ingredient sitting in any recipe version blocks the
  -- delete, including older versions the product no longer serves, because the
  -- foreign key does not distinguish between them either.
  select p.name, p.product_type
    into v_product_name, v_product_type
  from recipe_items ri
  join recipes r on r.id = ri.recipe_id
  join products p on p.id = r.product_id
  where ri.ingredient_id = p_ingredient_id
  order by p.name
  limit 1;

  if v_product_name is not null then
    return jsonb_build_object(
      'status',       'in_recipe',
      'product_name', v_product_name,
      'product_type', v_product_type
    );
  end if;

  -- Inventory state and operational history: all meaningless once the
  -- ingredient is gone. order_item_removed_ingredients is deliberately absent —
  -- its foreign key is ON DELETE SET NULL beside a name snapshot, so that row
  -- survives the delete and still reads correctly.
  delete from stock_movements                 where ingredient_id = p_ingredient_id;
  delete from inventory_balances              where ingredient_id = p_ingredient_id;
  delete from stock_transfer_items            where ingredient_id = p_ingredient_id;
  delete from purchase_order_items            where ingredient_id = p_ingredient_id;
  delete from order_item_inventory_components where ingredient_id = p_ingredient_id;
  delete from cart_item_removed_ingredients   where ingredient_id = p_ingredient_id;

  -- Every other reference keeps its NO ACTION foreign key, so a table this
  -- function does not know about raises here and rolls the whole delete back
  -- rather than leaving the ingredient half-removed.
  delete from ingredients where id = p_ingredient_id;

  return jsonb_build_object('status', 'deleted', 'id', p_ingredient_id, 'name', v_name);
end;
$function$;
