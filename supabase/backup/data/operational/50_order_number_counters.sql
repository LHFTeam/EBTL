-- EBTL data backup: public.order_number_counters
-- Per-Cairo-business-date order number counters. Restoring these keeps the
-- next order number continuous with the source database.
SET session_replication_role = replica;

INSERT INTO public.order_number_counters (order_date, last_number, updated_at)
SELECT (r->>0)::date, (r->>1)::integer, (r->>2)::timestamp with time zone
FROM jsonb_array_elements($json$[["2026-07-24", "104", "2026-07-24 19:14:18.939061+00"], ["2026-07-25", "102", "2026-07-25 19:40:03.79306+00"], ["2026-07-31", "101", "2026-07-31 08:45:36.510737+00"]]$json$::jsonb) AS r;

RESET session_replication_role;
