import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { BarChart3, Boxes, ClipboardList, MapPin, Martini, RefreshCw, ShoppingBag, Truck, Users } from 'lucide-react';
import './styles.css';

const API = '';
const tabs = [
  { key: 'dashboard', label: 'Dashboard', icon: BarChart3 },
  { key: 'orders', label: 'Orders', icon: ClipboardList },
  { key: 'inventory', label: 'Inventory', icon: Boxes },
  { key: 'transfers', label: 'Transfers', icon: Truck },
  { key: 'products', label: 'Products & Recipes', icon: Martini },
  { key: 'locations', label: 'Locations & Carts', icon: MapPin },
  { key: 'employees', label: 'Employees', icon: Users }
];

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

function Login({ onLogin }) {
  const [form, setForm] = useState({ username: 'admin', password: '' });
  const [error, setError] = useState('');
  async function submit(e) {
    e.preventDefault(); setError('');
    try { const r = await api('/api/login', { method: 'POST', body: JSON.stringify(form) }); onLogin(r); }
    catch (err) { setError(err.message); }
  }
  return <div className="loginShell">
    <form className="loginCard" onSubmit={submit}>
      <div className="brandMark">EBTL</div>
      <h1>Admin Dashboard</h1>
      <p>Manage beach carts, warehouse inventory, orders, recipes, and operations.</p>
      <label>Username<input value={form.username} onChange={e => setForm({ ...form, username: e.target.value })} /></label>
      <label>Password<input type="password" value={form.password} onChange={e => setForm({ ...form, password: e.target.value })} /></label>
      {error && <div className="error">{error}</div>}
      <button className="primary">Sign in</button>
    </form>
  </div>;
}

function Shell({ user, access, onLogout }) {
  const allowedTabs = tabs.filter(t => access.includes('*') || access.includes(t.key));
  const [active, setActive] = useState(allowedTabs[0]?.key || 'dashboard');
  const ActiveIcon = tabs.find(t => t.key === active)?.icon || BarChart3;
  return <div className="appShell">
    <aside>
      <div className="sideBrand"><span>EBTL</span><small>Operations</small></div>
      <nav>{allowedTabs.map(t => { const Icon = t.icon; return <button key={t.key} className={active === t.key ? 'active' : ''} onClick={() => setActive(t.key)}><Icon size={18} />{t.label}</button>; })}</nav>
      <div className="userBox"><b>{user.name}</b><span>{user.role}</span><button onClick={onLogout}>Logout</button></div>
    </aside>
    <main>
      <header><div><h1><ActiveIcon size={24} /> {tabs.find(t => t.key === active)?.label}</h1><p>Central warehouse + compound beach carts</p></div></header>
      {active === 'dashboard' && <Dashboard />}
      {active === 'orders' && <Orders />}
      {active === 'inventory' && <Inventory />}
      {active === 'transfers' && <Transfers />}
      {active === 'products' && <Products />}
      {active === 'locations' && <Locations />}
      {active === 'employees' && <Employees />}
    </main>
  </div>;
}

function useLoad(loader, deps = []) {
  const [state, setState] = useState({ loading: true, error: '', data: null });
  const load = async () => { setState(s => ({ ...s, loading: true, error: '' })); try { setState({ loading: false, error: '', data: await loader() }); } catch (e) { setState({ loading: false, error: e.message, data: null }); } };
  useEffect(() => { load(); }, deps);
  return { ...state, reload: load };
}

function Section({ title, action, children }) { return <section className="card"><div className="sectionHead"><h2>{title}</h2>{action}</div>{children}</section>; }
function Loading({ error }) { return error ? <div className="error">{error}</div> : <div className="muted">Loading…</div>; }

