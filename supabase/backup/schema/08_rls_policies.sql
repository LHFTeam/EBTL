-- ============================================================================
-- EBTL — Supabase schema backup: row level security
-- RLS is enabled on every public table. Tables that appear only in the ENABLE
-- block and have no policy below are deny-all for anon/authenticated —
-- reachable only through service_role (which bypasses RLS).
-- Requires 05_functions.sql for is_staff() / is_manager_or_admin().
-- ============================================================================

SET search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Enable RLS
-- ---------------------------------------------------------------------------

ALTER TABLE public.app_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_daily_closings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_daily_openings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_item_additions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_item_removed_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_credit_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_favorite_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.liquor_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.location_opening_hours ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_inventory_consumptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_item_additions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_item_inventory_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_item_removed_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_number_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_prep_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prep_stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_liquor_compatibility ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotion_redemptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipe_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_transfer_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_transfer_movement_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------

CREATE POLICY "Authenticated users can insert app events" ON public.app_events FOR INSERT TO authenticated
  WITH CHECK (((customer_id IS NULL) OR (customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "Staff can manage cart_daily_closings" ON public.cart_daily_closings FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Staff can manage cart_daily_openings" ON public.cart_daily_openings FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Customers can manage own cart additions" ON public.cart_item_additions FOR ALL TO authenticated
  USING ((EXISTS ( SELECT 1 FROM ((cart_items ci JOIN carts c ON ((c.id = ci.cart_id))) JOIN customers cu ON ((cu.id = c.customer_id))) WHERE ((ci.id = cart_item_additions.cart_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))))
  WITH CHECK ((EXISTS ( SELECT 1 FROM ((cart_items ci JOIN carts c ON ((c.id = ci.cart_id))) JOIN customers cu ON ((cu.id = c.customer_id))) WHERE ((ci.id = cart_item_additions.cart_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "Staff can manage cart additions" ON public.cart_item_additions FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Customers can manage own cart removed ingredients" ON public.cart_item_removed_ingredients FOR ALL TO authenticated
  USING ((EXISTS ( SELECT 1 FROM ((cart_items ci JOIN carts c ON ((c.id = ci.cart_id))) JOIN customers cu ON ((cu.id = c.customer_id))) WHERE ((ci.id = cart_item_removed_ingredients.cart_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))))
  WITH CHECK ((EXISTS ( SELECT 1 FROM ((cart_items ci JOIN carts c ON ((c.id = ci.cart_id))) JOIN customers cu ON ((cu.id = c.customer_id))) WHERE ((ci.id = cart_item_removed_ingredients.cart_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "Staff can manage cart removed ingredients" ON public.cart_item_removed_ingredients FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Customers can manage own cart items" ON public.cart_items FOR ALL TO authenticated
  USING ((cart_id IN ( SELECT c.id FROM (carts c JOIN customers cu ON ((cu.id = c.customer_id))) WHERE (cu.auth_user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((cart_id IN ( SELECT c.id FROM (carts c JOIN customers cu ON ((cu.id = c.customer_id))) WHERE (cu.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Customers can manage own carts" ON public.carts FOR ALL TO authenticated
  USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Customers can manage own addresses" ON public.customer_addresses FOR ALL TO authenticated
  USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Customers can delete own favorite products" ON public.customer_favorite_products FOR DELETE TO authenticated
  USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Customers can insert own favorite products" ON public.customer_favorite_products FOR INSERT TO authenticated
  WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Customers can read own favorite products" ON public.customer_favorite_products FOR SELECT TO authenticated
  USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Staff can read customer favorite products" ON public.customer_favorite_products FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Customers can read own notifications" ON public.customer_notifications FOR SELECT TO authenticated
  USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Customers can update own notifications" ON public.customer_notifications FOR UPDATE TO authenticated
  USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Staff can manage customer notifications" ON public.customer_notifications FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Customers can read own payment methods" ON public.customer_payment_methods FOR SELECT TO authenticated
  USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Staff can read customer payment methods" ON public.customer_payment_methods FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Customers can manage own push tokens" ON public.customer_push_tokens FOR ALL TO authenticated
  USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Staff can manage customer push tokens" ON public.customer_push_tokens FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Customers can insert own customer record" ON public.customers FOR INSERT TO authenticated
  WITH CHECK ((auth_user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Customers can read own customer record" ON public.customers FOR SELECT TO authenticated
  USING ((auth_user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Customers can update own customer record" ON public.customers FOR UPDATE TO authenticated
  USING ((auth_user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((auth_user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Managers can read employee credentials metadata" ON public.employee_credentials FOR SELECT TO public
  USING (is_manager_or_admin());

CREATE POLICY "Managers can manage employees" ON public.employees FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Staff can read employee records" ON public.employees FOR SELECT TO authenticated
  USING (((auth_user_id = ( SELECT auth.uid() AS uid)) OR is_manager_or_admin()));

CREATE POLICY "Managers can manage ingredients" ON public.ingredients FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Staff can read ingredients" ON public.ingredients FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Staff can read inventory_balances" ON public.inventory_balances FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Managers can manage liquor_types" ON public.liquor_types FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Public can read active liquor types" ON public.liquor_types FOR SELECT TO anon, authenticated
  USING ((is_active = true));

CREATE POLICY "Staff can read liquor_types" ON public.liquor_types FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Managers can manage location opening hours" ON public.location_opening_hours FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Public can read active location opening hours" ON public.location_opening_hours FOR SELECT TO anon, authenticated
  USING ((EXISTS ( SELECT 1 FROM locations l WHERE ((l.id = location_opening_hours.location_id) AND (l.is_active = true)))));

CREATE POLICY "Staff can read location opening hours" ON public.location_opening_hours FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Managers can manage locations" ON public.locations FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Staff can read locations" ON public.locations FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Staff can manage loyalty_accounts" ON public.loyalty_accounts FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Staff can manage loyalty_transactions" ON public.loyalty_transactions FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Customers can read own order additions" ON public.order_item_additions FOR SELECT TO authenticated
  USING ((EXISTS ( SELECT 1 FROM ((order_items oi JOIN orders o ON ((o.id = oi.order_id))) JOIN customers cu ON ((cu.id = o.customer_id))) WHERE ((oi.id = order_item_additions.order_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "Staff can manage order additions" ON public.order_item_additions FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Customers can read own order inventory components" ON public.order_item_inventory_components FOR SELECT TO authenticated
  USING ((EXISTS ( SELECT 1 FROM ((order_items oi JOIN orders o ON ((o.id = oi.order_id))) JOIN customers cu ON ((cu.id = o.customer_id))) WHERE ((oi.id = order_item_inventory_components.order_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "Staff can manage order inventory components" ON public.order_item_inventory_components FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Customers can read own order removed ingredients" ON public.order_item_removed_ingredients FOR SELECT TO authenticated
  USING ((EXISTS ( SELECT 1 FROM ((order_items oi JOIN orders o ON ((o.id = oi.order_id))) JOIN customers cu ON ((cu.id = o.customer_id))) WHERE ((oi.id = order_item_removed_ingredients.order_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "Staff can manage order removed ingredients" ON public.order_item_removed_ingredients FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Customers can create own order items" ON public.order_items FOR INSERT TO authenticated
  WITH CHECK ((order_id IN ( SELECT o.id FROM (orders o JOIN customers c ON ((c.id = o.customer_id))) WHERE (c.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Customers can read own order items" ON public.order_items FOR SELECT TO authenticated
  USING ((order_id IN ( SELECT o.id FROM (orders o JOIN customers c ON ((c.id = o.customer_id))) WHERE (c.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Staff can manage order_items" ON public.order_items FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Staff can manage order_prep_tasks" ON public.order_prep_tasks FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Customers can create own orders" ON public.orders FOR INSERT TO authenticated
  WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Customers can read own orders" ON public.orders FOR SELECT TO authenticated
  USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "Staff can manage orders" ON public.orders FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Managers can read payment events" ON public.payment_events FOR SELECT TO authenticated
  USING (is_manager_or_admin());

CREATE POLICY "Managers can read payments" ON public.payments FOR SELECT TO authenticated
  USING (is_manager_or_admin());

CREATE POLICY "Staff can read prep_stations" ON public.prep_stations FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Managers can manage product_categories" ON public.product_categories FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Public can read active categories" ON public.product_categories FOR SELECT TO anon, authenticated
  USING ((is_active = true));

CREATE POLICY "Staff can read product_categories" ON public.product_categories FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Managers can manage product_liquor_compatibility" ON public.product_liquor_compatibility FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Public can read product liquor compatibility" ON public.product_liquor_compatibility FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY "Staff can read product_liquor_compatibility" ON public.product_liquor_compatibility FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Managers can manage product_tags" ON public.product_tags FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Public can read active product tags" ON public.product_tags FOR SELECT TO anon, authenticated
  USING ((is_active = true));

CREATE POLICY "Staff can read product_tags" ON public.product_tags FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Managers can manage product_variants" ON public.product_variants FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Public can read active variants" ON public.product_variants FOR SELECT TO anon, authenticated
  USING ((is_active = true));

CREATE POLICY "Staff can read product_variants" ON public.product_variants FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Managers can manage products" ON public.products FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Public can read active products" ON public.products FOR SELECT TO anon, authenticated
  USING ((status = 'active'::product_status));

CREATE POLICY "Staff can read products" ON public.products FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Staff can manage promotion_redemptions" ON public.promotion_redemptions FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Managers can manage promotions" ON public.promotions FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Staff can read promotions" ON public.promotions FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Staff can manage purchase_order_items" ON public.purchase_order_items FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Staff can manage purchase_orders" ON public.purchase_orders FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Managers can manage recipe_items" ON public.recipe_items FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Staff can read recipe_items" ON public.recipe_items FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Managers can manage recipes" ON public.recipes FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Staff can read recipes" ON public.recipes FOR SELECT TO authenticated
  USING (is_staff());

CREATE POLICY "Managers can manage shop settings" ON public.shop_settings FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

CREATE POLICY "Public can read shop settings" ON public.shop_settings FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY "Staff can manage stock_movements" ON public.stock_movements FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Staff can manage stock_transfer_items" ON public.stock_transfer_items FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Staff can manage stock_transfers" ON public.stock_transfers FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "Managers can manage suppliers" ON public.suppliers FOR ALL TO authenticated
  USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());

-- ---------------------------------------------------------------------------
-- Demand forecasting module (server/forecast/), migration 20260807171440.
-- Appended as a block rather than sorted inline; the next full run of
-- ../tools/dump_schema.sql will re-sort these into place.
-- ---------------------------------------------------------------------------

ALTER TABLE public.forecast_accuracy_cart ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_accuracy_cart" ON public.forecast_accuracy_cart AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_accuracy_cart" ON public.forecast_accuracy_cart AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_accuracy_product ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_accuracy_product" ON public.forecast_accuracy_product AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_accuracy_product" ON public.forecast_accuracy_product AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_campaign_effects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_campaign_effects" ON public.forecast_campaign_effects AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_campaign_effects" ON public.forecast_campaign_effects AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_campaign_locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_campaign_locations" ON public.forecast_campaign_locations AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_campaign_locations" ON public.forecast_campaign_locations AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_campaign_observations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_campaign_observations" ON public.forecast_campaign_observations AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_campaign_observations" ON public.forecast_campaign_observations AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_campaign_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_campaign_products" ON public.forecast_campaign_products AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_campaign_products" ON public.forecast_campaign_products AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_campaigns ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_campaigns" ON public.forecast_campaigns AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_campaigns" ON public.forecast_campaigns AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_cart_assumptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_cart_assumptions" ON public.forecast_cart_assumptions AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_cart_assumptions" ON public.forecast_cart_assumptions AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_cart_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_cart_state" ON public.forecast_cart_state AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_cart_state" ON public.forecast_cart_state AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_daily_cart ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_daily_cart" ON public.forecast_daily_cart AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_daily_cart" ON public.forecast_daily_cart AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_daily_product ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_daily_product" ON public.forecast_daily_product AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_daily_product" ON public.forecast_daily_product AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_demand_daily_cart ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_demand_daily_cart" ON public.forecast_demand_daily_cart AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_demand_daily_cart" ON public.forecast_demand_daily_cart AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_demand_daily_product ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_demand_daily_product" ON public.forecast_demand_daily_product AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_demand_daily_product" ON public.forecast_demand_daily_product AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_network_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_network_state" ON public.forecast_network_state AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_network_state" ON public.forecast_network_state AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_product_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_product_state" ON public.forecast_product_state AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_product_state" ON public.forecast_product_state AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
ALTER TABLE public.forecast_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Managers can manage forecast_runs" ON public.forecast_runs AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_runs" ON public.forecast_runs AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
