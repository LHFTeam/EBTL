-- EBTL: beach-cart demand forecasting module
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is the record of a migration already
-- applied to the live project (`apply_migration`, ledger version
-- 20260807171440). It is idempotent and safe to re-run.
--
-- Why: staff have no way to answer "how much of what do we load onto the
-- Hacienda cart on Friday?". Analytics and v_daily_sales_by_location look
-- backwards only. This adds a forward-looking demand model — expected units per
-- product per cart per day — refreshed nightly after Cairo midnight from the
-- previous day's actuals, feeding cart stocking, warehouse prep, and revenue
-- and staffing planning.
--
-- STANDALONE MODULE. Every object here is prefixed `forecast_` and nothing
-- outside the module writes to any of it. No existing table, view, function or
-- trigger is altered. Dropping the module means dropping these tables and
-- unmounting server/forecast — no other part of the schema depends on them.
-- Foreign keys point outwards only (locations, products, promotions,
-- employees), never the reverse.
--
-- The model is a three-level hierarchical decomposition:
--
--   units(cart, date, product) = level x dow_index x campaign_uplift x mix_share
--
-- with every level shrunk toward a pooled prior by n/(n+k). That structure is
-- not decoration: at the time of writing the business has sold 84 units total
-- across 11 trading days and 2 carts, against ~966 (cart x product x weekday)
-- cells. Fitting those cells independently would be fitting noise. Shrinkage
-- means the model reports the prior, honestly and with wide intervals, until
-- the data earns something sharper — and needs no code change when it does.
--
-- Facts are kept separately from state (forecast_demand_daily_*) so the
-- recursive estimators can always be rebuilt deterministically from them. A
-- recursive model you cannot replay is a model you cannot audit.
--
-- Cart-level and product-level rows are separate tables rather than one table
-- with a nullable product_id. A nullable column in a primary key needs partial
-- unique indexes, and PostgREST upserts need a conflict target that matches a
-- real index — two plain composite keys keep the nightly job's upserts trivial.
--
-- RLS mirrors golden_hour_modes: is_manager_or_admin() writes, is_staff()
-- reads, no anon access. None of this is customer-facing.

-- ---------------------------------------------------------------------------
-- Facts. Built from orders + order_items, and the only input the model reads.
-- Materialised rather than computed on the fly so the nightly update is O(one
-- day) and so a change to order-status semantics cannot silently rewrite
-- history the model has already learned from.
-- ---------------------------------------------------------------------------

-- One row per cart per Cairo business date.
--
-- `traded` distinguishes "open and sold nothing" from "shut", which the level
-- recursion must not treat alike: a closed day is missing data, a zero day is
-- evidence. cart_daily_openings is empty in production, so ingest falls back to
-- location_opening_hours.is_closed — see the module's ingest.js.
--
-- `baseline_units` is `units` with the day's campaign uplift divided out. It,
-- not `units`, is what the smoother consumes, so a promotion cannot inflate the
-- level permanently. Storing both makes the base/lift split of any past day
-- inspectable instead of implicit.
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
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_demand_daily_cart_pkey PRIMARY KEY (location_id, business_date),
    CONSTRAINT forecast_demand_daily_cart_location_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE,
    CONSTRAINT forecast_demand_daily_cart_units_non_negative CHECK (units >= 0),
    CONSTRAINT forecast_demand_daily_cart_orders_non_negative CHECK (orders >= 0),
    CONSTRAINT forecast_demand_daily_cart_uplift_positive CHECK (applied_uplift > 0)
);

-- One row per cart per date per product actually sold. Absent rows are genuine
-- zeros; the Dirichlet mix supplies a share for products with no row.
CREATE TABLE IF NOT EXISTS public.forecast_demand_daily_product (
    location_id uuid NOT NULL,
    business_date date NOT NULL,
    product_id uuid NOT NULL,
    units integer DEFAULT 0 NOT NULL,
    revenue numeric(12,2) DEFAULT 0 NOT NULL,
    applied_uplift numeric(8,4) DEFAULT 1 NOT NULL,
    baseline_units numeric(12,3) DEFAULT 0 NOT NULL,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_demand_daily_product_pkey PRIMARY KEY (location_id, business_date, product_id),
    CONSTRAINT forecast_demand_daily_product_location_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE,
    CONSTRAINT forecast_demand_daily_product_product_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    CONSTRAINT forecast_demand_daily_product_units_non_negative CHECK (units >= 0),
    CONSTRAINT forecast_demand_daily_product_uplift_positive CHECK (applied_uplift > 0)
);

