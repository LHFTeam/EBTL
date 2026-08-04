-- EBTL: home hero carousel settings (auto-rotation interval)
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is the record of a migration already
-- applied to the live project (`apply_migration`, ledger version
-- 20260804195427). It is idempotent and safe to re-run.
--
-- Why: the home hero carousel (see 20260804083025_home_hero_banners.sql) now
-- advances itself. How long a slide dwells before it slides on is a
-- merchandising decision — a five-second beat suits three short slides and is
-- far too fast for a wordy one — so marketing owns the number from Marketing →
-- Banners rather than it being frozen into an app release.
--
-- Shape follows the other config tables (`shop_settings`, `referral_settings`):
-- one row pinned by a boolean primary key, with the `_singleton` check that
-- makes a second row impossible. The row is seeded here so readers never have
-- to handle its absence; the app defaults to 5 seconds anyway if the value
-- cannot be read at all.

create table if not exists public.home_hero_settings (
    id boolean default true not null,
    rotation_seconds integer default 5 not null,
    created_at timestamp with time zone default now() not null,
    updated_at timestamp with time zone default now() not null
);

alter table public.home_hero_settings enable row level security;

alter table public.home_hero_settings
    drop constraint if exists home_hero_settings_pkey;
alter table public.home_hero_settings
    add constraint home_hero_settings_pkey primary key (id);

alter table public.home_hero_settings
    drop constraint if exists home_hero_settings_singleton;
alter table public.home_hero_settings
    add constraint home_hero_settings_singleton check ((id = true));

-- Two seconds is the fastest a slide can be read; a minute is the slowest that
-- still reads as a carousel rather than a static image.
alter table public.home_hero_settings
    drop constraint if exists home_hero_settings_rotation_seconds_range;
alter table public.home_hero_settings
    add constraint home_hero_settings_rotation_seconds_range check (((rotation_seconds >= 2) and (rotation_seconds <= 60)));

drop trigger if exists trg_home_hero_settings_updated_at on public.home_hero_settings;
create trigger trg_home_hero_settings_updated_at
    before update on public.home_hero_settings
    for each row execute function set_updated_at();

drop policy if exists "Managers can manage home hero settings" on public.home_hero_settings;
create policy "Managers can manage home hero settings" on public.home_hero_settings
    as permissive for all to authenticated
    using (is_manager_or_admin()) with check (is_manager_or_admin());

drop policy if exists "Public can read home hero settings" on public.home_hero_settings;
create policy "Public can read home hero settings" on public.home_hero_settings
    as permissive for select to anon, authenticated
    using (true);

insert into public.home_hero_settings (id) values (true) on conflict (id) do nothing;

comment on table public.home_hero_settings is
    'Singleton config for the customer app home hero carousel.';
comment on column public.home_hero_settings.rotation_seconds is
    'How long each slide dwells before the carousel advances itself. The app falls back to 5 when this cannot be read.';
