-- Regenerates the baseline in db/schema/ from a live database.
--
-- The Postgres schema is managed in the Supabase dashboard, so the files in
-- db/schema/ are a *capture* of it rather than its source. This script is how
-- that capture is produced, so it can be refreshed rather than hand-edited.
--
-- Run each section against the project and write its single `ddl` column into
-- the matching file:
--
--   psql "$DATABASE_URL" -At -f db/tools/dump_schema.sql
--
-- or paste a section into the Supabase SQL editor. Sections are ordered so the
-- files apply cleanly in filename order against an empty database.

-- ===========================================================================
-- 00_extensions_and_types.sql
-- ===========================================================================
select string_agg(line, E'\n' order by ord, nm) as ddl from (
  select 'CREATE EXTENSION IF NOT EXISTS ' || quote_ident(e.extname)
         || ' WITH SCHEMA ' || quote_ident(n.nspname) || ';' as line, 1 as ord, e.extname as nm
  from pg_extension e join pg_namespace n on n.oid = e.extnamespace
  where e.extname <> 'plpgsql'
  union all
  select 'CREATE TYPE public.' || quote_ident(t.typname) || ' AS ENUM ('
         || (select string_agg(quote_literal(en.enumlabel), ', ' order by en.enumsortorder)
               from pg_enum en where en.enumtypid = t.oid) || ');', 2, t.typname
  from pg_type t join pg_namespace n on n.oid = t.typnamespace
  where n.nspname = 'public' and t.typtype = 'e'
) s;

-- ===========================================================================
-- 10_tables.sql — columns, defaults, generated/identity columns, RLS toggle
-- ===========================================================================
select string_agg(ddl, E'\n\n' order by nm) as ddl from (
  select c.relname as nm,
    'CREATE TABLE IF NOT EXISTS public.' || quote_ident(c.relname) || E' (\n' ||
    (select string_agg('    ' || quote_ident(a.attname) || ' ' || format_type(a.atttypid, a.atttypmod)
       || case when a.attidentity <> '' then ' GENERATED '
                    || case a.attidentity when 'a' then 'ALWAYS' else 'BY DEFAULT' end || ' AS IDENTITY'
               when a.attgenerated <> '' then ' GENERATED ALWAYS AS (' || pg_get_expr(ad.adbin, ad.adrelid) || ') STORED'
               when ad.adbin is not null then ' DEFAULT ' || pg_get_expr(ad.adbin, ad.adrelid)
               else '' end
       || case when a.attnotnull then ' NOT NULL' else '' end, E',\n' order by a.attnum)
     from pg_attribute a left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
     where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped)
    || E'\n);'
    || case when c.relrowsecurity
            then E'\nALTER TABLE public.' || quote_ident(c.relname) || ' ENABLE ROW LEVEL SECURITY;'
            else '' end as ddl
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
) s;

-- ===========================================================================
-- 20_constraints.sql — primary keys, uniques, foreign keys, checks
-- Ordered so referenced tables' keys exist before the foreign keys pointing
-- at them (p/u before f).
-- ===========================================================================
select string_agg(ddl, E'\n' order by ord, nm) as ddl from (
  select 'ALTER TABLE public.' || quote_ident(rel.relname)
         || ' ADD CONSTRAINT ' || quote_ident(con.conname)
         || ' ' || pg_get_constraintdef(con.oid) || ';' as ddl,
         case con.contype when 'p' then 1 when 'u' then 2 when 'c' then 3 else 4 end as ord,
         rel.relname || '.' || con.conname as nm
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace n on n.oid = con.connamespace
  where n.nspname = 'public' and con.contype in ('p','u','f','c')
) s;

-- ===========================================================================
-- 30_indexes.sql — indexes NOT already created by a constraint
-- ===========================================================================
select string_agg(indexdef || ';', E'\n' order by indexname) as ddl
from pg_indexes i
where i.schemaname = 'public'
  and not exists (
    select 1 from pg_constraint c
    join pg_class ic on ic.oid = c.conindid
    where ic.relname = i.indexname and c.contype in ('p','u','x')
  );

-- ===========================================================================
-- 40_views.sql
-- ===========================================================================
select string_agg('CREATE OR REPLACE VIEW public.' || quote_ident(c.relname)
       || E' AS\n' || pg_get_viewdef(c.oid, true), E'\n\n' order by c.relname) as ddl
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'v';

-- ===========================================================================
-- 50_functions.sql
-- ===========================================================================
select string_agg(pg_get_functiondef(p.oid) || ';', E'\n\n' order by p.proname) as ddl
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prokind in ('f','p');

-- ===========================================================================
-- 60_triggers.sql
-- ===========================================================================
select string_agg(pg_get_triggerdef(t.oid) || ';', E'\n' order by c.relname, t.tgname) as ddl
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and not t.tgisinternal;

-- ===========================================================================
-- 70_rls_policies.sql
-- RLS is enabled on every table (see 10_tables.sql); these are the policies
-- that go with it. The Express server connects with the service-role key,
-- which bypasses RLS entirely — so these govern any direct PostgREST access.
-- ===========================================================================
select string_agg(ddl, E'\n' order by tablename, policyname) as ddl from (
  select 'CREATE POLICY ' || quote_ident(policyname) || ' ON public.' || quote_ident(tablename)
         || ' AS ' || permissive
         || ' FOR ' || cmd
         || ' TO ' || array_to_string(roles, ', ')
         || coalesce(' USING (' || qual || ')', '')
         || coalesce(' WITH CHECK (' || with_check || ')', '')
         || ';' as ddl,
         tablename, policyname
  from pg_policies where schemaname = 'public'
) s;

-- ===========================================================================
-- 80_comments.sql
-- ===========================================================================
select string_agg(ddl, E'\n' order by nm) as ddl from (
  select 'COMMENT ON TABLE public.' || quote_ident(c.relname) || ' IS '
         || quote_literal(obj_description(c.oid, 'pg_class')) || ';' as ddl,
         c.relname as nm
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','v')
    and obj_description(c.oid, 'pg_class') is not null
  union all
  select 'COMMENT ON COLUMN public.' || quote_ident(c.relname) || '.' || quote_ident(a.attname)
         || ' IS ' || quote_literal(col_description(c.oid, a.attnum)) || ';',
         c.relname || '.' || a.attname
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  where n.nspname = 'public' and col_description(c.oid, a.attnum) is not null
) s;
