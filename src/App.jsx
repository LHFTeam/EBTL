import { Component, lazy, Suspense, useEffect, useState } from 'react';
import { api } from './api/client.js';
import Login from './features/auth/Login.jsx';
import PasswordChange from './features/auth/PasswordChange.jsx';

const Shell = lazy(() => import('./layout/Shell.jsx'));

function replacePath(path) {
  if (window.location.pathname !== path) {
    window.history.replaceState({}, '', path);
  }
}

class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error('EBTL dashboard render error:', error, info);
  }

  render() {
    if (this.state.error) {
      return (
        <div className="loginShell">
          <div className="loginCard">
            <div className="brandMark">EBTL</div>
            <h1>Dashboard error</h1>
            <p>The admin dashboard could not finish loading.</p>
            <div className="error">{this.state.error.message || String(this.state.error)}</div>
            <button className="primary" onClick={() => window.location.reload()}>Reload</button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

export default function App() {
  const [auth, setAuth] = useState({ loading: true, user: null, access: [] });

  useEffect(() => {
    let cancelled = false;

    api('/api/me')
      .then((r) => {
        if (!cancelled) setAuth({ loading: false, user: r.user, access: r.access });
      })
      .catch(() => {
        if (!cancelled) setAuth({ loading: false, user: null, access: [] });
      });

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (auth.loading) return;

    if (!auth.user || auth.user.must_change_password) {
      replacePath('/login');
      return;
    }

    if (
      window.location.pathname === '/login' ||
      window.location.pathname === '/' ||
      window.location.pathname === '/admin'
    ) {
      replacePath('/dashboard');
    }
  }, [auth.loading, auth.user]);

  async function logout() {
    await api('/api/logout', { method: 'POST' });
    setAuth({ loading: false, user: null, access: [] });
    replacePath('/login');
  }

  function handleLogin(result) {
    setAuth({ loading: false, user: result.user, access: result.access });
    replacePath('/dashboard');
  }

  function handlePasswordChanged(result) {
    setAuth({ loading: false, user: result.user, access: result.access });
    replacePath('/dashboard');
  }

  if (auth.loading) {
    return (
      <div className="loginShell">
        <div className="muted">Loading…</div>
      </div>
    );
  }

  if (!auth.user) {
    return <Login onLogin={handleLogin} />;
  }

  if (auth.user.must_change_password) {
    return <PasswordChange onChanged={handlePasswordChanged} onLogout={logout} />;
  }

  return (
    <ErrorBoundary>
      <Suspense fallback={<div className="loginShell"><div className="muted">Loading dashboard…</div></div>}>
        <Shell user={auth.user} access={auth.access} onLogout={logout} />
      </Suspense>
    </ErrorBoundary>
  );
}
