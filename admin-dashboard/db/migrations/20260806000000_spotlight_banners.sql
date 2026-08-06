-- EBTL: The Spotlight — merchandising banners that open a curated product grid
--
-- NOT YET APPLIED. Like 20260805000000_golden_hour_modes.sql, this file is a
-- migration waiting to be run rather than a record of one already applied — the
-- session that wrote it had no Supabase credentials. Apply it through the
-- dashboard (or `apply_migration`), then rename it to the ledger version it is
-- recorded under and refresh ../schema/ with ../tools/dump_schema.sql. Until
-- then the feature is inert rather than broken: `loadSpotlightBanners()` in
-- server/routes/customerRoutes.js answers with `[]` on any read error, the app
-- renders no Spotlight rail, and the Marketing → Banners tab shows its section
-- empty. It is idempotent and safe to re-run.
--
-- Why: the home hero carousel (home_hero_banners, 20260804083025) can only take
-- a customer to a destination the *app* already has — a tab, a cocktail, a
-- category. Marketing also needs to pitch a set of products that does not match
-- any single category: "Lunch in minutes", "Gatherings start with snacks". A
-- Spotlight banner is that pitch. Tapping one opens a sheet whose products are
-- chosen in the dashboard, so a new collection is a row here rather than an app
-- release.
--
-- Unlike a hero slide, a Spotlight banner has no deep link: its destination is
-- always its own sheet, and `title` is what that sheet is called. That is why
-- title is required here while headline/body are optional on a hero slide — a
-- sheet with no title has no heading to show.
--
-- The product selection is two child tables rather than one jsonb column,
-- because both sides are entities that can be archived: a product or a category
-- that goes away must take its selection with it, which `on delete cascade`
-- does and a jsonb array of ids cannot. The two are additive — a banner may
-- pick loose products, whole categories, or both, and the server unions them.
-- A banner with neither resolves to an empty sheet, which is a valid draft
-- state, so nothing here requires a selection.
--
-- Shape follows home_hero_banners: images live in the `shop-assets` storage
-- bucket under `banners/spotlight/…`, uploaded as WebP by
-- server/routes/bannerRoutes.js; RLS mirrors product_tags (managers manage,
-- staff read, public reads only active rows — the server holds the service-role
-- key and bypasses RLS, so these matter for any other client); and
-- `set_updated_at` is the same trigger function the other tables use.
--
-- The banner artwork is authored at a 2.5:1 aspect ratio (the app's
-- `HomeScreenVisuals.spotlightBannerAspectRatio`), which is not enforced here —
-- the column stores a URL, and the app scales whatever it is given to fit.

create table if not exists public.spotlight_banners (
    id uuid default gen_random_uuid() not null,
    image_url text not null,
    title text not null,
    subtitle text,
    display_order integer not null,
    is_active boolean default true not null,
    created_at timestamp with time zone default now() not null,
    updated_at timestamp with time zone default now() not null
);

alter table public.spotlight_banners enable row level security;

alter table public.spotlight_banners
    drop constraint if exists spotlight_banners_pkey;
alter table public.spotlight_banners
    add constraint spotlight_banners_pkey primary key (id);

alter table public.spotlight_banners
    drop constraint if exists spotlight_banners_image_url_not_blank;
alter table public.spotlight_banners
    add constraint spotlight_banners_image_url_not_blank check ((length(btrim(image_url)) > 0));

alter table public.spotlight_banners
    drop constraint if exists spotlight_banners_title_not_blank;
alter table public.spotlight_banners
    add constraint spotlight_banners_title_not_blank check ((length(btrim(title)) > 0));

alter table public.spotlight_banners
    drop constraint if exists spotlight_banners_title_max_80;
alter table public.spotlight_banners
    add constraint spotlight_banners_title_max_80 check ((char_length(title) <= 80));

alter table public.spotlight_banners
    drop constraint if exists spotlight_banners_subtitle_max_200;
alter table public.spotlight_banners
    add constraint spotlight_banners_subtitle_max_200 check ((subtitle is null or char_length(subtitle) <= 200));

alter table public.spotlight_banners
    drop constraint if exists spotlight_banners_display_order_non_negative;
alter table public.spotlight_banners
    add constraint spotlight_banners_display_order_non_negative check ((display_order >= 0));

create index if not exists idx_spotlight_banners_active_order
    on public.spotlight_banners using btree (is_active, display_order, created_at);

drop trigger if exists trg_spotlight_banners_updated_at on public.spotlight_banners;
create trigger trg_spotlight_banners_updated_at
    before update on public.spotlight_banners
    for each row execute function set_updated_at();

-- Loose products picked for a banner by name, independent of their category.
create table if not exists public.spotlight_banner_products (
    banner_id uuid not null,
    product_id uuid not null
);

