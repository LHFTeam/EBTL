# EBTL Supabase backup

Everything needed to rebuild the EBTL database — Supabase project `EBTL 1`
(`pfcncajijvtvsdwgwbjl`, PostgreSQL 17, eu-west-1) — from an empty database.

```
supabase/backup/
├── schema/                       full DDL, applied in filename order
├── data/reference/               catalog + config rows (committed)
├── scripts/restore.sh            rebuild a database from this backup
├── scripts/generate_data_dump.sql   re-dump any live database's data
├── scripts/dump.sh               pg_dump wrapper for raw snapshots
└── scripts/local-supabase-stub.sql  stand-ins for testing on plain Postgres
```

## Restoring

```bash
./supabase/backup/scripts/restore.sh "$DATABASE_URL" [schema|reference|full]
```

| mode        | what it loads                                              |
|-------------|------------------------------------------------------------|
| `schema`    | structure only, no rows                                     |
| `reference` | schema + `data/reference/` — the default                    |
| `full`      | schema + `data/reference/` + `data/operational/`            |

`full` requires you to generate `data/operational/` first — see
[Operational data](#operational-data). The target's `public` schema must be
empty.

## What the schema covers

`schema/` rebuilds the `public` and `private` schemas completely:

| | |
|---|---|
| Enum types | 11 |
| Tables | 78 |
| Columns | 713 |
| Primary key / unique constraints | 108 (78 + 30) |
| Check constraints | 135 |
| Foreign keys | 122 |
| Indexes | 104 (the non-constraint ones; `03_constraints.sql` creates the rest) |
| Functions | 14 in `public`, 1 in `private` |
| Views | 8 |
| Triggers | 41 |
| RLS policies | 135, across 78 RLS-enabled tables |
| Table / column comments | 68 |

These totals are the whole bundle, and every one of them was measured on
2026-08-15 by restoring `schema/` into an empty Postgres 17 and counting the
result against the live catalogs, object by object. They agree.

The demand-forecasting module (migration `20260807171440_forecast_module`, 16
`forecast_*` tables) is still appended to each file as a labelled block rather
than sorted inline. Everything else is in alphabetical order, including the nine
tables that arrived after that module — the spirit-profile, hero-carousel,
Golden Hour, Spotlight and ingredient-category work, which were added to the
capture on 2026-08-15 along with the `product_tags` visibility columns.

Files apply in order and each is independently runnable:

1. `01_prelude.sql` — extensions, enum types, standalone sequences
2. `02_tables.sql` — columns and defaults only
3. `03_constraints.sql` — keys, checks, foreign keys
4. `04_indexes.sql` — non-constraint indexes
5. `05_functions.sql` — `private.generate_order_number` plus the `public` functions
6. `06_views.sql`
7. `07_triggers.sql`
8. `08_rls_policies.sql` — `ENABLE ROW LEVEL SECURITY` and every policy
9. `09_grants_realtime_comments.sql` — grants, `supabase_realtime` publication, comments

### What is deliberately not here

Supabase provisions these on every project, so recreating them from a dump
would fight the platform rather than help it:

- the `auth`, `storage`, `realtime` and `vault` schemas and their tables
- the `anon`, `authenticated` and `service_role` roles
- `auth.uid()` / `auth.jwt()`
- Storage bucket contents. Several tables hold public Storage URLs
  (`products.image_url`, `locations.banner_image_url`,
  `liquor_types.image_url`, `shop_settings.banner_image_url`). Restoring into
  a *different* project leaves those URLs pointing at the old project — copy
  the buckets, or rewrite the host.

Auth users are not backed up either. `customers.auth_user_id` and
`employees.auth_user_id` are plain `uuid` columns with no foreign key to
`auth.users`, so rows restore cleanly, but those users won't be able to sign
in until the corresponding auth identities exist.

## Data

Rows are stored as one `INSERT ... SELECT` per table over a jsonb
array-of-arrays, with every value cast back through its own column type. uuids,
`text[]`, `jsonb`, enums, `numeric(p,s)` and timestamps all round-trip exactly,
and the encoding has no quoting pitfalls.

Each data file sets `session_replication_role = replica` for the load, which
disables triggers and foreign key checks. That is what keeps timestamps and
`stock_movements` from being rewritten on insert — the `trg_apply_stock_movement`
trigger would otherwise double-count `inventory_balances`. It also means table
load order does not matter.

### Reference data (committed)

`data/reference/` holds the catalog and configuration rows — the part that is
safe in git and useful for standing up a working environment:

| file | rows |
|---|---|
| `10_product_categories.sql` | 5 |
| `12_product_variants.sql` | 73 |
| `13_product_tags.sql` | 5 |
| `14_liquor_types.sql` | 9 |
| `15b_ingredient_categories.sql` | 10 |
| `16_ingredients.sql` | 57 |
| `20_locations.sql` | 3 |
| `21_location_opening_hours.sql` | 14 |
| `22_prep_stations.sql` | 3 |
| `30_settings.sql` | 2 (both singleton config tables) |

Also committed: `15_product_liquor_compatibility.sql` (72 rows) and
`17_recipes.sql` (74 rows).

`13_product_tags.sql`, `15b_ingredient_categories.sql` and `16_ingredients.sql`
were re-dumped from the live project on 2026-08-15, when `ingredients` lost its
`category` text column to `category_id`. The ingredient count drops 66 → 57
there: the old file was a June snapshot, and nine of its rows no longer exist.

Still to capture: `products`, `recipe_items`. Run the generator (below) and
move those two blocks into `data/reference/`.

### Operational data

`data/operational/` holds a literal snapshot of the live transactional tables,
committed deliberately. **It is sensitive:**

- `42_customers.sql` — real customer names, phone numbers, email addresses
- `40_employees.sql` — staff names and phone numbers
- `41_employee_credentials.sql` — staff usernames, password hashes and salts
- `51_orders.sql` — customer phone snapshots

Committed so far: `employees`, `employee_credentials`, `customers`,
`customer_favorite_products`, `carts`, `cart_items`,
`cart_item_removed_ingredients`, `order_number_counters`, `orders`,
`order_items`, `order_item_removed_ingredients`,
`order_inventory_consumptions`, `customer_notifications`.

Still to capture: `payments`, `payment_events`,
`order_item_inventory_components`, `stock_movements`, `inventory_balances`.

> **Before committing `payments` / `payment_event`s, read this.** Their
> `raw_payload` columns embed Stripe `client_secret` and `ephemeral_key_secret`
> values, including at least one `ek_live_…` key, plus full PaymentIntent
> objects. Those particular secrets are spent — ephemeral keys expire after an
> hour and a client secret only ever unlocks its own already-succeeded intent —
> but they are still live-mode credentials in plain text. Consider stripping or
> redacting `raw_payload` before committing those two tables.

### Snapshot consistency

Tables were captured one at a time against a live database, so the snapshot is
**not a single point in time**. A row in one file may reference a row that did
not yet exist when an earlier file was captured — for example `orders` includes
an order whose customer was created after `customers` was captured. Loading
still succeeds because foreign key checks are off, but the result can have
dangling references. The generator below dumps every table in one session and
does not have this problem.

### Regenerating

Generate the remaining tables — or refresh everything — with:

```bash
psql "$DATABASE_URL" -qAt \
  -f supabase/backup/scripts/generate_data_dump.sql \
  > supabase/backup/snapshots/data.sql
```

That emits **every** non-empty table in `public`, reference and operational
alike, as a single loadable file. `snapshots/` is git-ignored. Split out the
tables you want under `data/operational/` if you need `restore.sh full`, and
treat the result as sensitive.

`scripts/dump.sh` is the alternative when you have direct database
credentials — a thin `pg_dump` wrapper producing raw schema and data snapshots.

## Verifying a restore

`scripts/local-supabase-stub.sql` creates the roles, `auth.uid()` and
`auth.jwt()` that the policies and `private.generate_order_number` reference,
so the backup can be exercised against a plain PostgreSQL server:

```bash
createdb ebtl_test
psql ebtl_test -f supabase/backup/scripts/local-supabase-stub.sql
./supabase/backup/scripts/restore.sh "postgresql:///ebtl_test" reference
```

This backup was verified that way: restored into a scratch PostgreSQL 16
instance, and all 14 object-count categories in the table above matched the
live database exactly. The data encoding was then round-tripped — dumped from
the restored database, loaded into a second empty one, and compared per table
with an `md5` over every row — with identical results, Arabic text and
generated columns included.

## Keeping it current

The schema files are hand-curated rather than raw `pg_dump` output, so they
stay readable and reviewable. When the schema changes, apply the migration as
usual and update the matching file here. `scripts/dump.sh` gives you a raw
snapshot to diff against when you want to confirm nothing was missed.
