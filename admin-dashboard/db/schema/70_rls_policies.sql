-- EBTL baseline schema — row-level security policies.
--
-- Read this together with the note in README.md: the Express server connects
-- with the service-role key, which BYPASSES RLS entirely. These policies
-- therefore govern direct PostgREST/client access only — they are not what
-- protects the customer or admin APIs today.
--
-- Requires the helper functions in 50_functions.sql (is_staff,
-- is_manager_or_admin, current_employee_role).
--
-- Tables with RLS enabled and no policy below are deny-all for anon and
-- authenticated: app_events (insert only), customer_credit_ledger,
-- customer_favorite_liquor_types, customer_top_liquor_types,
-- order_inventory_consumptions, order_number_counters, referral_settings,
-- referrals, stock_transfer_movement_events. Enabling RLS is part of each
-- table's definition and lives in 10_tables.sql, not here.

CREATE POLICY "Authenticated users can insert app events" ON public.app_events AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((customer_id IS NULL) OR (customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid))))));
CREATE POLICY "Staff can manage cart_daily_closings" ON public.cart_daily_closings AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Staff can manage cart_daily_openings" ON public.cart_daily_openings AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Customers can manage own cart additions" ON public.cart_item_additions AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1 FROM ((cart_items ci JOIN carts c ON ((c.id = ci.cart_id))) JOIN customers cu ON ((cu.id = c.customer_id))) WHERE ((ci.id = cart_item_additions.cart_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid)))))) WITH CHECK ((EXISTS ( SELECT 1 FROM ((cart_items ci JOIN carts c ON ((c.id = ci.cart_id))) JOIN customers cu ON ((cu.id = c.customer_id))) WHERE ((ci.id = cart_item_additions.cart_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))));
CREATE POLICY "Staff can manage cart additions" ON public.cart_item_additions AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Customers can manage own cart removed ingredients" ON public.cart_item_removed_ingredients AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1 FROM ((cart_items ci JOIN carts c ON ((c.id = ci.cart_id))) JOIN customers cu ON ((cu.id = c.customer_id))) WHERE ((ci.id = cart_item_removed_ingredients.cart_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid)))))) WITH CHECK ((EXISTS ( SELECT 1 FROM ((cart_items ci JOIN carts c ON ((c.id = ci.cart_id))) JOIN customers cu ON ((cu.id = c.customer_id))) WHERE ((ci.id = cart_item_removed_ingredients.cart_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))));
CREATE POLICY "Staff can manage cart removed ingredients" ON public.cart_item_removed_ingredients AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Customers can manage own cart items" ON public.cart_items AS PERMISSIVE FOR ALL TO authenticated USING ((cart_id IN ( SELECT c.id FROM (carts c JOIN customers cu ON ((cu.id = c.customer_id))) WHERE (cu.auth_user_id = ( SELECT auth.uid() AS uid))))) WITH CHECK ((cart_id IN ( SELECT c.id FROM (carts c JOIN customers cu ON ((cu.id = c.customer_id))) WHERE (cu.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Customers can manage own carts" ON public.carts AS PERMISSIVE FOR ALL TO authenticated USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid))))) WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Customers can manage own addresses" ON public.customer_addresses AS PERMISSIVE FOR ALL TO authenticated USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid))))) WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Customers can delete own favorite products" ON public.customer_favorite_products AS PERMISSIVE FOR DELETE TO authenticated USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Customers can insert own favorite products" ON public.customer_favorite_products AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Customers can read own favorite products" ON public.customer_favorite_products AS PERMISSIVE FOR SELECT TO authenticated USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Staff can read customer favorite products" ON public.customer_favorite_products AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Customers can read own notifications" ON public.customer_notifications AS PERMISSIVE FOR SELECT TO authenticated USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Customers can update own notifications" ON public.customer_notifications AS PERMISSIVE FOR UPDATE TO authenticated USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid))))) WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Staff can manage customer notifications" ON public.customer_notifications AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Customers can read own payment methods" ON public.customer_payment_methods AS PERMISSIVE FOR SELECT TO authenticated USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Staff can read customer payment methods" ON public.customer_payment_methods AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Customers can manage own push tokens" ON public.customer_push_tokens AS PERMISSIVE FOR ALL TO authenticated USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid))))) WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Staff can manage customer push tokens" ON public.customer_push_tokens AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Customers can insert own customer record" ON public.customers AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((auth_user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY "Customers can read own customer record" ON public.customers AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY "Customers can update own customer record" ON public.customers AS PERMISSIVE FOR UPDATE TO authenticated USING ((auth_user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((auth_user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY "Managers can read employee credentials metadata" ON public.employee_credentials AS PERMISSIVE FOR SELECT TO public USING (is_manager_or_admin());
CREATE POLICY "Managers can manage employees" ON public.employees AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read employee records" ON public.employees AS PERMISSIVE FOR SELECT TO authenticated USING (((auth_user_id = ( SELECT auth.uid() AS uid)) OR is_manager_or_admin()));
CREATE POLICY "Managers can manage forecast_accuracy_cart" ON public.forecast_accuracy_cart AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_accuracy_cart" ON public.forecast_accuracy_cart AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_accuracy_product" ON public.forecast_accuracy_product AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_accuracy_product" ON public.forecast_accuracy_product AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_campaign_effects" ON public.forecast_campaign_effects AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_campaign_effects" ON public.forecast_campaign_effects AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_campaign_locations" ON public.forecast_campaign_locations AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_campaign_locations" ON public.forecast_campaign_locations AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_campaign_observations" ON public.forecast_campaign_observations AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_campaign_observations" ON public.forecast_campaign_observations AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_campaign_products" ON public.forecast_campaign_products AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_campaign_products" ON public.forecast_campaign_products AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_campaigns" ON public.forecast_campaigns AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_campaigns" ON public.forecast_campaigns AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_cart_assumptions" ON public.forecast_cart_assumptions AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_cart_assumptions" ON public.forecast_cart_assumptions AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_cart_state" ON public.forecast_cart_state AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_cart_state" ON public.forecast_cart_state AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_daily_cart" ON public.forecast_daily_cart AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_daily_cart" ON public.forecast_daily_cart AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_daily_product" ON public.forecast_daily_product AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_daily_product" ON public.forecast_daily_product AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_demand_daily_cart" ON public.forecast_demand_daily_cart AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_demand_daily_cart" ON public.forecast_demand_daily_cart AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_demand_daily_product" ON public.forecast_demand_daily_product AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_demand_daily_product" ON public.forecast_demand_daily_product AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_network_state" ON public.forecast_network_state AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_network_state" ON public.forecast_network_state AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_product_state" ON public.forecast_product_state AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_product_state" ON public.forecast_product_state AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage forecast_runs" ON public.forecast_runs AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read forecast_runs" ON public.forecast_runs AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage golden hour modes" ON public.golden_hour_modes AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read active golden hour modes" ON public.golden_hour_modes AS PERMISSIVE FOR SELECT TO anon, authenticated USING ((is_active = true));
CREATE POLICY "Staff can read golden hour modes" ON public.golden_hour_modes AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage home hero banners" ON public.home_hero_banners AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read active home hero banners" ON public.home_hero_banners AS PERMISSIVE FOR SELECT TO anon, authenticated USING ((is_active = true));
CREATE POLICY "Staff can read home hero banners" ON public.home_hero_banners AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage home hero settings" ON public.home_hero_settings AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read home hero settings" ON public.home_hero_settings AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "Managers can manage ingredient categories" ON public.ingredient_categories AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read ingredient categories" ON public.ingredient_categories AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage ingredients" ON public.ingredients AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read ingredients" ON public.ingredients AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Staff can read inventory_balances" ON public.inventory_balances AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage liquor_types" ON public.liquor_types AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read active liquor types" ON public.liquor_types AS PERMISSIVE FOR SELECT TO anon, authenticated USING ((is_active = true));
CREATE POLICY "Staff can read liquor_types" ON public.liquor_types AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage location opening hours" ON public.location_opening_hours AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read active location opening hours" ON public.location_opening_hours AS PERMISSIVE FOR SELECT TO anon, authenticated USING ((EXISTS ( SELECT 1 FROM locations l WHERE ((l.id = location_opening_hours.location_id) AND (l.is_active = true)))));
CREATE POLICY "Staff can read location opening hours" ON public.location_opening_hours AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage locations" ON public.locations AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read locations" ON public.locations AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Staff can manage loyalty_accounts" ON public.loyalty_accounts AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Staff can manage loyalty_transactions" ON public.loyalty_transactions AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Customers can read own order additions" ON public.order_item_additions AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1 FROM ((order_items oi JOIN orders o ON ((o.id = oi.order_id))) JOIN customers cu ON ((cu.id = o.customer_id))) WHERE ((oi.id = order_item_additions.order_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))));
CREATE POLICY "Staff can manage order additions" ON public.order_item_additions AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Customers can read own order inventory components" ON public.order_item_inventory_components AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1 FROM ((order_items oi JOIN orders o ON ((o.id = oi.order_id))) JOIN customers cu ON ((cu.id = o.customer_id))) WHERE ((oi.id = order_item_inventory_components.order_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))));
CREATE POLICY "Staff can manage order inventory components" ON public.order_item_inventory_components AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Customers can read own order removed ingredients" ON public.order_item_removed_ingredients AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1 FROM ((order_items oi JOIN orders o ON ((o.id = oi.order_id))) JOIN customers cu ON ((cu.id = o.customer_id))) WHERE ((oi.id = order_item_removed_ingredients.order_item_id) AND (cu.auth_user_id = ( SELECT auth.uid() AS uid))))));
CREATE POLICY "Staff can manage order removed ingredients" ON public.order_item_removed_ingredients AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Customers can create own order items" ON public.order_items AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((order_id IN ( SELECT o.id FROM (orders o JOIN customers c ON ((c.id = o.customer_id))) WHERE (c.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Customers can read own order items" ON public.order_items AS PERMISSIVE FOR SELECT TO authenticated USING ((order_id IN ( SELECT o.id FROM (orders o JOIN customers c ON ((c.id = o.customer_id))) WHERE (c.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Staff can manage order_items" ON public.order_items AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Staff can manage order_prep_tasks" ON public.order_prep_tasks AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Customers can create own orders" ON public.orders AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Customers can read own orders" ON public.orders AS PERMISSIVE FOR SELECT TO authenticated USING ((customer_id IN ( SELECT customers.id FROM customers WHERE (customers.auth_user_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY "Staff can manage orders" ON public.orders AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Managers can read payment events" ON public.payment_events AS PERMISSIVE FOR SELECT TO authenticated USING (is_manager_or_admin());
CREATE POLICY "Managers can read payments" ON public.payments AS PERMISSIVE FOR SELECT TO authenticated USING (is_manager_or_admin());
CREATE POLICY "Staff can read prep_stations" ON public.prep_stations AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage product_categories" ON public.product_categories AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read active categories" ON public.product_categories AS PERMISSIVE FOR SELECT TO anon, authenticated USING ((is_active = true));
CREATE POLICY "Staff can read product_categories" ON public.product_categories AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage product_liquor_compatibility" ON public.product_liquor_compatibility AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read product liquor compatibility" ON public.product_liquor_compatibility AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "Staff can read product_liquor_compatibility" ON public.product_liquor_compatibility AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage product_tags" ON public.product_tags AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read active product tags" ON public.product_tags AS PERMISSIVE FOR SELECT TO anon, authenticated USING ((is_active = true));
CREATE POLICY "Staff can read product_tags" ON public.product_tags AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage product_variants" ON public.product_variants AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read active variants" ON public.product_variants AS PERMISSIVE FOR SELECT TO anon, authenticated USING ((is_active = true));
CREATE POLICY "Staff can read product_variants" ON public.product_variants AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage products" ON public.products AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read active products" ON public.products AS PERMISSIVE FOR SELECT TO anon, authenticated USING ((status = 'active'::product_status));
CREATE POLICY "Staff can read products" ON public.products AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Staff can manage promotion_redemptions" ON public.promotion_redemptions AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Managers can manage promotions" ON public.promotions AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read promotions" ON public.promotions AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Staff can manage purchase_order_items" ON public.purchase_order_items AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Staff can manage purchase_orders" ON public.purchase_orders AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Managers can manage recipe_items" ON public.recipe_items AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read recipe_items" ON public.recipe_items AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage recipes" ON public.recipes AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Staff can read recipes" ON public.recipes AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Managers can manage shop settings" ON public.shop_settings AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read shop settings" ON public.shop_settings AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "Managers can manage spotlight banner categories" ON public.spotlight_banner_categories AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read spotlight banner categories" ON public.spotlight_banner_categories AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "Managers can manage spotlight banner products" ON public.spotlight_banner_products AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read spotlight banner products" ON public.spotlight_banner_products AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "Managers can manage spotlight banners" ON public.spotlight_banners AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
CREATE POLICY "Public can read active spotlight banners" ON public.spotlight_banners AS PERMISSIVE FOR SELECT TO anon, authenticated USING ((is_active = true));
CREATE POLICY "Staff can read spotlight banners" ON public.spotlight_banners AS PERMISSIVE FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY "Staff can manage stock_movements" ON public.stock_movements AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Staff can manage stock_transfer_items" ON public.stock_transfer_items AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Staff can manage stock_transfers" ON public.stock_transfers AS PERMISSIVE FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Managers can manage suppliers" ON public.suppliers AS PERMISSIVE FOR ALL TO authenticated USING (is_manager_or_admin()) WITH CHECK (is_manager_or_admin());
