-- EBTL data backup: public.prep_stations
SET session_replication_role = replica;

INSERT INTO public.prep_stations (id, location_id, name, is_active, created_at, updated_at)
SELECT (r->>0)::uuid, (r->>1)::uuid, (r->>2)::text, (r->>3)::boolean, (r->>4)::timestamp with time zone, (r->>5)::timestamp with time zone
FROM jsonb_array_elements($json$[["fd2a3c68-89b3-4934-9bbf-8dd1b60ab6e3", "743e3c2b-767a-4831-8c20-a5440843cf89", "Main Prep Station", "true", "2026-05-31 10:14:00.865684+00", "2026-05-31 10:14:00.865684+00"], ["58566cdf-0357-4d3a-b297-64e9ece5a1cf", "6d8dc341-2a08-4bd6-9fbf-47bfee86d4c9", "Main Prep Station", "true", "2026-05-31 10:14:00.865684+00", "2026-05-31 10:14:00.865684+00"], ["d7684818-48b1-4fab-8289-d91df5394a4d", "67150dbe-3183-4425-888b-27e8aba61b03", "Main Prep Station", "true", "2026-05-31 10:14:00.865684+00", "2026-05-31 10:14:00.865684+00"]]$json$::jsonb) AS r;

RESET session_replication_role;
