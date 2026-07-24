import { useState } from 'react';
import { api } from '../api/client.js';
import { roles } from '../config/constants.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { humanize, toBool, yesNo } from '../utils/format.js';

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
  const resetBlank = { username: '', password: '', confirm_password: '', must_change_password: true, credential_is_active: true };
  const [form, setForm] = useState(blank);
  const [editing, setEditing] = useState(null);
  const [resetting, setResetting] = useState(null);
  const [resetForm, setResetForm] = useState(resetBlank);
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState('');

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
    const hasCredential = Boolean(resetting.credential?.username);
    const newUsername = resetForm.username.trim();
    if (!hasCredential && !newUsername) {
      setErr('A dashboard username is required to create credentials for this employee.');
      return;
    }
    try {
      await api(`/api/employees/${resetting.id}/reset-password`, {
        method:'POST',
        body: JSON.stringify({
          password: resetForm.password,
          must_change_password: toBool(resetForm.must_change_password),
          credential_is_active: toBool(resetForm.credential_is_active),
          username: hasCredential ? undefined : newUsername
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

  if (loading || error) return <Loading error={error} onRetry={reload} />;
  const prepLocationRequired = form.role === 'prep';
  const availableLocations = prepLocationRequired
    ? data.locations.filter((location) => location.type === 'beach_cart' && location.is_active)
    : data.locations;

  function changeRole(role) {
    const selectedLocationIsValid = data.locations.some((location) => (
      location.id === form.default_location_id
      && location.type === 'beach_cart'
      && location.is_active
    ));

    setForm({
      ...form,
      role,
      default_location_id: role === 'prep' && !selectedLocationIsValid
        ? ''
        : form.default_location_id
    });
  }

  const allRows = data.employees.map(e => ({
    ...e,
    username: e.credential?.username,
    location: e.locations?.name,
    credential_active: e.credential?.is_active ?? false,
    must_change_password: e.credential?.must_change_password ?? false,
    auth_user_id: e.auth_user_id || '-'
  }));

  const searchText = search.trim().toLowerCase();
  const filtersActive = Boolean(searchText || roleFilter);
  const rows = allRows.filter(r => {
    const matchesSearch = !searchText || [r.full_name, r.username, r.phone, r.role, r.location]
      .some(value => String(value || '').toLowerCase().includes(searchText));
    const matchesRole = !roleFilter || r.role === roleFilter;
    return matchesSearch && matchesRole;
  });

  return <div className="grid">
    <Section title={editing ? 'Edit Employee' : 'Add Employee'} action={editing && <button onClick={() => { setEditing(null); setForm(blank); }}>Cancel edit</button>}>
      <form className="miniForm formGrid" onSubmit={save}>
        <input required aria-label="Full name" placeholder="Full name" value={form.full_name} onChange={e => setForm({...form, full_name:e.target.value})}/>
        <input required aria-label="Dashboard username" placeholder="Dashboard username" value={form.username} onChange={e => setForm({...form, username:e.target.value})}/>
        {!editing && <input required minLength={8} aria-label="Initial password" type="password" placeholder="Initial password" value={form.password} onChange={e => setForm({...form, password:e.target.value})}/>}
        <input aria-label="Phone" placeholder="Phone" value={form.phone || ''} onChange={e => setForm({...form, phone:e.target.value})}/>
        <select aria-label="Role" value={form.role} onChange={e => changeRole(e.target.value)}>{roles.map(r => <option key={r} value={r}>{humanize(r)}</option>)}</select>
        <select
          required={prepLocationRequired}
          aria-label={prepLocationRequired ? 'Required prep beach cart location' : 'Default location'}
          value={form.default_location_id || ''}
          onChange={e => setForm({...form, default_location_id:e.target.value})}
        >
          <option value="">{prepLocationRequired ? 'Select active beach cart (required)' : 'No default location'}</option>
          {availableLocations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}
        </select>
        <input aria-label="Optional Supabase Auth user UUID" placeholder="Optional Supabase Auth user UUID" value={form.auth_user_id || ''} onChange={e => setForm({...form, auth_user_id:e.target.value})}/>
        <label><input type="checkbox" checked={toBool(form.is_active)} onChange={e => setForm({...form, is_active:e.target.checked})}/> Employee active</label>
        <label><input type="checkbox" checked={toBool(form.credential_is_active)} onChange={e => setForm({...form, credential_is_active:e.target.checked})}/> Dashboard login active</label>
        <label><input type="checkbox" checked={toBool(form.must_change_password)} onChange={e => setForm({...form, must_change_password:e.target.checked})}/> Must change password</label>
        <button className="primary">{editing ? 'Save Changes' : 'Create Employee'}</button>
      </form>
      <p className="muted">Dashboard login uses employee_credentials. The Supabase Auth UUID is optional and is not required for this dashboard login flow.</p>
      {prepLocationRequired && <p className="muted">Prep employees must be assigned to an active beach cart. Their kitchen screen is locked to that location.</p>}
      <Message text={msg}/><Message text={err} type="error"/>
    </Section>

    {resetting && <Section title={`${resetting.credential?.username ? 'Reset Password' : 'Create Dashboard Login'}: ${resetting.full_name}`} action={<button onClick={() => setResetting(null)}>Cancel</button>}>
      <form className="miniForm formGrid" onSubmit={resetPassword}>
        {!resetting.credential?.username && <input required minLength={3} aria-label="Dashboard username" pattern="[a-zA-Z0-9._-]+" title="At least 3 characters: letters, numbers, dots, underscores or hyphens" placeholder="Dashboard username" value={resetForm.username} onChange={e => setResetForm({...resetForm, username:e.target.value})}/>}
        <input required minLength={8} aria-label="New temporary password" type="password" placeholder="New temporary password" value={resetForm.password} onChange={e => setResetForm({...resetForm, password:e.target.value})}/>
        <input required minLength={8} aria-label="Confirm temporary password" type="password" placeholder="Confirm temporary password" value={resetForm.confirm_password} onChange={e => setResetForm({...resetForm, confirm_password:e.target.value})}/>
        <label><input type="checkbox" checked={toBool(resetForm.must_change_password)} onChange={e => setResetForm({...resetForm, must_change_password:e.target.checked})}/> Require change on next login</label>
        <label><input type="checkbox" checked={toBool(resetForm.credential_is_active)} onChange={e => setResetForm({...resetForm, credential_is_active:e.target.checked})}/> Keep dashboard login active</label>
        <button className="primary">Reset Password</button>
      </form>
      <Message text={err} type="error"/>
    </Section>}

    <Section title="Employees">
      <div className="filtersBar">
        <input type="search" placeholder="Search by name, username, phone, or location" value={search} onChange={e => setSearch(e.target.value)}/>
        <select value={roleFilter} onChange={e => setRoleFilter(e.target.value)}>
          <option value="">All roles</option>
          {roles.map(r => <option key={r} value={r}>{humanize(r)}</option>)}
        </select>
        {filtersActive && <button onClick={() => { setSearch(''); setRoleFilter(''); }}>Clear filters</button>}
      </div>
      <SimpleTable
        rows={rows}
        columns={['full_name','username','phone','role','location','is_active','credential_active','must_change_password','auth_user_id']}
        emptyText={filtersActive ? 'No employees match the current filters.' : 'No records yet.'}
        format={{
          role: (value) => humanize(value),
          is_active: yesNo,
          credential_active: yesNo,
          must_change_password: yesNo
        }}
        actions={(r) => <div className="inlineActions"><button onClick={() => edit(r)}>Edit</button><button onClick={() => startReset(r)}>Reset Password</button><button onClick={() => deactivateEmployee(r)}>Deactivate</button></div>}
      />
    </Section>
  </div>;
}
