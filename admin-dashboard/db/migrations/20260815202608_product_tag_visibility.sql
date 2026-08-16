-- EBTL: product tags — separate where a tag is allowed to appear
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is the record of a migration already
-- applied to the live project (`apply_migration`, ledger version
-- 20260815202608). It is idempotent and safe to re-run.
--
-- BACKFILLED. It was applied without a file in this repo, and the statement
-- below is reproduced verbatim from `supabase_migrations.schema_migrations`,
-- as the six earlier gaps were. Only this header is new — the SQL and both
-- column comments are the ones that ran. The intent recorded below is read
-- back off those comments, not independently known.
--
-- What it does: `product_tags` already had `is_active`, which is all-or-nothing
-- — an inactive tag is gone everywhere. These two flags split that single
-- switch into the two surfaces a tag shows up on, so a tag can be worth
-- carrying without being worth offering as a filter, or worth badging on a
-- card without cluttering the filter list. Both default to true, so every tag
-- that existed before this kept behaving exactly as it did.
--
-- Per the comments, the product detail page shows a tag regardless of either
-- flag: these govern the filter chips and the card badges only.
--
-- NOTE for whoever picks this up: as of this backfill, nothing in
-- `admin-dashboard` or `customer-app` reads either column — the tag queries in
-- cocktailRoutes.js, shopRoutes.js and customerRoutes.js still `select('*')`
-- and filter on `is_active` alone. The columns are live but unread, so setting
-- either to false currently changes nothing in the apps. The reading code is
-- still to come.

alter table public.product_tags
  add column if not exists show_in_filters boolean not null default true,
  add column if not exists show_on_product_card boolean not null default true;

comment on column public.product_tags.show_in_filters is
  'Whether the cocktail finder offers this tag as a filter chip. Off keeps it out of the filter list only — products still carry the tag, and it still shows on the product page.';

comment on column public.product_tags.show_on_product_card is
  'Whether this tag is badged on product and cocktail cards. Off hides the badge; the product detail page shows the tag regardless.';
