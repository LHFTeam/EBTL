-- EBTL: Golden Hour launch modal (time-of-day modes)
--
-- NOT YET APPLIED. Unlike its neighbours in this directory, this file is a
-- migration waiting to be run, not a record of one already applied — the
-- session that wrote it had no Supabase credentials. Apply it through the
-- dashboard (or `apply_migration`), then rename it to the ledger version it is
-- recorded under and refresh ../schema/ with ../tools/dump_schema.sql. Until
-- then the Marketing → Golden Hour tab and the app's launch modal have no table
-- to read and the feature is inert: `/api/customer/home` answers with
-- `goldenHour: null` on any read error, so nothing breaks in the meantime.
-- It is idempotent and safe to re-run.
--
-- Why: when the customer app opens and a beach cart is already chosen, it
-- greets the customer with one cocktail suggestion suited to the hour — a
-- Bloody Mary at 9am is a different pitch from a Negroni at 9pm. That pitch is
-- pure merchandising, so marketing owns all of it (copy, image, cocktail,
-- pills, the hours each mode covers, and whether it runs at all) from the
-- dashboard rather than it being frozen into an app release.
--
-- Four modes, and only ever four: morning, afternoon, sunset, evening. They are
-- a fixed vocabulary shared with the dashboard tab and the app, not user data,
-- so `mode` is the primary key and the rows are seeded here. There is no create
-- or delete in the API — only editing these four — which is why nothing in the
-- schema supports a fifth.
--
-- Time windows are `time` columns compared in Africa/Cairo (the business time
-- zone, see BUSINESS_TIME_ZONE in server/routes/customerRoutes.js), and a
-- window may wrap midnight: evening's default 19:00–02:00 is `start_time >
-- end_time`, which the server reads as "at or after start, or before end".
-- That is why the only ordering constraint here is that the two differ — a
-- window equal at both ends would be either empty or eternal depending on how
-- you squint, and neither is what anyone meant to configure.
--
-- Shape follows home_hero_banners (20260804083025): images live in the
-- `shop-assets` bucket under `golden-hour/…` as WebP uploaded by
-- server/routes/goldenHourRoutes.js, RLS mirrors product_tags, and
-- `set_updated_at` is the same trigger function the other tables use.
--
-- `pills` is jsonb rather than a child table because the pills are display
-- copy, not entities: nothing references them, they are never queried across
-- rows, and "how many" is just the array's length. The server validates the
-- shape (`[{label, scheme}]`, at most four) with zod; the check constraint here
-- only holds the line on the parts a bad client could otherwise slip past.
--
-- The first pill is deliberately NOT in `pills`. It always reads
-- "Your <liquor type>", derived at request time from the chosen cocktail's
-- product_liquor_compatibility rows, so only its colour scheme is stored.

create table if not exists public.golden_hour_modes (
    mode text not null,
    is_active boolean default false not null,
    start_time time without time zone not null,
    end_time time without time zone not null,
    title text,
    subtitle text,
    product_id uuid,
    image_url text,
    image_caption text,
    spirit_pill_scheme text default 'sand' not null,
    pills jsonb default '[]'::jsonb not null,
    created_at timestamp with time zone default now() not null,
    updated_at timestamp with time zone default now() not null
);

alter table public.golden_hour_modes enable row level security;

alter table public.golden_hour_modes
    drop constraint if exists golden_hour_modes_pkey;
alter table public.golden_hour_modes
    add constraint golden_hour_modes_pkey primary key (mode);

-- The vocabulary is closed: the dashboard edits these four and the app knows
-- these four. A fifth would reach the app as a mode it cannot render.
alter table public.golden_hour_modes
    drop constraint if exists golden_hour_modes_mode_known;
alter table public.golden_hour_modes
    add constraint golden_hour_modes_mode_known check ((mode = any (array['morning'::text, 'afternoon'::text, 'sunset'::text, 'evening'::text])));

-- Equal ends describe either no window at all or every hour of the day. Both
-- are almost certainly a mistake, and neither is worth teaching the resolver.
alter table public.golden_hour_modes
    drop constraint if exists golden_hour_modes_window_not_empty;
alter table public.golden_hour_modes
    add constraint golden_hour_modes_window_not_empty check ((start_time <> end_time));

alter table public.golden_hour_modes
    drop constraint if exists golden_hour_modes_title_max_60;
alter table public.golden_hour_modes
    add constraint golden_hour_modes_title_max_60 check ((title is null or char_length(title) <= 60));

alter table public.golden_hour_modes
    drop constraint if exists golden_hour_modes_subtitle_max_160;
alter table public.golden_hour_modes
    add constraint golden_hour_modes_subtitle_max_160 check ((subtitle is null or char_length(subtitle) <= 160));

alter table public.golden_hour_modes
    drop constraint if exists golden_hour_modes_image_caption_max_120;
alter table public.golden_hour_modes
    add constraint golden_hour_modes_image_caption_max_120 check ((image_caption is null or char_length(image_caption) <= 120));

alter table public.golden_hour_modes
    drop constraint if exists golden_hour_modes_image_url_not_blank;
alter table public.golden_hour_modes
    add constraint golden_hour_modes_image_url_not_blank check ((image_url is null or length(btrim(image_url)) > 0));

-- Four is what the modal's pill row fits on the narrowest phone it targets.
alter table public.golden_hour_modes
    drop constraint if exists golden_hour_modes_pills_shape;
alter table public.golden_hour_modes
    add constraint golden_hour_modes_pills_shape check ((jsonb_typeof(pills) = 'array' and jsonb_array_length(pills) <= 4));

alter table public.golden_hour_modes
    drop constraint if exists golden_hour_modes_product_id_fkey;
alter table public.golden_hour_modes
    add constraint golden_hour_modes_product_id_fkey foreign key (product_id) references public.products(id) on delete set null;

drop trigger if exists trg_golden_hour_modes_updated_at on public.golden_hour_modes;
create trigger trg_golden_hour_modes_updated_at
    before update on public.golden_hour_modes
    for each row execute function set_updated_at();

drop policy if exists "Managers can manage golden hour modes" on public.golden_hour_modes;
create policy "Managers can manage golden hour modes" on public.golden_hour_modes
    as permissive for all to authenticated
    using (is_manager_or_admin()) with check (is_manager_or_admin());

drop policy if exists "Public can read active golden hour modes" on public.golden_hour_modes;
create policy "Public can read active golden hour modes" on public.golden_hour_modes
    as permissive for select to anon, authenticated
    using ((is_active = true));

drop policy if exists "Staff can read golden hour modes" on public.golden_hour_modes;
create policy "Staff can read golden hour modes" on public.golden_hour_modes
    as permissive for select to authenticated
    using (is_staff());

-- Seeded inactive and empty: the four rows exist so the dashboard has something
-- to edit, and a mode stays dark until marketing gives it a title and a
-- cocktail and switches it on. The hours are a sensible starting split of the
-- day, not a decision — every one of them is editable.
insert into public.golden_hour_modes (mode, start_time, end_time, spirit_pill_scheme)
values
    ('morning', '06:00', '11:00', 'sand'),
    ('afternoon', '11:00', '16:00', 'seafoam'),
    ('sunset', '16:00', '19:00', 'gold'),
    ('evening', '19:00', '02:00', 'navy')
on conflict (mode) do nothing;

comment on table public.golden_hour_modes is
    'The four time-of-day variants of the customer app''s launch modal ("Golden Hour"). Exactly four rows, seeded and edited from Marketing → Golden Hour; never created or deleted through the API.';
comment on column public.golden_hour_modes.start_time is
    'Inclusive start of the window this mode covers, in Africa/Cairo. May be later than end_time, which means the window wraps past midnight.';
comment on column public.golden_hour_modes.end_time is
    'Exclusive end of the window this mode covers, in Africa/Cairo.';
comment on column public.golden_hour_modes.product_id is
    'The cocktail the modal pitches, and the one its Add to Cart adds. Required before a mode can be switched on; nulled rather than blocking if the product is ever deleted, which switches the mode off on its next read.';
comment on column public.golden_hour_modes.spirit_pill_scheme is
    'Colour scheme of the leading pill only. Its text is always "Your <liquor type>", derived from the chosen cocktail rather than stored.';
comment on column public.golden_hour_modes.pills is
    'Pills shown after the leading spirit pill, in order: [{"label": "…", "scheme": "…"}]. Up to four; the array length is the count.';
