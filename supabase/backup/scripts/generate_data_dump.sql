-- ============================================================================
-- EBTL — generate a complete data dump of schema public.
--
--   psql "$DATABASE_URL" -qAt -f supabase/backup/scripts/generate_data_dump.sql \
--        > supabase/backup/snapshots/data.sql
--
-- Emits one INSERT per non-empty table, in foreign-key-safe order, using the
-- same jsonb array-of-arrays encoding as the checked-in files under data/.
-- Every value is round-tripped through its own column type, so uuids, arrays,
-- jsonb, enums, numerics and timestamps all survive exactly.
--
-- Generated columns are skipped (the target recomputes them). Triggers and FK
-- checks are disabled during load via session_replication_role, so the table
-- order below is a convenience, not a requirement.
--
-- Creates nothing permanent: the helper lives in a temp table that disappears
-- with the session.
--
-- This is the tool behind data/. Run it to refresh the committed snapshot, or
-- to capture the operational tables that are deliberately not committed —
-- those carry customer PII and staff credential hashes, so write the output
-- somewhere private (snapshots/ is git-ignored).
-- ============================================================================

\set QUIET on
\pset tuples_only on
\pset format unaligned

CREATE TEMP TABLE _dump (ord int, relname text, stmt text);

DO $dump$
DECLARE
    v_tables text[] := ARRAY[
        -- reference / catalog
        'product_categories', 'products', 'product_variants', 'product_tags',
        'liquor_types', 'product_liquor_compatibility',
        'ingredients', 'recipes', 'recipe_items',
        'locations', 'location_opening_hours', 'prep_stations',
        'shop_settings', 'referral_settings', 'promotions', 'suppliers',
        -- people
        'employees', 'employee_credentials',
        'customers', 'customer_addresses', 'customer_payment_methods',
        'customer_push_tokens', 'customer_favorite_products',
        'loyalty_accounts', 'loyalty_transactions',
        'referrals', 'customer_credit_ledger',
        -- carts and orders
        'carts', 'cart_items', 'cart_item_additions', 'cart_item_removed_ingredients',
        'order_number_counters', 'orders', 'order_items',
        'order_item_additions', 'order_item_inventory_components',
        'order_item_removed_ingredients', 'order_prep_tasks',
        'order_inventory_consumptions',
        'payments', 'payment_events', 'promotion_redemptions',
        'customer_notifications', 'app_events',
        -- inventory
        'purchase_orders', 'purchase_order_items',
        'stock_transfers', 'stock_transfer_items', 'stock_transfer_movement_events',
        'stock_movements', 'inventory_balances',
        'cart_daily_openings', 'cart_daily_closings'
    ];
    v_tbl text;
    v_i int := 0;
    v_cols text;
    v_casts text;
    v_build text;
    v_data text;
BEGIN
    FOREACH v_tbl IN ARRAY v_tables LOOP
        v_i := v_i + 1;

        -- Skip anything that is not a table in this database.
        CONTINUE WHEN to_regclass('public.' || quote_ident(v_tbl)) IS NULL;

        WITH c AS (
            SELECT attname,
                   format_type(atttypid, atttypmod) AS typ,
                   row_number() OVER (ORDER BY attnum) - 1 AS idx
            FROM pg_attribute
            WHERE attrelid = ('public.' || quote_ident(v_tbl))::regclass
              AND attnum > 0
              AND NOT attisdropped
              AND attgenerated = ''
        )
        SELECT string_agg(quote_ident(attname), ', ' ORDER BY idx),
               string_agg(format('(r->>%s)::%s', idx, typ), ', ' ORDER BY idx),
               string_agg(format('%I::text', attname), ', ' ORDER BY idx)
          INTO v_cols, v_casts, v_build
          FROM c;

        EXECUTE format(
            'SELECT jsonb_agg(jsonb_build_array(%s) ORDER BY 1)::text FROM public.%I t',
            v_build, v_tbl
        ) INTO v_data;

        CONTINUE WHEN v_data IS NULL;   -- empty table

        INSERT INTO _dump VALUES (v_i, v_tbl, format(
            '-- public.%I' || chr(10) ||
            'INSERT INTO public.%I (%s)' || chr(10) ||
            'SELECT %s' || chr(10) ||
            'FROM jsonb_array_elements($json$%s$json$::jsonb) AS r;',
            v_tbl, v_tbl, v_cols, v_casts, v_data));
    END LOOP;
END
$dump$;

SELECT '-- EBTL data dump, generated ' || now() || chr(10) ||
       '-- ' || count(*) || ' tables' || chr(10) ||
       'SET session_replication_role = replica;' || chr(10)
FROM _dump;

SELECT string_agg(stmt, chr(10) || chr(10) ORDER BY ord) FROM _dump;

SELECT chr(10) || 'RESET session_replication_role;';
