import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.jsx';
import './styles.css';

function showStartupError(error) {
  const root = document.getElementById('root');
  if (!root) return;
  const message = error?.message || String(error || 'Unknown startup error');
  root.innerHTML = `
    <div style="min-height:100vh;display:grid;place-items:center;padding:24px;background:#f6f2ec;color:#251d16;font-family:Inter,Arial,sans-serif">
      <div style="max-width:520px;background:#fffaf3;border:1px solid #e4d8c9;border-radius:24px;padding:24px;box-shadow:0 20px 60px rgba(95,67,36,.12)">
        <div style="font-weight:900;letter-spacing:.08em;margin-bottom:12px">EBTL</div>
        <h1 style="margin:0 0 8px;font-size:24px">Admin startup error</h1>
        <p style="color:#7c6d60;line-height:1.5">The dashboard JavaScript loaded, but React could not start.</p>
        <pre style="white-space:pre-wrap;background:#ffe9e6;color:#9f2d22;border:1px solid #ffc7bf;padding:12px;border-radius:12px">${message.replace(/[<>&]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;' })[c])}</pre>
        <button onclick="location.reload()" style="border:1px solid #2f6b4f;background:#2f6b4f;color:white;border-radius:12px;padding:10px 14px;font-weight:700">Reload</button>
      </div>
    </div>
  `;
}

try {
  window.__EBTL_MAIN_MODULE_RAN__ = true;
  fetch('/api/health?client_boot=main', { cache: 'no-store' }).catch(() => {});

  const rootEl = document.getElementById('root');
  if (!rootEl) throw new Error('Missing #root element in index.html');

  createRoot(rootEl).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>
  );
} catch (error) {
  console.error('EBTL dashboard startup error:', error);
  fetch('/api/client-error', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'startup', message: error?.message || String(error), stack: error?.stack, path: window.location.pathname })
  }).catch(() => {});
  showStartupError(error);
}
