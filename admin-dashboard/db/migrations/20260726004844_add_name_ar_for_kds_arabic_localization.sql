-- Backfilled from supabase_migrations.schema_migrations (leading indentation
-- normalised; the SQL is otherwise unchanged).
-- Already applied to the live project; recorded here for history, not to run.

alter table public.products         add column if not exists name_ar text;
alter table public.product_variants add column if not exists name_ar text;
alter table public.ingredients      add column if not exists name_ar text;
alter table public.locations        add column if not exists name_ar text;

comment on column public.products.name_ar         is 'Arabic display name (optional); falls back to name when null. Used by the KDS.';
comment on column public.product_variants.name_ar is 'Arabic display name (optional); falls back to name when null. Used by the KDS.';
comment on column public.ingredients.name_ar      is 'Arabic display name (optional); falls back to name when null. Used by the KDS.';
comment on column public.locations.name_ar        is 'Arabic display name (optional); falls back to name when null. Used by the KDS.';
