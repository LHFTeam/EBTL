-- Backfilled from supabase_migrations.schema_migrations (leading indentation
-- normalised; the SQL is otherwise unchanged).
-- Already applied to the live project; recorded here for history, not to run.

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'employees_prep_location_required'
      and conrelid = 'public.employees'::regclass
  ) then
    alter table public.employees
      add constraint employees_prep_location_required
      check (role <> 'prep'::public.employee_role or default_location_id is not null);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'orders_asap_only'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders
      add constraint orders_asap_only
      check (requested_fulfillment_at is null);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'orders'
  ) then
    execute 'alter publication supabase_realtime add table public.orders';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'order_items'
  ) then
    execute 'alter publication supabase_realtime add table public.order_items';
  end if;
end
$$;