CREATE INDEX IF NOT EXISTS forecast_demand_daily_cart_date_idx ON public.forecast_demand_daily_cart (business_date);
CREATE INDEX IF NOT EXISTS forecast_demand_daily_product_date_idx ON public.forecast_demand_daily_product (business_date);
CREATE INDEX IF NOT EXISTS forecast_demand_daily_product_product_idx ON public.forecast_demand_daily_product (product_id, business_date);

-- ---------------------------------------------------------------------------
-- Model state. Small, hot, and rebuildable from the facts above.
-- ---------------------------------------------------------------------------

-- Holt-Winters multiplicative state for one cart's daily unit volume.
--
-- dow_index holds the seven weekday factors (index 0 = Sunday, matching
-- JavaScript's getUTCDay, and location_opening_hours.day_of_week). They are
-- renormalised to mean 1.0 on every update — without that, multiplicative
-- Winters drifts (Archibald & Koehler 2003).
--
-- dow_obs_count is what makes the shrinkage honest: each weekday factor is
-- pulled toward the pooled network profile with weight n_d/(n_d+k), so a
-- weekday seen twice barely moves off the pooled shape.
CREATE TABLE IF NOT EXISTS public.forecast_cart_state (
    location_id uuid NOT NULL,
    level numeric(12,4) DEFAULT 0 NOT NULL,
    dispersion numeric(10,5) DEFAULT 0 NOT NULL,
    dow_index numeric(8,5)[] DEFAULT ARRAY[1,1,1,1,1,1,1]::numeric(8,5)[] NOT NULL,
    dow_obs_count integer[] DEFAULT ARRAY[0,0,0,0,0,0,0] NOT NULL,
    observations integer DEFAULT 0 NOT NULL,
    residual_sum_sq numeric(16,5) DEFAULT 0 NOT NULL,
    residual_count integer DEFAULT 0 NOT NULL,
    last_business_date date,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_cart_state_pkey PRIMARY KEY (location_id),
    CONSTRAINT forecast_cart_state_location_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE,
    CONSTRAINT forecast_cart_state_dow_index_len CHECK (array_length(dow_index, 1) = 7),
    CONSTRAINT forecast_cart_state_dow_count_len CHECK (array_length(dow_obs_count, 1) = 7)
);

-- Dirichlet pseudo-counts for the product mix at one cart. `alpha` decays by a
-- forgetting factor each day and accrues observed (baseline) units, so the
-- posterior share alpha_p / sum(alpha) tracks a drifting menu without a refit.
-- A product that has never sold keeps the small positive alpha seeded from the
-- pooled network mix, which is what stops the model asserting a hard zero for
-- 48 of the 69 active products.
CREATE TABLE IF NOT EXISTS public.forecast_product_state (
    location_id uuid NOT NULL,
    product_id uuid NOT NULL,
    alpha numeric(12,5) DEFAULT 0 NOT NULL,
    units_ewma numeric(12,5) DEFAULT 0 NOT NULL,
    observations integer DEFAULT 0 NOT NULL,
    last_sold_date date,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_product_state_pkey PRIMARY KEY (location_id, product_id),
    CONSTRAINT forecast_product_state_location_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE,
    CONSTRAINT forecast_product_state_product_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    CONSTRAINT forecast_product_state_alpha_non_negative CHECK (alpha >= 0)
);

-- The empirical-Bayes priors, pooled across every cart. Singleton, same shape
-- as referral_settings / home_hero_settings.
--
-- product_mix is jsonb ({product_id: share}) rather than a child table because
-- it is a derived snapshot rewritten wholesale on every run, never joined and
-- never queried across rows.
CREATE TABLE IF NOT EXISTS public.forecast_network_state (
    id boolean DEFAULT true NOT NULL,
    dow_index numeric(8,5)[] DEFAULT ARRAY[1,1,1,1,1,1,1]::numeric(8,5)[] NOT NULL,
    dow_obs_count integer[] DEFAULT ARRAY[0,0,0,0,0,0,0] NOT NULL,
    mean_level numeric(12,4) DEFAULT 0 NOT NULL,
    dispersion numeric(10,5) DEFAULT 0 NOT NULL,
    product_mix jsonb DEFAULT '{}'::jsonb NOT NULL,
    observations integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_network_state_pkey PRIMARY KEY (id),
    CONSTRAINT forecast_network_state_singleton CHECK (id = true),
    CONSTRAINT forecast_network_state_dow_index_len CHECK (array_length(dow_index, 1) = 7)
);

INSERT INTO public.forecast_network_state (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Manager planning assumptions — the seed prior.
--
-- With 84 units of history a purely data-driven prior is a flat line with very
-- wide intervals: statistically honest, operationally useless. A manager's
-- "we expect about 40 units on a Friday at Hacienda" is real information, and
-- this is where it enters. prior_strength_days is how many days of actual
-- trading it takes to outweigh it, so the assumption fades on its own as
-- evidence arrives rather than needing to be removed by hand.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.forecast_cart_assumptions (
    location_id uuid NOT NULL,
    day_of_week integer NOT NULL,
    expected_units numeric(10,2),
    expected_orders numeric(10,2),
    prior_strength_days integer DEFAULT 14 NOT NULL,
    notes text,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_cart_assumptions_pkey PRIMARY KEY (location_id, day_of_week),
    CONSTRAINT forecast_cart_assumptions_location_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE,
    CONSTRAINT forecast_cart_assumptions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.employees(id) ON DELETE SET NULL,
    CONSTRAINT forecast_cart_assumptions_dow_range CHECK (day_of_week BETWEEN 0 AND 6),
    CONSTRAINT forecast_cart_assumptions_units_non_negative CHECK (expected_units IS NULL OR expected_units >= 0),
    CONSTRAINT forecast_cart_assumptions_strength_positive CHECK (prior_strength_days > 0)
);

-- ---------------------------------------------------------------------------
-- Campaigns.
--
-- `promotions` is a promo-CODE engine: no product scoping, no location scoping,
-- and a redemption only exists once a customer types a code. `spotlight_banners`
-- has no date range at all. Neither can express "20% off Mojitos at Hacienda
-- this weekend", and neither can be replayed historically.
--
-- Extending the promo engine would mean touching checkout and the payment paths
-- in customerRoutes.js for what is a reporting feature. So campaigns live here
-- instead, decoupled from the money path: a campaign recorded here changes
-- forecasts and nothing else — it grants no discount. That also lets it cover
-- what actually moves a beach cart and never involves a code: banner
-- placements, Golden Hour pushes, social pushes, local events, weather.
--
-- campaign_type is free text validated in zod, not a Postgres enum: marketing
-- will invent new types and widening an enum is a migration.
-- ---------------------------------------------------------------------------
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
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_campaigns_pkey PRIMARY KEY (id),
    CONSTRAINT forecast_campaigns_promotion_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id) ON DELETE SET NULL,
    CONSTRAINT forecast_campaigns_scope_valid CHECK (scope IN ('network', 'cart', 'product')),
    CONSTRAINT forecast_campaigns_dates_ordered CHECK (ends_on >= starts_on),
    CONSTRAINT forecast_campaigns_uplift_sane CHECK (expected_uplift_pct > -100)
);

