import { useEffect, useMemo, useState } from 'react';
import { api } from '../api/client.js';
import { statuses } from '../config/constants.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { money, slugify, splitTags, toBool } from '../utils/format.js';

const blankProduct = {
  name: '',
  slug: '',
  category_id: '',
  description: '',
  image_url: '',
  status: 'active',
  is_featured: false,
  prep_time_minutes: 5,
  tags: '',
  variant_name: 'Standard',
  serving_count: 1,
  price_ex_vat: '',
  vat_rate: 0.14,
  yield_servings: 1,
  liquor_type_ids: [],
  recipe_items: [{ ingredient_id: '', quantity: '', unit: '' }]
};

const blankVariant = { name: '', serving_count: 1, price_ex_vat: '', vat_rate: 0.14, is_active: true };
const blankRecipe = { status: 'draft', yield_servings: 1, notes: '' };
const blankRecipeItem = { ingredient_id: '', quantity: '', unit: '', is_optional: false, is_customer_supplied: false };

function nullableText(value) {
  const text = String(value ?? '').trim();
  return text ? value : null;
}

function nullableUuid(value) {
  return value || null;
}

function numericInput(value) {
  return value ?? '';
}

function priceIncVatPreview(priceExVat, vatRate) {
  return Number((Number(priceExVat || 0) * (1 + Number(vatRate || 0))).toFixed(2));
}

