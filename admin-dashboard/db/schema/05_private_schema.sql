-- EBTL baseline schema — the `private` schema.
--
-- Holds one SECURITY DEFINER trigger function. It is separate from `public` so
-- it is not reachable over PostgREST: it allocates order numbers, and letting a
-- client call it directly would burn numbers out of the daily counter.

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
