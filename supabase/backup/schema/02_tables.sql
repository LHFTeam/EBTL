-- ============================================================================
-- EBTL — Supabase schema backup: tables (columns + defaults only)
-- Constraints live in 03_constraints.sql so tables can be created in any order.
-- ============================================================================

SET search_path = public, extensions;

CREATE TABLE IF NOT EXISTS public.app_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid,
    session_id text,
    event_type text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.cart_daily_closings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    location_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    business_date date DEFAULT CURRENT_DATE NOT NULL,
    closing_cash numeric(12,2) DEFAULT 0 NOT NULL,
    stock_check_completed boolean DEFAULT false NOT NULL,
    total_waste_value numeric(12,2) DEFAULT 0 NOT NULL,
    variance_notes text,
    closed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.cart_daily_openings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    location_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    business_date date DEFAULT CURRENT_DATE NOT NULL,
    opening_cash numeric(12,2) DEFAULT 0 NOT NULL,
    stock_check_completed boolean DEFAULT false NOT NULL,
    notes text,
    opened_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.cart_item_additions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cart_item_id uuid NOT NULL,
    addon_product_id uuid NOT NULL,
    addon_variant_id uuid NOT NULL,
    addon_recipe_id uuid,
    quantity_per_parent integer DEFAULT 1 NOT NULL,
    product_name_snapshot text NOT NULL,
    variant_name_snapshot text,
    unit_price_inc_vat_snapshot numeric(12,2) NOT NULL,
    vat_rate_snapshot numeric(5,4) DEFAULT 0.14 NOT NULL,
    serving_count_snapshot integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.cart_item_removed_ingredients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cart_item_id uuid NOT NULL,
    recipe_item_id uuid NOT NULL,
    ingredient_id uuid NOT NULL,
    ingredient_name_snapshot text NOT NULL,
    quantity_snapshot numeric(12,3) NOT NULL,
    unit_snapshot text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.cart_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cart_id uuid NOT NULL,
    product_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    unit_price_inc_vat_snapshot numeric(12,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    vat_rate_snapshot numeric(5,4) DEFAULT 0.14 NOT NULL,
    recipe_id uuid,
    base_unit_price_inc_vat_snapshot numeric(12,2),
    customization_total_inc_vat_snapshot numeric(12,2) DEFAULT 0 NOT NULL,
    customization_hash text DEFAULT 'base'::text NOT NULL,
    customization_summary text
);

CREATE TABLE IF NOT EXISTS public.carts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid,
    selected_liquor_type_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    label text,
    compound_name text,
    beach_name text,
    unit_number text,
    building text,
    floor text,
    delivery_notes text,
    latitude numeric(10,7),
    longitude numeric(10,7),
    is_default boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    address text
);

