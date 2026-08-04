-- EBTL: CMS-driven home hero banners
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is the record of a migration already
-- applied to the live project (`apply_migration`, ledger version
-- 20260804083025). It is idempotent and safe to re-run.
--
-- Why: the customer app's home hero carousel was three slides hardcoded in
-- Flutter (`features/home/widgets/home_hero_carousel.dart`), so changing the
-- merchandising message needed an app release. This table is the merchandising
-- slot behind it — marketing edits rows in the admin dashboard's Marketing →
-- Banners tab and the app picks them up on its next `/api/customer/home`.
--
-- Only `image_url` and `display_order` are required: a slide is an image and a
-- position, and the headline/body/deep link are optional decoration on top.
-- When no active row exists the app keeps rendering its three bundled slides,
-- so an empty table is a valid, shipping state — never a broken home screen.
--
-- Shape follows the existing shop assets it sits beside:
--   * images live in the `shop-assets` storage bucket under `banners/hero/…`,
--     uploaded as WebP by server/routes/bannerRoutes.js, same as the shop
--     banner and category images;
--   * RLS mirrors product_tags — managers manage, staff read, public reads only
--     active rows (the server itself holds the service-role key and bypasses
--     RLS, so these policies matter for any other client);
--   * `set_updated_at` is the same trigger function the other tables use.
--
-- deep_link is deliberately a plain text token rather than an enum or a foreign
-- key: it names an in-app destination (`finder`, `cocktail/<slug>`, …) that only
-- the client can resolve, and the set of destinations moves with the app, not
-- with the schema. It is validated in `bannerRoutes.js` and parsed in the app's
-- `HomeHeroBanner.link`; the column only enforces "not blank if present".

create table if not exists public.home_hero_banners (
    id uuid default gen_random_uuid() not null,
    image_url text not null,
    headline text,
    body text,
    deep_link text,
    display_order integer not null,
    is_active boolean default true not null,
    created_at timestamp with time zone default now() not null,
    updated_at timestamp with time zone default now() not null
);

alter table public.home_hero_banners enable row level security;

alter table public.home_hero_banners
    drop constraint if exists home_hero_banners_pkey;
alter table public.home_hero_banners
    add constraint home_hero_banners_pkey primary key (id);

alter table public.home_hero_banners
    drop constraint if exists home_hero_banners_image_url_not_blank;
alter table public.home_hero_banners
    add constraint home_hero_banners_image_url_not_blank check ((length(btrim(image_url)) > 0));

alter table public.home_hero_banners
    drop constraint if exists home_hero_banners_headline_max_80;
alter table public.home_hero_banners
    add constraint home_hero_banners_headline_max_80 check ((headline is null or char_length(headline) <= 80));

alter table public.home_hero_banners
    drop constraint if exists home_hero_banners_body_max_200;
alter table public.home_hero_banners
    add constraint home_hero_banners_body_max_200 check ((body is null or char_length(body) <= 200));

alter table public.home_hero_banners
    drop constraint if exists home_hero_banners_deep_link_not_blank;
alter table public.home_hero_banners
    add constraint home_hero_banners_deep_link_not_blank check ((deep_link is null or length(btrim(deep_link)) > 0));

alter table public.home_hero_banners
    drop constraint if exists home_hero_banners_display_order_non_negative;
alter table public.home_hero_banners
    add constraint home_hero_banners_display_order_non_negative check ((display_order >= 0));

create index if not exists idx_home_hero_banners_active_order
    on public.home_hero_banners using btree (is_active, display_order, created_at);

drop trigger if exists trg_home_hero_banners_updated_at on public.home_hero_banners;
create trigger trg_home_hero_banners_updated_at
    before update on public.home_hero_banners
    for each row execute function set_updated_at();

drop policy if exists "Managers can manage home hero banners" on public.home_hero_banners;
create policy "Managers can manage home hero banners" on public.home_hero_banners
    as permissive for all to authenticated
    using (is_manager_or_admin()) with check (is_manager_or_admin());

drop policy if exists "Public can read active home hero banners" on public.home_hero_banners;
create policy "Public can read active home hero banners" on public.home_hero_banners
    as permissive for select to anon, authenticated
    using ((is_active = true));

drop policy if exists "Staff can read home hero banners" on public.home_hero_banners;
create policy "Staff can read home hero banners" on public.home_hero_banners
    as permissive for select to authenticated
    using (is_staff());

comment on table public.home_hero_banners is
    'CMS-driven slides for the customer app home hero carousel. Only image_url and display_order are required; the app falls back to its bundled slides when no active row exists.';
comment on column public.home_hero_banners.deep_link is
    'Optional in-app destination for a tap: finder | explore | cart | orders | cocktail/<slug> | category/<category id>. Null makes the slide non-tappable.';
comment on column public.home_hero_banners.display_order is
    'Ascending carousel position. Required — marketing always chooses where a slide sits.';