function Dashboard() {
  const { data, loading, error, reload } = useLoad(() => api('/api/dashboard'));
  if (loading || error) return <Loading error={error} />;
  return <div className="grid">
    <div className="kpis">
      <Kpi label="Recent Orders" value={data.kpis.recentOrders} />
      <Kpi label="Completed Orders" value={data.kpis.completedOrders} />
      <Kpi label="Recent Revenue" value={money(data.kpis.recentRevenue)} />
      <Kpi label="Low Stock Items" value={data.kpis.lowStockItems} />
      <Kpi label="Active Locations" value={data.kpis.activeLocations} />
    </div>
    <Section title="Recent Orders" action={<button onClick={reload}><RefreshCw size={16}/>Refresh</button>}><SimpleTable rows={data.recentOrders} columns={['order_number','status','payment_status','total_amount','created_at']} format={{ total_amount: money, created_at: dt }} /></Section>
    <Section title="Low Stock"><SimpleTable rows={data.lowStock} columns={['location_name','ingredient_name','quantity_on_hand','reorder_point','par_level']} /></Section>
  </div>;
}
function Kpi({ label, value }) { return <div className="kpi"><span>{label}</span><b>{value}</b></div>; }

function SimpleTable({ rows = [], columns = [], format = {} }) {
  if (!rows.length) return <div className="empty">No records yet.</div>;
  return <div className="tableWrap"><table><thead><tr>{columns.map(c => <th key={c}>{c.replaceAll('_',' ')}</th>)}</tr></thead><tbody>{rows.map((r, i) => <tr key={r.id || i}>{columns.map(c => <td key={c}>{format[c] ? format[c](r[c]) : String(r[c] ?? '-')}</td>)}</tr>)}</tbody></table></div>;
}

function Orders() {
  const { data, loading, error, reload } = useLoad(() => api('/api/orders'));
  const [saving, setSaving] = useState('');
  async function update(id, status) { setSaving(id); await api(`/api/orders/${id}`, { method: 'PATCH', body: JSON.stringify({ status }) }); setSaving(''); reload(); }
  if (loading || error) return <Loading error={error} />;
  return <Section title="Orders" action={<button onClick={reload}><RefreshCw size={16}/>Refresh</button>}>
    <div className="cardsList">{data.orders.map(o => <div className="rowCard" key={o.id}>
      <div><b>{o.order_number || 'Draft order'}</b><span>{o.customers?.full_name || o.customers?.phone || 'No customer'} · {o.locations?.name}</span><small>{dt(o.created_at)} · {money(o.total_amount)}</small></div>
      <select value={o.status} disabled={saving === o.id} onChange={e => update(o.id, e.target.value)}>{['draft','pending_payment','confirmed','preparing','ready','out_for_delivery','completed','cancelled','refunded'].map(s => <option key={s}>{s}</option>)}</select>
    </div>)}</div>
  </Section>;
}

