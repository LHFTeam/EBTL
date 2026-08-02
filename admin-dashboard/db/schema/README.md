# Baseline schema

A capture of the live Postgres schema, in version control.

The schema itself is still managed in the Supabase dashboard — these files are
**not** its source of truth, and applying them to the live project is not the
intended use. They exist so schema change is reviewable in diffs, so a scratch
or test database can be built from something, and so the shape of the data model
can be read without dashboard access.

Captured from project `pfcncajijvtvsdwgwbjl` ("EBTL 1", eu-west-1, Postgres 17).

## What is here

| File | Contents |
| --- | --- |
| `00_extensions_and_types.sql` | 4 extensions, 11 enum types, 2 sequences |
| `05_private_schema.sql` | the `private` schema and its one SECURITY DEFINER function |
| `10_tables.sql` | 53 tables — columns, defaults, generated/identity columns, RLS enablement |
| `20_constraints.sql` | 261 constraints — 53 PK, 30 unique, 87 check, 91 FK |
| `30_indexes.sql` | 85 indexes (the 83 constraint-backed ones live in `20_`) |
| `40_views.sql` | 8 views |
| `50_functions.sql` | 13 functions in `public` |
| `60_triggers.sql` | 34 triggers |
| `70_rls_policies.sql` | 86 RLS policies |
| `80_comments.sql` | 36 table and column comments |

Every count matches the system catalogs. Filename order is apply order: types
and sequences first, then the `private` function that `orders` triggers call,
then tables, then the constraints referencing them (primary/unique before the
foreign keys pointing at them), then indexes, then functions before the views
and triggers that use them.

`../tools/dump_schema.sql` regenerates all of it — one query per file — so the
capture is refreshed rather than hand-edited.

## Scope

Only `public` and `private`. The `auth`, `storage`, `realtime`, `vault`,
`extensions` and `supabase_migrations` schemas are Supabase-managed and are
deliberately not captured.

## What this capture does not prove

**Nothing here has been applied to a database.** These files were produced by
reading system catalogs; no DDL was executed against the live project.

That also means the baseline is **unverified**: nobody has confirmed that
running these files against an empty database reproduces the schema. Verifying
it needs a scratch Postgres 17 — a container, or a Supabase branch (a paid
resource). Until that has been done, treat this as an accurate transcription
rather than a tested bootstrap.

## RLS, and why it is not what protects the API

Row-level security is enabled on all 53 tables, with 86 policies keyed off
`auth.uid()` and the `is_staff()` / `is_manager_or_admin()` helpers.

The Express server connects with the **service-role key**
(`server/lib/supabase.js`), which bypasses RLS entirely. So these policies
govern direct PostgREST access only — every authorization decision the customer
and admin APIs actually make is in application code. Do not read the policy list
as a description of how the APIs are secured.

Seven tables have RLS enabled and no policy at all, making them deny-all for
`anon` and `authenticated` (reachable only via the service-role key):
`customer_credit_ledger`, `order_inventory_consumptions`,
`order_number_counters`, `referral_settings`, `referrals`,
`stock_transfer_movement_events`, and `app_events` for everything except INSERT.
