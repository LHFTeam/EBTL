-- EBTL: Spotlight banners — link to a markdown slide instead of a product grid
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is **not yet applied** — written in a
-- session with no Supabase credentials, so it carries a placeholder timestamp
-- rather than a ledger version. Apply it with `apply_migration`, rename it to
-- the version the ledger records, add it to the table in README.md, and
-- refresh `../schema/`. Until then the dashboard has no column to write to and
-- every Spotlight banner keeps opening its product-grid sheet, so nothing else
-- breaks in the meantime. It is idempotent and safe to re-run.
--
-- Why: a Spotlight banner's destination has always been its own sheet over a
-- curated product grid (20260806211254_spotlight_banners.sql). Marketing also
-- wants to pitch things that are not a product at all — a story, a recipe, a
-- "how it works" — as free-form copy with headings, images and lists rather
-- than a picked set of SKUs. `content_type` is the switch between the two
-- sheets a banner can open; `markdown_body` is the copy for the second one.
--
-- `content_type` defaults to 'products' so every banner from before this
-- migration keeps its existing behaviour with no backfill required. A banner
-- switched to 'markdown' does not lose its product selection rows — they just
-- go unread until it is switched back — because clearing them on every toggle
-- would make the switch itself a destructive action.

alter table public.spotlight_banners
    add column if not exists content_type text not null default 'products';

alter table public.spotlight_banners
    add column if not exists markdown_body text;

alter table public.spotlight_banners
    drop constraint if exists spotlight_banners_content_type_valid;
alter table public.spotlight_banners
    add constraint spotlight_banners_content_type_valid check ((content_type in ('products', 'markdown')));

-- A markdown banner with nothing written is a draft, not a valid slide — the
-- app has nothing to render. A products banner is unconstrained here, same as
-- before: an empty selection is a valid draft state for that sheet.
alter table public.spotlight_banners
    drop constraint if exists spotlight_banners_markdown_body_required_when_markdown;
alter table public.spotlight_banners
    add constraint spotlight_banners_markdown_body_required_when_markdown
    check ((content_type <> 'markdown' or length(btrim(coalesce(markdown_body, ''))) > 0));

alter table public.spotlight_banners
    drop constraint if exists spotlight_banners_markdown_body_max_20000;
alter table public.spotlight_banners
    add constraint spotlight_banners_markdown_body_max_20000 check ((markdown_body is null or char_length(markdown_body) <= 20000));

comment on column public.spotlight_banners.content_type is
    'Which sheet tapping this banner opens: ''products'' (the curated grid from spotlight_banner_products/spotlight_banner_categories, the original and default behaviour) or ''markdown'' (markdown_body rendered as a slide).';
comment on column public.spotlight_banners.markdown_body is
    'Markdown copy for a content_type = ''markdown'' banner''s slide. Supports headings (its first heading takes the place of the sheet title), images, and ordered/unordered lists. Unused and ignored when content_type = ''products''.';
