-- EBTL data backup: public.order_inventory_consumptions
-- Idempotency guard for consume_inventory_when_order_completed. Restoring
-- these rows stops a later status update from re-consuming stock.
SET session_replication_role = replica;

INSERT INTO public.order_inventory_consumptions (order_id, consumed_at)
SELECT (r->>0)::uuid, (r->>1)::timestamp with time zone
FROM jsonb_array_elements($json$[["30976e08-3eca-4e36-9857-345d2cf83798", "2026-06-15 09:32:40.403564+00"], ["cd92e1e8-5a61-49e8-8f60-6d63d97370d1", "2026-07-23 21:03:27.731958+00"], ["fe0a023e-9e8e-4931-ab7b-bce605a1dc1b", "2026-07-23 21:05:18.77123+00"], ["c6c426b8-3d6c-4d74-8eec-e9c17479fa7e", "2026-07-24 18:58:14.816704+00"], ["f6263608-36ae-49b7-a31c-5e6af0b0f2f6", "2026-07-24 18:58:17.099342+00"], ["870d93ff-2aec-4d75-8a4f-e26dd4fbb975", "2026-07-24 18:58:19.094435+00"], ["61039db4-96e4-4c19-b3b3-becf5e073a33", "2026-07-24 18:58:23.379121+00"], ["fe765fae-8749-4acd-a380-16389def03e7", "2026-07-24 19:18:23.941065+00"], ["234453d9-7722-4c74-803a-5932a573b52b", "2026-07-24 21:20:38.767771+00"], ["90f7b537-6a75-4a00-8455-9c4ecbc0c713", "2026-07-24 21:44:07.29337+00"], ["6d7a12a2-f2ca-466c-8b6b-84d70157475d", "2026-07-25 19:38:12.970005+00"], ["3f5b468e-3967-416c-b338-3ab0ab98c602", "2026-07-25 19:47:31.223823+00"]]$json$::jsonb) AS r;

RESET session_replication_role;
