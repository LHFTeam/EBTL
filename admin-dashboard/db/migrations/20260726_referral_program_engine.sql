-- EBTL: referral program engine — double-sided referral loop with store credit
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is a hand-written migration meant to be
-- applied to the Supabase project (dashboard SQL editor, `supabase db push`,
-- or the Supabase MCP `apply_migration`). It is written to be idempotent and
-- safe to re-run.
--
-- Context: the customer app has no login — a customer is an anonymous session
-- token mapped to a row in `customers`. This migration introduces a referral
-- loop on top of the existing promo-code engine (see
-- server/routes/customerRoutes.js — resolvePromotion /
-- recordPromotionRedemptionIfNeeded and server/lib/referrals.js):
--   * Each customer gets a unique, shareable `referral_code`.
--   * A new customer who applies a code is attributed to the referrer and earns
--     a first-order discount (the "referee" reward, computed at checkout).
--   * Once that referee completes a qualifying paid first order, the referrer
--     earns store credit (the "referrer" reward), tracked in an append-only
--     ledger and auto-applied at the referrer's next checkout.
--
-- This migration:
--   1. Adds referral columns to `customers`.
--   2. Creates `referral_settings` (single-row program config) with a seed row.
--   3. Creates `referrals` (one row per attributed friend).
--   4. Creates `customer_credit_ledger` (append-only store-credit wallet).
--   5. Adds supporting indexes.

begin;

-- ---------------------------------------------------------------------------
-- 1. Referral columns on `customers`
-- ---------------------------------------------------------------------------

alter table public.customers
  add column if not exists referral_code text,
  add column if not exists referred_by_customer_id uuid references public.customers(id) on delete set null,
  add column if not exists referral_attributed_at timestamptz;

comment on column public.customers.referral_code is
  'The customer''s own shareable referral code (e.g. EBTL-XXXXX). Lazily generated.';
comment on column public.customers.referred_by_customer_id is
  'The customer who referred this customer, if they applied a referral code.';
comment on column public.customers.referral_attributed_at is
  'When this customer was attributed to a referrer (first successful code apply).';

-- Case-insensitive uniqueness for referral codes. Non-unique index kept as a
-- fallback; the unique index is the authoritative guard. Both are conditional
-- so the migration never fails on legacy NULLs.
create unique index if not exists customers_referral_code_lower_uidx
  on public.customers (lower(referral_code))
  where referral_code is not null;

-- ---------------------------------------------------------------------------
-- 2. Program configuration (single row)
-- ---------------------------------------------------------------------------

create table if not exists public.referral_settings (
  id                          boolean     primary key default true,
  is_active                   boolean     not null default true,
  referrer_reward_amount      numeric(12,2) not null default 100,
  referee_discount_type       text        not null default 'fixed_amount',
  referee_discount_value      numeric(12,2) not null default 75,
  referee_max_discount_amount numeric(12,2),
  min_qualifying_order_value  numeric(12,2) not null default 0,
  reward_cap_per_referrer     integer,
  terms                       text,
  updated_at                  timestamptz not null default now(),
  constraint referral_settings_singleton check (id = true)
);

comment on table public.referral_settings is
  'Single-row referral program configuration. Backs the admin Referrals page and checkout/reward enforcement.';
comment on column public.referral_settings.referrer_reward_amount is
  'Store credit (EGP) granted to the referrer when a referee completes a qualifying paid first order.';
comment on column public.referral_settings.referee_discount_type is
  'How the referee''s first-order discount is computed: percentage or fixed_amount.';
comment on column public.referral_settings.referee_max_discount_amount is
  'Optional cap (EGP) on the referee discount. Most useful for percentage discounts.';
comment on column public.referral_settings.min_qualifying_order_value is
  'Minimum order subtotal (EGP) for a referee order to unlock the referrer reward.';
comment on column public.referral_settings.reward_cap_per_referrer is
  'Max number of rewarded referrals a single referrer may earn. NULL = unlimited.';

-- Seed the singleton config row (no-op if it already exists).
insert into public.referral_settings (id)
values (true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Referrals (one row per attributed friend)
-- ---------------------------------------------------------------------------

create table if not exists public.referrals (
  id                      uuid        primary key default gen_random_uuid(),
  referrer_customer_id    uuid        not null references public.customers(id) on delete cascade,
  referee_customer_id     uuid        not null unique references public.customers(id) on delete cascade,
  referral_code           text        not null,
  status                  text        not null default 'pending',
  qualifying_order_id     uuid,
  referee_discount_amount numeric(12,2) not null default 0,
  referrer_reward_amount  numeric(12,2) not null default 0,
  created_at              timestamptz not null default now(),
  qualified_at            timestamptz,
  rewarded_at             timestamptz,
  constraint referrals_status_chk
    check (status in ('pending', 'qualified', 'rewarded', 'void')),
  constraint referrals_no_self_referral
    check (referrer_customer_id <> referee_customer_id)
);

comment on table public.referrals is
  'One row per attributed referral. status: pending (attributed) -> rewarded (referee''s first qualifying paid order granted the referrer credit). void = disqualified.';
comment on column public.referrals.qualifying_order_id is
  'The referee order that unlocked the referrer reward (idempotency guard).';

-- ---------------------------------------------------------------------------
-- 4. Store-credit wallet (append-only ledger)
-- ---------------------------------------------------------------------------

create table if not exists public.customer_credit_ledger (
  id            uuid        primary key default gen_random_uuid(),
  customer_id   uuid        not null references public.customers(id) on delete cascade,
  delta_amount  numeric(12,2) not null,
  reason        text        not null,
  referral_id   uuid        references public.referrals(id) on delete set null,
  order_id      uuid,
  created_at    timestamptz not null default now(),
  constraint customer_credit_ledger_reason_chk
    check (reason in ('referral_reward', 'order_redemption', 'admin_adjustment'))
);

comment on table public.customer_credit_ledger is
  'Append-only store-credit wallet. Positive delta = credit earned, negative = credit spent. Balance = sum(delta_amount) per customer.';

-- ---------------------------------------------------------------------------
-- 5. Order linkage (referral attribution + credit spent)
-- ---------------------------------------------------------------------------

alter table public.orders
  add column if not exists referral_id uuid references public.referrals(id) on delete set null,
  add column if not exists credit_applied numeric(12,2) not null default 0;

comment on column public.orders.referral_id is
  'The referral this order fulfilled the referee side of (earned the referee a first-order discount).';
comment on column public.orders.credit_applied is
  'Store credit (EGP) spent on this order, redeemed from customer_credit_ledger on payment success.';

-- ---------------------------------------------------------------------------
-- 6. Indexes
-- ---------------------------------------------------------------------------

create index if not exists referrals_referrer_idx
  on public.referrals (referrer_customer_id);

create index if not exists referrals_referee_idx
  on public.referrals (referee_customer_id);

create index if not exists referrals_status_idx
  on public.referrals (status);

create index if not exists customer_credit_ledger_customer_idx
  on public.customer_credit_ledger (customer_id);

-- One reward ledger row per referral (idempotent reward grant).
create unique index if not exists customer_credit_ledger_referral_reward_uidx
  on public.customer_credit_ledger (referral_id)
  where reason = 'referral_reward' and referral_id is not null;

-- One redemption ledger row per order (idempotent credit spend across the
-- COD / Geidea / Stripe payment-success paths).
create unique index if not exists customer_credit_ledger_order_redemption_uidx
  on public.customer_credit_ledger (order_id)
  where reason = 'order_redemption' and order_id is not null;

commit;
