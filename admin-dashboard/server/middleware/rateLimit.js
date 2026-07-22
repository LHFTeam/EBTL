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

// Mounted at /api/customer, so req.path is relative to that (e.g. `/session`,
// `/cart/items`). The Geidea callback lives at /api/payments/... and never
// reaches here, so it is not rate limited.
export function customerRateLimiter(req, res, next) {
  if (req.method === 'POST' && req.path === '/session') {
    return sessionLimiter(req, res, next);
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return writeLimiter(req, res, next);
  }

  return next();
}
