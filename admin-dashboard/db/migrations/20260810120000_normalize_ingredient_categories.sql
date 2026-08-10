create table if not exists public.ingredient_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingredient_categories_name_not_blank check (btrim(name) <> '')
);

create unique index if not exists ingredient_categories_name_lower_key
  on public.ingredient_categories (lower(name));

alter table public.ingredient_categories enable row level security;

drop policy if exists "Staff can read ingredient categories"
  on public.ingredient_categories;
create policy "Staff can read ingredient categories"
  on public.ingredient_categories for select to authenticated
  using (is_staff());

drop policy if exists "Managers can manage ingredient categories"
  on public.ingredient_categories;
create policy "Managers can manage ingredient categories"
  on public.ingredient_categories for all to authenticated
  using (is_manager_or_admin()) with check (is_manager_or_admin());

drop trigger if exists trg_ingredient_categories_updated_at
  on public.ingredient_categories;
create trigger trg_ingredient_categories_updated_at
  before update on public.ingredient_categories
  for each row execute function set_updated_at();

alter table public.ingredients add column if not exists category_id uuid;

do $migration$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'ingredients'
      and column_name = 'category'
  ) then
    insert into public.ingredient_categories (name)
    select distinct case
      when lower(btrim(category)) = 'syrup' then 'Syrup'
      when lower(btrim(category)) in ('mixer', 'mixers') then 'Mixer'
      when lower(btrim(category)) in ('juice', 'juices') then 'Juice'
      when lower(btrim(category)) = 'essential' then 'Essential'
      when lower(btrim(category)) = 'snack' then 'Snack'
      else btrim(category)
    end
    from public.ingredients
    where nullif(btrim(category), '') is not null
    on conflict do nothing;

    update public.ingredients ingredient
    set category_id = category.id
    from public.ingredient_categories category
    where lower(category.name) = lower(case
      when lower(btrim(ingredient.category)) = 'syrup' then 'Syrup'
      when lower(btrim(ingredient.category)) in ('mixer', 'mixers') then 'Mixer'
      when lower(btrim(ingredient.category)) in ('juice', 'juices') then 'Juice'
      when lower(btrim(ingredient.category)) = 'essential' then 'Essential'
      when lower(btrim(ingredient.category)) = 'snack' then 'Snack'
      else btrim(ingredient.category)
    end);
  end if;
end;
$migration$;

do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ingredients'::regclass
      and conname = 'ingredients_category_id_fkey'
  ) then
    alter table public.ingredients
      add constraint ingredients_category_id_fkey
      foreign key (category_id) references public.ingredient_categories(id);
  end if;
end;
$migration$;

create index if not exists idx_ingredients_active_category_id
  on public.ingredients (is_active, category_id);

drop index if exists public.idx_ingredients_active_category;
alter table public.ingredients drop column if exists category;
