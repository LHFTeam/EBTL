import { can } from '../config/appConfig.js';
import { loadCurrentEmployeeUser } from '../lib/currentEmployee.js';
import { clearSessionCookie, decodeSession, getCookie } from '../lib/session.js';

export function auth(req, res, next) {
  req.user = decodeSession(getCookie(req, 'ebtl_admin'));

  if (req.user?.source === 'env') {
    if (req.user.role === 'prep') {
      req.user = null;
      clearSessionCookie(res);
    }
    return next();
  }

  if (req.user && (req.user.source !== 'employee' || !req.user.employee_id)) {
    req.user = null;
    clearSessionCookie(res);
  }

  next();
}

async function refreshEmployeeSession(req, res) {
  if (req.user?.source !== 'employee') return true;

  try {
    req.user = await loadCurrentEmployeeUser(req.user.employee_id);
    if (!req.user) clearSessionCookie(res);
  } catch (error) {
    console.error('Failed to refresh employee session', error);
    res.status(503).json({ error: 'Unable to verify this dashboard session. Please try again.' });
    return false;
  }

  return true;
}

export async function requireAuth(req, res, next) {
  if (!await refreshEmployeeSession(req, res)) return;
  if (!req.user) return res.status(401).json({ error: 'Not logged in' });
  next();
}

export function requireArea(area) {
  return async (req, res, next) => {
    if (!await refreshEmployeeSession(req, res)) return;
    if (!req.user) return res.status(401).json({ error: 'Not logged in' });
    if (req.user.must_change_password) return res.status(403).json({ error: 'Password change required before continuing.' });
    if (!can(req.user.role, area)) return res.status(403).json({ error: 'Not allowed' });
    next();
  };
}

export async function requireEmployeeSession(req, res, next) {
  if (!await refreshEmployeeSession(req, res)) return;
  if (!req.user) return res.status(401).json({ error: 'Not logged in' });
  if (req.user.source !== 'employee' || !req.user.employee_id) {
    return res.status(403).json({ error: 'Password changes are only available for employee dashboard accounts.' });
  }
  next();
}
