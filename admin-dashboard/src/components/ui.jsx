export function Section({ title, action, children }) { return <section className="card"><div className="sectionHead"><h2>{title}</h2>{action}</div>{children}</section>; }
export function Loading({ error, onRetry }) {
  if (!error) return <div className="muted">Loading…</div>;
  return <div className="loadError"><div className="error">{error}</div>{onRetry && <button type="button" className="primary" onClick={onRetry}>Retry</button>}</div>;
}
export function Message({ text, type = 'ok' }) { return text ? <div className={type === 'error' ? 'error' : 'success'}>{text}</div> : null; }
export function Kpi({ label, value }) { return <div className="kpi"><span>{label}</span><b>{value}</b></div>; }

export function SimpleTable({ rows = [], columns = [], format = {}, actions, emptyText = 'No records yet.' }) {
  if (!rows.length) return <div className="empty">{emptyText}</div>;
  return <div className="tableWrap"><table><thead><tr>{columns.map(c => <th key={c}>{c.replaceAll('_', ' ')}</th>)}{actions && <th>Actions</th>}</tr></thead><tbody>{rows.map((r, i) => <tr key={r.id || i}>{columns.map(c => <td key={c}>{format[c] ? format[c](r[c], r) : String(r[c] ?? '-')}</td>)}{actions && <td>{actions(r)}</td>}</tr>)}</tbody></table></div>;
}
