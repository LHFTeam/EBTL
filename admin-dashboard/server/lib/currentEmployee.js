import { roles } from '../config/appConfig.js';
import { supabase } from './supabase.js';

function relatedRow(value) {
  return Array.isArray(value) ? value[0] || null : value || null;
}

export function employeeCredentialToUser(credential) {
  const employee = relatedRow(credential?.employees);
  if (!credential?.is_active || !employee?.is_active || !roles.includes(employee.role)) {
    return null;
  }

  const location = relatedRow(employee.locations);
  if (
    employee.role === 'prep'
    && (
      !employee.default_location_id
      || !location
      || location.id !== employee.default_location_id
      || location.type !== 'beach_cart'
      || !location.is_active
    )
  ) {
    return null;
  }

  return {
    username: credential.username,
    name: employee.full_name,
    role: employee.role,
    employee_id: employee.id,
    location_id: employee.default_location_id,
    location_name: location?.name || null,
    must_change_password: Boolean(credential.must_change_password),
    source: 'employee'
  };
}

export async function loadCurrentEmployeeUser(employeeId) {
  if (!employeeId) return null;

  const result = await supabase
    .from('employee_credentials')
    .select(`
      username,
      must_change_password,
      is_active,
      employees(
        id,
        full_name,
        role,
        is_active,
        default_location_id,
        locations(id,name,type,is_active)
      )
    `)
    .eq('employee_id', employeeId)
    .maybeSingle();

  if (result.error) throw result.error;
  return employeeCredentialToUser(result.data);
}
