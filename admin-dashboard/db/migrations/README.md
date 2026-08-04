# Migrations

Every migration applied to the live project — plus, listed separately below,
any that are written but **not yet applied**.

The schema is owned by the Supabase dashboard, so this directory is a record
rather than a pipeline: **none of these files should be re-run.** They are here
so schema change has a reviewable history, and so the `db/schema/` capture can
be read alongside the changes that produced it.

## Ledger mapping

Supabase records what it has applied in `supabase_migrations.schema_migrations`.
All ten entries now have a file:

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

## Not yet applied

| File | What it adds |
| --- | --- |
| `20260804_customer_spirit_profile.sql` | `customer_favorite_liquor_types` and `customer_top_liquor_types` — the two spirit lists on the customer profile (see `server/lib/customerSpirits.js`). |

Until this is applied, `GET /api/customer/spirits` answers with the Postgres
error, the profile's `spirits` block degrades to empty lists (the profile
itself keeps loading), and every order confirmation logs a failed
`recomputeCustomerTopSpirits` — deliberately non-fatal, so payments still
settle. Apply it, then move its row into the ledger table above and refresh
`../schema/`.

## Notes on the applied set

Six of them were recorded with no file in the repo and were backfilled
from the ledger's stored statements. They carry a header saying so. The four
older files predate that and keep their original `YYYYMMDD_name` names; new
files use the full ledger version, because three migrations share 2026-07-24 and
a date alone cannot order or name them.

To check the two are still in step:

```sql
select version, name from supabase_migrations.schema_migrations order by version;
```

## Adding one

Write the SQL, apply it through the dashboard or `apply_migration`, then save it
here under its ledger version so the record stays complete. Refresh
`../schema/` afterwards with `../tools/dump_schema.sql` so the captured schema
reflects the change.
