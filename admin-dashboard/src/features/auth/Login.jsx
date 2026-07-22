import { useState } from 'react';
import { api } from '../../api/client.js';

export default function Login({ onLogin }) {
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