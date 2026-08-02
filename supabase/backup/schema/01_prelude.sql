-- ============================================================================
-- EBTL — Supabase schema backup: prelude
-- Extensions, schemas, enum types, standalone sequences.
-- Run first. Everything here is idempotent.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;

CREATE SCHEMA IF NOT EXISTS public;

SET search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Enum types
-- ---------------------------------------------------------------------------

DO $$ BEGIN
    CREATE TYPE public.employee_role AS ENUM ('prep', 'cart_operator', 'warehouse', 'supervisor', 'manager', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.fulfillment_type AS ENUM ('pickup_at_cart', 'delivery_to_unit');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.location_type AS ENUM ('central_warehouse', 'beach_cart');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.movement_type AS ENUM ('purchase_received', 'transfer_out', 'transfer_in', 'sale_consumption', 'waste', 'adjustment', 'return_to_warehouse');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.order_status AS ENUM ('draft', 'pending_payment', 'expired', 'confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed', 'cancelled', 'refunded');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.payment_status AS ENUM ('unpaid', 'pending', 'paid', 'failed', 'refunded', 'partially_refunded');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.prep_status AS ENUM ('queued', 'in_progress', 'packed', 'blocked', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.product_status AS ENUM ('draft', 'active', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.product_type AS ENUM ('cocktail', 'snack', 'essential', 'bundle', 'add_on');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.promotion_discount_type AS ENUM ('percentage', 'fixed_amount', 'free_delivery');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE public.transfer_status AS ENUM ('draft', 'picked', 'in_transit', 'received', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- Standalone sequences (not owned by a column)
-- ---------------------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS public.order_number_seq AS bigint START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
CREATE SEQUENCE IF NOT EXISTS public.transfer_number_seq AS bigint START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
