-- Whether an ingredient is offered by the customer app search bar. Ingredients
-- are part of the search scope, and some of them (water, ice, plain sugar) are
-- noise as search rows, so each ingredient carries its own visibility flag.
-- Existing ingredients keep showing up, which is the behaviour before this
-- column existed.
alter table public.ingredients
  add column if not exists is_searchable boolean not null default true;

comment on column public.ingredients.is_searchable is
  'Whether the customer app search bar may surface this ingredient: as its own result row, and as a term its products match on. Off hides it from search only — recipes, the cocktail ingredient list, and inventory are unaffected.';
