-- EBTL baseline schema — views. Depend on functions in 50_functions.sql only
-- where noted; otherwise plain selects over the tables.

CREATE OR REPLACE VIEW public.v_active_product_recipes AS
 SELECT DISTINCT ON (product_id) product_id,
    id AS recipe_id,
    version,
    yield_servings,
    status
   FROM recipes r
  WHERE status = 'active'::product_status
  ORDER BY product_id, version DESC;

CREATE OR REPLACE VIEW public.v_daily_sales_by_location AS
 SELECT date_trunc('day'::text, o.created_at)::date AS sales_date,
    o.location_id,
    l.name AS location_name,
    l.type AS location_type,
    l.compound_name,
    l.beach_name,
    count(*) AS order_count,
    sum(o.total_amount) AS gross_sales,
    sum(o.subtotal_ex_vat) AS subtotal_ex_vat,
    sum(o.vat_amount) AS vat_amount,
    sum(o.discount_amount) AS discounts,
    avg(o.total_amount) AS average_order_value
   FROM orders o
     JOIN locations l ON l.id = o.location_id
  WHERE o.status = 'completed'::order_status
  GROUP BY (date_trunc('day'::text, o.created_at)::date), o.location_id, l.name, l.type, l.compound_name, l.beach_name;

CREATE OR REPLACE VIEW public.v_inventory_low_stock AS
 SELECT ib.location_id,
    l.name AS location_name,
    l.type AS location_type,
    l.compound_name,
    ib.ingredient_id,
    i.name AS ingredient_name,
    i.base_unit,
    ib.quantity_on_hand,
    ib.reserved_quantity,
    ib.reorder_point,
    ib.par_level
   FROM inventory_balances ib
     JOIN locations l ON l.id = ib.location_id
     JOIN ingredients i ON i.id = ib.ingredient_id
  WHERE ib.quantity_on_hand <= ib.reorder_point;

CREATE OR REPLACE VIEW public.v_order_prep_queue AS
 SELECT o.id AS order_id,
    o.order_number,
    o.location_id,
    l.name AS location_name,
    o.status AS order_status,
    o.requested_fulfillment_at,
    oi.id AS order_item_id,
    oi.product_name_snapshot,
    oi.variant_name_snapshot,
    oi.customization_summary,
    oi.quantity,
    oi.prep_status,
    oi.issue_reason,
    o.created_at
   FROM orders o
     JOIN locations l ON l.id = o.location_id
     JOIN order_items oi ON oi.order_id = o.id
  WHERE (o.status = ANY (ARRAY['confirmed'::order_status, 'preparing'::order_status, 'ready'::order_status])) AND (oi.prep_status = ANY (ARRAY['queued'::prep_status, 'in_progress'::prep_status, 'blocked'::prep_status]))
  ORDER BY o.created_at;

CREATE OR REPLACE VIEW public.v_product_location_availability AS
 SELECT p.id AS product_id,
    p.name AS product_name,
    p.slug,
    p.product_type,
    l.id AS location_id,
    l.name AS location_name,
        CASE
            WHEN count(ri.id) = 0 THEN true
            ELSE bool_and((COALESCE(ib.quantity_on_hand, 0::numeric) - COALESCE(ib.reserved_quantity, 0::numeric)) >= (ri.quantity / r.yield_servings::numeric))
        END AS is_available
   FROM products p
     CROSS JOIN locations l
     LEFT JOIN recipes r ON r.product_id = p.id AND r.status = 'active'::product_status
     LEFT JOIN recipe_items ri ON ri.recipe_id = r.id AND COALESCE(ri.is_customer_supplied, false) = false
     LEFT JOIN ingredients i ON i.id = ri.ingredient_id AND COALESCE(i.is_customer_supplied, false) = false
     LEFT JOIN inventory_balances ib ON ib.ingredient_id = ri.ingredient_id AND ib.location_id = l.id
  WHERE p.status = 'active'::product_status AND l.is_active = true
  GROUP BY p.id, p.name, p.slug, p.product_type, l.id, l.name;

CREATE OR REPLACE VIEW public.v_product_sales AS
 SELECT oi.product_id,
    oi.product_name_snapshot,
    count(DISTINCT oi.order_id) AS order_count,
    sum(oi.quantity) AS units_sold,
    sum(oi.line_total) AS sales_value
   FROM order_items oi
     JOIN orders o ON o.id = oi.order_id
  WHERE o.status = 'completed'::order_status
  GROUP BY oi.product_id, oi.product_name_snapshot;

CREATE OR REPLACE VIEW public.v_stock_on_hand_by_location AS
 SELECT l.id AS location_id,
    l.name AS location_name,
    l.type AS location_type,
    l.compound_name,
    i.id AS ingredient_id,
    i.name AS ingredient_name,
    i.base_unit,
    ib.quantity_on_hand,
    ib.reserved_quantity,
    ib.quantity_on_hand - ib.reserved_quantity AS available_quantity,
    ib.reorder_point,
    ib.par_level,
    ib.updated_at
   FROM inventory_balances ib
     JOIN locations l ON l.id = ib.location_id
     JOIN ingredients i ON i.id = ib.ingredient_id;

CREATE OR REPLACE VIEW public.v_transfer_summary AS
 SELECT st.id,
    st.transfer_number,
    st.status,
    from_l.name AS from_location,
    to_l.name AS to_location,
    st.requested_at,
    st.dispatched_at,
    st.received_at,
    count(sti.id) AS item_count,
    sum(sti.requested_qty) AS total_requested_qty,
    sum(sti.dispatched_qty) AS total_dispatched_qty,
    sum(sti.received_qty) AS total_received_qty,
    sum(sti.variance_qty) AS total_variance_qty
   FROM stock_transfers st
     JOIN locations from_l ON from_l.id = st.from_location_id
     JOIN locations to_l ON to_l.id = st.to_location_id
     LEFT JOIN stock_transfer_items sti ON sti.transfer_id = st.id
  GROUP BY st.id, st.transfer_number, st.status, from_l.name, to_l.name, st.requested_at, st.dispatched_at, st.received_at;