export default function Cocktails() {
  const { data, loading, error, reload } = useLoad(() => api('/api/cocktails'));
  const [form, setForm] = useState(blankProduct);
  const [editing, setEditing] = useState(null);
  const [productEdit, setProductEdit] = useState({});
  const [variantEdits, setVariantEdits] = useState({});
  const [newVariant, setNewVariant] = useState(blankVariant);
  const [recipeEdit, setRecipeEdit] = useState(blankRecipe);
  const [recipeItemEdits, setRecipeItemEdits] = useState({});
  const [newRecipeItem, setNewRecipeItem] = useState(blankRecipeItem);
  const [recipeReplaceRows, setRecipeReplaceRows] = useState([blankRecipeItem]);
  const [compatEdit, setCompatEdit] = useState([]);  
  const [msg, setMsg] = useState('');
  const [msgType, setMsgType] = useState('ok');

  const categories = data?.categories || [];
  const products = data?.products || [];
  const variants = data?.variants || [];
  const recipes = data?.recipes || [];
  const recipeItems = data?.recipeItems || [];
  const liquorTypes = data?.liquorTypes || [];
  const ingredients = data?.ingredients || [];
  const compatibility = data?.compatibility || [];
  const firstCategory = categories[0]?.id || '';
  const selectedProduct = products.find((product) => product.id === editing) || null;

  const variantRows = useMemo(
    () => variants.map((variant) => ({ ...variant, product: products.find((product) => product.id === variant.product_id)?.name || '-' })),
    [variants, products]
  );

  const currentVariants = useMemo(
    () => variants.filter((variant) => variant.product_id === editing).sort((a, b) => String(a.name).localeCompare(String(b.name))),
    [variants, editing]
  );

  const currentRecipe = useMemo(() => {
    const productRecipes = recipes.filter((recipe) => recipe.product_id === editing);
    return productRecipes.sort((a, b) => Number(b.version || 0) - Number(a.version || 0) || String(b.created_at || '').localeCompare(String(a.created_at || '')))[0] || null;
  }, [recipes, editing]);

  const currentRecipeItems = useMemo(
    () => recipeItems.filter((item) => item.recipe_id === currentRecipe?.id),
    [recipeItems, currentRecipe]
  );

  const recipeRows = useMemo(() => products.map((product) => {
    const latestRecipe = recipes
      .filter((recipe) => recipe.product_id === product.id)
      .sort((a, b) => Number(b.version || 0) - Number(a.version || 0) || String(b.created_at || '').localeCompare(String(a.created_at || '')))[0] || null;
  
    return {
      id: product.id,
      cocktail: product.name,
      recipe_status: latestRecipe?.status || 'none',
      recipe_version: latestRecipe?.version || '-',
      yield_servings: latestRecipe?.yield_servings || '-',
      item_count: latestRecipe ? recipeItems.filter((item) => item.recipe_id === latestRecipe.id).length : 0
    };
  }), [products, recipes, recipeItems]);

  useEffect(() => {
    if (categories.length && !form.category_id) setForm((current) => ({ ...current, category_id: categories[0].id }));
  }, [categories, form.category_id]);

  useEffect(() => {
    if (!selectedProduct) return;

    const productVariants = variants.filter((variant) => variant.product_id === selectedProduct.id);
    const latestRecipe = recipes
      .filter((recipe) => recipe.product_id === selectedProduct.id)
      .sort((a, b) => Number(b.version || 0) - Number(a.version || 0) || String(b.created_at || '').localeCompare(String(a.created_at || '')))[0] || null;
    const latestRecipeItems = latestRecipe ? recipeItems.filter((item) => item.recipe_id === latestRecipe.id) : [];

    setProductEdit({
      name: selectedProduct.name || '',
      slug: selectedProduct.slug || '',
      category_id: selectedProduct.category_id || '',
      description: selectedProduct.description || '',
      image_url: selectedProduct.image_url || '',
      status: selectedProduct.status || 'draft',
      is_featured: !!selectedProduct.is_featured,
      prep_time_minutes: selectedProduct.prep_time_minutes ?? 5,
      tags: (selectedProduct.tags || []).join(', ')
    });

    setVariantEdits(Object.fromEntries(productVariants.map((variant) => [variant.id, {
      name: variant.name || '',
      serving_count: variant.serving_count ?? 1,
      price_ex_vat: variant.price_ex_vat ?? '',
      vat_rate: variant.vat_rate ?? 0.14,
      is_active: !!variant.is_active
    }])));

    setNewVariant(blankVariant);
    setRecipeEdit(latestRecipe ? {
      status: latestRecipe.status || selectedProduct.status || 'draft',
      yield_servings: latestRecipe.yield_servings ?? 1,
      notes: latestRecipe.notes || ''
    } : { ...blankRecipe, status: selectedProduct.status || 'draft' });


    setRecipeItemEdits(Object.fromEntries(latestRecipeItems.map((item) => [item.id, {
      ingredient_id: item.ingredient_id || '',
      quantity: item.quantity ?? '',
      unit: item.unit || item.ingredients?.base_unit || '',
      is_optional: !!item.is_optional,
      is_customer_supplied: !!item.is_customer_supplied
    }])));
    
    setRecipeReplaceRows(latestRecipeItems.length
      ? latestRecipeItems.map((item) => ({
          ingredient_id: item.ingredient_id || '',
          quantity: item.quantity ?? '',
          unit: item.unit || item.ingredients?.base_unit || '',
          is_optional: !!item.is_optional,
          is_customer_supplied: !!item.is_customer_supplied
        }))
      : [{ ...blankRecipeItem }]);
    
    setNewRecipeItem(blankRecipeItem);
    
    setCompatEdit(compatibility.filter((row) => row.product_id === selectedProduct.id).map((row) => row.liquor_type_id));
  }, [selectedProduct, variants, recipes, recipeItems, compatibility]);

  function ingredientUnit(ingredientId) {
    return ingredients.find((ingredient) => ingredient.id === ingredientId)?.base_unit || '';
  }

  function setCreateRecipeLine(index, patch) {
    setForm((current) => ({
      ...current,
      recipe_items: current.recipe_items.map((item, itemIndex) => (itemIndex === index ? { ...item, ...patch } : item))
    }));
  }

  function setCreateRecipeIngredient(index, ingredientId) {
    setCreateRecipeLine(index, { ingredient_id: ingredientId, unit: ingredientUnit(ingredientId) });
  }

  function recipeItemsPayload(items) {
    return items
      .filter((item) => item.ingredient_id && item.quantity !== '')
      .map((item) => ({
        ingredient_id: item.ingredient_id,
        quantity: item.quantity,
        unit: ingredientUnit(item.ingredient_id) || item.unit,
        is_optional: toBool(item.is_optional),
        is_customer_supplied: toBool(item.is_customer_supplied)
      }));
  }
  
  function setRecipeReplaceLine(index, patch) {
    setRecipeReplaceRows((current) => current.map((item, itemIndex) => (itemIndex === index ? { ...item, ...patch } : item)));
  }
  
  function setRecipeReplaceIngredient(index, ingredientId) {
    setRecipeReplaceLine(index, { ingredient_id: ingredientId, unit: ingredientUnit(ingredientId) });
  }
  
  function addRecipeReplaceLine() {
    setRecipeReplaceRows((current) => [...current, { ...blankRecipeItem }]);
  }
  
  function removeRecipeReplaceLine(index) {
    setRecipeReplaceRows((current) => current.length === 1 ? [{ ...blankRecipeItem }] : current.filter((_, itemIndex) => itemIndex !== index));
  }

  function removeCreateRecipeLine(index) {
    setForm((current) => ({
      ...current,
      recipe_items: current.recipe_items.length === 1
        ? [{ ingredient_id: '', quantity: '', unit: '' }]
        : current.recipe_items.filter((_, itemIndex) => itemIndex !== index)
    }));
  }
  
  function toggleCreateLiquor(id) {
    setForm((current) => ({
      ...current,
      liquor_type_ids: current.liquor_type_ids.includes(id)
        ? current.liquor_type_ids.filter((liquorId) => liquorId !== id)
        : [...current.liquor_type_ids, id]
    }));
  }

  function toggleEditLiquor(id) {
    setCompatEdit((current) => current.includes(id) ? current.filter((liquorId) => liquorId !== id) : [...current, id]);
  }

  function showMessage(text, type = 'ok') {
    setMsg(text);
    setMsgType(type);
  }

  async function runAction(action, successText) {
    setMsg('');
    try {
      await action();
      showMessage(successText);
      await reload();
    } catch (err) {
      showMessage(err.message || 'Request failed', 'error');
    }
  }

  async function add(e) {
    e.preventDefault();
    const payload = {
      ...form,
      category_id: nullableUuid(form.category_id),
      description: nullableText(form.description),
      image_url: nullableText(form.image_url),
      tags: splitTags(form.tags),
      is_featured: toBool(form.is_featured),
      liquor_type_ids: form.liquor_type_ids,
      recipe_items: recipeItemsPayload(form.recipe_items)
    };

    await runAction(async () => {
      await api('/api/cocktails', { method: 'POST', body: JSON.stringify(payload) });
      setForm({ ...blankProduct, category_id: firstCategory });
    }, 'Cocktail saved.');
  }

  function startEdit(row) {
    setEditing(row.id);
    showMessage(`Editing ${row.name}.`);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  async function saveProduct(e) {
    e.preventDefault();
    await runAction(async () => {
      await api(`/api/cocktails/${editing}`, {
        method: 'PATCH',
        body: JSON.stringify({
          name: productEdit.name,
          slug: productEdit.slug,
          category_id: nullableUuid(productEdit.category_id),
          description: nullableText(productEdit.description),
          image_url: nullableText(productEdit.image_url),
          status: productEdit.status,
          is_featured: toBool(productEdit.is_featured),
          prep_time_minutes: productEdit.prep_time_minutes,
          tags: splitTags(productEdit.tags)
        })
      });
    }, 'Cocktail details updated.');
  }

  async function archiveProduct() {
    const name = selectedProduct?.name || 'this cocktail';
    if (!window.confirm(`Archive ${name}? This will hide it from the app and deactivate its variants.`)) return;
    await runAction(async () => {
      await api(`/api/cocktails/${editing}`, { method: 'DELETE' });
      setEditing(null);
    }, 'Cocktail archived.');
  }

  async function saveVariant(variantId) {
    const variant = variantEdits[variantId];
    await runAction(async () => {
      await api(`/api/product-variants/${variantId}`, { method: 'PATCH', body: JSON.stringify(variant) });
    }, 'Variant updated.');
  }
  
  async function setVariantActive(variantId, isActive) {
    const variant = variants.find((row) => row.id === variantId);
    if (!isActive && !window.confirm(`Deactivate variant "${variant?.name || 'this variant'}"? It will no longer be available for new orders.`)) return;
  
    await runAction(async () => {
      if (isActive) {
        await api(`/api/product-variants/${variantId}`, { method: 'PATCH', body: JSON.stringify({ is_active: true }) });
      } else {
        await api(`/api/product-variants/${variantId}`, { method: 'DELETE' });
      }
    }, isActive ? 'Variant activated.' : 'Variant deactivated.');
  }
  
  async function addVariant(e) {
    e.preventDefault();
    await runAction(async () => {
      await api(`/api/cocktails/${editing}/variants`, { method: 'POST', body: JSON.stringify(newVariant) });
      setNewVariant(blankVariant);
    }, 'Variant added.');
  }

  async function saveLiquors() {
    await runAction(async () => {
      await api(`/api/cocktails/${editing}/liquors`, { method: 'POST', body: JSON.stringify({ liquor_type_ids: compatEdit }) });
    }, 'Compatible liquor bottles updated.');
  }

  async function createRecipe(e) {
    e.preventDefault();
    await runAction(async () => {
      await api('/api/recipes', {
        method: 'POST',
        body: JSON.stringify({
          product_id: editing,
          status: recipeEdit.status,
          yield_servings: recipeEdit.yield_servings,
          notes: nullableText(recipeEdit.notes)
        })
      });
    }, 'Recipe created. You can add recipe items now.');
  }

  async function saveRecipe(e) {
    e.preventDefault();
    await runAction(async () => {
      await api(`/api/recipes/${currentRecipe.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          status: recipeEdit.status,
          yield_servings: recipeEdit.yield_servings,
          notes: nullableText(recipeEdit.notes)
        })
      });
    }, 'Recipe updated.');
  }

  async function replaceRecipeItems(e) {
    e.preventDefault();
    await runAction(async () => {
      await api(`/api/cocktails/${editing}/recipe-items`, {
        method: 'PUT',
        body: JSON.stringify({
          recipe_id: currentRecipe?.id,
          recipe: {
            status: recipeEdit.status,
            yield_servings: recipeEdit.yield_servings,
            notes: nullableText(recipeEdit.notes)
          },
          items: recipeItemsPayload(recipeReplaceRows)
        })
      });
    }, 'Full recipe items replaced.');
  }

  function setRecipeItemIngredient(itemId, ingredientId) {
    setRecipeItemEdits((current) => ({
      ...current,
      [itemId]: { ...current[itemId], ingredient_id: ingredientId, unit: ingredientUnit(ingredientId) }
    }));
  }

  async function saveRecipeItem(itemId) {
    await runAction(async () => {
      await api(`/api/recipe-items/${itemId}`, { method: 'PATCH', body: JSON.stringify(recipeItemEdits[itemId]) });
    }, 'Recipe item updated.');
  }

  async function removeRecipeItem(itemId) {
    if (!window.confirm('Remove this recipe line?')) return;
    await runAction(async () => {
      await api(`/api/recipe-items/${itemId}`, { method: 'DELETE' });
    }, 'Recipe item removed.');
  }

  async function addRecipeItem(e) {
    e.preventDefault();
    await runAction(async () => {
      await api(`/api/recipes/${currentRecipe.id}/items`, { method: 'POST', body: JSON.stringify(newRecipeItem) });
      setNewRecipeItem(blankRecipeItem);
    }, 'Recipe item added.');
  }

  if (loading || error) return <Loading error={error} />;

  return <div className="grid">
    <Section title="Add New Cocktail">
      <form className="miniForm formGrid" onSubmit={add}>
        <input required placeholder="Cocktail name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value, slug: slugify(e.target.value) })} />
        <input required placeholder="Slug" value={form.slug} onChange={(e) => setForm({ ...form, slug: e.target.value })} />
        <select value={form.category_id || ''} onChange={(e) => setForm({ ...form, category_id: e.target.value })}>
          <option value="">No category</option>
          {categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}
        </select>
        <select value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value })}>{statuses.map((status) => <option key={status}>{status}</option>)}</select>
        <input placeholder="Description" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
        <input placeholder="Image URL" value={form.image_url} onChange={(e) => setForm({ ...form, image_url: e.target.value })} />
        <input type="number" min="0" placeholder="Prep time minutes" value={form.prep_time_minutes} onChange={(e) => setForm({ ...form, prep_time_minutes: e.target.value })} />
        <input placeholder="Tags, comma separated" value={form.tags} onChange={(e) => setForm({ ...form, tags: e.target.value })} />
        <input required placeholder="Variant name" value={form.variant_name} onChange={(e) => setForm({ ...form, variant_name: e.target.value })} />
        <input required type="number" min="1" placeholder="Serving count" value={form.serving_count} onChange={(e) => setForm({ ...form, serving_count: e.target.value })} />
        <input required type="number" min="0" step="0.01" placeholder="Price ex VAT" value={form.price_ex_vat} onChange={(e) => setForm({ ...form, price_ex_vat: e.target.value })} />
        <input type="number" min="0" max="1" step="0.0001" placeholder="VAT rate" value={form.vat_rate} onChange={(e) => setForm({ ...form, vat_rate: e.target.value })} />
        <input required type="number" min="1" placeholder="Recipe yield servings" value={form.yield_servings} onChange={(e) => setForm({ ...form, yield_servings: e.target.value })} />
        <label><input type="checkbox" checked={toBool(form.is_featured)} onChange={(e) => setForm({ ...form, is_featured: e.target.checked })} /> Featured</label>

        <div className="full subPanel">
          <b>Compatible liquor bottles</b>
          <div className="checks">
            {liquorTypes.map((liquor) => <label key={liquor.id}><input type="checkbox" checked={form.liquor_type_ids.includes(liquor.id)} onChange={() => toggleCreateLiquor(liquor.id)} /> {liquor.name}</label>)}
          </div>
        </div>

        <div className="full subPanel">
          <b>Recipe Items</b>
          <p className="muted smallText noPad">Units are locked to each ingredient's base unit because inventory consumption depends on this match.</p>
          {form.recipe_items.map((item, index) => <div className="inlineRow recipeLine" key={index}>
            <select value={item.ingredient_id} onChange={(e) => setCreateRecipeIngredient(index, e.target.value)}>
              <option value="">Ingredient</option>
              {ingredients.map((ingredient) => <option key={ingredient.id} value={ingredient.id}>{ingredient.name}{ingredient.is_active ? '' : ' (inactive)'}</option>)}
            </select>
            <input type="number" min="0" step="0.001" placeholder="Qty" value={item.quantity} onChange={(e) => setCreateRecipeLine(index, { quantity: e.target.value })} />
            <input disabled placeholder="Unit" value={item.unit || ingredientUnit(item.ingredient_id)} />
            <button type="button" onClick={() => removeCreateRecipeLine(index)}>Remove</button>
          </div>)}
          <button type="button" onClick={() => setForm({ ...form, recipe_items: [...form.recipe_items, { ingredient_id: '', quantity: '', unit: '' }] })}>Add recipe line</button>
        </div>

        <button className="primary">Save Cocktail</button>
      </form>
    </Section>

    <Message text={msg} type={msgType} />

    {selectedProduct && <Section title={`Edit Cocktail: ${selectedProduct.name}`} action={<div className="inlineActions"><button onClick={() => setEditing(null)}>Close editor</button><button className="danger" onClick={archiveProduct}>Archive cocktail</button></div>}>
      <form className="miniForm formGrid" onSubmit={saveProduct}>
        <input required value={productEdit.name || ''} onChange={(e) => setProductEdit({ ...productEdit, name: e.target.value, slug: slugify(e.target.value) })} />
        <input required value={productEdit.slug || ''} onChange={(e) => setProductEdit({ ...productEdit, slug: e.target.value })} />
        <select value={productEdit.category_id || ''} onChange={(e) => setProductEdit({ ...productEdit, category_id: e.target.value })}>
          <option value="">No category</option>
          {categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}
        </select>
        <select value={productEdit.status || 'draft'} onChange={(e) => setProductEdit({ ...productEdit, status: e.target.value })}>{statuses.map((status) => <option key={status}>{status}</option>)}</select>
        <input placeholder="Description" value={productEdit.description || ''} onChange={(e) => setProductEdit({ ...productEdit, description: e.target.value })} />
        <input placeholder="Image URL" value={productEdit.image_url || ''} onChange={(e) => setProductEdit({ ...productEdit, image_url: e.target.value })} />
        <input type="number" min="0" value={productEdit.prep_time_minutes ?? ''} onChange={(e) => setProductEdit({ ...productEdit, prep_time_minutes: e.target.value })} />
        <input placeholder="Tags, comma separated" value={productEdit.tags || ''} onChange={(e) => setProductEdit({ ...productEdit, tags: e.target.value })} />
        <label><input type="checkbox" checked={toBool(productEdit.is_featured)} onChange={(e) => setProductEdit({ ...productEdit, is_featured: e.target.checked })} /> Featured</label>
        <button className="primary">Save product details</button>
      </form>

      <div className="editorStack">
        <div className="subPanel">
          <h3>Variants / Prices</h3>
          {currentVariants.length ? currentVariants.map((variant) => {
            const draft = variantEdits[variant.id] || {};
            return <div className="editLine variantLine" key={variant.id}>
              <input value={draft.name || ''} onChange={(e) => setVariantEdits({ ...variantEdits, [variant.id]: { ...draft, name: e.target.value } })} />
              <input type="number" min="1" value={numericInput(draft.serving_count)} onChange={(e) => setVariantEdits({ ...variantEdits, [variant.id]: { ...draft, serving_count: e.target.value } })} />
              <input type="number" min="0" step="0.01" value={numericInput(draft.price_ex_vat)} onChange={(e) => setVariantEdits({ ...variantEdits, [variant.id]: { ...draft, price_ex_vat: e.target.value } })} />
              <input type="number" min="0" max="1" step="0.0001" value={numericInput(draft.vat_rate)} onChange={(e) => setVariantEdits({ ...variantEdits, [variant.id]: { ...draft, vat_rate: e.target.value } })} />
              <span className="muted smallText">Inc VAT preview: {money(priceIncVatPreview(draft.price_ex_vat, draft.vat_rate))}</span>
              <label><input type="checkbox" checked={toBool(draft.is_active)} onChange={(e) => setVariantEdits({ ...variantEdits, [variant.id]: { ...draft, is_active: e.target.checked } })} /> Active</label>
              <div className="inlineActions">
                <button type="button" onClick={() => saveVariant(variant.id)}>Save</button>
                <button type="button" className={variant.is_active ? 'danger' : ''} onClick={() => setVariantActive(variant.id, !variant.is_active)}>{variant.is_active ? 'Deactivate' : 'Activate'}</button>
              </div>
            </div>;
          }) : <div className="empty">No variants yet. Add one below.</div>}

          <form className="editLine variantLine" onSubmit={addVariant}>
            <input required placeholder="New variant name" value={newVariant.name} onChange={(e) => setNewVariant({ ...newVariant, name: e.target.value })} />
            <input required type="number" min="1" placeholder="Serving count" value={newVariant.serving_count} onChange={(e) => setNewVariant({ ...newVariant, serving_count: e.target.value })} />
            <input required type="number" min="0" step="0.01" placeholder="Price ex VAT" value={newVariant.price_ex_vat} onChange={(e) => setNewVariant({ ...newVariant, price_ex_vat: e.target.value })} />
            <input type="number" min="0" max="1" step="0.0001" placeholder="VAT rate" value={newVariant.vat_rate} onChange={(e) => setNewVariant({ ...newVariant, vat_rate: e.target.value })} />
            <label><input type="checkbox" checked={toBool(newVariant.is_active)} onChange={(e) => setNewVariant({ ...newVariant, is_active: e.target.checked })} /> Active</label>
            <span className="muted smallText">Inc VAT preview: {money(priceIncVatPreview(newVariant.price_ex_vat, newVariant.vat_rate))}</span>
            <button className="primary">Add variant</button>
          </form>
        </div>

        <div className="subPanel">
          <h3>Compatible Liquor Bottles</h3>
          <div className="checks">
            {liquorTypes.map((liquor) => <label key={liquor.id}><input type="checkbox" checked={compatEdit.includes(liquor.id)} onChange={() => toggleEditLiquor(liquor.id)} /> {liquor.name}</label>)}
          </div>
          <button type="button" className="primary compactButton" onClick={saveLiquors}>Save compatible bottles</button>
        </div>

        <div className="subPanel">
          <h3>Recipe</h3>
          {!currentRecipe ? <>
            <div className="empty">This cocktail has no recipe yet. This is okay for drafts; create a recipe when you are ready to define inventory consumption.</div>
            <form className="miniForm formGrid" onSubmit={createRecipe}>
              <select value={recipeEdit.status || 'draft'} onChange={(e) => setRecipeEdit({ ...recipeEdit, status: e.target.value })}>{statuses.map((status) => <option key={status}>{status}</option>)}</select>
              <input required type="number" min="1" value={recipeEdit.yield_servings ?? 1} onChange={(e) => setRecipeEdit({ ...recipeEdit, yield_servings: e.target.value })} />
              <input placeholder="Recipe notes" value={recipeEdit.notes || ''} onChange={(e) => setRecipeEdit({ ...recipeEdit, notes: e.target.value })} />
              <button className="primary">Create recipe</button>
            </form>
          </> : <>
            <form className="miniForm formGrid" onSubmit={saveRecipe}>
              <select value={recipeEdit.status || 'draft'} onChange={(e) => setRecipeEdit({ ...recipeEdit, status: e.target.value })}>{statuses.map((status) => <option key={status}>{status}</option>)}</select>
              <input required type="number" min="1" value={recipeEdit.yield_servings ?? 1} onChange={(e) => setRecipeEdit({ ...recipeEdit, yield_servings: e.target.value })} />
              <input placeholder="Recipe notes" value={recipeEdit.notes || ''} onChange={(e) => setRecipeEdit({ ...recipeEdit, notes: e.target.value })} />
              <button className="primary">Save recipe yield/status</button>
            </form>

            <h3>Recipe Items</h3>
            <p className="muted smallText noPad">This editor replaces the full recipe item set for the cocktail. Remove a line here, then save, to delete it from the recipe.</p>
            
            <form onSubmit={replaceRecipeItems}>
              {recipeReplaceRows.map((item, index) => <div className="editLine recipeItemLine" key={index}>
                <select value={item.ingredient_id || ''} onChange={(e) => setRecipeReplaceIngredient(index, e.target.value)}>
                  <option value="">Ingredient</option>
                  {ingredients.map((ingredient) => <option key={ingredient.id} value={ingredient.id}>{ingredient.name}{ingredient.is_active ? '' : ' (inactive)'}</option>)}
                </select>
                <input type="number" min="0" step="0.001" placeholder="Qty" value={numericInput(item.quantity)} onChange={(e) => setRecipeReplaceLine(index, { quantity: e.target.value })} />
                <input disabled placeholder="Unit" value={item.unit || ingredientUnit(item.ingredient_id)} />
                <label><input type="checkbox" checked={toBool(item.is_optional)} onChange={(e) => setRecipeReplaceLine(index, { is_optional: e.target.checked })} /> Optional</label>
                <label><input type="checkbox" checked={toBool(item.is_customer_supplied)} onChange={(e) => setRecipeReplaceLine(index, { is_customer_supplied: e.target.checked })} /> Customer supplied</label>
                <button type="button" className="danger" onClick={() => removeRecipeReplaceLine(index)}>Remove</button>
              </div>)}
            
              <div className="inlineActions">
                <button type="button" onClick={addRecipeReplaceLine}>Add recipe line</button>
                <button className="primary">Save full recipe items</button>
              </div>
            </form>
          </>}
        </div>
      </div>
    </Section>}

    <Section title="Cocktails">
      <SimpleTable
        rows={products}
        columns={['name', 'slug', 'status', 'is_featured', 'prep_time_minutes']}
        format={{ is_featured: (value) => value ? 'Yes' : 'No' }}
        actions={(row) => <button onClick={() => startEdit(row)}>Edit</button>}
      />
    </Section>

    <Section title="Recipes">
      <SimpleTable
        rows={recipeRows}
        columns={['cocktail', 'recipe_status', 'recipe_version', 'yield_servings', 'item_count']}
        actions={(row) => (
          <button type="button" onClick={() => startEdit({ id: row.id, name: row.cocktail })}>
            Edit recipe
          </button>
        )}
      />
    </Section>

    <Section title="Variants">
      <SimpleTable
        rows={variantRows}
        columns={['product', 'name', 'serving_count', 'price_ex_vat', 'price_inc_vat', 'vat_rate', 'is_active']}
        format={{
          price_ex_vat: (value) => money(value),
          price_inc_vat: (value) => money(value),
          vat_rate: (value) => `${Number(value || 0) * 100}%`,
          is_active: (value) => value ? 'Active' : 'Inactive'
        }}
        actions={(row) => (
          <button type="button" onClick={() => startEdit({ id: row.product_id, name: row.product })}>
            Edit in cocktail
          </button>
        )}
      />
    </Section>    
  </div>;
}
