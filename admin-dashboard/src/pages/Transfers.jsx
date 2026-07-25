import { useState } from 'react';
import { api } from '../api/client.js';
import { Loading, Message, Section } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { d, humanize } from '../utils/format.js';

export default function Transfers() {
  const { data, loading, error, reload } = useLoad(() => api('/api/transfers'));
  const [form, setForm] = useState({ from_location_id:'', to_location_id:'', notes:'' });
  const [item, setItem] = useState({ ingredient_id:'', requested_qty:'', dispatched_qty:'', received_qty:'' });
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');
  async function create(e) {
    e.preventDefault();
    setMsg('');
    setErr('');
    try {
      await api('/api/transfers', { method:'POST', body: JSON.stringify({ ...form, items: item.ingredient_id ? [item] : [] }) });
      setForm({ from_location_id:'', to_location_id:'', notes:'' });
      setItem({ ingredient_id:'', requested_qty:'', dispatched_qty:'', received_qty:'' });
      setMsg('Transfer created.');
      reload();
    } catch (e) {
      setErr(e.message);
    }
  }
  async function status(id, status) {
    setMsg('');
    setErr('');
    try {
      await api(`/api/transfers/${id}`, { method:'PATCH', body: JSON.stringify({ status }) });
      setMsg('Transfer status updated.');
      reload();
    } catch (e) {
      setErr(e.message);
    }
  }
  if (loading || error) return <Loading error={error} onRetry={reload} />;
  return <div className="grid2"><Section title="Create Transfer"><form className="miniForm" onSubmit={create}><select required aria-label="From location" value={form.from_location_id} onChange={e => setForm({...form, from_location_id:e.target.value})}><option value="">From</option>{data.locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select><select required aria-label="To location" value={form.to_location_id} onChange={e => setForm({...form, to_location_id:e.target.value})}><option value="">To</option>{data.locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select><select aria-label="Optional first item" value={item.ingredient_id} onChange={e => setItem({...item, ingredient_id:e.target.value})}><option value="">Optional first item</option>{data.ingredients.map(i => <option key={i.id} value={i.id}>{i.name}</option>)}</select><input type="number" aria-label="Requested quantity" step="0.001" placeholder="Requested qty" value={item.requested_qty} onChange={e => setItem({...item, requested_qty:e.target.value})}/><input type="number" aria-label="Dispatched quantity" step="0.001" placeholder="Dispatched qty" value={item.dispatched_qty} onChange={e => setItem({...item, dispatched_qty:e.target.value})}/><input aria-label="Notes" placeholder="Notes" value={form.notes} onChange={e => setForm({...form, notes:e.target.value})}/><button className="primary">Create Transfer</button></form><Message text={msg}/><Message text={err} type="error"/></Section>
    <Section title="Transfers"><div className="cardsList">{data.transfers.map(t => <div className="rowCard" key={t.id}><div><b>{t.transfer_number}</b><span>{t.from?.name} → {t.to?.name}</span><small>{d(t.requested_at)}</small></div><select aria-label={`Status for ${t.transfer_number}`} value={t.status} onChange={e => status(t.id, e.target.value)}>{['draft','picked','in_transit','received','cancelled'].map(s => <option key={s} value={s}>{humanize(s)}</option>)}</select></div>)}</div></Section></div>;
}