function Inventory() {
  const { data, loading, error, reload } = useLoad(() => api('/api/inventory'));
  const [form, setForm] = useState({ ingredient_id: '', location_id: '', quantity_delta: '', reason: '' });
  async function adjust(e) { e.preventDefault(); await api('/api/inventory/adjust', { method: 'POST', body: JSON.stringify(form) }); setForm({ ingredient_id: '', location_id: '', quantity_delta: '', reason: '' }); reload(); }
  if (loading || error) return <Loading error={error} />;
  return <div className="grid2">
    <Section title="Inventory Balances"><SimpleTable rows={data.balances.map(b => ({...b, ingredient: b.ingredients?.name, location: b.locations?.name}))} columns={['location','ingredient','quantity_on_hand','reserved_quantity','reorder_point','par_level']} /></Section>
    <Section title="Manual Stock Adjustment"><form className="miniForm" onSubmit={adjust}>
      <select required value={form.location_id} onChange={e => setForm({...form, location_id:e.target.value})}><option value="">Location</option>{data.locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select>
      <select required value={form.ingredient_id} onChange={e => setForm({...form, ingredient_id:e.target.value})}><option value="">Ingredient</option>{data.ingredients.map(i => <option key={i.id} value={i.id}>{i.name}</option>)}</select>
      <input required type="number" step="0.001" placeholder="Qty delta e.g. 10 or -2" value={form.quantity_delta} onChange={e => setForm({...form, quantity_delta:e.target.value})}/>
      <input placeholder="Reason" value={form.reason} onChange={e => setForm({...form, reason:e.target.value})}/>
      <button className="primary">Post Movement</button>
    </form></Section>
    <Section title="Recent Movements"><SimpleTable rows={data.movements.map(m => ({...m, ingredient: m.ingredients?.name, location: m.locations?.name}))} columns={['created_at','location','ingredient','movement_type','quantity_delta','reason']} format={{created_at: dt}} /></Section>
  </div>;
}

function Transfers() {
  const { data, loading, error, reload } = useLoad(() => api('/api/transfers'));
  const [form, setForm] = useState({ from_location_id:'', to_location_id:'', notes:'' });
  const [item, setItem] = useState({ ingredient_id:'', requested_qty:'', dispatched_qty:'', received_qty:'' });
  async function create(e) { e.preventDefault(); await api('/api/transfers', { method:'POST', body: JSON.stringify({ ...form, items: item.ingredient_id ? [item] : [] }) }); setForm({ from_location_id:'', to_location_id:'', notes:'' }); setItem({ ingredient_id:'', requested_qty:'', dispatched_qty:'', received_qty:'' }); reload(); }
  async function status(id, status) { await api(`/api/transfers/${id}`, { method:'PATCH', body: JSON.stringify({ status }) }); reload(); }
  if (loading || error) return <Loading error={error} />;
  return <div className="grid2">
    <Section title="Create Transfer"><form className="miniForm" onSubmit={create}>
      <select required value={form.from_location_id} onChange={e => setForm({...form, from_location_id:e.target.value})}><option value="">From</option>{data.locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select>
      <select required value={form.to_location_id} onChange={e => setForm({...form, to_location_id:e.target.value})}><option value="">To</option>{data.locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select>
      <select value={item.ingredient_id} onChange={e => setItem({...item, ingredient_id:e.target.value})}><option value="">Optional first item</option>{data.ingredients.map(i => <option key={i.id} value={i.id}>{i.name}</option>)}</select>
      <input type="number" step="0.001" placeholder="Requested qty" value={item.requested_qty} onChange={e => setItem({...item, requested_qty:e.target.value})}/>
      <input type="number" step="0.001" placeholder="Dispatched qty" value={item.dispatched_qty} onChange={e => setItem({...item, dispatched_qty:e.target.value})}/>
      <input placeholder="Notes" value={form.notes} onChange={e => setForm({...form, notes:e.target.value})}/>
      <button className="primary">Create Transfer</button>
    </form></Section>
    <Section title="Transfers"><div className="cardsList">{data.transfers.map(t => <div className="rowCard" key={t.id}><div><b>{t.transfer_number}</b><span>{t.from?.name} → {t.to?.name}</span><small>{d(t.requested_at)}</small></div><select value={t.status} onChange={e => status(t.id, e.target.value)}>{['draft','picked','in_transit','received','cancelled'].map(s => <option key={s}>{s}</option>)}</select></div>)}</div></Section>
  </div>;
}

function Products() {
  const { data, loading, error, reload } = useLoad(() => api('/api/products'));
  const [product, setProduct] = useState({ name:'', slug:'', description:'', status:'active', prep_time_minutes:5 });
  const [ingredient, setIngredient] = useState({ name:'', base_unit:'ml', category:'' });
  async function addProduct(e) { e.preventDefault(); await api('/api/products', { method:'POST', body: JSON.stringify(product) }); setProduct({ name:'', slug:'', description:'', status:'active', prep_time_minutes:5 }); reload(); }
  async function addIngredient(e) { e.preventDefault(); await api('/api/ingredients', { method:'POST', body: JSON.stringify(ingredient) }); setIngredient({ name:'', base_unit:'ml', category:'' }); reload(); }
  if (loading || error) return <Loading error={error} />;
  return <div className="grid2">
    <Section title="Add Product"><form className="miniForm" onSubmit={addProduct}><input required placeholder="Name" value={product.name} onChange={e => setProduct({...product, name:e.target.value, slug: e.target.value.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')})}/><input required placeholder="Slug" value={product.slug} onChange={e => setProduct({...product, slug:e.target.value})}/><input placeholder="Description" value={product.description} onChange={e => setProduct({...product, description:e.target.value})}/><select value={product.status} onChange={e => setProduct({...product, status:e.target.value})}><option>active</option><option>draft</option><option>archived</option></select><button className="primary">Add Product</button></form></Section>
    <Section title="Add Ingredient"><form className="miniForm" onSubmit={addIngredient}><input required placeholder="Ingredient name" value={ingredient.name} onChange={e => setIngredient({...ingredient, name:e.target.value})}/><select value={ingredient.base_unit} onChange={e => setIngredient({...ingredient, base_unit:e.target.value})}><option>ml</option><option>g</option><option>piece</option><option>bottle</option><option>pack</option></select><input placeholder="Category" value={ingredient.category} onChange={e => setIngredient({...ingredient, category:e.target.value})}/><button className="primary">Add Ingredient</button></form></Section>
    <Section title="Products"><SimpleTable rows={data.products} columns={['name','slug','status','is_featured','prep_time_minutes']} /></Section>
    <Section title="Ingredients"><SimpleTable rows={data.ingredients} columns={['name','category','base_unit','cost_per_base_unit','is_perishable']} /></Section>
  </div>;
}

function Locations() {
  const { data, loading, error, reload } = useLoad(() => api('/api/locations'));
  const [form, setForm] = useState({ name:'', type:'beach_cart', compound_name:'', beach_name:'' });
  async function add(e) { e.preventDefault(); await api('/api/locations', { method:'POST', body: JSON.stringify(form) }); setForm({ name:'', type:'beach_cart', compound_name:'', beach_name:'' }); reload(); }
  if (loading || error) return <Loading error={error} />;
  return <div className="grid2"><Section title="Add Location / Cart"><form className="miniForm" onSubmit={add}><input required placeholder="Name" value={form.name} onChange={e => setForm({...form, name:e.target.value})}/><select value={form.type} onChange={e => setForm({...form, type:e.target.value})}><option value="central_warehouse">central_warehouse</option><option value="beach_cart">beach_cart</option></select><input placeholder="Compound name" value={form.compound_name} onChange={e => setForm({...form, compound_name:e.target.value})}/><input placeholder="Beach name" value={form.beach_name} onChange={e => setForm({...form, beach_name:e.target.value})}/><button className="primary">Add Location</button></form></Section><Section title="Locations"><SimpleTable rows={data} columns={['name','type','compound_name','beach_name','is_active']} /></Section></div>;
}

function Employees() {
  const { data, loading, error, reload } = useLoad(() => api('/api/employees'));
  const [form, setForm] = useState({ full_name:'', role:'cart_operator', phone:'' });
  async function add(e) { e.preventDefault(); await api('/api/employees', { method:'POST', body: JSON.stringify(form) }); setForm({ full_name:'', role:'cart_operator', phone:'' }); reload(); }
  if (loading || error) return <Loading error={error} />;
  return <div className="grid2"><Section title="Add Employee"><form className="miniForm" onSubmit={add}><input required placeholder="Full name" value={form.full_name} onChange={e => setForm({...form, full_name:e.target.value})}/><input placeholder="Phone" value={form.phone} onChange={e => setForm({...form, phone:e.target.value})}/><select value={form.role} onChange={e => setForm({...form, role:e.target.value})}>{['prep','cart_operator','warehouse','supervisor','manager','admin'].map(r => <option key={r}>{r}</option>)}</select><button className="primary">Add Employee</button></form></Section><Section title="Employees"><SimpleTable rows={data.map(e => ({...e, location: e.locations?.name}))} columns={['full_name','phone','role','location','is_active']} /></Section></div>;
}

function App() {
  const [auth, setAuth] = useState({ loading: true, user: null, access: [] });
  useEffect(() => { api('/api/me').then(r => setAuth({ loading:false, user:r.user, access:r.access })).catch(() => setAuth({ loading:false, user:null, access:[] })); }, []);
  async function logout() { await api('/api/logout', { method:'POST' }); setAuth({ loading:false, user:null, access:[] }); }
  if (auth.loading) return <div className="loginShell"><div className="muted">Loading…</div></div>;
  if (!auth.user) return <Login onLogin={r => setAuth({ loading:false, user:r.user, access:[] }) && api('/api/me').then(me => setAuth({ loading:false, user:me.user, access:me.access }))} />;
  return <Shell user={auth.user} access={auth.access} onLogout={logout} />;
}

createRoot(document.getElementById('root')).render(<App />);
