import crypto from 'crypto';
import { SESSION_SECRET } from '../config/appConfig.js';

// The pickup code a customer shows at the cart, in both the forms it takes: the
// QR the attendant scans, and the six digits printed under it for when the
// camera or the screen will not cooperate.
//
// Both are derived, not stored. The code for an order is a function of the
// order id, a thirty-second time window, and SESSION_SECRET — the same HMAC
// primitive `session.js` uses for dashboard cookies. Nothing is written when a
// code is issued, so the app can ask for one as often as it likes, and the
// server can verify one it has never seen.
//
// Deriving from a window rather than minting a random nonce is what makes the
// six-digit fallback possible at all: the server can recompute the digits for
// an order, which it could not do for a random value it never kept. The window
// is also the rotation — a screenshotted code stops working on its own, which
// is the whole defence against a code forwarded to the next beach.
//
// Three windows are accepted, so a code is good for the ninety seconds after
// the window it was minted in. That is long enough to cross a beach and short
// enough that a forwarded screenshot is useless.

const WINDOW_MS = 30_000;
const ACCEPTED_WINDOWS = 3;
const SHORT_CODE_DIGITS = 6;
const TOKEN_VERSION = 1;

// version + order id + window + truncated signature. Deliberately compact: this
// is scanned off a phone screen in direct sun, and every byte is QR density the
// attendant's camera has to resolve.
const SIGNATURE_BYTES = 16;
const TOKEN_BYTES = 1 + 16 + 4 + SIGNATURE_BYTES;

export const PICKUP_CODE_REFRESH_MS = WINDOW_MS;
export const PICKUP_CODE_LIFETIME_MS = WINDOW_MS * ACCEPTED_WINDOWS;

function uuidToBytes(value) {
  const hex = String(value || '').replace(/-/g, '');
  if (!/^[0-9a-f]{32}$/i.test(hex)) return null;
  return Buffer.from(hex, 'hex');
}

function bytesToUuid(buffer) {
  const hex = buffer.toString('hex');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20)
  ].join('-');
}

function digestFor(orderId, window) {
  return crypto
    .createHmac('sha256', SESSION_SECRET)
    .update(`pickup.v${TOKEN_VERSION}.${orderId}.${window}`)
    .digest();
}

function equalBuffers(a, b) {
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export function pickupWindowAt(at = Date.now()) {
  return Math.floor(at / WINDOW_MS);
}

/**
 * Windows a code may still be presented in, newest first. A code minted in the
 * current window stays good for the two that follow it.
 */
export function acceptedWindowsAt(at = Date.now()) {
  const current = pickupWindowAt(at);
  return Array.from({ length: ACCEPTED_WINDOWS }, (_, index) => current - index);
}

/**
 * The handoff's replay key. Deterministic per order and window, so spending a
 * code is recorded as a row `order_handoffs.token_nonce` can hold unique — one
 * code, one handoff, even inside its ninety seconds.
 */
export function pickupNonce(orderId, window) {
  return digestFor(orderId, window).subarray(0, 12).toString('base64url');
}

function shortCodeFrom(digest) {
  // Truncation exactly as HOTP does it: take the low nibble of the last byte as
  // an offset, read a 31-bit integer from there, and keep the last six digits.
  const offset = digest[digest.length - 1] & 0x0f;
  const binary = digest.readUInt32BE(offset) & 0x7fffffff;
  return String(binary % 10 ** SHORT_CODE_DIGITS).padStart(SHORT_CODE_DIGITS, '0');
}

/**
 * Issues the code for an order at a moment in time. Pure — nothing is stored,
 * and asking twice inside one window returns the same code.
 */
export function encodePickupCode({ orderId, at = Date.now() }) {
  const orderBytes = uuidToBytes(orderId);
  if (!orderBytes) return null;

  const window = pickupWindowAt(at);
  const digest = digestFor(orderId, window);

  const payload = Buffer.alloc(TOKEN_BYTES);
  payload.writeUInt8(TOKEN_VERSION, 0);
  orderBytes.copy(payload, 1);
  payload.writeUInt32BE(window, 17);
  digest.copy(payload, 21, 0, SIGNATURE_BYTES);

  return {
    token: payload.toString('base64url'),
    short_code: shortCodeFrom(digest),
    nonce: pickupNonce(orderId, window),
    // When the code the customer is looking at stops being accepted, and when
    // the app should have replaced it. The gap between the two is the margin.
    expires_at: new Date((window + ACCEPTED_WINDOWS) * WINDOW_MS).toISOString(),
    refresh_after_ms: PICKUP_CODE_REFRESH_MS
  };
}

/**
 * Reads a scanned QR back.
 *
 * Returns `{ ok: true, order_id, window, nonce }`, or `{ ok: false, reason }`
 * where reason is `malformed`, `signature` or `expired`. The three are kept
 * apart because only staff see them, and an attendant needs "ask them to
 * refresh" to read differently from "that is not one of ours" — one is a
 * customer waiting ten more seconds, the other is a conversation.
 *
 * The signature is checked before the window, so `expired` is only ever said
 * about a code this server really did issue.
 */
export function decodePickupToken(token, { at = Date.now() } = {}) {
  let payload;
  try {
    payload = Buffer.from(String(token || ''), 'base64url');
  } catch {
    return { ok: false, reason: 'malformed' };
  }

  if (payload.length !== TOKEN_BYTES) return { ok: false, reason: 'malformed' };
  if (payload.readUInt8(0) !== TOKEN_VERSION) return { ok: false, reason: 'malformed' };

  const orderId = bytesToUuid(payload.subarray(1, 17));
  const window = payload.readUInt32BE(17);
  const signature = payload.subarray(21);

  if (!equalBuffers(signature, digestFor(orderId, window).subarray(0, SIGNATURE_BYTES))) {
    return { ok: false, reason: 'signature' };
  }

  if (!acceptedWindowsAt(at).includes(window)) return { ok: false, reason: 'expired' };

  return { ok: true, order_id: orderId, window, nonce: pickupNonce(orderId, window) };
}

/**
 * Checks six typed digits against an order the caller has already identified
 * (by order number, at their own cart). Six digits is a far weaker secret than
 * the QR, which is why this path is rate limited and why the attendant has to
 * know a live order number at their own cart to use it at all.
 */
export function verifyPickupShortCode({ orderId, shortCode, at = Date.now() }) {
  const candidate = String(shortCode || '').trim();
  if (!/^\d{6}$/.test(candidate)) return null;
  if (!uuidToBytes(orderId)) return null;

  const attempt = Buffer.from(candidate);

  for (const window of acceptedWindowsAt(at)) {
    const expected = Buffer.from(shortCodeFrom(digestFor(orderId, window)));
    if (equalBuffers(attempt, expected)) {
      return { order_id: orderId, window, nonce: pickupNonce(orderId, window) };
    }
  }

  return null;
}
