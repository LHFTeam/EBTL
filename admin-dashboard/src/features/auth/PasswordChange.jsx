import { useState } from 'react';
import { api } from '../../api/client.js';

export default function PasswordChange({ onChanged, onLogout }) {
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