import { Component, lazy, Suspense, useEffect, useState } from 'react';
import { api } from './api/client.js';
import Login from './features/auth/Login.jsx';
import PasswordChange from './features/auth/PasswordChange.jsx';

const Shell = lazy(() => import('./layout/Shell.jsx'));
const PrepOrders = lazy(() => import('./pages/PrepOrders.jsx'));
const AUTH_SYNC_KEY = 'ebtl-auth-session-changed';

window.__EBTL_APP_COMPONENT_LOADED__ = true;
fetch('/api/health?client_boot=app', { cache: 'no-store' }).catch(() => {});

function replacePath(path) {
  if (window.location.pathname !== path) {
    window.history.replaceState({}, '', path);
  }
}

function authenticatedPath(user) {
  return user?.role === 'prep' ? '/prep/orders' : '/dashboard';
}

function broadcastAuthChange() {
  try {
    window.localStorage.setItem(AUTH_SYNC_KEY, `${Date.now()}:${Math.random()}`);
  } catch {
    // Storage can be disabled; the active tab still updates normally.
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
    function handleAuthChange(event) {
      if (event.key === AUTH_SYNC_KEY) window.location.reload();
    }

    window.addEventListener('storage', handleAuthChange);
    return () => window.removeEventListener('storage', handleAuthChange);
  }, []);

  useEffect(() => {
    if (auth.loading) return;

    if (!auth.user || auth.user.must_change_password) {
      replacePath('/login');
      return;
    }

    if (auth.user.role === 'prep') {
      replacePath('/prep/orders');
      return;
    }

    if (
      window.location.pathname === '/login' ||
      window.location.pathname === '/' ||
      window.location.pathname === '/admin' ||
      window.location.pathname.startsWith('/prep')
    ) {
      replacePath('/dashboard');
    }
  }, [auth.loading, auth.user]);

  async function logout() {
    await api('/api/logout', { method: 'POST' });
    broadcastAuthChange();
    setAuth({ loading: false, user: null, access: [] });
    replacePath('/login');
  }

  function handleLogin(result) {
    broadcastAuthChange();
    setAuth({ loading: false, user: result.user, access: result.access });
    replacePath(authenticatedPath(result.user));
  }

  function handlePasswordChanged(result) {
    broadcastAuthChange();
    setAuth({ loading: false, user: result.user, access: result.access });
    replacePath(authenticatedPath(result.user));
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

  if (auth.user.role === 'prep') {
    return (
      <ErrorBoundary>
        <Suspense fallback={<div className="loginShell"><div className="muted">Loading prep orders…</div></div>}>
          <PrepOrders user={auth.user} onLogout={logout} />
        </Suspense>
      </ErrorBoundary>
    );
  }

  return (
    <ErrorBoundary>
      <Suspense fallback={<div className="loginShell"><div className="muted">Loading dashboard…</div></div>}>
        <Shell user={auth.user} access={auth.access} onLogout={logout} />
      </Suspense>
    </ErrorBoundary>
  );
}
