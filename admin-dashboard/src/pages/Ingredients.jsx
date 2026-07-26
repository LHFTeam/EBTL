import { useMemo, useState } from 'react';
import { api } from '../api/client.js';
import { baseUnits } from '../config/constants.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { splitTags, toBool, yesNo } from '../utils/format.js';

const blank = {
  name: '',
  name_ar: '',
  category: '',
  icon_key: '',
  base_unit: 'ml',
  purchase_unit_name: '',
  purchase_unit_size: '',
  purchase_unit_cost: '',
  cost_per_base_unit: '',
  is_perishable: false,
  shelf_life_days: '',
  allergen_flags: '',
  is_customer_supplied: false,
  is_active: true
};

const ingredientIconSuggestions = [
  'agave',
  'basil',
  'berry',
  'bitters',
  'cherry',
  'citrus',
  'cola',
  'cranberry',
  'cream',
  'cucumber',
  'fruit',
  'garnish',
  'ginger',
  'grapefruit',
  'grenadine',
  'ice',
  'lemon',
  'lime',
  'mango',
  'mint',
  'mixer',
  'orange',
  'passionfruit',
  'peach',
  'pineapple',
  'salt',
  'soda',
  'sugar',
  'syrup',
  'tonic',
  'watermelon'
];

function optionalText(value) {
  const text = String(value ?? '').trim();
  return text ? text : null;
}

function optionalIconKey(value) {
  const text = String(value ?? '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_');

  return text ? text : null;
}
function optionalNumber(value) {
  if (value === '' || value === null || value === undefined) return null;
  return Number(value);
}

function optionalInteger(value) {
  if (value === '' || value === null || value === undefined) return null;
  return Number.parseInt(value, 10);
}

function displayNumber(value, maximumFractionDigits = 6) {
  if (value === '' || value === null || value === undefined) return '-';
  return Number(value).toLocaleString(undefined, { maximumFractionDigits });
}

function calculatedCostPreview(form) {
  const purchaseUnitCost = optionalNumber(form.purchase_unit_cost);
  const purchaseUnitSize = optionalNumber(form.purchase_unit_size);

  if (purchaseUnitCost === null || purchaseUnitSize === null || purchaseUnitSize <= 0) return null;
  return purchaseUnitCost / purchaseUnitSize;
}

