import { useMemo, useState } from 'react';
import { ArrowLeft } from 'lucide-react';
import { api } from '../api/client.js';
import { Loading, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';

function productTypeLabel(value) {
  return String(value || '')
    .split('_')
    .map((part) => part ? part[0].toUpperCase() + part.slice(1) : '')
    .join(' ');
}

function quantityLabel(row) {
  if (row.quantity === null || row.quantity === undefined) return '-';

  const amount = `${Number(row.quantity).toLocaleString(undefined, { maximumFractionDigits: 3 })} ${row.unit || ''}`.trim();
  const notes = [row.is_optional && 'optional', row.is_customer_supplied && 'customer supplied'].filter(Boolean);
  return notes.length ? `${amount} (${notes.join(', ')})` : amount;
}

function recipeLabel(row) {
  const recipe = `v${row.recipe_version} · ${row.recipe_status}`;
  return row.is_current_recipe ? recipe : `${recipe} (older version)`;
}

export default function IngredientProducts({ ingredientId, ingredientName, onBack }) {
  const { data, loading, error, reload } = useLoad(() => api(`/api/ingredients/${ingredientId}/products`), [ingredientId]);
  const [search, setSearch] = useState('');

  const products = data?.products || [];
  const name = data?.ingredient?.name || ingredientName;

  const rows = useMemo(() => {
    const searchText = search.trim().toLowerCase();
    if (!searchText) return products;
    return products.filter((product) => [product.name, product.short_description, product.product_type]
      .some((value) => String(value || '').toLowerCase().includes(searchText)));
  }, [products, search]);

  const backButton = <button type="button" onClick={onBack}><ArrowLeft size={14} /> Back to ingredients</button>;

  if (loading || error) {
    return <div className="grid">
      <Section title={`Products using ${name}`} action={backButton}>
        <Loading error={error} onRetry={reload} />
      </Section>
    </div>;
  }

  return <div className="grid">
    <Section title={`Products using ${name}`} action={backButton}>
      <p className="muted">
        {products.length
          ? `${products.length} ${products.length === 1 ? 'product uses' : 'products use'} this ingredient in a recipe. Edit them from the Cocktails or Additional Products tab.`
          : 'No product recipe uses this ingredient.'}
      </p>

      {products.length > 0 && <div className="filtersBar">
        <input type="search" placeholder="Search by name, description, or type" value={search} onChange={(e) => setSearch(e.target.value)} />
        {search && <button type="button" onClick={() => setSearch('')}>Clear search</button>}
      </div>}

      <SimpleTable
        rows={rows}
        emptyText={search ? 'No product matches the current search.' : 'No product recipe uses this ingredient.'}
        columns={['image_url', 'product_type', 'name', 'short_description', 'quantity', 'recipe_version', 'status']}
        format={{
          image_url: (value, row) => value ? <img className="tableImageThumb" src={value} alt={row.name} /> : '-',
          product_type: (value) => productTypeLabel(value),
          quantity: (_value, row) => quantityLabel(row),
          recipe_version: (_value, row) => recipeLabel(row)
        }}
      />
    </Section>
  </div>;
}
