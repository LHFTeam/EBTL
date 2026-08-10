// Every tunable the forecasting model has, in one place, with the reasoning for
// each default. Nothing else in the module hardcodes a constant.
//
// The defaults are chosen for a business with very little history. At the time
// of writing that is 84 units sold across 11 trading days and 2 carts. Smoothing
// constants are therefore small and prior strengths large: at this sample size a
// responsive filter is an amplifier for noise, not a feature.

function num(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

// Bumped whenever a change would make today's forecasts incomparable with
// yesterday's. Stamped onto every forecast row so an accuracy series that spans
// a model change is not read as one continuous experiment.
export const MODEL_VERSION = '1.0.0';

export const BUSINESS_TIME_ZONE = 'Africa/Cairo';

export const config = {
  // --- Level 1: cart-day volume -------------------------------------------

  // Holt-Winters smoothing constants. Low, deliberately: alpha 0.15 gives the
  // level a half-life of roughly 4 trading days, which tracks a real trend
  // without chasing a single busy Friday. gamma is lower still because a
  // weekday factor gets one observation per week — it must not lurch.
  alpha: num(process.env.FORECAST_ALPHA, 0.15),
  gamma: num(process.env.FORECAST_GAMMA, 0.05),

  // Shrinkage half-weight for weekday factors: a weekday needs `dowShrinkK`
  // observations before its own factor outweighs the pooled network profile.
  // Eight means "about two months of Fridays", which is roughly when a weekday
  // pattern becomes believable rather than a coincidence of two data points.
  dowShrinkK: num(process.env.FORECAST_DOW_SHRINK_K, 8),

  // Strength of the manager's planning assumption, in pseudo-days. The cart
  // needs this many real trading days before its own level outweighs what the
  // manager said to expect.
  levelPriorDays: num(process.env.FORECAST_LEVEL_PRIOR_DAYS, 14),

  // --- Level 2: product mix ------------------------------------------------

  // Dirichlet forgetting factor. 0.97/day is a ~23-day half-life: old mix
  // evidence fades fast enough to follow a changing menu and seasonal taste,
  // slowly enough that one quiet week does not rewrite the ranking.
  mixForgetting: num(process.env.FORECAST_MIX_FORGETTING, 0.97),

  // Total pseudo-units in the mix prior, spread across products by the pooled
  // network mix. Twenty is about a quarter of all units ever sold — high on
  // purpose, because the alternative is asserting a hard zero for the 48 active
  // products that have never sold.
  mixPriorStrength: num(process.env.FORECAST_MIX_PRIOR_STRENGTH, 20),

  // Floor on any single product's prior share, so a brand-new product is never
  // seeded at exactly zero and can climb out on its first sale.
  mixPriorFloor: num(process.env.FORECAST_MIX_PRIOR_FLOOR, 0.001),

  // --- Level 3: uncertainty ------------------------------------------------

  // The stocking quantile. 0.9 is the newsvendor critical fractile Cu/(Cu+Co) —
  // asserting a stockout costs about 9x carrying a spare kit. A beach cart
  // cannot restock mid-day, which is what justifies a number this high.
  serviceQuantile: num(process.env.FORECAST_SERVICE_QUANTILE, 0.9),

  // Negative-binomial dispersion bounds. 0 is pure Poisson; the cap stops a
  // couple of freak days producing an interval so wide it is useless.
  minDispersion: num(process.env.FORECAST_MIN_DISPERSION, 0),
  maxDispersion: num(process.env.FORECAST_MAX_DISPERSION, 4),

  // --- Campaigns -----------------------------------------------------------

  // Pseudo-observations behind a campaign's planned uplift. Five days of the
  // campaign actually running are needed before measurement outweighs the plan,
  // which stops a single unusual day rewriting the lift.
  campaignPriorObs: num(process.env.FORECAST_CAMPAIGN_PRIOR_OBS, 5),

  // Hard clamps on any learned lift. A measured 12x uplift is a data problem,
  // not a marketing triumph, and must not reach a stocking decision.
  minUplift: num(process.env.FORECAST_MIN_UPLIFT, 0.5),
  maxUplift: num(process.env.FORECAST_MAX_UPLIFT, 5),

  // --- Horizon and scheduling ---------------------------------------------

  forecastHorizonDays: num(process.env.FORECAST_HORIZON_DAYS, 14),

  // How often to check whether the Cairo business date has rolled over. Polling
  // beats a fire-at-midnight timer: it survives restarts, deploys and multi-day
  // outages, all of which silently skip a one-shot timer.
  schedulerIntervalMinutes: num(process.env.FORECAST_SCHEDULER_INTERVAL_MINUTES, 15),

  // Delay before the first check, to stay out of the way of a cold start. Same
  // reasoning as lib/pendingOrderCleanup.js.
  schedulerFirstRunDelayMs: num(process.env.FORECAST_SCHEDULER_FIRST_RUN_DELAY_MS, 90_000),

  // Cap on how much history one catch-up run will replay, so a long outage
  // cannot turn a nightly job into an unbounded backfill. Anything older is
  // picked up by the next run.
  maxCatchUpDays: num(process.env.FORECAST_MAX_CATCH_UP_DAYS, 60),

  // --- Confidence reporting -----------------------------------------------

  // Trading days behind a cart's estimate before its forecast stops being
  // labelled 'low'. These thresholds exist so a number built from two
  // observations never appears on screen looking like one built from two
  // hundred.
  confidenceMediumDays: num(process.env.FORECAST_CONFIDENCE_MEDIUM_DAYS, 21),
  confidenceHighDays: num(process.env.FORECAST_CONFIDENCE_HIGH_DAYS, 56)
};

// Discount depth buckets. Campaign lift is pooled within a bucket rather than
// regressed on depth: fitting an elasticity curve to a handful of campaigns
// would be inventing precision. Buckets are the honest version, and elasticity
// is the documented upgrade once campaigns number in the dozens.
export function discountBucket(discountPct) {
  const pct = Number(discountPct);
  if (!Number.isFinite(pct) || pct <= 0) return 'none';
  if (pct < 10) return 'lt10';
  if (pct < 20) return '10_20';
  if (pct < 30) return '20_30';
  if (pct < 50) return '30_50';
  return 'gte50';
}

export const campaignTypes = [
  'promo_code',
  'spotlight',
  'golden_hour',
  'social',
  'event',
  'price_cut',
  'other'
];

export const campaignScopes = ['network', 'cart', 'product'];
