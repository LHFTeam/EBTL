import { can } from '../config/appConfig.js';
import { decodeSession, getCookie } from '../lib/session.js';

export function auth(req, _res, next) {
  req.user = decodeSession(getCookie(req, 'ebtl_admin'));
  next();
}

export function requireAuth(req, res, next) {
  if (!req.user) return res.status(401).json({ error: 'Not logged in' });
  next();
}

export function requireArea(area) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'Not logged in' });
    if (req.user.must_change_password) return res.status(403).json({ error: 'Password change required before continuing.' });
    if (!can(req.user.role, area)) return res.status(403).json({ error: 'Not allowed' });
    next();
  };
}

export function requireEmployeeSession(req, res, next) {
  if (!req.user) return res.status(401).json({ error: 'Not logged in' });
  if (req.user.source !== 'employee' || !req.user.employee_id) {
    return res.status(403).json({ error: 'Password changes are only available for employee dashboard accounts.' });
  }
  next();
}
