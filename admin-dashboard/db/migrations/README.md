# Migrations

Every migration applied to the live project, plus the one still waiting to be
applied — listed under "Not yet applied" below, and nothing else.

The schema is owned by the Supabase dashboard, so this directory is a record
rather than a pipeline: **none of these files should be re-run.** They are here
so schema change has a reviewable history, and so the `db/schema/` capture can
be read alongside the changes that produced it.

## Ledger mapping

Supabase records what it has applied in `supabase_migrations.schema_migrations`.
All twenty entries have a file:

| Ledger version | Name | File |
| --- | --- | --- |
| 20260724002633 | enable_prep_kitchen_realtime | `20260724002633_…sql` |
| 20260724003429 | add_order_confirmation_timer | `20260724003429_…sql` |
| 20260724003509 | make_order_confirmation_timer_immutable | `20260724003509_…sql` |
| 20260724005738 | atomic_cart_order_status_transition | `20260724005738_…sql` |
| 20260724164758 | daily_order_number_and_lifecycle_timestamps | `20260724_daily_order_number_and_lifecycle_timestamps.sql` |
| 20260725114416 | promo_code_engine_controls | `20260725_promo_code_engine.sql` |
| 20260725190557 | scope_order_numbers_by_cairo_business_date | `20260725190557_…sql` |
| 20260726004844 | add_name_ar_for_kds_arabic_localization | `20260726004844_…sql` |
| 20260726213254 | referral_program_engine | `20260726_referral_program_engine.sql` |
| 20260731185443 | expired_order_status | `20260731_expired_order_status.sql` |
| 20260804083025 | home_hero_banners | `20260804083025_…sql` |
| 20260804191747 | customer_spirit_profile | `20260804191747_customer_spirit_profile.sql` |
| 20260804195427 | home_hero_settings | `20260804195427_…sql` |
| 20260805073530 | golden_hour_modes | `20260805073530_golden_hour_modes.sql` |
| 20260806211254 | spotlight_banners | `20260806211254_spotlight_banners.sql` |
| 20260807124610 | spotlight_banner_markdown_slide | `20260807124610_…sql` |
| 20260807171440 | forecast_module | `20260807171440_forecast_module.sql` |
| 20260810132333 | normalize_ingredient_categories | `20260810120000_normalize_ingredient_categories.sql` |
| 20260810174101 | cascade_ingredient_delete | `20260810174101_cascade_ingredient_delete.sql` |
| 20260810221934 | ingredient_search_visibility | `20260810221934_ingredient_search_visibility.sql` |

## Notes on the applied set

`normalize_ingredient_categories` is the one file whose name does not match its
ledger version: it was saved as `20260810120000_…` before the ledger assigned
`20260810132333`. Renaming it would break nothing, but the mapping above is what
makes the pair readable until then.

Six of them were recorded with no file in the repo and were backfilled
from the ledger's stored statements. They carry a header saying so. The four
older files predate that and keep their original `YYYYMMDD_name` names; new
files use the full ledger version, because three migrations share 2026-07-24 and
a date alone cannot order or name them.

To check the two are still in step:

```sql
select version, name from supabase_migrations.schema_migrations order by version;
```

## Not yet applied

| File | What it does |
| --- | --- |
| `20260815120000_product_tag_visibility.sql` | Adds `show_in_filters` and `show_on_product_card` to `product_tags` |

Apply it through the dashboard or `apply_migration`, confirm the ledger version
it lands under matches the filename, move its row into the mapping above, and
refresh `../schema/` with `../tools/dump_schema.sql`. Until then the capture in
`../schema/` does not describe these two columns.

Reads survive the wait: the customer API takes both flags as "on unless the
column says otherwise", so every tag keeps filtering and badging the way it did
before. Writes do not — saving a tag from Shop → Product Tags sends both columns
and Postgres rejects the update until the migration lands.

## Adding one

Write the SQL, apply it through the dashboard or `apply_migration`, then save it
here under its ledger version so the record stays complete. Refresh
`../schema/` afterwards with `../tools/dump_schema.sql` so the captured schema
reflects the change.
