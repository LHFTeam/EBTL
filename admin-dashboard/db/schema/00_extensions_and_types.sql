-- EBTL baseline schema — extensions and enum types.
-- Captured from the live Supabase project; see README.md in this directory.

-- Extensions
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- Enum types
CREATE TYPE public.employee_role AS ENUM ('prep', 'cart_operator', 'warehouse', 'supervisor', 'manager', 'admin');
CREATE TYPE public.fulfillment_type AS ENUM ('pickup_at_cart', 'delivery_to_unit');
CREATE TYPE public.location_type AS ENUM ('central_warehouse', 'beach_cart');
CREATE TYPE public.movement_type AS ENUM ('purchase_received', 'transfer_out', 'transfer_in', 'sale_consumption', 'waste', 'adjustment', 'return_to_warehouse');
CREATE TYPE public.order_status AS ENUM ('draft', 'pending_payment', 'expired', 'confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed', 'cancelled', 'refunded');
CREATE TYPE public.payment_status AS ENUM ('unpaid', 'pending', 'paid', 'failed', 'refunded', 'partially_refunded');
CREATE TYPE public.prep_status AS ENUM ('queued', 'in_progress', 'packed', 'blocked', 'cancelled');
CREATE TYPE public.product_status AS ENUM ('draft', 'active', 'archived');
CREATE TYPE public.product_type AS ENUM ('cocktail', 'snack', 'essential', 'bundle', 'add_on');
CREATE TYPE public.promotion_discount_type AS ENUM ('percentage', 'fixed_amount', 'free_delivery');
CREATE TYPE public.transfer_status AS ENUM ('draft', 'picked', 'in_transit', 'received', 'cancelled');
