-- EBTL data backup: public.locations
SET session_replication_role = replica;

INSERT INTO public.locations (id, name, type, compound_name, beach_name, address, latitude, longitude, is_active, created_at, updated_at, banner_image_url, delivery_fee, name_ar)
SELECT (r->>0)::uuid, (r->>1)::text, (r->>2)::location_type, (r->>3)::text, (r->>4)::text, (r->>5)::text, (r->>6)::numeric(10,7), (r->>7)::numeric(10,7), (r->>8)::boolean, (r->>9)::timestamp with time zone, (r->>10)::timestamp with time zone, (r->>11)::text, (r->>12)::numeric(12,2), (r->>13)::text
FROM jsonb_array_elements($json$[["743e3c2b-767a-4831-8c20-a5440843cf89", "Central Warehouse", "central_warehouse", null, null, null, null, null, "true", "2026-05-30 19:34:15.546051+00", "2026-07-26 01:05:08.957784+00", null, "0.00", "المستودع المركزي"], ["67150dbe-3183-4425-888b-27e8aba61b03", "Hacienda Cart", "beach_cart", "Hacienda", "North Coast", null, null, null, "true", "2026-05-31 10:08:51.591438+00", "2026-07-26 01:05:08.957784+00", "https://pfcncajijvtvsdwgwbjl.supabase.co/storage/v1/object/public/locations/location-banners/67150dbe-3183-4425-888b-27e8aba61b03/1780751143114.webp", "0.00", "عربة هاسيندا"], ["6d8dc341-2a08-4bd6-9fbf-47bfee86d4c9", "Marassi Cart", "beach_cart", "Marassi", "North Coast", null, null, null, "true", "2026-05-31 10:08:51.591438+00", "2026-07-26 01:05:08.957784+00", "https://pfcncajijvtvsdwgwbjl.supabase.co/storage/v1/object/public/locations/location-banners/6d8dc341-2a08-4bd6-9fbf-47bfee86d4c9/1780751165432.webp", "0.00", "عربة مراسي"]]$json$::jsonb) AS r;

RESET session_replication_role;
