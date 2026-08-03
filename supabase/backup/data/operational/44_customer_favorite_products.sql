-- EBTL data backup: public.customer_favorite_products
SET session_replication_role = replica;

INSERT INTO public.customer_favorite_products (customer_id, product_id, created_at)
SELECT (r->>0)::uuid, (r->>1)::uuid, (r->>2)::timestamp with time zone
FROM jsonb_array_elements($json$[["eca02a63-5f65-473f-9d17-fcac60cf5b5f", "b830c969-eaab-4c42-8f06-72a1db03f4b2", "2026-07-24 19:19:16.16255+00"], ["eca02a63-5f65-473f-9d17-fcac60cf5b5f", "ed55d6ca-ecf7-4fea-a444-31c8192f755a", "2026-07-24 21:34:15.641701+00"]]$json$::jsonb) AS r;

RESET session_replication_role;
