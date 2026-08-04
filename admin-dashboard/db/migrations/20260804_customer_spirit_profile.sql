-- EBTL: customer spirit profile — favorite spirits + most-ordered spirits
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is a hand-written migration meant to be
-- applied to the Supabase project with the Supabase MCP `apply_migration`
-- operation (preferred, because it records migration history) or the dashboard
-- SQL editor. This repo does not use the standard `supabase/migrations` layout,
-- so `supabase db push` will not discover this file automatically. It is
-- written to be idempotent and safe to re-run.
--
-- Context: "spirits" are rows in `liquor_types` — the bottles a customer brings
-- (the Cocktail Finder filters cocktails by them). The customer profile now
-- carries two spirit lists:
--
--   1. `customer_favorite_liquor_types` — spirits the customer picked by hand
--      on the profile screen. Mirrors `customer_favorite_products` (favorite
--      cocktails): a plain join table the customer adds to and removes from.
--
--   2. `customer_top_liquor_types` — the spirits that appear most often across
--      the customer's placed orders, recomputed by the backend on every order
--      confirmation (server/lib/customerSpirits.js). A spirit counts once per
--      order however many of its cocktails that order contains, and the list
--      keeps the top *two counts* — so ties at first or second place keep every
--      spirit that qualifies, and the list can hold more than two rows.
--
-- This migration:
--   1. Creates `customer_favorite_liquor_types`.
--   2. Creates `customer_top_liquor_types`.
--   3. Enables RLS and limits both tables to the service-role backend.
--   4. Adds supporting indexes.
--
-- NOT verified against the live schema — it was written without database
-- access. After applying, refresh the `db/schema/` capture with
-- `db/tools/dump_schema.sql` so the checked-in schema reflects these tables.

begin;

-- ---------------------------------------------------------------------------
-- 1. Favorite spirits (customer-curated)
-- ---------------------------------------------------------------------------

create table if not exists public.customer_favorite_liquor_types (
  customer_id     uuid        not null references public.customers(id) on delete cascade,
  liquor_type_id  uuid        not null references public.liquor_types(id) on delete cascade,
  created_at      timestamptz not null default now(),
  primary key (customer_id, liquor_type_id)
);

comment on table public.customer_favorite_liquor_types is
  'Spirits a customer marked as a favorite on their profile. Curated by hand — compare customer_top_liquor_types, which the backend computes.';

-- ---------------------------------------------------------------------------
-- 2. Most-ordered spirits (backend-computed)
-- ---------------------------------------------------------------------------

create table if not exists public.customer_top_liquor_types (
  customer_id     uuid        not null references public.customers(id) on delete cascade,
  liquor_type_id  uuid        not null references public.liquor_types(id) on delete cascade,
  order_count     integer     not null default 0,
  rank            integer     not null default 1,
  computed_at     timestamptz not null default now(),
  primary key (customer_id, liquor_type_id),
  constraint customer_top_liquor_types_order_count_positive_chk
    check (order_count > 0),
  constraint customer_top_liquor_types_rank_chk
    check (rank in (1, 2))
);

comment on table public.customer_top_liquor_types is
  'The spirits a customer orders most, recomputed in full on every order confirmation (server/lib/customerSpirits.js). Never written by hand.';
comment on column public.customer_top_liquor_types.order_count is
  'How many of the customer''s placed orders contain at least one cocktail using this spirit. Counted once per order, not per cocktail.';
comment on column public.customer_top_liquor_types.rank is
  'Which of the two kept places this spirit holds: 1 = most-ordered count, 2 = second-most. Ties share a rank, so a rank may hold several rows and the table may hold more than two per customer.';

-- ---------------------------------------------------------------------------
-- 3. Data API access
-- ---------------------------------------------------------------------------

-- Both tables are reached only through the Express backend's service-role
-- client. Keep them inaccessible to direct anon/authenticated Data API calls.
alter table public.customer_favorite_liquor_types enable row level security;
alter table public.customer_top_liquor_types enable row level security;

revoke all on table
  public.customer_favorite_liquor_types,
  public.customer_top_liquor_types
from anon, authenticated;

grant select, insert, delete
  on table public.customer_favorite_liquor_types
  to service_role;

grant select, insert, update, delete
  on table public.customer_top_liquor_types
  to service_role;

-- ---------------------------------------------------------------------------
-- 4. Indexes
-- ---------------------------------------------------------------------------

-- Both tables are read per customer, and the composite primary key already
-- covers that lead column. These cover the reverse lookup — "who favors /
-- mostly orders this spirit" — which the admin side will want, and which a
-- liquor-type delete cascade walks.
create index if not exists customer_favorite_liquor_types_liquor_type_idx
  on public.customer_favorite_liquor_types (liquor_type_id);

create index if not exists customer_top_liquor_types_liquor_type_idx
  on public.customer_top_liquor_types (liquor_type_id);

-- Favorites are listed newest-first.
create index if not exists customer_favorite_liquor_types_customer_created_at_idx
  on public.customer_favorite_liquor_types (customer_id, created_at desc);

commit;
