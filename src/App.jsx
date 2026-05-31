import { useEffect, useState } from 'react';
import { api } from './api/client.js';
import Login from './features/auth/Login.jsx';
import PasswordChange from './features/auth/PasswordChange.jsx';
import Shell from './layout/Shell.jsx';

function goTo(path) {
  if (window.location.pathname !== path) {
    window.history.replaceState({}, '', path);
  }
}

export default function App() {
  const [auth, setAuth] = useState({ loading: true, user: null, access: [] });

  useEffect(() => {
    api('/api/me')
      .then((r) => {
        setAuth({ loading: false, user: r.user, access: r.access });
      })
      .catch(() => {
        setAuth({ loading: false, user: null, access: [] });
      });
  }, []);

  async function logout() {
    await api('/api/logout', { method: 'POST' });
    setAuth({ loading: false, user: null, access: [] });
    goTo('/login');
  }

  function handleLogin(result) {
    setAuth({ loading: false, user: result.user, access: result.access });
    goTo('/dashboard');
  }

  function handlePasswordChanged(result) {
    setAuth({ loading: false, user: result.user, access: result.access });
    goTo('/dashboard');
  }

  if (auth.loading) {
    return (
      <div className="loginShell">
        <div className="muted">Loading…</div>
      </div>
    );
  }

  if (!auth.user) {
    goTo('/login');
    return <Login onLogin={handleLogin} />;
  }

  if (auth.user.must_change_password) {
    goTo('/login');
    return <PasswordChange onChanged={handlePasswordChanged} onLogout={logout} />;
  }

  goTo('/dashboard');
  return <Shell user={auth.user} access={auth.access} onLogout={logout} />;
}
