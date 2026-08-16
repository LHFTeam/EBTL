import { rateLimit } from 'express-rate-limit';

// Basic abuse protection for the public, unauthenticated customer API.
// The mobile app mints an anonymous bearer token from POST /customer/session
// with no other gate, so session creation and write endpoints are the flood
// surface. Reads (browsing) are intentionally left unlimited: they are the
// most frequent calls and the most likely to share a NAT'd IP (a beach
// compound behind one public address), where IP-based limiting would produce
// false positives.
//
// Limits are IP-based (express-rate-limit's default keying, which masks IPv6
// subnets) and tunable via env so ops can adjust without a redeploy of code.

function minutes(count) {
  return count * 60 * 1000;
}

function intFromEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

const tooManyRequests = (_req, res) =>
  res.status(429).json({
    error: 'Too many requests. Please slow down and try again in a moment.'
  });

const sessionLimiter = rateLimit({
  windowMs: minutes(intFromEnv('RATE_LIMIT_SESSION_WINDOW_MIN', 15)),
  max: intFromEnv('RATE_LIMIT_SESSION_MAX', 60),
  standardHeaders: true,
  legacyHeaders: false,
  handler: tooManyRequests
});

const writeLimiter = rateLimit({
  windowMs: minutes(intFromEnv('RATE_LIMIT_WRITE_WINDOW_MIN', 15)),
  max: intFromEnv('RATE_LIMIT_WRITE_MAX', 300),
  standardHeaders: true,
  legacyHeaders: false,
  handler: tooManyRequests
});

// Pickup handoffs (routes/orderRoutes.js). These sit behind an employee session
// and are not part of the customer API, so they are exported for that router to
// mount rather than going through customerRateLimiter.
//
// The QR path needs no limiting worth the name — forging a token means forging
// an HMAC. The six-digit fallback is the guessing surface: a code is one in a
// million, but only until someone tries a million times. `skipSuccessfulRequests`
// means a busy cart handing over real orders never approaches the limit, and
// only a run of failures does.
export const pickupAttemptLimiter = rateLimit({
  windowMs: minutes(intFromEnv('RATE_LIMIT_PICKUP_WINDOW_MIN', 10)),
  max: intFromEnv('RATE_LIMIT_PICKUP_MAX_FAILURES', 30),
  skipSuccessfulRequests: true,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (_req, res) =>
    res.status(429).json({
      error: 'Too many failed pickup attempts. Wait a moment, then try again or use an override.'
    })
});

// Mounted at /api/customer, so req.path is relative to that (e.g. `/session`,
// `/cart/items`). The Geidea callback lives at /api/payments/... and never
// reaches here, so it is not rate limited.
export function customerRateLimiter(req, res, next) {
  // Social sign-in mints a session the same way /session does, and is the one
  // endpoint where a wrong answer is worth brute-forcing, so it shares the
  // tighter limit rather than the general write one.
  if (req.method === 'POST' && (req.path === '/session' || req.path === '/auth/social')) {
    return sessionLimiter(req, res, next);
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return writeLimiter(req, res, next);
  }

  return next();
}
