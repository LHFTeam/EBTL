import test from 'node:test';
import assert from 'node:assert/strict';

// `pickupToken.js` imports `appConfig.js`, which refuses to load without
// Supabase credentials. CI has no secrets, so stand in placeholders and import
// dynamically — a static import would be hoisted above these lines and throw
// before they ran. The functions under test are pure; nothing here opens a
// connection or touches the network.
process.env.SUPABASE_URL ||= 'http://supabase.invalid';
process.env.SUPABASE_SERVICE_ROLE_KEY ||= 'test-key';

const {
  PICKUP_CODE_LIFETIME_MS,
  decodePickupToken,
  encodePickupCode,
  pickupNonce,
  pickupWindowAt,
  verifyPickupShortCode
} = await import('./pickupToken.js');

// This code is the only thing standing between a paid order and whoever asks
// for it at the cart, so what matters is that a real code opens exactly one
// order, and that everything else — a tampered one, an old one, someone else's
// — does not.

const ORDER = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';
const OTHER_ORDER = '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d';
const AT = Date.UTC(2026, 7, 15, 13, 0, 0);

test('a freshly issued code opens the order it was issued for', () => {
  const code = encodePickupCode({ orderId: ORDER, at: AT });

  assert.deepEqual(decodePickupToken(code.token, { at: AT }), {
    ok: true,
    order_id: ORDER,
    window: pickupWindowAt(AT),
    nonce: code.nonce
  });
  assert.equal(verifyPickupShortCode({ orderId: ORDER, shortCode: code.short_code, at: AT })?.order_id, ORDER);
});

test('the same order inside one window gets the same code', () => {
  // The app re-asks on a timer and on every screen open. Handing back a new
  // code each time would mean the QR on screen and the digits under it could
  // drift apart mid-scan.
  const first = encodePickupCode({ orderId: ORDER, at: AT });
  const second = encodePickupCode({ orderId: ORDER, at: AT + 5_000 });

  assert.equal(first.token, second.token);
  assert.equal(first.short_code, second.short_code);
});

test('another order never shares a code', () => {
  const code = encodePickupCode({ orderId: ORDER, at: AT });

  assert.equal(decodePickupToken(code.token, { at: AT }).order_id, ORDER);
  assert.equal(verifyPickupShortCode({ orderId: OTHER_ORDER, shortCode: code.short_code, at: AT }), null);
});

test('a code still works while the customer walks over, and stops soon after', () => {
  const code = encodePickupCode({ orderId: ORDER, at: AT });

  // Comfortably inside the window it was minted in.
  assert.equal(decodePickupToken(code.token, { at: AT + 20_000 }).ok, true);
  assert.ok(verifyPickupShortCode({ orderId: ORDER, shortCode: code.short_code, at: AT + 20_000 }));

  // Past the accepted windows, both forms are dead. This is what makes a
  // screenshot forwarded to a friend worthless. AT sits on a window boundary,
  // so this code gets the full lifetime and not a millisecond more.
  const expired = AT + PICKUP_CODE_LIFETIME_MS;
  assert.deepEqual(decodePickupToken(code.token, { at: expired }), { ok: false, reason: 'expired' });
  assert.equal(verifyPickupShortCode({ orderId: ORDER, shortCode: code.short_code, at: expired }), null);
});

test('a tampered signature is refused', () => {
  const code = encodePickupCode({ orderId: ORDER, at: AT });
  const bytes = Buffer.from(code.token, 'base64url');
  bytes[bytes.length - 1] ^= 0xff;

  // Told apart from an expired code, because the attendant acts differently on
  // each: one is worth waiting ten seconds for, the other never will be.
  assert.deepEqual(decodePickupToken(bytes.toString('base64url'), { at: AT }), { ok: false, reason: 'signature' });
});

test('swapping the order id into someone else\'s token is refused', () => {
  // The signature covers the order id, so re-pointing a valid token at another
  // order breaks it — a customer cannot turn their own code into a claim on the
  // order behind them in the queue.
  const code = encodePickupCode({ orderId: ORDER, at: AT });
  const bytes = Buffer.from(code.token, 'base64url');
  Buffer.from(OTHER_ORDER.replace(/-/g, ''), 'hex').copy(bytes, 1);

  assert.deepEqual(decodePickupToken(bytes.toString('base64url'), { at: AT }), { ok: false, reason: 'signature' });
});

test('junk in place of a token is refused rather than thrown at', () => {
  for (const value of [null, undefined, '', 'not-a-token', 'AAAA']) {
    assert.deepEqual(decodePickupToken(value, { at: AT }), { ok: false, reason: 'malformed' });
  }

  // Right length, wrong everything else: shape alone proves nothing.
  assert.equal(decodePickupToken(Buffer.alloc(37).toString('base64url'), { at: AT }).ok, false);
});

test('a short code is six digits, and nothing else is accepted', () => {
  const code = encodePickupCode({ orderId: ORDER, at: AT });

  assert.match(code.short_code, /^\d{6}$/);

  for (const value of [null, '', '12345', '1234567', 'abcdef', ' 123456 ', code.short_code.slice(1)]) {
    assert.equal(verifyPickupShortCode({ orderId: ORDER, shortCode: value, at: AT }), null);
  }
});

test('the nonce is stable per window and changes with it', () => {
  // It is the replay key: the unique index on order_handoffs.token_nonce is
  // what stops one code closing two orders, so it has to be the same value
  // however the code was presented, and a different one next window.
  const window = pickupWindowAt(AT);
  const code = encodePickupCode({ orderId: ORDER, at: AT });

  assert.equal(code.nonce, pickupNonce(ORDER, window));
  assert.equal(decodePickupToken(code.token, { at: AT }).nonce, code.nonce);
  assert.equal(verifyPickupShortCode({ orderId: ORDER, shortCode: code.short_code, at: AT }).nonce, code.nonce);
  assert.notEqual(pickupNonce(ORDER, window + 1), code.nonce);
  assert.notEqual(pickupNonce(OTHER_ORDER, window), code.nonce);
});

test('a malformed order id yields no code at all', () => {
  assert.equal(encodePickupCode({ orderId: 'not-a-uuid', at: AT }), null);
  assert.equal(encodePickupCode({ orderId: null, at: AT }), null);
});