CREATE TABLE IF NOT EXISTS public.customer_credit_ledger (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    delta_amount numeric(12,2) NOT NULL,
    reason text NOT NULL,
    referral_id uuid,
    order_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_favorite_liquor_types (
    customer_id uuid NOT NULL,
    liquor_type_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_favorite_products (
    customer_id uuid NOT NULL,
    product_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    order_id uuid,
    type text NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    dedupe_key text,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_payment_methods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    provider text DEFAULT 'geidea'::text NOT NULL,
    provider_token_id text NOT NULL,
    provider_agreement_id text,
    agreement_type text DEFAULT 'Unscheduled'::text,
    card_brand text,
    cardholder_name text,
    masked_card_number text,
    expiry_month integer,
    expiry_year integer,
    is_default boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    last_used_at timestamp with time zone,
    raw_payload jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_push_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    token text NOT NULL,
    token_hash text NOT NULL,
    platform text DEFAULT 'unknown'::text NOT NULL,
    device_id text,
    is_active boolean DEFAULT true NOT NULL,
    last_registered_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_top_liquor_types (
    customer_id uuid NOT NULL,
    liquor_type_id uuid NOT NULL,
    order_count integer DEFAULT 0 NOT NULL,
    rank integer DEFAULT 1 NOT NULL,
    computed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_user_id uuid,
    full_name text,
    phone text,
    email text,
    birthday date,
    marketing_opt_in boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    gender text,
    referral_code text,
    referred_by_customer_id uuid,
    referral_attributed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.employee_credentials (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    username text NOT NULL,
    password_hash text NOT NULL,
    password_salt text NOT NULL,
    must_change_password boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.employees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_user_id uuid,
    full_name text NOT NULL,
    phone text,
    role public.employee_role NOT NULL,
    default_location_id uuid,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.golden_hour_modes (
    mode text NOT NULL,
    is_active boolean DEFAULT false NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    title text,
    subtitle text,
    product_id uuid,
    image_url text,
    image_caption text,
    spirit_pill_scheme text DEFAULT 'sand'::text NOT NULL,
    pills jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.home_hero_banners (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    image_url text NOT NULL,
    headline text,
    body text,
    deep_link text,
    display_order integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.home_hero_settings (
    id boolean DEFAULT true NOT NULL,
    rotation_seconds integer DEFAULT 5 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ingredient_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ingredients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    base_unit text NOT NULL,
    purchase_unit_name text,
    purchase_unit_size numeric(12,3),
    purchase_unit_cost numeric(12,2),
    cost_per_base_unit numeric(12,6),
    is_perishable boolean DEFAULT false NOT NULL,
    shelf_life_days integer,
    allergen_flags text[] DEFAULT '{}'::text[] NOT NULL,
    is_customer_supplied boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    icon_key text,
    name_ar text,
    category_id uuid,
    is_searchable boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inventory_balances (
    ingredient_id uuid NOT NULL,
    location_id uuid NOT NULL,
    quantity_on_hand numeric(14,3) DEFAULT 0 NOT NULL,
    reserved_quantity numeric(14,3) DEFAULT 0 NOT NULL,
    reorder_point numeric(14,3) DEFAULT 0 NOT NULL,
    par_level numeric(14,3) DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.liquor_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    image_url text,
    display_order integer DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.location_opening_hours (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    location_id uuid NOT NULL,
    day_of_week integer NOT NULL,
    opens_at time without time zone,
    closes_at time without time zone,
    is_closed boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.locations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    type public.location_type NOT NULL,
    compound_name text,
    beach_name text,
    address text,
    latitude numeric(10,7),
    longitude numeric(10,7),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    banner_image_url text,
    delivery_fee numeric(12,2) DEFAULT 0 NOT NULL,
    name_ar text
);

CREATE TABLE IF NOT EXISTS public.loyalty_accounts (
    customer_id uuid NOT NULL,
    points_balance integer DEFAULT 0 NOT NULL,
    tier text DEFAULT 'standard'::text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.loyalty_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    order_id uuid,
    points_delta integer NOT NULL,
    reason text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.order_inventory_consumptions (
    order_id uuid NOT NULL,
    consumed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.order_item_additions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_item_id uuid NOT NULL,
    addon_product_id uuid,
    addon_variant_id uuid,
    addon_recipe_id uuid,
    quantity_per_parent integer DEFAULT 1 NOT NULL,
    product_name_snapshot text NOT NULL,
    variant_name_snapshot text,
    unit_price_inc_vat_snapshot numeric(12,2) NOT NULL,
    vat_rate_snapshot numeric(5,4) DEFAULT 0.14 NOT NULL,
    serving_count_snapshot integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.order_item_inventory_components (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_item_id uuid NOT NULL,
    ingredient_id uuid NOT NULL,
    ingredient_name_snapshot text NOT NULL,
    source_type text NOT NULL,
    source_ref_id uuid,
    quantity_per_order_item_unit numeric(12,3) NOT NULL,
    unit_snapshot text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.order_item_removed_ingredients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_item_id uuid NOT NULL,
    recipe_item_id uuid,
    ingredient_id uuid,
    ingredient_name_snapshot text NOT NULL,
    quantity_snapshot numeric(12,3) NOT NULL,
    unit_snapshot text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.order_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    product_id uuid,
    variant_id uuid,
    recipe_id uuid,
    product_name_snapshot text NOT NULL,
    variant_name_snapshot text,
    quantity integer NOT NULL,
    unit_price_inc_vat_snapshot numeric(12,2) NOT NULL,
    vat_rate_snapshot numeric(5,4) DEFAULT 0.14 NOT NULL,
    line_total numeric(12,2) NOT NULL,
    prep_status public.prep_status DEFAULT 'queued'::public.prep_status NOT NULL,
    issue_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    base_unit_price_inc_vat_snapshot numeric(12,2),
    customization_total_inc_vat_snapshot numeric(12,2) DEFAULT 0 NOT NULL,
    customization_summary text
);

CREATE TABLE IF NOT EXISTS public.order_number_counters (
    order_date date NOT NULL,
    last_number integer NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.order_prep_tasks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_item_id uuid NOT NULL,
    station_id uuid,
    assigned_employee_id uuid,
    status public.prep_status DEFAULT 'queued'::public.prep_status NOT NULL,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    issue_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_number text NOT NULL,
    customer_id uuid,
    location_id uuid NOT NULL,
    customer_address_id uuid,
    order_channel text DEFAULT 'app'::text NOT NULL,
    fulfillment_type public.fulfillment_type DEFAULT 'pickup_at_cart'::public.fulfillment_type NOT NULL,
    status public.order_status DEFAULT 'draft'::public.order_status NOT NULL,
    payment_status public.payment_status DEFAULT 'unpaid'::public.payment_status NOT NULL,
    requested_fulfillment_at timestamp with time zone,
    subtotal_ex_vat numeric(12,2) DEFAULT 0 NOT NULL,
    vat_amount numeric(12,2) DEFAULT 0 NOT NULL,
    discount_amount numeric(12,2) DEFAULT 0 NOT NULL,
    delivery_fee numeric(12,2) DEFAULT 0 NOT NULL,
    total_amount numeric(12,2) DEFAULT 0 NOT NULL,
    customer_notes text,
    internal_notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    customer_phone_snapshot text,
    customer_address_snapshot text,
    confirmed_at timestamp with time zone,
    preparing_at timestamp with time zone,
    ready_at timestamp with time zone,
    completed_at timestamp with time zone,
    business_date date DEFAULT ((now() AT TIME ZONE 'Africa/Cairo'::text))::date NOT NULL,
    referral_id uuid,
    credit_applied numeric(12,2) DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.payment_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider text NOT NULL,
    provider_event_id text NOT NULL,
    event_type text NOT NULL,
    processed_at timestamp with time zone,
    raw_payload jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    provider text NOT NULL,
    provider_payment_id text,
    amount numeric(12,2) NOT NULL,
    currency text DEFAULT 'EGP'::text NOT NULL,
    status public.payment_status DEFAULT 'pending'::public.payment_status NOT NULL,
    idempotency_key text,
    raw_payload jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.prep_stations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    location_id uuid NOT NULL,
    name text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.product_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    slug text,
    image_url text
);

CREATE TABLE IF NOT EXISTS public.product_liquor_compatibility (
    product_id uuid NOT NULL,
    liquor_type_id uuid NOT NULL,
    required_ml_per_serving numeric(12,3),
    display_instruction text
);

CREATE TABLE IF NOT EXISTS public.product_tags (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    color_hex text NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    show_in_filters boolean DEFAULT true NOT NULL,
    show_on_product_card boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    product_id uuid NOT NULL,
    name text NOT NULL,
    serving_count integer DEFAULT 1 NOT NULL,
    price_ex_vat numeric(12,2) DEFAULT 0 NOT NULL,
    vat_rate numeric(5,4) DEFAULT 0.14 NOT NULL,
    price_inc_vat numeric(12,2) GENERATED ALWAYS AS (round((price_ex_vat * ((1)::numeric + vat_rate)), 2)) STORED,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    name_ar text
);

CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category_id uuid,
    name text NOT NULL,
    slug text NOT NULL,
    description text,
    image_url text,
    status public.product_status DEFAULT 'draft'::public.product_status NOT NULL,
    is_featured boolean DEFAULT false NOT NULL,
    prep_time_minutes integer DEFAULT 5 NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    product_type public.product_type DEFAULT 'cocktail'::public.product_type NOT NULL,
    short_description text,
    name_ar text
);

CREATE TABLE IF NOT EXISTS public.promotion_redemptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    promotion_id uuid NOT NULL,
    customer_id uuid,
    order_id uuid,
    discount_amount numeric(12,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.promotions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    discount_type public.promotion_discount_type NOT NULL,
    discount_value numeric(12,2) NOT NULL,
    min_order_value numeric(12,2) DEFAULT 0 NOT NULL,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    usage_limit integer,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    description text,
    max_discount_amount numeric(12,2),
    per_customer_limit integer,
    first_order_only boolean DEFAULT false NOT NULL,
    allowed_fulfillment_type text
);

CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    purchase_order_id uuid NOT NULL,
    ingredient_id uuid NOT NULL,
    ordered_quantity numeric(14,3) DEFAULT 0 NOT NULL,
    received_quantity numeric(14,3) DEFAULT 0 NOT NULL,
    unit_cost numeric(12,4) DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    supplier_id uuid,
    location_id uuid NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    expected_date date,
    received_at timestamp with time zone,
    total_cost numeric(12,2) DEFAULT 0 NOT NULL,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.recipe_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    recipe_id uuid NOT NULL,
    ingredient_id uuid NOT NULL,
    quantity numeric(12,3) NOT NULL,
    unit text NOT NULL,
    is_optional boolean DEFAULT false NOT NULL,
    is_customer_supplied boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.recipes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    product_id uuid NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    status public.product_status DEFAULT 'draft'::public.product_status NOT NULL,
    yield_servings integer DEFAULT 1 NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.referral_settings (
    id boolean DEFAULT true NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    referrer_reward_amount numeric(12,2) DEFAULT 100 NOT NULL,
    referee_discount_type text DEFAULT 'fixed_amount'::text NOT NULL,
    referee_discount_value numeric(12,2) DEFAULT 75 NOT NULL,
    referee_max_discount_amount numeric(12,2),
    min_qualifying_order_value numeric(12,2) DEFAULT 0 NOT NULL,
    reward_cap_per_referrer integer,
    terms text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.referrals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    referrer_customer_id uuid NOT NULL,
    referee_customer_id uuid NOT NULL,
    referral_code text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    qualifying_order_id uuid,
    referee_discount_amount numeric(12,2) DEFAULT 0 NOT NULL,
    referrer_reward_amount numeric(12,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    qualified_at timestamp with time zone,
    rewarded_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.shop_settings (
    id boolean DEFAULT true NOT NULL,
    banner_image_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.spotlight_banner_categories (
    banner_id uuid NOT NULL,
    category_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS public.spotlight_banner_products (
    banner_id uuid NOT NULL,
    product_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS public.spotlight_banners (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    image_url text NOT NULL,
    title text NOT NULL,
    subtitle text,
    display_order integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    content_type text DEFAULT 'products'::text NOT NULL,
    markdown_body text
);

CREATE TABLE IF NOT EXISTS public.stock_movements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ingredient_id uuid NOT NULL,
    location_id uuid NOT NULL,
    movement_type public.movement_type NOT NULL,
    quantity_delta numeric(14,3) NOT NULL,
    unit_cost numeric(12,4),
    related_order_id uuid,
    related_transfer_id uuid,
    reason text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.stock_transfer_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    transfer_id uuid NOT NULL,
    ingredient_id uuid NOT NULL,
    requested_qty numeric(14,3) DEFAULT 0 NOT NULL,
    dispatched_qty numeric(14,3) DEFAULT 0 NOT NULL,
    received_qty numeric(14,3) DEFAULT 0 NOT NULL,
    variance_qty numeric(14,3) GENERATED ALWAYS AS ((received_qty - dispatched_qty)) STORED
);

CREATE TABLE IF NOT EXISTS public.stock_transfer_movement_events (
    transfer_id uuid NOT NULL,
    event_type text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.stock_transfers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    transfer_number text,
    from_location_id uuid NOT NULL,
    to_location_id uuid NOT NULL,
    status public.transfer_status DEFAULT 'draft'::public.transfer_status NOT NULL,
    requested_by uuid,
    approved_by uuid,
    dispatched_by uuid,
    received_by uuid,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    dispatched_at timestamp with time zone,
    received_at timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    contact_name text,
    phone text,
    email text,
    address text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

-- ---------------------------------------------------------------------------
-- Demand forecasting module (server/forecast/), migration 20260807171440.
-- Appended as a block rather than sorted inline; the next full run of
-- ../tools/dump_schema.sql will re-sort these into place.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.forecast_accuracy_cart (
    location_id uuid NOT NULL,
    business_date date NOT NULL,
    horizon_days integer DEFAULT 1 NOT NULL,
    forecast_p50 integer DEFAULT 0 NOT NULL,
    forecast_p90 integer DEFAULT 0 NOT NULL,
    expected_units numeric(12,4) DEFAULT 0 NOT NULL,
    actual_units integer DEFAULT 0 NOT NULL,
    abs_error numeric(12,4) DEFAULT 0 NOT NULL,
    naive_forecast numeric(12,4),
    naive_abs_error numeric(12,4),
    pinball_loss numeric(12,4) DEFAULT 0 NOT NULL,
    within_p90 boolean DEFAULT true NOT NULL,
    scored_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_accuracy_product (
    location_id uuid NOT NULL,
    business_date date NOT NULL,
    product_id uuid NOT NULL,
    horizon_days integer DEFAULT 1 NOT NULL,
    forecast_p50 integer DEFAULT 0 NOT NULL,
    forecast_p90 integer DEFAULT 0 NOT NULL,
    expected_units numeric(12,4) DEFAULT 0 NOT NULL,
    actual_units integer DEFAULT 0 NOT NULL,
    abs_error numeric(12,4) DEFAULT 0 NOT NULL,
    naive_forecast numeric(12,4),
    naive_abs_error numeric(12,4),
    pinball_loss numeric(12,4) DEFAULT 0 NOT NULL,
    within_p90 boolean DEFAULT true NOT NULL,
    scored_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_campaign_effects (
    campaign_type text NOT NULL,
    discount_bucket text NOT NULL,
    log_uplift_mean numeric(10,6) DEFAULT 0 NOT NULL,
    observations integer DEFAULT 0 NOT NULL,
    pull_forward_ratio numeric(6,4) DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_campaign_locations (
    campaign_id uuid NOT NULL,
    location_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_campaign_observations (
    campaign_id uuid NOT NULL,
    location_id uuid NOT NULL,
    business_date date NOT NULL,
    actual_units integer DEFAULT 0 NOT NULL,
    baseline_forecast numeric(12,4) DEFAULT 0 NOT NULL,
    ratio numeric(10,5),
    promo_order_share numeric(6,4) DEFAULT 0 NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_campaign_products (
    campaign_id uuid NOT NULL,
    product_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_campaigns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    campaign_type text DEFAULT 'promo_code'::text NOT NULL,
    scope text DEFAULT 'network'::text NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    promotion_id uuid,
    discount_pct numeric(6,3),
    expected_uplift_pct numeric(8,3) DEFAULT 0 NOT NULL,
    expected_promo_order_share numeric(6,4),
    learned_log_uplift numeric(10,6),
    learned_observations integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_cart_assumptions (
    location_id uuid NOT NULL,
    day_of_week integer NOT NULL,
    expected_units numeric(10,2),
    expected_orders numeric(10,2),
    prior_strength_days integer DEFAULT 14 NOT NULL,
    notes text,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_cart_state (
    location_id uuid NOT NULL,
    level numeric(12,4) DEFAULT 0 NOT NULL,
    dispersion numeric(10,5) DEFAULT 0 NOT NULL,
    dow_index numeric(8,5)[] DEFAULT ARRAY[(1)::numeric(8,5), (1)::numeric(8,5), (1)::numeric(8,5), (1)::numeric(8,5), (1)::numeric(8,5), (1)::numeric(8,5), (1)::numeric(8,5)] NOT NULL,
    dow_obs_count integer[] DEFAULT ARRAY[0, 0, 0, 0, 0, 0, 0] NOT NULL,
    observations integer DEFAULT 0 NOT NULL,
    residual_sum_sq numeric(16,5) DEFAULT 0 NOT NULL,
    residual_count integer DEFAULT 0 NOT NULL,
    last_business_date date,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_daily_cart (
    location_id uuid NOT NULL,
    business_date date NOT NULL,
    horizon_days integer DEFAULT 0 NOT NULL,
    expected_units numeric(12,4) DEFAULT 0 NOT NULL,
    p50 integer DEFAULT 0 NOT NULL,
    p90 integer DEFAULT 0 NOT NULL,
    expected_orders numeric(12,4) DEFAULT 0 NOT NULL,
    expected_revenue numeric(12,2) DEFAULT 0 NOT NULL,
    campaign_uplift numeric(8,4) DEFAULT 1 NOT NULL,
    campaign_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    confidence text DEFAULT 'low'::text NOT NULL,
    sample_size integer DEFAULT 0 NOT NULL,
    model_version text NOT NULL,
    generated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_daily_product (
    location_id uuid NOT NULL,
    business_date date NOT NULL,
    product_id uuid NOT NULL,
    horizon_days integer DEFAULT 0 NOT NULL,
    mix_share numeric(8,6) DEFAULT 0 NOT NULL,
    expected_units numeric(12,4) DEFAULT 0 NOT NULL,
    p50 integer DEFAULT 0 NOT NULL,
    p90 integer DEFAULT 0 NOT NULL,
    expected_revenue numeric(12,2) DEFAULT 0 NOT NULL,
    campaign_uplift numeric(8,4) DEFAULT 1 NOT NULL,
    confidence text DEFAULT 'low'::text NOT NULL,
    sample_size integer DEFAULT 0 NOT NULL,
    model_version text NOT NULL,
    generated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_demand_daily_cart (
    location_id uuid NOT NULL,
    business_date date NOT NULL,
    units integer DEFAULT 0 NOT NULL,
    orders integer DEFAULT 0 NOT NULL,
    revenue numeric(12,2) DEFAULT 0 NOT NULL,
    traded boolean DEFAULT true NOT NULL,
    promo_orders integer DEFAULT 0 NOT NULL,
    promo_order_share numeric(6,4) DEFAULT 0 NOT NULL,
    mean_discount_pct numeric(7,3) DEFAULT 0 NOT NULL,
    applied_uplift numeric(8,4) DEFAULT 1 NOT NULL,
    baseline_units numeric(12,3) DEFAULT 0 NOT NULL,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_demand_daily_product (
    location_id uuid NOT NULL,
    business_date date NOT NULL,
    product_id uuid NOT NULL,
    units integer DEFAULT 0 NOT NULL,
    revenue numeric(12,2) DEFAULT 0 NOT NULL,
    applied_uplift numeric(8,4) DEFAULT 1 NOT NULL,
    baseline_units numeric(12,3) DEFAULT 0 NOT NULL,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_network_state (
    id boolean DEFAULT true NOT NULL,
    dow_index numeric(8,5)[] DEFAULT ARRAY[(1)::numeric(8,5), (1)::numeric(8,5), (1)::numeric(8,5), (1)::numeric(8,5), (1)::numeric(8,5), (1)::numeric(8,5), (1)::numeric(8,5)] NOT NULL,
    dow_obs_count integer[] DEFAULT ARRAY[0, 0, 0, 0, 0, 0, 0] NOT NULL,
    mean_level numeric(12,4) DEFAULT 0 NOT NULL,
    dispersion numeric(10,5) DEFAULT 0 NOT NULL,
    product_mix jsonb DEFAULT '{}'::jsonb NOT NULL,
    observations integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_product_state (
    location_id uuid NOT NULL,
    product_id uuid NOT NULL,
    alpha numeric(12,5) DEFAULT 0 NOT NULL,
    units_ewma numeric(12,5) DEFAULT 0 NOT NULL,
    observations integer DEFAULT 0 NOT NULL,
    last_sold_date date,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.forecast_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    trigger text DEFAULT 'schedule'::text NOT NULL,
    through_date date,
    dates_processed integer DEFAULT 0 NOT NULL,
    forecasts_written integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'running'::text NOT NULL,
    error text,
    model_version text
);
