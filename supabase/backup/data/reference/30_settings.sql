-- EBTL data backup: public.shop_settings, public.referral_settings (single-row config tables)
SET session_replication_role = replica;

INSERT INTO public.shop_settings (id, banner_image_url, created_at, updated_at)
SELECT (r->>0)::boolean, (r->>1)::text, (r->>2)::timestamp with time zone, (r->>3)::timestamp with time zone
FROM jsonb_array_elements($json$[["true", "https://pfcncajijvtvsdwgwbjl.supabase.co/storage/v1/object/public/shop-assets/banners/shop/1780825377503.webp", "2026-06-03 22:44:34.27553+00", "2026-06-07 09:42:57.842757+00"]]$json$::jsonb) AS r;

INSERT INTO public.referral_settings (id, is_active, referrer_reward_amount, referee_discount_type, referee_discount_value, referee_max_discount_amount, min_qualifying_order_value, reward_cap_per_referrer, terms, updated_at)
SELECT (r->>0)::boolean, (r->>1)::boolean, (r->>2)::numeric(12,2), (r->>3)::text, (r->>4)::numeric(12,2), (r->>5)::numeric(12,2), (r->>6)::numeric(12,2), (r->>7)::integer, (r->>8)::text, (r->>9)::timestamp with time zone
FROM jsonb_array_elements($json$[["true", "true", "100.00", "fixed_amount", "75.00", null, "0.00", null, null, "2026-07-26 21:32:54.44305+00"]]$json$::jsonb) AS r;

RESET session_replication_role;
