export function money(v) { return `EGP ${Number(v || 0).toLocaleString(undefined, { maximumFractionDigits: 2 })}`; }
export function dt(v) { return v ? new Date(v).toLocaleString() : '-'; }
export function d(v) { return v ? new Date(v).toLocaleDateString() : '-'; }
export function slugify(v) { return String(v || '').toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''); }
export function toBool(v) { return v === true || v === 'true'; }
export function splitTags(v) { return String(v || '').split(',').map(x => x.trim()).filter(Boolean); }
