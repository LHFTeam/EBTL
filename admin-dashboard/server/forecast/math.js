// Pure statistical primitives. No I/O, no Supabase, no dates, no config lookups
// — everything arrives as arguments and everything is deterministic, which is
// what makes this file the one part of the model that can be tested against
// results worked out by hand (see math.test.js).

// --------------------------------------------------------------------------
// Basics
// --------------------------------------------------------------------------

export function clamp(value, min, max) {
  if (!Number.isFinite(value)) return min;
  return Math.min(max, Math.max(min, value));
}

export function mean(values) {
  if (!values.length) return 0;
  return values.reduce((sum, v) => sum + v, 0) / values.length;
}

// --------------------------------------------------------------------------
// Shrinkage
//
// The single most important operation in this model. With 84 units of sales
// history, almost every cell the model is asked about has too little data to
// estimate on its own; shrinkage is what lets it answer anyway without
// pretending. `weight` is n/(n+k) — an estimate backed by n observations is
// pulled toward a pooled prior, and the pull only relaxes as n grows. This is
// the James-Stein / Efron-Morris result, and it is why the model needs no
// special "not enough data" branch: at n=0 it returns exactly the prior, and it
// converges on the estimate as n goes to infinity, continuously and with no
// threshold anywhere.
// --------------------------------------------------------------------------

export function shrinkWeight(observations, k) {
  const n = Math.max(0, Number(observations) || 0);
  const strength = Math.max(0, Number(k) || 0);
  if (n + strength === 0) return 0;
  return n / (n + strength);
}

export function shrink(estimate, prior, observations, k) {
  const w = shrinkWeight(observations, k);
  return w * estimate + (1 - w) * prior;
}

// Multiplicative quantities (uplifts, seasonal factors) are shrunk in log space,
// where the weighted mean is a geometric mean. That is the right centre for a
// ratio — averaging 0.5x and 2.0x should give 1.0x, not 1.25x — and it cannot
// produce a negative multiplier however the weights fall.
export function shrinkLog(estimate, prior, observations, k) {
  const safeEstimate = estimate > 0 ? estimate : prior;
  if (!(safeEstimate > 0) || !(prior > 0)) return 1;
  return Math.exp(shrink(Math.log(safeEstimate), Math.log(prior), observations, k));
}

// --------------------------------------------------------------------------
// Seasonal factors
// --------------------------------------------------------------------------

// Rescale so the factors average exactly 1. Multiplicative Holt-Winters drifts
// without this — level and seasonality are only identified up to a constant, so
// nothing stops the two absorbing each other over time (Archibald & Koehler
// 2003). Renormalising after every update pins them apart.
export function renormaliseSeasonal(factors) {
  const positive = factors.map((f) => (Number.isFinite(f) && f > 0 ? f : 1));
  const avg = mean(positive);
  if (!(avg > 0)) return positive.map(() => 1);
  return positive.map((f) => f / avg);
}

// One Holt-Winters multiplicative step (Winters 1960).
//
// The observation is deseasonalised before it touches the level, and the level
// is used to re-estimate that weekday's factor. Both are exponentially
// weighted, so old data fades rather than being dropped at a window edge.
//
// `seasonalFactor` is the factor actually used for the day, which is the shrunk
// one, not the raw stored one — the level must be deseasonalised by the same
// number the forecast was built from, or the residual is measuring the
// shrinkage rather than the error.
export function wintersStep({ level, seasonal, dow, value, seasonalFactor, alpha, gamma }) {
  const factor = seasonalFactor > 0 ? seasonalFactor : 1;
  const deseasonalised = value / factor;

  // First real observation: seed the level rather than smoothing from zero,
  // which would otherwise take a dozen days to climb to a sensible magnitude.
  const nextLevel = level > 0
    ? alpha * deseasonalised + (1 - alpha) * level
    : deseasonalised;

  const nextSeasonal = seasonal.slice();
  if (nextLevel > 0) {
    const observedFactor = value / nextLevel;
    nextSeasonal[dow] = gamma * observedFactor + (1 - gamma) * nextSeasonal[dow];
  }

  return { level: nextLevel, seasonal: renormaliseSeasonal(nextSeasonal) };
}

// --------------------------------------------------------------------------
// Dirichlet-multinomial product mix
//
// Rather than fit 69 sparse per-product time series, forecast each product's
// SHARE of its cart's volume. The Dirichlet is conjugate to the multinomial, so
// "observe today's units" is one addition per product, and the exponential
// forgetting factor makes old evidence fade so a changing menu needs no refit.
//
// The prior is what stops the model asserting a hard zero for the 48 active
// products that have never sold.
// --------------------------------------------------------------------------

export function dirichletUpdate(alphas, observed, forgetting) {
  const next = new Map();
  const rho = clamp(forgetting, 0, 1);

  for (const [key, value] of alphas) {
    next.set(key, value * rho);
  }
  for (const [key, units] of observed) {
    next.set(key, (next.get(key) || 0) + Math.max(0, units));
  }
  return next;
}

