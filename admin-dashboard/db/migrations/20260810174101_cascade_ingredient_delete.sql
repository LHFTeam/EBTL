-- Deleting an ingredient takes its inventory state and operational history with
-- it, in one transaction, but never touches a product or cocktail recipe: a
-- recipe that calls for the ingredient stops the delete instead.
create or replace function public.delete_ingredient_cascade(p_ingredient_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name         text;
  v_product_name text;
  v_product_type text;
begin
  select name into v_name from ingredients where id = p_ingredient_id;
  if v_name is null then
    return jsonb_build_object('status', 'not_found');
  end if;

  -- The one hard stop. An ingredient sitting in any recipe version blocks the
  -- delete, including older versions the product no longer serves, because the
  -- foreign key does not distinguish between them either.
  select p.name, p.product_type
    into v_product_name, v_product_type
  from recipe_items ri
  join recipes r on r.id = ri.recipe_id
  join products p on p.id = r.product_id
  where ri.ingredient_id = p_ingredient_id
  order by p.name
  limit 1;

  if v_product_name is not null then
    return jsonb_build_object(
      'status',       'in_recipe',
      'product_name', v_product_name,
      'product_type', v_product_type
    );
  end if;

  -- Inventory state and operational history: all meaningless once the
  -- ingredient is gone. order_item_removed_ingredients is deliberately absent —
  -- its foreign key is ON DELETE SET NULL beside a name snapshot, so that row
  -- survives the delete and still reads correctly.
  delete from stock_movements                 where ingredient_id = p_ingredient_id;
  delete from inventory_balances              where ingredient_id = p_ingredient_id;
  delete from stock_transfer_items            where ingredient_id = p_ingredient_id;
  delete from purchase_order_items            where ingredient_id = p_ingredient_id;
  delete from order_item_inventory_components where ingredient_id = p_ingredient_id;
  delete from cart_item_removed_ingredients   where ingredient_id = p_ingredient_id;

  -- Every other reference keeps its NO ACTION foreign key, so a table this
  -- function does not know about raises here and rolls the whole delete back
  -- rather than leaving the ingredient half-removed.
  delete from ingredients where id = p_ingredient_id;

  return jsonb_build_object('status', 'deleted', 'id', p_ingredient_id, 'name', v_name);
end;
$$;

comment on function public.delete_ingredient_cascade(uuid) is
  'Permanently deletes an ingredient together with its inventory balances, stock movements, transfer lines, purchase order lines, order inventory components and cart removals. Returns status=in_recipe (naming the product) instead of deleting when a recipe still uses it.';

-- Destructive, so it is not reachable from a browser session: the admin server
-- calls it with the service role key.
revoke all on function public.delete_ingredient_cascade(uuid) from public;
revoke all on function public.delete_ingredient_cascade(uuid) from anon;
revoke all on function public.delete_ingredient_cascade(uuid) from authenticated;
grant execute on function public.delete_ingredient_cascade(uuid) to service_role;
