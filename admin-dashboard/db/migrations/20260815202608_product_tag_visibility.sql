-- Where a product tag is allowed to appear. A tag did two jobs at once: a badge
-- on the product card, and a chip in the cocktail finder's filter list, and
-- every tag did both. Each tag now carries the two placements separately, so a
-- tag can filter without crowding the card, or badge a card without becoming a
-- filter. The product detail page shows every tag either way.
-- Existing tags keep doing both, which is the behaviour before these columns
-- existed.
alter table public.product_tags
  add column if not exists show_in_filters boolean not null default true,
  add column if not exists show_on_product_card boolean not null default true;

comment on column public.product_tags.show_in_filters is
  'Whether the cocktail finder offers this tag as a filter chip. Off keeps it out of the filter list only — products still carry the tag, and it still shows on the product page.';

comment on column public.product_tags.show_on_product_card is
  'Whether this tag is badged on product and cocktail cards. Off hides the badge; the product detail page shows the tag regardless.';
