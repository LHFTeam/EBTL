import test from 'node:test';
import assert from 'node:assert/strict';

// `notifications.js` reaches the database, and importing it pulls in
// `appConfig.js`, which refuses to load without Supabase credentials. CI has no
// secrets, so stand in placeholders and import dynamically — a static import
// would be hoisted above these lines and throw before they ran. The functions
// under test are pure; nothing here opens a connection.
process.env.SUPABASE_URL ||= 'http://supabase.invalid';
process.env.SUPABASE_SERVICE_ROLE_KEY ||= 'test-key';

const { fcmErrorCode, isTokenGoneFcm } = await import('./notifications.js');

// These decide whether a failed send retires the device token. Retiring one
// that was fine costs the customer every future notification, so the split
// between "this token is dead" and "this send went wrong" is the whole point.

const fcmError = (status, errorCode) => ({
  status,
  body: {
    error: {
      code: status,
      status: status === 404 ? 'NOT_FOUND' : 'INVALID_ARGUMENT',
      message: 'Requested entity was not found.',
      details: [{
        '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
        errorCode
      }]
    }
  }
});

test('an uninstalled app retires its token', () => {
  assert.equal(isTokenGoneFcm(fcmError(404, 'UNREGISTERED')), true);
});

test('a token minted for another Firebase project retires', () => {
  assert.equal(isTokenGoneFcm(fcmError(403, 'SENDER_ID_MISMATCH')), true);
});

test('a rejected payload keeps the token', () => {
  // FCM answers INVALID_ARGUMENT for a malformed message as well as for a
  // malformed token. Acting on it would let one bad notification unregister
  // every device it was addressed to.
  assert.equal(isTokenGoneFcm(fcmError(400, 'INVALID_ARGUMENT')), false);
});

test('a server-side FCM outage keeps the token', () => {
  assert.equal(isTokenGoneFcm(fcmError(503, 'UNAVAILABLE')), false);
  assert.equal(isTokenGoneFcm(fcmError(500, 'INTERNAL')), false);
});

test('an expired service account keeps the token', () => {
  assert.equal(isTokenGoneFcm({
    status: 401,
    body: { error: { code: 401, status: 'UNAUTHENTICATED', message: 'Request had invalid authentication credentials.' } }
  }), false);
});

test('a 404 with no details is read as a dead token', () => {
  // The project and the endpoint are ours, so nothing else on that request can
  // be missing.
  assert.equal(isTokenGoneFcm({ status: 404, body: {} }), true);
});

test('an unparseable response keeps the token', () => {
  assert.equal(isTokenGoneFcm({ status: 502, body: {} }), false);
});

test('the FCM error code is read out of the details array', () => {
  assert.equal(fcmErrorCode(fcmError(404, 'UNREGISTERED').body), 'UNREGISTERED');
  assert.equal(fcmErrorCode({ error: { status: 'NOT_FOUND' } }), '');
  assert.equal(fcmErrorCode({}), '');
  assert.equal(fcmErrorCode(undefined), '');
});
