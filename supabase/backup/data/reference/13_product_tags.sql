-- EBTL data backup: public.product_tags
SET session_replication_role = replica;

INSERT INTO public.product_tags (id, name, color_hex, display_order, is_active, created_at, updated_at)
SELECT (r->>0)::uuid, (r->>1)::text, (r->>2)::text, (r->>3)::integer, (r->>4)::boolean, (r->>5)::timestamp with time zone, (r->>6)::timestamp with time zone
FROM jsonb_array_elements($json$[["14e39a14-23de-4bc4-80c2-b31a96ec8ea6", "Sunset Pick", "#E7BD68", "2", "true", "2026-06-01 08:59:42.471055+00", "2026-06-06 17:55:52.936819+00"], ["d52806a2-20b9-4aa2-803c-4ae3ee4ef4af", "Tropical", "#1f6f68", "40", "false", "2026-06-01 08:59:42.471055+00", "2026-06-06 17:55:52.936819+00"], ["bffe7fec-7a36-401f-9b29-6493d1661d35", "Seasonal", "#F8C9BD", "50", "false", "2026-06-01 08:59:42.471055+00", "2026-06-06 17:55:52.936819+00"], ["4fdd6040-4d17-40fb-8b93-e0cfa312b075", "Beach Favorite", "#f35f4b", "3", "true", "2026-06-01 08:59:42.471055+00", "2026-06-06 18:09:59.288921+00"], ["b1dfab20-714e-4838-9a08-91fdcec62b81", "Popular", "#1f6f68", "1", "true", "2026-06-01 08:59:42.471055+00", "2026-06-06 18:10:10.290549+00"]]$json$::jsonb) AS r;

RESET session_replication_role;