alter table public.spotlight_banner_products enable row level security;

alter table public.spotlight_banner_products
    drop constraint if exists spotlight_banner_products_pkey;
alter table public.spotlight_banner_products
    add constraint spotlight_banner_products_pkey primary key (banner_id, product_id);

alter table public.spotlight_banner_products
    drop constraint if exists spotlight_banner_products_banner_id_fkey;
alter table public.spotlight_banner_products
    add constraint spotlight_banner_products_banner_id_fkey
    foreign key (banner_id) references public.spotlight_banners(id) on delete cascade;

alter table public.spotlight_banner_products
    drop constraint if exists spotlight_banner_products_product_id_fkey;
alter table public.spotlight_banner_products
    add constraint spotlight_banner_products_product_id_fkey
    foreign key (product_id) references public.products(id) on delete cascade;

create index if not exists idx_spotlight_banner_products_product
    on public.spotlight_banner_products using btree (product_id);

-- Whole categories picked for a banner. Resolved to products at request time,
-- so a product added to the category later shows up without touching the banner.
create table if not exists public.spotlight_banner_categories (
    banner_id uuid not null,
    category_id uuid not null
);

alter table public.spotlight_banner_categories enable row level security;

alter table public.spotlight_banner_categories
    drop constraint if exists spotlight_banner_categories_pkey;
alter table public.spotlight_banner_categories
    add constraint spotlight_banner_categories_pkey primary key (banner_id, category_id);

alter table public.spotlight_banner_categories
    drop constraint if exists spotlight_banner_categories_banner_id_fkey;
alter table public.spotlight_banner_categories
    add constraint spotlight_banner_categories_banner_id_fkey
    foreign key (banner_id) references public.spotlight_banners(id) on delete cascade;

alter table public.spotlight_banner_categories
    drop constraint if exists spotlight_banner_categories_category_id_fkey;
alter table public.spotlight_banner_categories
    add constraint spotlight_banner_categories_category_id_fkey
    foreign key (category_id) references public.product_categories(id) on delete cascade;

create index if not exists idx_spotlight_banner_categories_category
    on public.spotlight_banner_categories using btree (category_id);

drop policy if exists "Managers can manage spotlight banners" on public.spotlight_banners;
create policy "Managers can manage spotlight banners" on public.spotlight_banners
    as permissive for all to authenticated
    using (is_manager_or_admin()) with check (is_manager_or_admin());

drop policy if exists "Public can read active spotlight banners" on public.spotlight_banners;
create policy "Public can read active spotlight banners" on public.spotlight_banners
    as permissive for select to anon, authenticated
    using ((is_active = true));

drop policy if exists "Staff can read spotlight banners" on public.spotlight_banners;
create policy "Staff can read spotlight banners" on public.spotlight_banners
    as permissive for select to authenticated
    using (is_staff());

drop policy if exists "Managers can manage spotlight banner products" on public.spotlight_banner_products;
create policy "Managers can manage spotlight banner products" on public.spotlight_banner_products
    as permissive for all to authenticated
    using (is_manager_or_admin()) with check (is_manager_or_admin());

drop policy if exists "Public can read spotlight banner products" on public.spotlight_banner_products;
create policy "Public can read spotlight banner products" on public.spotlight_banner_products
    as permissive for select to anon, authenticated
    using (true);

drop policy if exists "Managers can manage spotlight banner categories" on public.spotlight_banner_categories;
create policy "Managers can manage spotlight banner categories" on public.spotlight_banner_categories
    as permissive for all to authenticated
    using (is_manager_or_admin()) with check (is_manager_or_admin());

drop policy if exists "Public can read spotlight banner categories" on public.spotlight_banner_categories;
create policy "Public can read spotlight banner categories" on public.spotlight_banner_categories
    as permissive for select to anon, authenticated
    using (true);

comment on table public.spotlight_banners is
    'CMS-driven banners for the customer app home "The Spotlight" rail. Tapping one opens a sheet titled `title` over a grid of the products selected in spotlight_banner_products and spotlight_banner_categories.';
comment on column public.spotlight_banners.title is
    'Heading of the sheet the banner opens. Required — a sheet with no title has no heading to show.';
comment on column public.spotlight_banners.subtitle is
    'Optional line under the sheet title.';
comment on column public.spotlight_banners.display_order is
    'Ascending position in the Spotlight rail. Required — marketing always chooses where a banner sits.';
comment on table public.spotlight_banner_products is
    'Loose products picked for a Spotlight banner. Unioned with the products of spotlight_banner_categories to build the banner sheet.';
comment on table public.spotlight_banner_categories is
    'Whole categories picked for a Spotlight banner, resolved to active products at request time.';
