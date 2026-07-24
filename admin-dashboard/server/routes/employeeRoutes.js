import { Router } from 'express';
import { z } from 'zod';
import { employeeRoles } from '../config/appConfig.js';
import { requireArea } from '../middleware/auth.js';
import { clean } from '../lib/objectUtils.js';
import { hashPassword } from '../lib/passwords.js';
import { supabase } from '../lib/supabase.js';

export const employeeRouter = Router();

async function validatePrepLocation(employee) {
  if (employee.role !== 'prep') return { ok: true };
  if (!employee.default_location_id) {
    return { ok: false, error: 'Prep employees require an assigned active beach cart location.' };
  }

  const location = await supabase
    .from('locations')
    .select('id,type,is_active')
    .eq('id', employee.default_location_id)
    .maybeSingle();

  if (location.error) return { ok: false, error: location.error.message };
  if (!location.data || location.data.type !== 'beach_cart' || !location.data.is_active) {
    return { ok: false, error: 'Prep employees require an assigned active beach cart location.' };
  }

  return { ok: true };
}

async function canDeactivateEmployee(employeeId) {
  const current = await supabase.from('employees').select('id,role').eq('id', employeeId).single();
  if (current.error) return { ok: false, error: current.error.message };

  if (current.data.role !== 'admin') return { ok: true };

  const admins = await supabase
    .from('employees')
    .select('id, employee_credentials!inner(is_active)')
    .eq('role', 'admin')
    .eq('is_active', true)
    .eq('employee_credentials.is_active', true)
    .neq('id', employeeId);

  if (admins.error) return { ok: false, error: admins.error.message };
  if (!admins.data.length) return { ok: false, error: 'Cannot deactivate the last active admin with active dashboard credentials.' };
  return { ok: true };
}

employeeRouter.get('/employees', requireArea('employees'), async (_req, res) => {
  const [employees, locations, credentials] = await Promise.all([
    supabase.from('employees').select('*, locations(name,type,compound_name)').order('full_name'),
    supabase.from('locations').select('*').order('name'),
    supabase.from('employee_credentials').select('employee_id,username,is_active,must_change_password,updated_at')
  ]);
  for (const result of [employees, locations]) if (result.error) return res.status(400).json({ error: result.error.message });
  if (credentials.error) console.warn(credentials.error.message);
  const credentialMap = new Map((credentials.data || []).map((c) => [c.employee_id, c]));
  res.json({ employees: employees.data.map((e) => ({ ...e, credential: credentialMap.get(e.id) || null })), locations: locations.data, roles: employeeRoles });
});

