-- EBTL: promo code engine — richer promotion controls
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is a hand-written migration meant to be
-- applied to the Supabase project (dashboard SQL editor, `supabase db push`,
-- or the Supabase MCP `apply_migration`). It is written to be idempotent and
-- safe to re-run.
--
-- Context: the customer checkout already reads `promotions` and writes
-- `promotion_redemptions` (see server/routes/customerRoutes.js —
-- resolvePromotion / recordPromotionRedemptionIfNeeded). Those tables already
-- exist in the live schema with at least:
--   promotions(id, code, name, discount_type, discount_value, is_active,
--              starts_at, ends_at, min_order_value, usage_limit)
--   promotion_redemptions(id, promotion_id, customer_id, order_id,
--                         discount_amount)
--
-- This migration:
--   1. Bootstraps both tables with CREATE TABLE IF NOT EXISTS so a fresh
--      environment has them (no-op where they already exist).
--   2. Adds the new admin-facing control columns to `promotions` that the
--      promo-code engine's admin page and checkout enforcement rely on. Each
--      ADD COLUMN IF NOT EXISTS is the authoritative change for an existing DB.
--   3. Adds supporting indexes.

begin;

-- ---------------------------------------------------------------------------
-- 1. Bootstrap tables (no-op when they already exist)
-- ---------------------------------------------------------------------------

create table if not exists public.promotions (
  id              uuid        primary key default gen_random_uuid(),
  code            text        not null unique,
  name            text        not null,
  description     text,
  discount_type   text        not null default 'percentage',
  discount_value  numeric(12,2) not null default 0,
  max_discount_amount numeric(12,2),
  min_order_value numeric(12,2) not null default 0,
  usage_limit     integer,
  per_customer_limit integer,
  first_order_only boolean     not null default false,
  allowed_fulfillment_type text,
  starts_at       timestamptz,
  ends_at         timestamptz,
  is_active       boolean     not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.promotions is
  'Promo codes. Backs the admin promo-code engine and customer checkout discounting.';

create table if not exists public.promotion_redemptions (
  id              uuid        primary key default gen_random_uuid(),
  promotion_id    uuid        not null references public.promotions(id) on delete cascade,
  customer_id     uuid,
  order_id        uuid,
  discount_amount numeric(12,2) not null default 0,
  created_at      timestamptz not null default now()
);

comment on table public.promotion_redemptions is
  'One row per time a promo code was applied to a placed/paid order.';

-- ---------------------------------------------------------------------------
-- 2. New control columns on promotions (authoritative for existing DBs)
-- ---------------------------------------------------------------------------

alter table public.promotions
  add column if not exists description text,
  add column if not exists max_discount_amount numeric(12,2),
  add column if not exists per_customer_limit integer,
  add column if not exists first_order_only boolean not null default false,
  add column if not exists allowed_fulfillment_type text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

comment on column public.promotions.description is
  'Internal-only note about the promo (never shown to customers).';
comment on column public.promotions.max_discount_amount is
  'Optional cap on the discount value in EGP. Most useful for percentage codes.';
comment on column public.promotions.per_customer_limit is
  'Max times a single customer may redeem this code. NULL = unlimited.';
comment on column public.promotions.first_order_only is
  'When true, only customers with no prior non-cancelled orders may redeem.';
comment on column public.promotions.allowed_fulfillment_type is
  'Restrict the code to a fulfillment type: pickup_at_cart or delivery_to_unit. NULL = any.';

-- ---------------------------------------------------------------------------
-- 3. Indexes
-- ---------------------------------------------------------------------------

-- Case-insensitive lookup by code (checkout does ilike on code). Kept
-- non-unique so the migration never fails on legacy case-variant rows; the
-- admin API normalizes codes to upper-case and the existing `code` unique
-- constraint enforces uniqueness.
create index if not exists promotions_code_lower_idx
  on public.promotions (lower(code));

create index if not exists promotion_redemptions_promotion_id_idx
  on public.promotion_redemptions (promotion_id);

create index if not exists promotion_redemptions_customer_idx
  on public.promotion_redemptions (promotion_id, customer_id);

commit;
