-- EBTL data backup: public.cart_item_removed_ingredients
SET session_replication_role = replica;

INSERT INTO public.cart_item_removed_ingredients (id, cart_item_id, recipe_item_id, ingredient_id, ingredient_name_snapshot, quantity_snapshot, unit_snapshot, created_at)
SELECT (r->>0)::uuid, (r->>1)::uuid, (r->>2)::uuid, (r->>3)::uuid, (r->>4)::text, (r->>5)::numeric(12,3), (r->>6)::text, (r->>7)::timestamp with time zone
FROM jsonb_array_elements($json$[["84aa1484-6715-4c68-bda2-6b3d450277b5", "b151f148-86ba-461e-95d0-ed91cd340f32", "ce628e36-585d-45dc-81b6-fb4d0fa4ccf6", "75ff1a03-e554-4745-a09c-18bc44de6ed7", "Garnish - Lemon", "1.000", "piece", "2026-06-11 08:23:07.70905+00"], ["24825835-b6b7-4775-8575-05f3a758b1f8", "ea1cc3cd-d4b0-492e-9e40-7cac29b8e714", "97acb95b-98c8-4b02-8776-1d508dc72ea2", "8cc9160a-a253-441f-a24d-9d672b9d0740", "Garnish - Pineapple", "1.000", "piece", "2026-07-16 09:58:27.810877+00"]]$json$::jsonb) AS r;

RESET session_replication_role;