export default function Ingredients() {
  const { data, loading, error, reload } = useLoad(() => api('/api/ingredients'));
  const [form, setForm] = useState(blank);
  const [editing, setEditing] = useState(null);
  const [original, setOriginal] = useState(null);
  const [costManuallyEdited, setCostManuallyEdited] = useState(false);
  const [search, setSearch] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');

  const categories = useMemo(() => {
    return [...new Set((data || []).map(row => row.category).filter(Boolean))].sort((a, b) => a.localeCompare(b));
  }, [data]);

  const rows = useMemo(() => {
    const searchText = search.trim().toLowerCase();
    return (data || []).filter(row => {
      const matchesSearch = !searchText || [row.name, row.category, row.icon_key, row.base_unit]
        .some(value => String(value || '').toLowerCase().includes(searchText));
      const matchesCategory = !categoryFilter || row.category === categoryFilter;
      return matchesSearch && matchesCategory;
    });
  }, [data, search, categoryFilter]);

  const baseUnitChanged = editing && original && original.base_unit !== form.base_unit;
  const costPreview = calculatedCostPreview(form);

  function resetForm() {
    setForm(blank);
    setEditing(null);
    setOriginal(null);
    setCostManuallyEdited(false);
  }

  function buildPayload() {
    const payload = {
      name: form.name.trim(),
      name_ar: optionalText(form.name_ar),
      category: optionalText(form.category),
      icon_key: optionalIconKey(form.icon_key),
      base_unit: form.base_unit,
      purchase_unit_name: optionalText(form.purchase_unit_name),
      purchase_unit_size: optionalNumber(form.purchase_unit_size),
      purchase_unit_cost: optionalNumber(form.purchase_unit_cost),
      is_perishable: toBool(form.is_perishable),
      shelf_life_days: optionalInteger(form.shelf_life_days),
      allergen_flags: splitTags(form.allergen_flags),
      is_customer_supplied: toBool(form.is_customer_supplied),
      is_active: toBool(form.is_active)
    };

    if (!editing || costManuallyEdited) {
      payload.cost_per_base_unit = optionalNumber(form.cost_per_base_unit);
    }

    if (baseUnitChanged) {
      payload.confirm_base_unit_change = true;
    }

    return payload;
  }

  async function save(e) {
    e.preventDefault();
    setMsg('');
    setErr('');

    if (baseUnitChanged) {
      const confirmed = confirm(
        `Change base unit from ${original.base_unit} to ${form.base_unit}?\n\n` +
        'This can affect recipe units, stock quantities, and costing reports. Only continue if you have reviewed the related recipes and inventory.'
      );
      if (!confirmed) return;
    }

    try {
      const payload = buildPayload();
      if (editing) {
        await api(`/api/ingredients/${editing}`, { method: 'PATCH', body: JSON.stringify(payload) });
      } else {
        await api('/api/ingredients', { method: 'POST', body: JSON.stringify(payload) });
      }
      resetForm();
      setMsg('Ingredient saved.');
      reload();
    } catch (e) {
      setErr(e.message);
    }
  }

  function edit(row) {
    setEditing(row.id);
    setOriginal(row);
    setCostManuallyEdited(false);
    setMsg('');
    setErr('');
    setForm({
      ...blank,
      ...row,
      name_ar: row.name_ar || '',
      category: row.category || '',
      icon_key: row.icon_key || '',
      purchase_unit_name: row.purchase_unit_name || '',    
      purchase_unit_size: row.purchase_unit_size ?? '',
      purchase_unit_cost: row.purchase_unit_cost ?? '',
      cost_per_base_unit: row.cost_per_base_unit ?? '',
      shelf_life_days: row.shelf_life_days ?? '',
      allergen_flags: (row.allergen_flags || []).join(', ')
    });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  async function archiveIngredient(row) {
    setMsg('');
    setErr('');

    if (row.is_active) {
      const confirmed = confirm(
        `Archive ${row.name}?\n\n` +
        'Archived ingredients stay in the database but should no longer be used for new operations.'
      );
      if (!confirmed) return;
    }

    try {
      await api(`/api/ingredients/${row.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ is_active: !row.is_active })
      });
      setMsg(row.is_active ? 'Ingredient archived.' : 'Ingredient restored.');
      reload();
    } catch (e) {
      setErr(e.message);
    }
  }

  if (loading || error) return <Loading error={error} onRetry={reload} />;

  return <div className="grid">
    <Section title={editing ? 'Edit Ingredient' : 'Add Ingredient'} action={editing && <button onClick={resetForm}>Cancel edit</button>}>
      <form className="miniForm formGrid" onSubmit={save}>
        <input required placeholder="Name" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })}/>
        <input placeholder="Name (Arabic)" dir="rtl" lang="ar" value={form.name_ar || ''} onChange={e => setForm({ ...form, name_ar: e.target.value })}/>
        <input placeholder="Category" value={form.category || ''} onChange={e => setForm({ ...form, category: e.target.value })}/>
        <input
          list="ingredient-icon-key-options"
          placeholder="Icon key e.g. lime, syrup, salt"
          value={form.icon_key || ''}
          onChange={e => setForm({ ...form, icon_key: e.target.value })}
          title="Use lowercase keys. The customer app maps these keys to local SVG icons."
        />
        <datalist id="ingredient-icon-key-options">
          {ingredientIconSuggestions.map(iconKey => <option key={iconKey} value={iconKey} />)}
        </datalist>
        <select value={form.base_unit} onChange={e => setForm({ ...form, base_unit: e.target.value })}>
          {baseUnits.map(unit => <option key={unit}>{unit}</option>)}
        </select>
        <input placeholder="Purchase unit name e.g. 1L bottle" value={form.purchase_unit_name || ''} onChange={e => setForm({ ...form, purchase_unit_name: e.target.value })}/>
        <input type="number" step="0.001" placeholder="Purchase unit size" value={form.purchase_unit_size ?? ''} onChange={e => setForm({ ...form, purchase_unit_size: e.target.value })}/>
        <input type="number" step="0.01" placeholder="Purchase unit cost" value={form.purchase_unit_cost ?? ''} onChange={e => setForm({ ...form, purchase_unit_cost: e.target.value })}/>
        <input
          type="number"
          step="0.000001"
          placeholder="Cost per base unit"
          value={form.cost_per_base_unit ?? ''}
          onChange={e => {
            setCostManuallyEdited(true);
            setForm({ ...form, cost_per_base_unit: e.target.value });
          }}
        />
        <input type="number" placeholder="Shelf life days" value={form.shelf_life_days ?? ''} onChange={e => setForm({ ...form, shelf_life_days: e.target.value })}/>
        <input placeholder="Allergens, comma separated" value={form.allergen_flags || ''} onChange={e => setForm({ ...form, allergen_flags: e.target.value })}/>
        <label><input type="checkbox" checked={toBool(form.is_perishable)} onChange={e => setForm({ ...form, is_perishable: e.target.checked })}/> Perishable</label>
        <label><input type="checkbox" checked={toBool(form.is_customer_supplied)} onChange={e => setForm({ ...form, is_customer_supplied: e.target.checked })}/> Customer supplied</label>
        <label><input type="checkbox" checked={toBool(form.is_active)} onChange={e => setForm({ ...form, is_active: e.target.checked })}/> Active</label>

        {baseUnitChanged && <div className="warning full">
          You changed the base unit from <b>{original.base_unit}</b> to <b>{form.base_unit}</b>. This can affect recipes, inventory quantities, and costing reports.
        </div>}

        <p className="muted full costHint">
          Auto cost preview: {costPreview === null ? 'enter purchase cost and size' : `${displayNumber(costPreview)} per ${form.base_unit}`}. On edit, this is recalculated automatically when purchase cost or purchase size changes unless you manually type a cost per base unit.
        </p>

        <button className="primary">{editing ? 'Save Changes' : 'Add Ingredient'}</button>
      </form>
      <Message text={msg}/>
      <Message text={err} type="error"/>
    </Section>

    <Section title="Ingredients">
      <div className="filtersBar">
        <input type="search" placeholder="Search by name, category, or unit" value={search} onChange={e => setSearch(e.target.value)}/>
        <select value={categoryFilter} onChange={e => setCategoryFilter(e.target.value)}>
          <option value="">All categories</option>
          {categories.map(category => <option key={category} value={category}>{category}</option>)}
        </select>
        {(search || categoryFilter) && <button onClick={() => { setSearch(''); setCategoryFilter(''); }}>Clear filters</button>}
      </div>
      <SimpleTable
        rows={rows}
        emptyText={(search || categoryFilter) ? 'No ingredients match the current filters.' : 'No records yet.'}
        columns={['name', 'category', 'icon_key', 'base_unit', 'purchase_unit_cost', 'purchase_unit_size', 'cost_per_base_unit', 'is_perishable', 'is_customer_supplied', 'is_active']}
        format={{
          purchase_unit_cost: value => displayNumber(value, 2),
          purchase_unit_size: value => displayNumber(value, 3),
          cost_per_base_unit: value => displayNumber(value, 6),
          is_perishable: yesNo,
          is_customer_supplied: yesNo,
          is_active: yesNo
        }}
        actions={(row) => <div className="inlineActions">
          <button onClick={() => edit(row)}>Edit</button>
          <button onClick={() => archiveIngredient(row)}>{row.is_active ? 'Archive' : 'Restore'}</button>
        </div>}
      />
    </Section>
  </div>;
}
