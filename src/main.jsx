import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { BarChart3, Boxes, ClipboardList, MapPin, Martini, RefreshCw, ShoppingBag, Truck, Users, FlaskConical } from 'lucide-react';
import './styles.css';

const API = '';
const tabs = [
  { key: 'dashboard', label: 'Dashboard', icon: BarChart3 },
  { key: 'orders', label: 'Orders', icon: ClipboardList },
  { key: 'inventory', label: 'Inventory', icon: Boxes },
  { key: 'transfers', label: 'Transfers', icon: Truck },
  { key: 'ingredients', label: 'Ingredients', icon: FlaskConical },
  { key: 'cocktails', label: 'Cocktails', icon: Martini },
  { key: 'locations', label: 'Locations', icon: MapPin },
  { key: 'employees', label: 'Employees', icon: Users }
];
const roles = ['prep', 'cart_operator', 'warehouse', 'supervisor', 'manager', 'admin'];
const baseUnits = ['ml', 'g', 'piece', 'bottle', 'pack'];
const statuses = ['draft', 'active', 'archived'];

async function api(path, options = {}) {
  const res = await fetch(API + path, {
    credentials: 'include',
    headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
    ...options
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}
function money(v) { return `EGP ${Number(v || 0).toLocaleString(undefined, { maximumFractionDigits: 2 })}`; }
function dt(v) { return v ? new Date(v).toLocaleString() : '-'; }
function d(v) { return v ? new Date(v).toLocaleDateString() : '-'; }
function slugify(v) { return String(v || '').toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''); }
function toBool(v) { return v === true || v === 'true'; }
function splitTags(v) { return String(v || '').split(',').map(x => x.trim()).filter(Boolean); }

function Login({ onLogin }) {
  const [form, setForm] = useState({ username: 'admin', password: '' });
  const [error, setError] = useState('');
  async function submit(e) {
    e.preventDefault(); setError('');
    try { onLogin(await api('/api/login', { method: 'POST', body: JSON.stringify(form) })); }
    catch (err) { setError(err.message); }
  }
  return <div className="loginShell"><form className="loginCard" onSubmit={submit}>
    <div className="brandMark">EBTL</div><h1>Admin Dashboard</h1><p>Manage beach carts, warehouse inventory, orders, recipes, and operations.</p>
    <label>Username<input value={form.username} onChange={e => setForm({ ...form, username: e.target.value })} /></label>
    <label>Password<input type="password" value={form.password} onChange={e => setForm({ ...form, password: e.target.value })} /></label>
    {error && <div className="error">{error}</div>}<button className="primary">Sign in</button>
  </form></div>;
}

function PasswordChange({ onChanged, onLogout }) {
  const [form, setForm] = useState({ current_password: '', new_password: '', confirm_password: '' });
  const [error, setError] = useState('');
  async function submit(e) {
    e.preventDefault();
    setError('');
    if (form.new_password !== form.confirm_password) {
      setError('New password and confirmation do not match.');
      return;
    }
    try {
      const result = await api('/api/me/password', {
        method: 'POST',
        body: JSON.stringify({ current_password: form.current_password, new_password: form.new_password })
      });
      onChanged(result);
    } catch (err) {
      setError(err.message);
    }
  }
  return <div className="loginShell"><form className="loginCard" onSubmit={submit}>
    <div className="brandMark">EBTL</div><h1>Change Password</h1><p>Your dashboard account was marked for password reset. Create a new password before continuing.</p>
    <label>Current / temporary password<input required type="password" value={form.current_password} onChange={e => setForm({ ...form, current_password: e.target.value })} /></label>
    <label>New password<input required minLength={8} type="password" value={form.new_password} onChange={e => setForm({ ...form, new_password: e.target.value })} /></label>
    <label>Confirm new password<input required minLength={8} type="password" value={form.confirm_password} onChange={e => setForm({ ...form, confirm_password: e.target.value })} /></label>
    {error && <div className="error">{error}</div>}
    <button className="primary">Save New Password</button>
    <button type="button" onClick={onLogout}>Logout</button>
  </form></div>;
}

function Shell({ user, access, onLogout }) {
  const allowedTabs = tabs.filter(t => access.includes('*') || access.includes(t.key));
  const [active, setActive] = useState(allowedTabs[0]?.key || 'dashboard');
  const ActiveIcon = tabs.find(t => t.key === active)?.icon || BarChart3;
  return <div className="appShell"><aside>
    <div className="sideBrand"><span>EBTL</span><small>Operations</small></div>
    <nav>{allowedTabs.map(t => { const Icon = t.icon; return <button key={t.key} className={active === t.key ? 'active' : ''} onClick={() => setActive(t.key)}><Icon size={18} />{t.label}</button>; })}</nav>
    <div className="userBox"><b>{user.name}</b><span>{user.role}</span><button onClick={onLogout}>Logout</button></div>
  </aside><main>
    <header><div><h1><ActiveIcon size={24} /> {tabs.find(t => t.key === active)?.label}</h1><p>Central warehouse + compound beach carts</p></div></header>
    {active === 'dashboard' && <Dashboard />}{active === 'orders' && <Orders />}{active === 'inventory' && <Inventory />}{active === 'transfers' && <Transfers />}{active === 'ingredients' && <Ingredients />}{active === 'cocktails' && <Cocktails />}{active === 'locations' && <Locations />}{active === 'employees' && <Employees />}
  </main></div>;
}

function useLoad(loader, deps = []) {
  const [state, setState] = useState({ loading: true, error: '', data: null });
  const load = async () => { setState(s => ({ ...s, loading: true, error: '' })); try { setState({ loading: false, error: '', data: await loader() }); } catch (e) { setState({ loading: false, error: e.message, data: null }); } };
  useEffect(() => { load(); }, deps);
  return { ...state, reload: load };
}
function Section({ title, action, children }) { return <section className="card"><div className="sectionHead"><h2>{title}</h2>{action}</div>{children}</section>; }
function Loading({ error }) { return error ? <div className="error">{error}</div> : <div className="muted">Loading…</div>; }
function Message({ text, type = 'ok' }) { return text ? <div className={type === 'error' ? 'error' : 'success'}>{text}</div> : null; }
function Kpi({ label, value }) { return <div className="kpi"><span>{label}</span><b>{value}</b></div>; }
function SimpleTable({ rows = [], columns = [], format = {}, actions }) {
  if (!rows.length) return <div className="empty">No records yet.</div>;
  return <div className="tableWrap"><table><thead><tr>{columns.map(c => <th key={c}>{c.replaceAll('_', ' ')}</th>)}{actions && <th>Actions</th>}</tr></thead><tbody>{rows.map((r, i) => <tr key={r.id || i}>{columns.map(c => <td key={c}>{format[c] ? format[c](r[c], r) : String(r[c] ?? '-')}</td>)}{actions && <td>{actions(r)}</td>}</tr>)}</tbody></table></div>;
}

function Dashboard() {
  const { data, loading, error, reload } = useLoad(() => api('/api/dashboard'));
  if (loading || error) return <Loading error={error} />;
  return <div className="grid"><div className="kpis"><Kpi label="Recent Orders" value={data.kpis.recentOrders} /><Kpi label="Completed Orders" value={data.kpis.completedOrders} /><Kpi label="Recent Revenue" value={money(data.kpis.recentRevenue)} /><Kpi label="Low Stock Items" value={data.kpis.lowStockItems} /><Kpi label="Active Locations" value={data.kpis.activeLocations} /></div>
    <Section title="Recent Orders" action={<button onClick={reload}><RefreshCw size={16}/>Refresh</button>}><SimpleTable rows={data.recentOrders} columns={['order_number','status','payment_status','total_amount','created_at']} format={{ total_amount: money, created_at: dt }} /></Section>
    <Section title="Low Stock"><SimpleTable rows={data.lowStock} columns={['location_name','ingredient_name','quantity_on_hand','reorder_point','par_level']} /></Section></div>;
}

function Orders() {
  const { data, loading, error, reload } = useLoad(() => api('/api/orders'));
  const [saving, setSaving] = useState('');
  async function update(id, status) { setSaving(id); await api(`/api/orders/${id}`, { method: 'PATCH', body: JSON.stringify({ status }) }); setSaving(''); reload(); }
  if (loading || error) return <Loading error={error} />;
  return <Section title="Orders" action={<button onClick={reload}><RefreshCw size={16}/>Refresh</button>}><div className="cardsList">{data.orders.map(o => <div className="rowCard" key={o.id}><div><b>{o.order_number || 'Draft order'}</b><span>{o.customers?.full_name || o.customers?.phone || 'No customer'} · {o.locations?.name}</span><small>{dt(o.created_at)} · {money(o.total_amount)}</small></div><select value={o.status} disabled={saving === o.id} onChange={e => update(o.id, e.target.value)}>{['draft','pending_payment','confirmed','preparing','ready','out_for_delivery','completed','cancelled','refunded'].map(s => <option key={s}>{s}</option>)}</select></div>)}</div></Section>;
}

function Inventory() {
  const { data, loading, error, reload } = useLoad(() => api('/api/inventory'));
  const [form, setForm] = useState({ ingredient_id: '', location_id: '', quantity_delta: '', reason: '' });
  async function adjust(e) { e.preventDefault(); await api('/api/inventory/adjust', { method: 'POST', body: JSON.stringify(form) }); setForm({ ingredient_id: '', location_id: '', quantity_delta: '', reason: '' }); reload(); }
  if (loading || error) return <Loading error={error} />;
  return <div className="grid2"><Section title="Inventory Balances"><SimpleTable rows={data.balances.map(b => ({...b, ingredient: b.ingredients?.name, location: b.locations?.name}))} columns={['location','ingredient','quantity_on_hand','reserved_quantity','reorder_point','par_level']} /></Section>
    <Section title="Manual Stock Adjustment"><form className="miniForm" onSubmit={adjust}><select required value={form.location_id} onChange={e => setForm({...form, location_id:e.target.value})}><option value="">Location</option>{data.locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select><select required value={form.ingredient_id} onChange={e => setForm({...form, ingredient_id:e.target.value})}><option value="">Ingredient</option>{data.ingredients.map(i => <option key={i.id} value={i.id}>{i.name}</option>)}</select><input required type="number" step="0.001" placeholder="Qty delta e.g. 10 or -2" value={form.quantity_delta} onChange={e => setForm({...form, quantity_delta:e.target.value})}/><input placeholder="Reason" value={form.reason} onChange={e => setForm({...form, reason:e.target.value})}/><button className="primary">Post Movement</button></form></Section>
    <Section title="Recent Movements"><SimpleTable rows={data.movements.map(m => ({...m, ingredient: m.ingredients?.name, location: m.locations?.name}))} columns={['created_at','location','ingredient','movement_type','quantity_delta','reason']} format={{created_at: dt}} /></Section></div>;
}

function Transfers() {
  const { data, loading, error, reload } = useLoad(() => api('/api/transfers'));
  const [form, setForm] = useState({ from_location_id:'', to_location_id:'', notes:'' });
  const [item, setItem] = useState({ ingredient_id:'', requested_qty:'', dispatched_qty:'', received_qty:'' });
  async function create(e) { e.preventDefault(); await api('/api/transfers', { method:'POST', body: JSON.stringify({ ...form, items: item.ingredient_id ? [item] : [] }) }); setForm({ from_location_id:'', to_location_id:'', notes:'' }); setItem({ ingredient_id:'', requested_qty:'', dispatched_qty:'', received_qty:'' }); reload(); }
  async function status(id, status) { await api(`/api/transfers/${id}`, { method:'PATCH', body: JSON.stringify({ status }) }); reload(); }
  if (loading || error) return <Loading error={error} />;
  return <div className="grid2"><Section title="Create Transfer"><form className="miniForm" onSubmit={create}><select required value={form.from_location_id} onChange={e => setForm({...form, from_location_id:e.target.value})}><option value="">From</option>{data.locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select><select required value={form.to_location_id} onChange={e => setForm({...form, to_location_id:e.target.value})}><option value="">To</option>{data.locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select><select value={item.ingredient_id} onChange={e => setItem({...item, ingredient_id:e.target.value})}><option value="">Optional first item</option>{data.ingredients.map(i => <option key={i.id} value={i.id}>{i.name}</option>)}</select><input type="number" step="0.001" placeholder="Requested qty" value={item.requested_qty} onChange={e => setItem({...item, requested_qty:e.target.value})}/><input type="number" step="0.001" placeholder="Dispatched qty" value={item.dispatched_qty} onChange={e => setItem({...item, dispatched_qty:e.target.value})}/><input placeholder="Notes" value={form.notes} onChange={e => setForm({...form, notes:e.target.value})}/><button className="primary">Create Transfer</button></form></Section>
    <Section title="Transfers"><div className="cardsList">{data.transfers.map(t => <div className="rowCard" key={t.id}><div><b>{t.transfer_number}</b><span>{t.from?.name} → {t.to?.name}</span><small>{d(t.requested_at)}</small></div><select value={t.status} onChange={e => status(t.id, e.target.value)}>{['draft','picked','in_transit','received','cancelled'].map(s => <option key={s}>{s}</option>)}</select></div>)}</div></Section></div>;
}

function Ingredients() {
  const { data, loading, error, reload } = useLoad(() => api('/api/ingredients'));
  const blank = { name:'', category:'', base_unit:'ml', purchase_unit_name:'', purchase_unit_size:'', purchase_unit_cost:'', cost_per_base_unit:'', is_perishable:false, shelf_life_days:'', allergen_flags:'', is_customer_supplied:false, is_active:true };
  const [form, setForm] = useState(blank);
  const [editing, setEditing] = useState(null);
  const [msg, setMsg] = useState('');
  async function save(e) { e.preventDefault(); setMsg(''); const payload = { ...form, allergen_flags: splitTags(form.allergen_flags), is_perishable: toBool(form.is_perishable), is_customer_supplied: toBool(form.is_customer_supplied), is_active: toBool(form.is_active) }; if (editing) await api(`/api/ingredients/${editing}`, { method:'PATCH', body: JSON.stringify(payload) }); else await api('/api/ingredients', { method:'POST', body: JSON.stringify(payload) }); setForm(blank); setEditing(null); setMsg('Saved.'); reload(); }
  function edit(row) { setEditing(row.id); setForm({ ...blank, ...row, allergen_flags: (row.allergen_flags || []).join(', ') }); window.scrollTo({top:0, behavior:'smooth'}); }
  if (loading || error) return <Loading error={error} />;
  return <div className="grid"><Section title={editing ? 'Edit Ingredient' : 'Add Ingredient'} action={editing && <button onClick={() => { setEditing(null); setForm(blank); }}>Cancel edit</button>}><form className="miniForm formGrid" onSubmit={save}><input required placeholder="Name" value={form.name} onChange={e => setForm({...form, name:e.target.value})}/><input placeholder="Category" value={form.category || ''} onChange={e => setForm({...form, category:e.target.value})}/><select value={form.base_unit} onChange={e => setForm({...form, base_unit:e.target.value})}>{baseUnits.map(u => <option key={u}>{u}</option>)}</select><input placeholder="Purchase unit name e.g. 1L bottle" value={form.purchase_unit_name || ''} onChange={e => setForm({...form, purchase_unit_name:e.target.value})}/><input type="number" step="0.001" placeholder="Purchase unit size" value={form.purchase_unit_size || ''} onChange={e => setForm({...form, purchase_unit_size:e.target.value})}/><input type="number" step="0.01" placeholder="Purchase unit cost" value={form.purchase_unit_cost || ''} onChange={e => setForm({...form, purchase_unit_cost:e.target.value})}/><input type="number" step="0.000001" placeholder="Cost per base unit" value={form.cost_per_base_unit || ''} onChange={e => setForm({...form, cost_per_base_unit:e.target.value})}/><input type="number" placeholder="Shelf life days" value={form.shelf_life_days || ''} onChange={e => setForm({...form, shelf_life_days:e.target.value})}/><input placeholder="Allergens, comma separated" value={form.allergen_flags || ''} onChange={e => setForm({...form, allergen_flags:e.target.value})}/><label><input type="checkbox" checked={toBool(form.is_perishable)} onChange={e => setForm({...form, is_perishable:e.target.checked})}/> Perishable</label><label><input type="checkbox" checked={toBool(form.is_customer_supplied)} onChange={e => setForm({...form, is_customer_supplied:e.target.checked})}/> Customer supplied</label><label><input type="checkbox" checked={toBool(form.is_active)} onChange={e => setForm({...form, is_active:e.target.checked})}/> Active</label><button className="primary">{editing ? 'Save Changes' : 'Add Ingredient'}</button></form><Message text={msg}/></Section>
    <Section title="Ingredients"><SimpleTable rows={data} columns={['name','category','base_unit','purchase_unit_cost','cost_per_base_unit','is_perishable','is_customer_supplied','is_active']} actions={(r) => <button onClick={() => edit(r)}>Edit</button>} /></Section></div>;
}

function Cocktails() {
  const { data, loading, error, reload } = useLoad(() => api('/api/cocktails'));
  const blank = { name:'', slug:'', description:'', image_url:'', status:'active', is_featured:false, prep_time_minutes:5, tags:'', variant_name:'Standard', serving_count:1, price_ex_vat:'', vat_rate:0.14, yield_servings:1, liquor_type_ids:[], recipe_items:[{ ingredient_id:'', quantity:'', unit:'ml' }] };
  const [form, setForm] = useState(blank);
  const [editing, setEditing] = useState(null);
  const [editForm, setEditForm] = useState({});
  const [msg, setMsg] = useState('');
  const firstCategory = data?.categories?.[0]?.id || '';
  useEffect(() => { if (data?.categories?.length && !form.category_id) setForm(f => ({...f, category_id: data.categories[0].id})); }, [data]);
  async function add(e) { e.preventDefault(); setMsg(''); const payload = { ...form, tags: splitTags(form.tags), is_featured: toBool(form.is_featured), liquor_type_ids: form.liquor_type_ids, recipe_items: form.recipe_items.filter(i => i.ingredient_id && i.quantity !== '').map(i => ({...i, is_optional:false, is_customer_supplied:false})) }; await api('/api/cocktails', { method:'POST', body: JSON.stringify(payload) }); setForm({...blank, category_id:firstCategory}); setMsg('Cocktail saved.'); reload(); }
  function addRecipeLine() { setForm({...form, recipe_items:[...form.recipe_items, { ingredient_id:'', quantity:'', unit:'ml' }]}); }
  function setRecipeLine(index, patch) { setForm({...form, recipe_items: form.recipe_items.map((it, i) => i === index ? {...it, ...patch} : it)}); }
  function toggleLiquor(id) { setForm(f => ({...f, liquor_type_ids: f.liquor_type_ids.includes(id) ? f.liquor_type_ids.filter(x => x !== id) : [...f.liquor_type_ids, id]})); }
  function startEdit(row) { setEditing(row.id); setEditForm({ name:row.name, slug:row.slug, description:row.description || '', image_url:row.image_url || '', status:row.status, is_featured:row.is_featured, prep_time_minutes:row.prep_time_minutes, tags:(row.tags || []).join(', ') }); window.scrollTo({top:0, behavior:'smooth'}); }
  async function saveEdit(e) { e.preventDefault(); await api(`/api/cocktails/${editing}`, { method:'PATCH', body: JSON.stringify({...editForm, tags: splitTags(editForm.tags), is_featured: toBool(editForm.is_featured)}) }); setEditing(null); setEditForm({}); reload(); }
  if (loading || error) return <Loading error={error} />;
  const variantRows = data.variants.map(v => ({...v, product: data.products.find(p => p.id === v.product_id)?.name}));
  return <div className="grid"><Section title="Add New Cocktail"><form className="miniForm formGrid" onSubmit={add}><input required placeholder="Cocktail name" value={form.name} onChange={e => setForm({...form, name:e.target.value, slug: slugify(e.target.value)})}/><input required placeholder="Slug" value={form.slug} onChange={e => setForm({...form, slug:e.target.value})}/><select value={form.category_id || ''} onChange={e => setForm({...form, category_id:e.target.value})}>{data.categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select><select value={form.status} onChange={e => setForm({...form, status:e.target.value})}>{statuses.map(s => <option key={s}>{s}</option>)}</select><input placeholder="Description" value={form.description} onChange={e => setForm({...form, description:e.target.value})}/><input placeholder="Image URL" value={form.image_url} onChange={e => setForm({...form, image_url:e.target.value})}/><input type="number" placeholder="Prep time minutes" value={form.prep_time_minutes} onChange={e => setForm({...form, prep_time_minutes:e.target.value})}/><input placeholder="Tags, comma separated" value={form.tags} onChange={e => setForm({...form, tags:e.target.value})}/><input required placeholder="Variant name" value={form.variant_name} onChange={e => setForm({...form, variant_name:e.target.value})}/><input required type="number" placeholder="Serving count" value={form.serving_count} onChange={e => setForm({...form, serving_count:e.target.value})}/><input required type="number" step="0.01" placeholder="Price ex VAT" value={form.price_ex_vat} onChange={e => setForm({...form, price_ex_vat:e.target.value})}/><input type="number" step="0.0001" placeholder="VAT rate" value={form.vat_rate} onChange={e => setForm({...form, vat_rate:e.target.value})}/><input required type="number" placeholder="Recipe yield servings" value={form.yield_servings} onChange={e => setForm({...form, yield_servings:e.target.value})}/><label><input type="checkbox" checked={toBool(form.is_featured)} onChange={e => setForm({...form, is_featured:e.target.checked})}/> Featured</label><div className="full"><b>Compatible liquor bottles</b><div className="checks">{data.liquorTypes.map(l => <label key={l.id}><input type="checkbox" checked={form.liquor_type_ids.includes(l.id)} onChange={() => toggleLiquor(l.id)}/> {l.name}</label>)}</div></div><div className="full"><b>Recipe Items</b>{form.recipe_items.map((it, idx) => <div className="inlineRow" key={idx}><select value={it.ingredient_id} onChange={e => setRecipeLine(idx, { ingredient_id:e.target.value })}><option value="">Ingredient</option>{data.ingredients.map(i => <option key={i.id} value={i.id}>{i.name}</option>)}</select><input type="number" step="0.001" placeholder="Qty" value={it.quantity} onChange={e => setRecipeLine(idx, { quantity:e.target.value })}/><select value={it.unit} onChange={e => setRecipeLine(idx, { unit:e.target.value })}>{baseUnits.map(u => <option key={u}>{u}</option>)}</select></div>)}<button type="button" onClick={addRecipeLine}>Add recipe line</button></div><button className="primary">Save Cocktail</button></form><Message text={msg}/></Section>
    {editing && <Section title="Edit Cocktail" action={<button onClick={() => setEditing(null)}>Cancel edit</button>}><form className="miniForm formGrid" onSubmit={saveEdit}><input required value={editForm.name || ''} onChange={e => setEditForm({...editForm, name:e.target.value})}/><input required value={editForm.slug || ''} onChange={e => setEditForm({...editForm, slug:e.target.value})}/><select value={editForm.status || 'active'} onChange={e => setEditForm({...editForm, status:e.target.value})}>{statuses.map(s => <option key={s}>{s}</option>)}</select><input value={editForm.description || ''} onChange={e => setEditForm({...editForm, description:e.target.value})}/><input value={editForm.image_url || ''} onChange={e => setEditForm({...editForm, image_url:e.target.value})}/><input type="number" value={editForm.prep_time_minutes || ''} onChange={e => setEditForm({...editForm, prep_time_minutes:e.target.value})}/><input value={editForm.tags || ''} onChange={e => setEditForm({...editForm, tags:e.target.value})}/><label><input type="checkbox" checked={toBool(editForm.is_featured)} onChange={e => setEditForm({...editForm, is_featured:e.target.checked})}/> Featured</label><button className="primary">Save Changes</button></form></Section>}
    <Section title="Cocktails"><SimpleTable rows={data.products} columns={['name','slug','status','is_featured','prep_time_minutes']} actions={(r) => <button onClick={() => startEdit(r)}>Edit</button>} /></Section><Section title="Variants"><SimpleTable rows={variantRows} columns={['product','name','serving_count','price_ex_vat','price_inc_vat','is_active']} /></Section></div>;
}

function Locations() {
  const { data, loading, error, reload } = useLoad(() => api('/api/locations'));
  const blank = { name:'', type:'beach_cart', compound_name:'', beach_name:'', address:'', latitude:'', longitude:'', is_active:true };
  const [form, setForm] = useState(blank);
  const [editing, setEditing] = useState(null);
  async function save(e) { e.preventDefault(); if (editing) await api(`/api/locations/${editing}`, { method:'PATCH', body: JSON.stringify(form) }); else await api('/api/locations', { method:'POST', body: JSON.stringify(form) }); setForm(blank); setEditing(null); reload(); }
  function edit(row) { setEditing(row.id); setForm({ ...blank, ...row }); window.scrollTo({top:0, behavior:'smooth'}); }
  async function deactivate(row) { await api(`/api/locations/${row.id}`, { method:'PATCH', body: JSON.stringify({ is_active: !row.is_active }) }); reload(); }
  if (loading || error) return <Loading error={error} />;
  return <div className="grid"><Section title={editing ? 'Edit Location' : 'Add Location'} action={editing && <button onClick={() => { setEditing(null); setForm(blank); }}>Cancel edit</button>}><form className="miniForm formGrid" onSubmit={save}><input required placeholder="Name" value={form.name} onChange={e => setForm({...form, name:e.target.value})}/><select value={form.type} onChange={e => setForm({...form, type:e.target.value})}><option value="central_warehouse">central_warehouse</option><option value="beach_cart">beach_cart</option></select><input placeholder="Compound name" value={form.compound_name || ''} onChange={e => setForm({...form, compound_name:e.target.value})}/><input placeholder="Beach name" value={form.beach_name || ''} onChange={e => setForm({...form, beach_name:e.target.value})}/><input placeholder="Address" value={form.address || ''} onChange={e => setForm({...form, address:e.target.value})}/><input type="number" step="0.0000001" placeholder="Latitude" value={form.latitude || ''} onChange={e => setForm({...form, latitude:e.target.value})}/><input type="number" step="0.0000001" placeholder="Longitude" value={form.longitude || ''} onChange={e => setForm({...form, longitude:e.target.value})}/><label><input type="checkbox" checked={toBool(form.is_active)} onChange={e => setForm({...form, is_active:e.target.checked})}/> Active</label><button className="primary">{editing ? 'Save Changes' : 'Add Location'}</button></form></Section><Section title="Locations"><SimpleTable rows={data} columns={['name','type','compound_name','beach_name','address','is_active']} actions={(r) => <div className="inlineActions"><button onClick={() => edit(r)}>Edit</button><button onClick={() => deactivate(r)}>{r.is_active ? 'Deactivate' : 'Activate'}</button></div>} /></Section></div>;
}

function Employees() {
  const { data, loading, error, reload } = useLoad(() => api('/api/employees'));
  const blank = {
    full_name: '',
    username: '',
    password: '',
    role: 'cart_operator',
    phone: '',
    default_location_id: '',
    auth_user_id: '',
    is_active: true,
    credential_is_active: true,
    must_change_password: true
  };
  const resetBlank = { password: '', confirm_password: '', must_change_password: true, credential_is_active: true };
  const [form, setForm] = useState(blank);
  const [editing, setEditing] = useState(null);
  const [resetting, setResetting] = useState(null);
  const [resetForm, setResetForm] = useState(resetBlank);
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');

  function cleanEmployeePayload(payload, isEdit = false) {
    const out = {
      ...payload,
      phone: payload.phone || null,
      default_location_id: payload.default_location_id || null,
      auth_user_id: payload.auth_user_id || null,
      is_active: toBool(payload.is_active),
      credential_is_active: toBool(payload.credential_is_active),
      must_change_password: toBool(payload.must_change_password)
    };
    if (isEdit) delete out.password;
    return out;
  }

  async function save(e) {
    e.preventDefault();
    setMsg('');
    setErr('');
    try {
      if (editing) {
        await api(`/api/employees/${editing}`, { method:'PATCH', body: JSON.stringify(cleanEmployeePayload(form, true)) });
      } else {
        await api('/api/employees', { method:'POST', body: JSON.stringify(cleanEmployeePayload(form)) });
      }
      setForm(blank);
      setEditing(null);
      setMsg('Employee saved.');
      reload();
    } catch (e) {
      setErr(e.message);
    }
  }

  function edit(row) {
    setEditing(row.id);
    setResetting(null);
    setForm({
      full_name: row.full_name || '',
      username: row.credential?.username || '',
      password: '',
      role: row.role,
      phone: row.phone || '',
      default_location_id: row.default_location_id || '',
      auth_user_id: row.auth_user_id || '',
      is_active: row.is_active,
      credential_is_active: row.credential?.is_active ?? false,
      must_change_password: row.credential?.must_change_password ?? false
    });
    window.scrollTo({top:0, behavior:'smooth'});
  }

  function startReset(row) {
    setResetting(row);
    setEditing(null);
    setResetForm(resetBlank);
    setMsg('');
    setErr('');
    window.scrollTo({top:0, behavior:'smooth'});
  }

  async function resetPassword(e) {
    e.preventDefault();
    setMsg('');
    setErr('');
    if (resetForm.password !== resetForm.confirm_password) {
      setErr('Password and confirmation do not match.');
      return;
    }
    try {
      await api(`/api/employees/${resetting.id}/reset-password`, {
        method:'POST',
        body: JSON.stringify({
          password: resetForm.password,
          must_change_password: toBool(resetForm.must_change_password),
          credential_is_active: toBool(resetForm.credential_is_active),
          username: resetting.credential?.username ? undefined : resetting.username
        })
      });
      setResetting(null);
      setResetForm(resetBlank);
      setMsg('Password reset.');
      reload();
    } catch (e) {
      setErr(e.message);
    }
  }

  async function softDelete(row) {
    if (!confirm(`Soft-delete ${row.full_name}? This will deactivate the employee and disable their dashboard login.`)) return;
    setMsg('');
    setErr('');
    try {
      await api(`/api/employees/${row.id}`, { method:'DELETE' });
      setMsg('Employee soft-deleted.');
      reload();
    } catch (e) {
      setErr(e.message);
    }
  }

  if (loading || error) return <Loading error={error} />;
  const rows = data.employees.map(e => ({
    ...e,
    username: e.credential?.username,
    location: e.locations?.name,
    credential_active: e.credential?.is_active ?? false,
    must_change_password: e.credential?.must_change_password ?? false,
    auth_user_id: e.auth_user_id || '-'
  }));

  return <div className="grid">
    <Section title={editing ? 'Edit Employee' : 'Add Employee'} action={editing && <button onClick={() => { setEditing(null); setForm(blank); }}>Cancel edit</button>}>
      <form className="miniForm formGrid" onSubmit={save}>
        <input required placeholder="Full name" value={form.full_name} onChange={e => setForm({...form, full_name:e.target.value})}/>
        <input required placeholder="Dashboard username" value={form.username} onChange={e => setForm({...form, username:e.target.value})}/>
        {!editing && <input required minLength={8} type="password" placeholder="Initial password" value={form.password} onChange={e => setForm({...form, password:e.target.value})}/>} 
        <input placeholder="Phone" value={form.phone || ''} onChange={e => setForm({...form, phone:e.target.value})}/>
        <select value={form.role} onChange={e => setForm({...form, role:e.target.value})}>{roles.map(r => <option key={r}>{r}</option>)}</select>
        <select value={form.default_location_id || ''} onChange={e => setForm({...form, default_location_id:e.target.value})}><option value="">No default location</option>{data.locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select>
        <input placeholder="Optional Supabase Auth user UUID" value={form.auth_user_id || ''} onChange={e => setForm({...form, auth_user_id:e.target.value})}/>
        <label><input type="checkbox" checked={toBool(form.is_active)} onChange={e => setForm({...form, is_active:e.target.checked})}/> Employee active</label>
        <label><input type="checkbox" checked={toBool(form.credential_is_active)} onChange={e => setForm({...form, credential_is_active:e.target.checked})}/> Dashboard login active</label>
        <label><input type="checkbox" checked={toBool(form.must_change_password)} onChange={e => setForm({...form, must_change_password:e.target.checked})}/> Must change password</label>
        <button className="primary">{editing ? 'Save Changes' : 'Create Employee'}</button>
      </form>
      <p className="muted">Dashboard login uses employee_credentials. The Supabase Auth UUID is optional and is not required for this dashboard login flow.</p>
      <Message text={msg}/><Message text={err} type="error"/>
    </Section>

    {resetting && <Section title={`Reset Password: ${resetting.full_name}`} action={<button onClick={() => setResetting(null)}>Cancel reset</button>}>
      <form className="miniForm formGrid" onSubmit={resetPassword}>
        <input required minLength={8} type="password" placeholder="New temporary password" value={resetForm.password} onChange={e => setResetForm({...resetForm, password:e.target.value})}/>
        <input required minLength={8} type="password" placeholder="Confirm temporary password" value={resetForm.confirm_password} onChange={e => setResetForm({...resetForm, confirm_password:e.target.value})}/>
        <label><input type="checkbox" checked={toBool(resetForm.must_change_password)} onChange={e => setResetForm({...resetForm, must_change_password:e.target.checked})}/> Require change on next login</label>
        <label><input type="checkbox" checked={toBool(resetForm.credential_is_active)} onChange={e => setResetForm({...resetForm, credential_is_active:e.target.checked})}/> Keep dashboard login active</label>
        <button className="primary">Reset Password</button>
      </form>
      <Message text={err} type="error"/>
    </Section>}

    <Section title="Employees">
      <SimpleTable rows={rows} columns={['full_name','username','phone','role','location','is_active','credential_active','must_change_password','auth_user_id']} actions={(r) => <div className="inlineActions"><button onClick={() => edit(r)}>Edit</button><button onClick={() => startReset(r)}>Reset Password</button><button onClick={() => softDelete(r)}>Soft Delete</button></div>} />
    </Section>
  </div>;
}

function App() {
  const [auth, setAuth] = useState({ loading: true, user: null, access: [] });
  useEffect(() => { api('/api/me').then(r => setAuth({ loading:false, user:r.user, access:r.access })).catch(() => setAuth({ loading:false, user:null, access:[] })); }, []);
  async function logout() { await api('/api/logout', { method:'POST' }); setAuth({ loading:false, user:null, access:[] }); }
  if (auth.loading) return <div className="loginShell"><div className="muted">Loading…</div></div>;
  if (!auth.user) return <Login onLogin={r => setAuth({ loading:false, user:r.user, access:r.access })} />;
  if (auth.user.must_change_password) return <PasswordChange onChanged={r => setAuth({ loading:false, user:r.user, access:r.access })} onLogout={logout} />;
  return <Shell user={auth.user} access={auth.access} onLogout={logout} />;
}

createRoot(document.getElementById('root')).render(<App />);