employeeRouter.post('/employees', requireArea('employees'), async (req, res) => {
  const parsed = z.object({
    full_name: z.string().min(1),
    username: z.string().min(3).regex(/^[a-zA-Z0-9._-]+$/),
    password: z.string().min(8),
    phone: z.string().nullable().optional(),
    role: z.enum(employeeRoles),
    default_location_id: z.string().uuid().nullable().optional(),
    auth_user_id: z.string().uuid().nullable().optional(),
    is_active: z.boolean().optional(),
    credential_is_active: z.boolean().optional(),
    must_change_password: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid employee. Username must be at least 3 characters; password at least 8 characters.' });

  const { username, password, credential_is_active, must_change_password, ...employeePayload } = parsed.data;
  const prepLocation = await validatePrepLocation(employeePayload);
  if (!prepLocation.ok) return res.status(400).json({ error: prepLocation.error });

  const created = await supabase.from('employees').insert(clean(employeePayload)).select().single();
  if (created.error) return res.status(400).json({ error: created.error.message });

  const { salt, hash } = hashPassword(password);
  const cred = await supabase.from('employee_credentials').insert({
    employee_id: created.data.id,
    username,
    password_hash: hash,
    password_salt: salt,
    is_active: credential_is_active ?? employeePayload.is_active ?? true,
    must_change_password: must_change_password ?? true
  }).select('employee_id,username,is_active,must_change_password').single();

  if (cred.error) {
    await supabase.from('employees').delete().eq('id', created.data.id);
    return res.status(400).json({ error: cred.error.message });
  }

  res.json({ ...created.data, credential: cred.data });
});

employeeRouter.patch('/employees/:id', requireArea('employees'), async (req, res) => {
  const parsed = z.object({
    full_name: z.string().min(1).optional(),
    phone: z.string().nullable().optional(),
    role: z.enum(employeeRoles).optional(),
    default_location_id: z.string().uuid().nullable().optional(),
    auth_user_id: z.string().uuid().nullable().optional(),
    is_active: z.boolean().optional(),
    username: z.string().min(3).regex(/^[a-zA-Z0-9._-]+$/).optional(),
    credential_is_active: z.boolean().optional(),
    must_change_password: z.boolean().optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid employee update' });

  const { username, credential_is_active, must_change_password, ...employeePayload } = parsed.data;
  const existing = await supabase
    .from('employees')
    .select('id,role,default_location_id,is_active')
    .eq('id', req.params.id)
    .single();
  if (existing.error) return res.status(400).json({ error: existing.error.message });

  const prepLocation = await validatePrepLocation({ ...existing.data, ...employeePayload });
  if (!prepLocation.ok) return res.status(400).json({ error: prepLocation.error });

  if (employeePayload.is_active === false) {
    if (req.user.employee_id === req.params.id) return res.status(400).json({ error: 'You cannot deactivate your own employee record.' });
    const allowed = await canDeactivateEmployee(req.params.id);
    if (!allowed.ok) return res.status(400).json({ error: allowed.error });
  }

  const updates = clean(employeePayload);
  let employee = null;
  if (Object.keys(updates).length) {
    const updated = await supabase.from('employees').update(updates).eq('id', req.params.id).select().single();
    if (updated.error) return res.status(400).json({ error: updated.error.message });
    employee = updated.data;
  }

  if (username || credential_is_active !== undefined || must_change_password !== undefined) {
    const current = await supabase.from('employee_credentials').select('*').eq('employee_id', req.params.id).maybeSingle();
    if (current.error) return res.status(400).json({ error: current.error.message });
    if (!current.data) return res.status(400).json({ error: 'This employee does not have dashboard credentials yet. Use reset password to create credentials.' });

    if (credential_is_active === false) {
      if (req.user.employee_id === req.params.id) return res.status(400).json({ error: 'You cannot deactivate your own dashboard credentials.' });
      const allowed = await canDeactivateEmployee(req.params.id);
      if (!allowed.ok) return res.status(400).json({ error: allowed.error });
    }

    const credentialPayload = {};
    if (username) credentialPayload.username = username;
    if (credential_is_active !== undefined) credentialPayload.is_active = credential_is_active;
    if (must_change_password !== undefined) credentialPayload.must_change_password = must_change_password;

    const cred = await supabase
      .from('employee_credentials')
      .update(credentialPayload)
      .eq('employee_id', req.params.id)
      .select('employee_id,username,is_active,must_change_password')
      .single();
    if (cred.error) return res.status(400).json({ error: cred.error.message });
  }

  if (!employee) {
    const fetched = await supabase.from('employees').select('*').eq('id', req.params.id).single();
    if (fetched.error) return res.status(400).json({ error: fetched.error.message });
    employee = fetched.data;
  }
  res.json(employee);
});

employeeRouter.post('/employees/:id/reset-password', requireArea('employees'), async (req, res) => {
  const parsed = z.object({
    password: z.string().min(8),
    must_change_password: z.boolean().optional(),
    credential_is_active: z.boolean().optional(),
    username: z.string().min(3).regex(/^[a-zA-Z0-9._-]+$/).optional()
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Password must be at least 8 characters, and a username (when creating credentials) must be at least 3 characters using letters, numbers, dots, underscores or hyphens.' });

  const existingEmployee = await supabase.from('employees').select('id,is_active').eq('id', req.params.id).single();
  if (existingEmployee.error) return res.status(400).json({ error: existingEmployee.error.message });

  const { password, must_change_password, credential_is_active, username } = parsed.data;
  const { salt, hash } = hashPassword(password);
  const current = await supabase.from('employee_credentials').select('*').eq('employee_id', req.params.id).maybeSingle();
  if (current.error) return res.status(400).json({ error: current.error.message });

  const credentialPayload = {
    password_hash: hash,
    password_salt: salt,
    must_change_password: must_change_password ?? true,
    is_active: credential_is_active ?? true
  };
  if (username) credentialPayload.username = username;

  if (current.data) {
    const updated = await supabase
      .from('employee_credentials')
      .update(credentialPayload)
      .eq('employee_id', req.params.id)
      .select('employee_id,username,is_active,must_change_password')
      .single();
    if (updated.error) return res.status(400).json({ error: updated.error.message });
    return res.json({ credential: updated.data });
  }

  if (!username) return res.status(400).json({ error: 'Username is required when creating credentials for an employee who does not already have credentials.' });
  const inserted = await supabase
    .from('employee_credentials')
    .insert({ employee_id: req.params.id, username, ...credentialPayload })
    .select('employee_id,username,is_active,must_change_password')
    .single();
  if (inserted.error) return res.status(400).json({ error: inserted.error.message });
  res.json({ credential: inserted.data });
});

employeeRouter.delete('/employees/:id', requireArea('employees'), async (req, res) => {
  if (req.user.employee_id === req.params.id) return res.status(400).json({ error: 'You cannot deactivate your own employee account.' });
  const allowed = await canDeactivateEmployee(req.params.id);
  if (!allowed.ok) return res.status(400).json({ error: allowed.error });

  const employee = await supabase
    .from('employees')
    .update({ is_active: false })
    .eq('id', req.params.id)
    .select('id,full_name,is_active')
    .single();
  if (employee.error) return res.status(400).json({ error: employee.error.message });

  const credential = await supabase
    .from('employee_credentials')
    .update({ is_active: false })
    .eq('employee_id', req.params.id)
    .select('employee_id,username,is_active')
    .maybeSingle();
  if (credential.error) return res.status(400).json({ error: credential.error.message });

  res.json({ employee: employee.data, credential: credential.data });
});
