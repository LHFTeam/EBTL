import { useState } from 'react';
import { api } from '../api/client.js';
import { Loading, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { toBool } from '../utils/format.js';

export default function Locations() {
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