export function dirichletShares(alphas) {
  let total = 0;
  for (const value of alphas.values()) total += Math.max(0, value);

  const shares = new Map();
  if (!(total > 0)) {
    // No evidence and no prior at all: spread evenly rather than divide by zero.
    const even = alphas.size ? 1 / alphas.size : 0;
    for (const key of alphas.keys()) shares.set(key, even);
    return shares;
  }
  for (const [key, value] of alphas) shares.set(key, Math.max(0, value) / total);
  return shares;
}

// Rescale a share map to sum to 1. Used after campaign uplifts are applied to
// individual products: because shares are renormalised, promoting one product
// mechanically takes share from the others, so cannibalisation falls out of the
// model instead of needing a term of its own.
export function normaliseShares(shares) {
  let total = 0;
  for (const value of shares.values()) total += Math.max(0, value);

  const out = new Map();
  if (!(total > 0)) return out;
  for (const [key, value] of shares) out.set(key, Math.max(0, value) / total);
  return out;
}

// --------------------------------------------------------------------------
// Negative binomial predictive distribution
//
// Demand is a count, usually a small one, and over-dispersed relative to
// Poisson. A normal interval would put probability on negative sales and get
// the tail wrong exactly where the stocking decision is made.
//
// Parameterised by mean mu and dispersion phi, with Var = mu + phi*mu^2. phi=0
// collapses to Poisson, which is the right behaviour when residuals show no
// excess variance rather than a special case to branch on.
// --------------------------------------------------------------------------

// PMF as an ascending sequence, computed by recurrence to avoid gamma functions
// and the overflow that comes with them.
function* countPmf(muInput, dispersion) {
  const mu = Math.max(0, muInput);
  if (mu === 0) {
    yield 1;
    return;
  }

  if (!(dispersion > 0)) {
    // Poisson: P(0) = e^-mu, P(k) = P(k-1) * mu / k
    let p = Math.exp(-mu);
    let k = 0;
    while (true) {
      yield p;
      k += 1;
      p = (p * mu) / k;
    }
  }

  // Negative binomial: r = 1/phi successes, p = r/(r+mu)
  const r = 1 / dispersion;
  const prob = r / (r + mu);
  let p = Math.pow(prob, r);
  let k = 0;
  while (true) {
    yield p;
    k += 1;
    p = (p * (k - 1 + r) * (1 - prob)) / k;
  }
}

// Smallest k with CDF(k) >= q.
//
// Summed exactly rather than approximated. The counts here are single digits,
// which is precisely where a normal approximation is worst and where summing
// costs nothing. The iteration cap is a safety net for a pathological mean, not
// part of the maths.
export function countQuantile(mu, dispersion, quantile) {
  const q = clamp(quantile, 0, 0.999999);
  const maxIterations = 100_000;

  let cumulative = 0;
  let k = 0;
  for (const p of countPmf(mu, dispersion)) {
    cumulative += p;
    if (cumulative >= q) return k;
    k += 1;
    if (k > maxIterations) return k;
  }
  return k;
}

// Method-of-moments dispersion from Pearson residuals: E[(y-mu)^2] = mu + phi*mu^2,
// so phi = mean((y-mu)^2 - mu) / mean(mu^2). Negative estimates mean the data is
// under-dispersed relative to Poisson, which for demand is a small-sample
// artefact rather than a finding — floored at 0, i.e. back to Poisson.
export function dispersionFromResiduals(residualSumSq, sumMuSquared, sumMu, count) {
  if (!count || !(sumMuSquared > 0)) return 0;
  const excess = residualSumSq - sumMu;
  if (!(excess > 0)) return 0;
  return excess / sumMuSquared;
}

// --------------------------------------------------------------------------
// Scoring
// --------------------------------------------------------------------------

// Pinball (quantile) loss. Scores a quantile forecast on its own terms:
// under-forecasting a P90 is penalised 9x as heavily as over-forecasting it,
// which is the asymmetry a stocking number is supposed to encode. Judging a P90
// by absolute error would be judging it by the wrong thing.
export function pinballLoss(actual, forecast, quantile) {
  const q = clamp(quantile, 0, 1);
  const diff = actual - forecast;
  return diff >= 0 ? q * diff : (q - 1) * diff;
}

// MASE (Hyndman & Koehler 2006): mean absolute error over the mean absolute
// error of a seasonal-naive baseline. Scale-free, so it can be averaged across
// carts of wildly different size, and — unlike MAPE — defined on the zero-demand
// days that dominate this dataset.
//
// A MASE of 1 means "no better than predicting last Tuesday". Anything at or
// above 1 is worth surfacing rather than hiding: it is the honest signal that
// the model has not yet earned its place.
export function mase(absErrors, naiveAbsErrors) {
  const naiveMean = mean(naiveAbsErrors.filter((e) => Number.isFinite(e)));
  if (!(naiveMean > 0)) return null;
  return mean(absErrors.filter((e) => Number.isFinite(e))) / naiveMean;
}