CREATE INDEX IF NOT EXISTS forecast_campaigns_window_idx ON public.forecast_campaigns (starts_on, ends_on) WHERE is_active;
CREATE INDEX IF NOT EXISTS forecast_campaigns_promotion_idx ON public.forecast_campaigns (promotion_id) WHERE promotion_id IS NOT NULL;

-- Empty set = every cart. Same for products: empty = the whole menu, i.e. a
-- pure volume campaign with no mix effect.
CREATE TABLE IF NOT EXISTS public.forecast_campaign_locations (
    campaign_id uuid NOT NULL,
    location_id uuid NOT NULL,
    CONSTRAINT forecast_campaign_locations_pkey PRIMARY KEY (campaign_id, location_id),
    CONSTRAINT forecast_campaign_locations_campaign_fkey FOREIGN KEY (campaign_id) REFERENCES public.forecast_campaigns(id) ON DELETE CASCADE,
    CONSTRAINT forecast_campaign_locations_location_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.forecast_campaign_products (
    campaign_id uuid NOT NULL,
    product_id uuid NOT NULL,
    CONSTRAINT forecast_campaign_products_pkey PRIMARY KEY (campaign_id, product_id),
    CONSTRAINT forecast_campaign_products_campaign_fkey FOREIGN KEY (campaign_id) REFERENCES public.forecast_campaigns(id) ON DELETE CASCADE,
    CONSTRAINT forecast_campaign_products_product_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE
);

-- One row per campaign per cart per day it ran. `ratio` is actual / baseline
-- forecast, where the forecast was made before the model saw that day — so the
-- lift is never measured against a number it helped set.
--
-- Kept as rows rather than folded straight into a running mean so the learned
-- uplift can be recomputed from scratch on rebuild, and so a single anomalous
-- day is visible rather than buried in an average.
CREATE TABLE IF NOT EXISTS public.forecast_campaign_observations (
    campaign_id uuid NOT NULL,
    location_id uuid NOT NULL,
    business_date date NOT NULL,
    actual_units integer DEFAULT 0 NOT NULL,
    baseline_forecast numeric(12,4) DEFAULT 0 NOT NULL,
    ratio numeric(10,5),
    promo_order_share numeric(6,4) DEFAULT 0 NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_campaign_observations_pkey PRIMARY KEY (campaign_id, location_id, business_date),
    CONSTRAINT forecast_campaign_observations_campaign_fkey FOREIGN KEY (campaign_id) REFERENCES public.forecast_campaigns(id) ON DELETE CASCADE,
    CONSTRAINT forecast_campaign_observations_location_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE
);

-- The pooled prior each new campaign starts from. A single campaign never has
-- enough days to estimate its own lift, but "20-30%-off codes" accumulates
-- evidence across every campaign of that shape — which is the only reason a
-- third campaign can be forecast at all.
--
-- Uplifts are stored as logs because they are multiplicative and must stay
-- positive; averaging in log space is a geometric mean, which is the right
-- centre for a ratio.
--
-- pull_forward_ratio (post-promotion dip: customers stocked up, so the days
-- after sag) defaults to 0 — switched off. The effect is real and documented,
-- but at 84 units it is not identifiable, and a fabricated number would be
-- worse than none. The hook exists for when it is.
CREATE TABLE IF NOT EXISTS public.forecast_campaign_effects (
    campaign_type text NOT NULL,
    discount_bucket text NOT NULL,
    log_uplift_mean numeric(10,6) DEFAULT 0 NOT NULL,
    observations integer DEFAULT 0 NOT NULL,
    pull_forward_ratio numeric(6,4) DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_campaign_effects_pkey PRIMARY KEY (campaign_type, discount_bucket),
    CONSTRAINT forecast_campaign_effects_pull_forward_range CHECK (pull_forward_ratio >= 0 AND pull_forward_ratio <= 1)
);

-- ---------------------------------------------------------------------------
-- Output.
-- ---------------------------------------------------------------------------

-- p50 is the planning point estimate; p90 is the stocking quantile — the
-- newsvendor critical fractile Cu/(Cu+Co), i.e. asserting a stockout costs
-- about 9x a spare kit's carrying cost. A cart cannot restock mid-day, which is
-- what justifies a quantile that high.
--
-- sample_size and confidence travel WITH the numbers, deliberately. A forecast
-- built from two observations must never appear on screen looking like one
-- built from two hundred.
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
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_daily_cart_pkey PRIMARY KEY (location_id, business_date),
    CONSTRAINT forecast_daily_cart_location_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE,
    CONSTRAINT forecast_daily_cart_confidence_valid CHECK (confidence IN ('low', 'medium', 'high')),
    CONSTRAINT forecast_daily_cart_quantiles_ordered CHECK (p90 >= p50)
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
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_daily_product_pkey PRIMARY KEY (location_id, business_date, product_id),
    CONSTRAINT forecast_daily_product_location_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE,
    CONSTRAINT forecast_daily_product_product_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    CONSTRAINT forecast_daily_product_confidence_valid CHECK (confidence IN ('low', 'medium', 'high')),
    CONSTRAINT forecast_daily_product_quantiles_ordered CHECK (p90 >= p50)
);

