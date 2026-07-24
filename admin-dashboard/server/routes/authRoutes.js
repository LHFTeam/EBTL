import { Router } from 'express';
import { z } from 'zod';
import { envUsers, roleAccess, roles } from '../config/appConfig.js';
import { requireAuth, requireEmployeeSession } from '../middleware/auth.js';
import { employeeCredentialToUser, loadCurrentEmployeeUser } from '../lib/currentEmployee.js';
import { hashPassword, verifyPassword } from '../lib/passwords.js';
import { clearSessionCookie, setSessionCookie } from '../lib/session.js';
import { supabase } from '../lib/supabase.js';

export const authRouter = Router();

authRouter.post('/login', async (req, res) => {
  const parsed = z.object({ username: z.string().min(1), password: z.string().min(1) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid login payload' });
  const { username, password } = parsed.data;

  const foundEnv = envUsers().find((user) => user.username === username && user.password === password);
  if (foundEnv && roles.includes(foundEnv.role)) {
    if (foundEnv.role === 'prep') {
      return res.status(403).json({ error: 'Prep access requires an active employee account with an assigned beach cart.' });
    }
    const user = { username: foundEnv.username, name: foundEnv.name || foundEnv.username, role: foundEnv.role, source: 'env' };
    setSessionCookie(res, user);
    return res.json({ user, access: roleAccess[user.role] || [] });
  }

  const { data, error } = await supabase
    .from('employee_credentials')
    .select('username,password_hash,password_salt,must_change_password,is_active, employees(id,full_name,role,is_active,default_location_id, locations(id,name,type,is_active))')
    .eq('username', username)
    .maybeSingle();

  if (error && !String(error.message || '').includes('employee_credentials')) {
    console.error(error);
  }

  const user = employeeCredentialToUser(data);
  if (!data || !user || !verifyPassword(password, data.password_salt, data.password_hash)) {
    return res.status(401).json({ error: 'Invalid username or password' });
  }

  setSessionCookie(res, user);
  res.json({ user, access: roleAccess[user.role] || [] });
});

authRouter.post('/logout', (_req, res) => {
  clearSessionCookie(res);
  res.json({ ok: true });
});

authRouter.get('/me', requireAuth, (req, res) => {
  setSessionCookie(res, req.user);
  res.json({ user: req.user, access: roleAccess[req.user.role] || [] });
});

authRouter.post('/me/password', requireEmployeeSession, async (req, res) => {
  const parsed = z.object({
    current_password: z.string().min(1),
    new_password: z.string().min(8)
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Current password and a new password of at least 8 characters are required.' });

  const { current_password, new_password } = parsed.data;
  const current = await supabase
    .from('employee_credentials')
    .select('password_hash,password_salt,is_active, employees(id,full_name,role,is_active,default_location_id)')
    .eq('employee_id', req.user.employee_id)
    .maybeSingle();

  if (current.error) return res.status(400).json({ error: current.error.message });
  if (!current.data || !current.data.is_active || !current.data.employees?.is_active) return res.status(403).json({ error: 'This dashboard account is inactive.' });
  if (!verifyPassword(current_password, current.data.password_salt, current.data.password_hash)) {
    return res.status(401).json({ error: 'Current password is incorrect.' });
  }

  const { salt, hash } = hashPassword(new_password);
  const updated = await supabase
    .from('employee_credentials')
    .update({ password_hash: hash, password_salt: salt, must_change_password: false })
    .eq('employee_id', req.user.employee_id);
  if (updated.error) return res.status(400).json({ error: updated.error.message });

  let user;
  try {
    user = await loadCurrentEmployeeUser(req.user.employee_id);
  } catch (error) {
    console.error('Failed to refresh employee after password change', error);
    return res.status(503).json({ error: 'Password changed, but the dashboard session could not be refreshed. Please log in again.' });
  }
  if (!user) {
    clearSessionCookie(res);
    return res.status(403).json({ error: 'Password changed, but this dashboard account is no longer active or valid.' });
  }

  setSessionCookie(res, user);
  res.json({ user, access: roleAccess[user.role] || [] });
});
