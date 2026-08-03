-- EBTL data backup: public.employee_credentials
--
-- SECRETS: this file contains staff login usernames together with their
-- password hashes and salts. Anyone who can read this file can mount an
-- offline attack against those passwords. Treat it as credential material:
-- restrict who can read the repository, and rotate the staff passwords if it
-- is ever exposed more widely than intended.
SET session_replication_role = replica;

INSERT INTO public.employee_credentials (id, employee_id, username, password_hash, password_salt, must_change_password, is_active, created_at, updated_at)
SELECT (r->>0)::uuid, (r->>1)::uuid, (r->>2)::text, (r->>3)::text, (r->>4)::text, (r->>5)::boolean, (r->>6)::boolean, (r->>7)::timestamp with time zone, (r->>8)::timestamp with time zone
FROM jsonb_array_elements($json$[["fffe9f3c-786e-431c-86b6-bf91a7bd43e2", "b7432c0b-7cf6-4686-a27a-5ffc6c240fe5", "prep", "au2E3cTusWbtZsadSqM23ab_HgLdvv0QYPpaxekG3K8", "uPJQiX9VHOxmXTZIimfztA", "false", "true", "2026-07-24 10:07:36.755077+00", "2026-07-24 10:37:37.809094+00"], ["58013387-7aa0-456b-9a6e-aae8b654f5ea", "bd85d0a3-cb01-425c-b042-0e8415da0181", "prep2", "AqmIrpMd-EXhs3elshHYmT-TUtL-D8ow53nv_CS3-5U", "NPpp0WAczy4_TUUOwsndLQ", "false", "true", "2026-07-24 21:42:48.650122+00", "2026-07-24 21:42:48.650122+00"]]$json$::jsonb) AS r;

RESET session_replication_role;
