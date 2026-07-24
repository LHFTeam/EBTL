import { loadCurrentEmployeeUser } from '../lib/currentEmployee.js';
import { decodeSessionDetails, getCookie } from '../lib/session.js';

function firstForwardedValue(value) {
  return String(value || '').split(',')[0].trim().toLowerCase();
}

export function isSameOriginSocketRequest(req) {
  const origin = firstForwardedValue(req.headers.origin);
  const requestHost = firstForwardedValue(req.headers['x-forwarded-host'] || req.headers.host);
  if (!origin || !requestHost) return false;

  try {
    return new URL(origin).host.toLowerCase() === requestHost;
  } catch {
    return false;
  }
}

export async function authorizePrepSocket(req) {
  const session = decodeSessionDetails(getCookie(req, 'ebtl_admin'));
  if (!session || session.user.source !== 'employee' || !session.user.employee_id) {
    throw new Error('A valid employee session is required.');
  }

  let user;
  try {
    user = await loadCurrentEmployeeUser(session.user.employee_id);
  } catch (error) {
    console.error('Prep socket employee lookup failed:', error?.message || 'Unknown Supabase error');
    const unavailableError = new Error('Could not validate this employee session.');
    unavailableError.code = 'PREP_SOCKET_UNAVAILABLE';
    throw unavailableError;
  }
  if (!user) {
    throw new Error('This employee account is inactive or unavailable.');
  }
  if (user.must_change_password) {
    throw new Error('Password change required before continuing.');
  }
  if (user.role !== 'prep' || !user.location_id) {
    throw new Error('This kitchen display is only available to assigned prep employees.');
  }
  if (Date.now() >= session.exp) {
    throw new Error('Your session has expired.');
  }

  return {
    user,
    expiresAt: session.exp,
    location: {
      id: user.location_id,
      name: user.location_name
    }
  };
}
