-- EBTL data backup: public.product_categories
SET session_replication_role = replica;

INSERT INTO public.product_categories (id, name, sort_order, is_active, created_at, updated_at, slug, image_url)
SELECT (r->>0)::uuid, (r->>1)::text, (r->>2)::integer, (r->>3)::boolean, (r->>4)::timestamp with time zone, (r->>5)::timestamp with time zone, (r->>6)::text, (r->>7)::text
FROM jsonb_array_elements($json$[["c4c35696-b85b-4f24-ac98-37988693c6a0", "Bundles", "2", "true", "2026-05-30 19:34:15.546051+00", "2026-06-01 06:46:42.939648+00", "bundles", null], ["18e06fd3-697d-41ec-bbc2-0b3588a98117", "Add-ons", "3", "true", "2026-05-30 19:34:15.546051+00", "2026-06-01 06:46:42.939648+00", "add-ons", null], ["38ef44f4-07ff-429a-a22b-b025d1c7986b", "Snacks", "4", "true", "2026-06-01 06:46:33.097732+00", "2026-06-01 06:46:42.939648+00", "snacks", null], ["297d67bc-81bb-40f2-94b2-59455a4384a0", "Essentials", "5", "true", "2026-06-01 06:46:33.097732+00", "2026-06-01 06:46:42.939648+00", "essentials", null], ["841edc45-a429-4270-baab-0d06a20b99d5", "Cocktails", "1", "true", "2026-05-30 19:34:15.546051+00", "2026-06-06 18:57:48.557037+00", "cocktails", null]]$json$::jsonb) AS r;

RESET session_replication_role;
