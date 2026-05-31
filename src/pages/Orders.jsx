import { useState } from 'react';
import { RefreshCw } from 'lucide-react';
import { api } from '../api/client.js';
import { Loading, Section } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { dt, money } from '../utils/format.js';

export default function Orders() {
  const { data, loading, error, reload } = useLoad(() => api('/api/orders'));
  const [saving, setSaving] = useState('');
  async function update(id, status) { setSaving(id); await api(`/api/orders/${id}`, { method: 'PATCH', body: JSON.stringify({ status }) }); setSaving(''); reload(); }
  if (loading || error) return <Loading error={error} />;
  return <Section title="Orders" action={<button onClick={reload}><RefreshCw size={16}/>Refresh</button>}><div className="cardsList">{data.orders.map(o => <div className="rowCard" key={o.id}><div><b>{o.order_number || 'Draft order'}</b><span>{o.customers?.full_name || o.customers?.phone || 'No customer'} · {o.locations?.name}</span><small>{dt(o.created_at)} · {money(o.total_amount)}</small></div><select value={o.status} disabled={saving === o.id} onChange={e => update(o.id, e.target.value)}>{['draft','pending_payment','confirmed','preparing','ready','out_for_delivery','completed','cancelled','refunded'].map(s => <option key={s}>{s}</option>)}</select></div>)}</div></Section>;
}