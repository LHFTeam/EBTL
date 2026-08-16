# Migrations

Every migration applied to the live project, and nothing that has not been.

The schema is owned by the Supabase dashboard, so this directory is a record
rather than a pipeline: **none of these files should be re-run.** They are here
so schema change has a reviewable history, and so the `db/schema/` capture can
be read alongside the changes that produced it.

## Ledger mapping

Supabase records what it has applied in `supabase_migrations.schema_migrations`.
Twenty-one of the twenty-two entries have a file; the exception is called out
under [Known gap](#known-gap) below.

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
| 20260815202608 | product_tag_visibility | **none — see Known gap** |
| 20260816004356 | order_handoff_log | `20260816004356_order_handoff_log.sql` |

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

## Known gap

`20260815202608 product_tag_visibility` is in the live ledger but has **no file
here**. It was applied outside this repo, so the mapping above is one row short
of complete. Backfill it the way the six earlier ones were — read its statements
out of `supabase_migrations.schema_migrations` and save them under that version
with a header saying so.

## Adding one

Write the SQL, apply it through the dashboard or `apply_migration`, then save it
here under its ledger version so the record stays complete. Refresh
`../schema/` afterwards with `../tools/dump_schema.sql` so the captured schema
reflects the change.
