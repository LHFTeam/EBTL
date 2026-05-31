import { useEffect, useState } from 'react';
import { api } from './api/client.js';
import Login from './features/auth/Login.jsx';
import PasswordChange from './features/auth/PasswordChange.jsx';
import Shell from './layout/Shell.jsx';

export default function App() {
  const [auth, setAuth] = useState({ loading: true, user: null, access: [] });
  useEffect(() => { api('/api/me').then(r => setAuth({ loading:false, user:r.user, access:r.access })).catch(() => setAuth({ loading:false, user:null, access:[] })); }, []);
  async function logout() { await api('/api/logout', { method:'POST' }); setAuth({ loading:false, user:null, access:[] }); }
  if (auth.loading) return <div className="loginShell"><div className="muted">Loading…</div></div>;
  if (!auth.user) return <Login onLogin={r => setAuth({ loading:false, user:r.user, access:r.access })} />;
  if (auth.user.must_change_password) return <PasswordChange onChanged={r => setAuth({ loading:false, user:r.user, access:r.access })} onLogout={logout} />;
  return <Shell user={auth.user} access={auth.access} onLogout={logout} />;
}