CREATE INDEX IF NOT EXISTS forecast_daily_cart_date_idx ON public.forecast_daily_cart (business_date);
CREATE INDEX IF NOT EXISTS forecast_daily_product_date_idx ON public.forecast_daily_product (business_date);
CREATE INDEX IF NOT EXISTS forecast_daily_product_lookup_idx ON public.forecast_daily_product (location_id, business_date, expected_units DESC);

-- ---------------------------------------------------------------------------
-- Accuracy. Scored the morning after, against the forecast as it stood before
-- the model saw the day — genuinely out of sample.
--
-- naive_abs_error is the seasonal-naive (lag-7) baseline's error, stored rather
-- than derived so "is the model beating last Friday?" is answerable instead of
-- asserted. MASE is the ratio of the two means (Hyndman & Koehler 2006); MAPE
-- is not used because it is undefined on the zero-demand days that dominate
-- this dataset.
--
-- pinball_loss scores the P90 on its own terms — a stocking quantile judged by
-- point error is judged by the wrong thing.
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
    scored_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_accuracy_cart_pkey PRIMARY KEY (location_id, business_date, horizon_days),
    CONSTRAINT forecast_accuracy_cart_location_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE
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
    scored_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT forecast_accuracy_product_pkey PRIMARY KEY (location_id, business_date, product_id, horizon_days),
    CONSTRAINT forecast_accuracy_product_location_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE,
    CONSTRAINT forecast_accuracy_product_product_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS forecast_accuracy_cart_date_idx ON public.forecast_accuracy_cart (business_date);
