-- EBTL data backup: public.employees
-- Contains staff names and phone numbers.
SET session_replication_role = replica;

INSERT INTO public.employees (id, auth_user_id, full_name, phone, role, default_location_id, is_active, created_at, updated_at)
SELECT (r->>0)::uuid, (r->>1)::uuid, (r->>2)::text, (r->>3)::text, (r->>4)::public.employee_role, (r->>5)::uuid, (r->>6)::boolean, (r->>7)::timestamp with time zone, (r->>8)::timestamp with time zone
FROM jsonb_array_elements($json$[["d4bf5402-7cf8-4292-b87b-324b3f9fd96c", "e0efb62d-50e6-455b-8983-82a3542a7556", "Ali Nasser", "+201224098424", "admin", "743e3c2b-767a-4831-8c20-a5440843cf89", "true", "2026-05-31 10:11:11.104831+00", "2026-05-31 10:19:50.091402+00"], ["b7432c0b-7cf6-4686-a27a-5ffc6c240fe5", null, "John", null, "prep", "67150dbe-3183-4425-888b-27e8aba61b03", "true", "2026-07-24 10:07:36.562159+00", "2026-07-24 10:36:55.504969+00"], ["bd85d0a3-cb01-425c-b042-0e8415da0181", null, "Joe", null, "prep", "6d8dc341-2a08-4bd6-9fbf-47bfee86d4c9", "true", "2026-07-24 21:42:48.445767+00", "2026-07-24 21:42:48.445767+00"]]$json$::jsonb) AS r;

RESET session_replication_role;
