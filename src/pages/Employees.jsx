import { useState } from 'react';
import { api } from '../api/client.js';
import { roles } from '../config/constants.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { toBool } from '../utils/format.js';

export default function Employees() {
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

  async function deactivateEmployee(row) {
    if (!confirm(`Deactivate ${row.full_name}? This will mark the employee inactive and disable their dashboard login.`)) return;
    setMsg('');
    setErr('');
    try {
      await api(`/api/employees/${row.id}`, { method:'DELETE' });
      setMsg('Employee deactivated.');
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
      <SimpleTable rows={rows} columns={['full_name','username','phone','role','location','is_active','credential_active','must_change_password','auth_user_id']} actions={(r) => <div className="inlineActions"><button onClick={() => edit(r)}>Edit</button><button onClick={() => startReset(r)}>Reset Password</button><button onClick={() => deactivateEmployee(r)}>Deactivate</button></div>} />
    </Section>
  </div>;
}