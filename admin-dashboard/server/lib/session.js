import crypto from 'crypto';
import { isProd, SESSION_SECRET } from '../config/appConfig.js';

function sign(value) {
  return crypto.createHmac('sha256', SESSION_SECRET).update(value).digest('base64url');
}

export function encodeSession(user) {
  const payload = Buffer.from(JSON.stringify({ user, exp: Date.now() + 12 * 60 * 60 * 1000 })).toString('base64url');
  return `${payload}.${sign(payload)}`;
}

export function decodeSessionDetails(token) {
  try {
    if (!token || !token.includes('.')) return null;
    const [payload, signature] = token.split('.');
    const expected = sign(payload);
    if (signature.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (!data.exp || Date.now() > data.exp) return null;
    if (!data.user || typeof data.user !== 'object') return null;
    return { user: data.user, exp: data.exp };
  } catch {
    return null;
  }
}

export function decodeSession(token) {
  return decodeSessionDetails(token)?.user || null;
}

export function getCookie(req, name) {
  const cookies = req.headers.cookie || '';
  return cookies
    .split(';')
    .map((cookie) => cookie.trim())
    .find((cookie) => cookie.startsWith(`${name}=`))
    ?.slice(name.length + 1);
}

export function setSessionCookie(res, user) {
  const secure = isProd ? '; Secure' : '';
  res.setHeader('Set-Cookie', `ebtl_admin=${encodeSession(user)}; HttpOnly; Path=/; SameSite=Lax; Max-Age=43200${secure}`);
}

export function clearSessionCookie(res) {
  res.setHeader('Set-Cookie', 'ebtl_admin=; HttpOnly; Path=/; SameSite=Lax; Max-Age=0');
}