CREATE INDEX IF NOT EXISTS forecast_accuracy_product_date_idx ON public.forecast_accuracy_product (business_date);

-- Ops log for the nightly job. Also the answer to "did last night run?", which
-- for an in-process scheduler on a single Render instance is not otherwise
-- observable.
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
    model_version text,
    CONSTRAINT forecast_runs_pkey PRIMARY KEY (id),
    CONSTRAINT forecast_runs_status_valid CHECK (status IN ('running', 'ok', 'failed')),
    CONSTRAINT forecast_runs_trigger_valid CHECK (trigger IN ('schedule', 'manual', 'rebuild', 'backtest'))
);

CREATE INDEX IF NOT EXISTS forecast_runs_started_idx ON public.forecast_runs (started_at DESC);

-- ---------------------------------------------------------------------------
-- updated_at triggers, using the existing shared function.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS set_forecast_campaigns_updated_at ON public.forecast_campaigns;
CREATE TRIGGER set_forecast_campaigns_updated_at BEFORE UPDATE ON public.forecast_campaigns
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_forecast_cart_assumptions_updated_at ON public.forecast_cart_assumptions;
CREATE TRIGGER set_forecast_cart_assumptions_updated_at BEFORE UPDATE ON public.forecast_cart_assumptions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS. The server uses the service-role key and bypasses all of this; the
-- policies exist so direct PostgREST access stays locked down, mirroring
-- golden_hour_modes. Nothing here is customer-facing, so `anon` gets nothing.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    t text;
    tables text[] := ARRAY[
        'forecast_demand_daily_cart', 'forecast_demand_daily_product',
        'forecast_cart_state', 'forecast_product_state', 'forecast_network_state',
        'forecast_cart_assumptions', 'forecast_campaigns',
        'forecast_campaign_locations', 'forecast_campaign_products',
        'forecast_campaign_observations', 'forecast_campaign_effects',
        'forecast_daily_cart', 'forecast_daily_product',
        'forecast_accuracy_cart', 'forecast_accuracy_product', 'forecast_runs'
    ];
BEGIN
    FOREACH t IN ARRAY tables LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);

        EXECUTE format('DROP POLICY IF EXISTS "Staff can read %s" ON public.%I', t, t);
        EXECUTE format(
            'CREATE POLICY "Staff can read %s" ON public.%I AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff())',
            t, t
        );

        EXECUTE format('DROP POLICY IF EXISTS "Managers can manage %s" ON public.%I', t, t);
        EXECUTE format(
            'CREATE POLICY "Managers can manage %s" ON public.%I AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin())',
            t, t
        );
    END LOOP;
END $$;

-- ---------------------------------------------------------------------------
COMMENT ON TABLE public.forecast_demand_daily_cart IS 'Per-cart per-day demand facts. baseline_units is units with campaign uplift divided out, and is what the model smooths.';
COMMENT ON TABLE public.forecast_cart_state IS 'Holt-Winters multiplicative state per cart. dow_index is renormalised to mean 1 on every update; dow_obs_count drives shrinkage toward the pooled network profile.';
COMMENT ON TABLE public.forecast_product_state IS 'Dirichlet pseudo-counts for the product mix per cart, with exponential forgetting.';
COMMENT ON TABLE public.forecast_campaigns IS 'Forecast-side campaign calendar. Decoupled from the promotions code engine: a campaign here changes forecasts only and grants no discount.';
COMMENT ON TABLE public.forecast_campaign_effects IS 'Pooled log-uplift per campaign type and discount bucket. The empirical-Bayes prior a new campaign starts from.';
COMMENT ON COLUMN public.forecast_daily_cart.p90 IS 'Stocking quantile (newsvendor critical fractile). Quantiles do not add: this is computed from the cart-level negative binomial, never by summing product p90s.';
