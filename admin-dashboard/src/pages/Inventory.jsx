import { useState } from 'react';
import { api } from '../api/client.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { dt } from '../utils/format.js';

export default function Inventory() {
  const { data, loading, error, reload } = useLoad(() => api('/api/inventory'));
  const [form, setForm] = useState({ ingredient_id: '', location_id: '', quantity_delta: '', reason: '' });
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');
  async function adjust(e) {
    e.preventDefault();
    setMsg('');
    setErr('');
    try {
      await api('/api/inventory/adjust', { method: 'POST', body: JSON.stringify(form) });
      setForm({ ingredient_id: '', location_id: '', quantity_delta: '', reason: '' });
      setMsg('Stock movement posted.');
      reload();
    } catch (e) {
      setErr(e.message);
    }
  }
  if (loading || error) return <Loading error={error} />;
  return <div className="grid2"><Section title="Inventory Balances"><SimpleTable rows={data.balances.map(b => ({...b, ingredient: b.ingredients?.name, location: b.locations?.name}))} columns={['location','ingredient','quantity_on_hand','reserved_quantity','reorder_point','par_level']} /></Section>
    <Section title="Manual Stock Adjustment"><form className="miniForm" onSubmit={adjust}><select required value={form.location_id} onChange={e => setForm({...form, location_id:e.target.value})}><option value="">Location</option>{data.locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select><select required value={form.ingredient_id} onChange={e => setForm({...form, ingredient_id:e.target.value})}><option value="">Ingredient</option>{data.ingredients.map(i => <option key={i.id} value={i.id}>{i.name}</option>)}</select><input required type="number" step="0.001" placeholder="Qty delta e.g. 10 or -2" value={form.quantity_delta} onChange={e => setForm({...form, quantity_delta:e.target.value})}/><input placeholder="Reason" value={form.reason} onChange={e => setForm({...form, reason:e.target.value})}/><button className="primary">Post Movement</button></form><Message text={msg}/><Message text={err} type="error"/></Section>
    <Section title="Recent Movements"><SimpleTable rows={data.movements.map(m => ({...m, ingredient: m.ingredients?.name, location: m.locations?.name}))} columns={['created_at','location','ingredient','movement_type','quantity_delta','reason']} format={{created_at: dt}} /></Section></div>;
}