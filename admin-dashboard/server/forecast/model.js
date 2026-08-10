// The model's state machine. Pure functions over plain state objects — no
// Supabase, no clock. store.js loads state in, job.js drives the recursion,
// and everything that decides a number lives here.
//
//   units(cart, date, product) = level x dow[dow] x U(campaigns) x share_p
//
// Each factor is shrunk toward a pooled prior by n/(n+k). That is not
// decoration: with ~966 (cart x product x weekday) cells and 84 units of
// history, fitting the cells independently would be fitting noise and
// presenting it as insight. Shrinkage means the model answers every question it
// is asked, with the prior when that is all it has, and sharpens on its own as
// evidence arrives — with no thresholds and no "insufficient data" branch.

import {
  clamp,
  countQuantile,
  dirichletShares,
  dirichletUpdate,
  shrink
} from './math.js';
import { applyProductUplifts, cartUplift, productUplifts } from './campaigns.js';
import { config } from './config.js';
import { dayOfWeek } from './businessDate.js';

const NEUTRAL_WEEK = [1, 1, 1, 1, 1, 1, 1];

export function emptyCartState(locationId) {
  return {
    location_id: locationId,
    level: 0,
    dispersion: 0,
    dow_index: NEUTRAL_WEEK.slice(),
    dow_obs_count: [0, 0, 0, 0, 0, 0, 0],
    observations: 0,
    residual_sum_sq: 0,
    residual_count: 0,
    last_business_date: null
  };
}

export function emptyNetworkState() {
  return {
    dow_index: NEUTRAL_WEEK.slice(),
    dow_obs_count: [0, 0, 0, 0, 0, 0, 0],
    mean_level: 0,
    dispersion: 0,
    product_mix: {},
    observations: 0
  };
}

// --------------------------------------------------------------------------
// Effective (shrunk) parameters
// --------------------------------------------------------------------------

// The weekday factor actually used. Two stages of shrinkage, because both the
// cart's own estimate and the network's are thin:
//
//   1. the pooled network profile is pulled toward 1.0 by its own sample size,
//      so with almost no data the whole network claims a flat week;
//   2. the cart's factor is pulled toward that pooled profile.
//
// The consequence today is that every weekday factor sits at ~1.0 — the model
// correctly reports that it does not yet know Friday from Tuesday, rather than
// inventing a weekend effect from two Fridays.
export function effectiveDowIndex(cartState, networkState) {
  return NEUTRAL_WEEK.map((_, dow) => {
    const pooled = shrink(
      Number(networkState.dow_index[dow]) || 1,
      1,
      Number(networkState.dow_obs_count[dow]) || 0,
      config.dowShrinkK
    );
    return shrink(
      Number(cartState.dow_index[dow]) || 1,
      pooled,
      Number(cartState.dow_obs_count[dow]) || 0,
      config.dowShrinkK
    );
  });
}

// The cart's level, pulled toward the network mean. This is what carries a cart
// like Marassi — two orders in its entire life — on the network's shoulders
// instead of forecasting near-zero for it forever.
export function effectiveLevel(cartState, networkState) {
  const prior = Number(networkState.mean_level) || 0;
  if (!(prior > 0)) return Number(cartState.level) || 0;
  return shrink(Number(cartState.level) || 0, prior, cartState.observations, config.levelPriorDays);
}

export function effectiveDispersion(cartState, networkState) {
  const value = shrink(
    Number(cartState.dispersion) || 0,
    Number(networkState.dispersion) || 0,
    cartState.residual_count,
    config.levelPriorDays
  );
  return clamp(value, config.minDispersion, config.maxDispersion);
}

export function confidenceFor(observations) {
  if (observations >= config.confidenceHighDays) return 'high';
  if (observations >= config.confidenceMediumDays) return 'medium';
  return 'low';
}

// --------------------------------------------------------------------------
// Forecasting
// --------------------------------------------------------------------------

// Expected units for a cart on a date, before any campaign lift.
//
// The manager's planning assumption for that weekday enters here as the prior,
// with its own per-row strength: it dominates on day one and fades on its own as
// real trading days accumulate, so nobody has to remember to go and delete it.
// That is the whole reason the model is useful before it has data.
export function baselineCartUnits({ cartState, networkState, assumption, dow }) {
  const level = effectiveLevel(cartState, networkState);
  const dowFactor = effectiveDowIndex(cartState, networkState)[dow];
  const modelled = level * dowFactor;

  const planned = assumption ? Number(assumption.expected_units) : null;
  if (!Number.isFinite(planned) || planned < 0) return modelled;

  const strength = Math.max(1, Number(assumption.prior_strength_days) || config.levelPriorDays);
  return shrink(modelled, planned, cartState.observations, strength);
}

// Full cart-day forecast, campaigns included.
export function forecastCartDay({
  cartState,
  networkState,
  assumption,
  campaigns,
  effects,
  locationId,
  dateKey,
  horizonDays
}) {
  const dow = dayOfWeek(dateKey);
  const baseline = baselineCartUnits({ cartState, networkState, assumption, dow });
  const { uplift, campaignIds } = cartUplift(campaigns, locationId, dateKey, effects);

  const expectedUnits = Math.max(0, baseline * uplift);
  const dispersion = effectiveDispersion(cartState, networkState);

  return {
    location_id: locationId,
    business_date: dateKey,
    horizon_days: horizonDays,
    expected_units: expectedUnits,
    baseline_units: baseline,
    p50: countQuantile(expectedUnits, dispersion, 0.5),
    p90: countQuantile(expectedUnits, dispersion, config.serviceQuantile),
    campaign_uplift: uplift,
    campaign_ids: campaignIds,
    confidence: confidenceFor(cartState.observations),
    sample_size: cartState.observations,
    dispersion
  };
}

// --------------------------------------------------------------------------
// Product mix
// --------------------------------------------------------------------------

// The Dirichlet posterior: stored alpha holds accumulated (and forgotten)
// evidence, and the prior is added here at use time rather than baked into the
// stored value. That way the pooled network mix can improve and every cart's
// prior improves with it — including for products that cart has never sold.
export function posteriorAlphas({ productStates, networkMix, activeProductIds }) {
  const priorShares = new Map();
  let priorTotal = 0;
  for (const productId of activeProductIds) {
    const share = Math.max(Number(networkMix[productId]) || 0, config.mixPriorFloor);
    priorShares.set(productId, share);
    priorTotal += share;
  }

  const alphas = new Map();
  for (const productId of activeProductIds) {
    const prior = priorTotal > 0
      ? (config.mixPriorStrength * priorShares.get(productId)) / priorTotal
      : 0;
    const evidence = Number(productStates.get(productId)?.alpha) || 0;
    alphas.set(productId, prior + evidence);
  }
  return alphas;
}

// Shares for a cart-date, with product-targeted campaigns applied and
// renormalised — so promoting one cocktail necessarily takes share from the
// rest.
export function forecastProductShares({
  productStates,
  networkMix,
  activeProductIds,
  campaigns,
  effects,
  locationId,
  dateKey
}) {
  const alphas = posteriorAlphas({ productStates, networkMix, activeProductIds });
  const shares = dirichletShares(alphas);
  const uplifts = productUplifts(campaigns, locationId, dateKey, effects);
  return applyProductUplifts(shares, uplifts);
}

// Per-product forecasts for one cart-day.
//
// Note what is NOT done here: the cart's p90 is not the sum of these p90s.
// Quantiles do not add — summing them would authorise stocking for a day where
// every product simultaneously hits its 90th percentile, which is not a day that
// happens. Each level's quantile comes from its own distribution.
export function forecastProductsForDay({ cartForecast, shares, dispersion, priceByProduct, meanPrice }) {
  const rows = [];
  for (const [productId, share] of shares) {
    const expected = cartForecast.expected_units * share;
    if (!(expected > 0)) continue;

    const price = Number(priceByProduct.get(productId)) || meanPrice || 0;
    rows.push({
      location_id: cartForecast.location_id,
      business_date: cartForecast.business_date,
      product_id: productId,
      horizon_days: cartForecast.horizon_days,
      mix_share: share,
      expected_units: expected,
      p50: countQuantile(expected, dispersion, 0.5),
      p90: countQuantile(expected, dispersion, config.serviceQuantile),
      expected_revenue: expected * price,
      campaign_uplift: cartForecast.campaign_uplift,
      confidence: cartForecast.confidence,
      sample_size: cartForecast.sample_size
    });
  }
  return rows;
}

// --------------------------------------------------------------------------
// State advance
// --------------------------------------------------------------------------

// One day of evidence into one cart's state.
//
// Three rules that matter more than the arithmetic:
//
//   1. A date at or before last_business_date is ignored. Exponential smoothing
//      is order-dependent, so a double-applied day silently corrupts the level
//      with nothing to show for it. This gate is what makes the nightly job safe
//      to run twice.
//   2. A day the cart did not trade is skipped entirely. A closed day is missing
//      data, not a zero-demand observation, and feeding it in as zero would drag
//      the level down for every cart that takes a day off.
//   3. The recursion consumes BASELINE units — the day with campaign lift
//      divided out — so a promotion can never permanently inflate the level.
export function advanceCartState({ cartState, networkState, assumption, dateKey, baselineUnits, traded }) {
  if (cartState.last_business_date && dateKey <= cartState.last_business_date) {
    return { state: cartState, applied: false };
  }
  if (!traded) {
    return { state: { ...cartState, last_business_date: dateKey }, applied: false };
  }

  const dow = dayOfWeek(dateKey);
  const dowIndexUsed = effectiveDowIndex(cartState, networkState);
  const factor = dowIndexUsed[dow] > 0 ? dowIndexUsed[dow] : 1;

  // Score the day against the forecast the model would have made for it, before
  // the state absorbs it. Deferring this until after the update would be scoring
  // the model on data it has already seen.
  const expected = baselineCartUnits({ cartState, networkState, assumption, dow });
  const residual = baselineUnits - expected;

  const level = Number(cartState.level) || 0;
  const deseasonalised = baselineUnits / factor;
  const nextLevel = level > 0
    ? config.alpha * deseasonalised + (1 - config.alpha) * level
    : deseasonalised;

  const seasonal = cartState.dow_index.map(Number);
  if (nextLevel > 0) {
    const observedFactor = baselineUnits / nextLevel;
    seasonal[dow] = config.gamma * observedFactor + (1 - config.gamma) * seasonal[dow];
  }

  // Renormalise to mean 1. Level and seasonality are only identified up to a
  // constant, so without this they drift into each other (Archibald & Koehler
  // 2003).
  const seasonalMean = seasonal.reduce((sum, value) => sum + value, 0) / 7;
  const normalised = seasonalMean > 0 ? seasonal.map((value) => value / seasonalMean) : NEUTRAL_WEEK.slice();

  // Per-day method-of-moments dispersion, smoothed. Var = mu + phi*mu^2, so
  // phi_t = ((y-mu)^2 - mu) / mu^2. Negative values mean under-dispersion, which
  // at this sample size is an artefact rather than a finding — floored at 0,
  // i.e. back to Poisson.
  let dispersion = Number(cartState.dispersion) || 0;
  if (expected > 0) {
    const pointEstimate = Math.max(0, (residual * residual - expected) / (expected * expected));
    dispersion = cartState.residual_count > 0
      ? config.alpha * pointEstimate + (1 - config.alpha) * dispersion
      : pointEstimate;
  }

  const dowObsCount = cartState.dow_obs_count.map(Number);
  dowObsCount[dow] += 1;

  return {
    applied: true,
    expected,
    state: {
      ...cartState,
      level: nextLevel,
      dispersion: clamp(dispersion, config.minDispersion, config.maxDispersion),
      dow_index: normalised,
      dow_obs_count: dowObsCount,
      observations: cartState.observations + 1,
      residual_sum_sq: Number(cartState.residual_sum_sq) + residual * residual,
      residual_count: cartState.residual_count + 1,
      last_business_date: dateKey
    }
  };
}

// One day of evidence into a cart's product mix.
//
// Every product in state decays, whether or not it sold — that is what makes the
// forgetting factor a half-life rather than a penalty for being absent. Baseline
// units are used here too, so a product promoted for a weekend does not keep an
// inflated share afterwards.
export function advanceProductStates({ productStates, observedBaselineUnits, dateKey }) {
  const alphas = new Map();
  for (const [productId, state] of productStates) {
    alphas.set(productId, Number(state.alpha) || 0);
  }
  for (const productId of observedBaselineUnits.keys()) {
    if (!alphas.has(productId)) alphas.set(productId, 0);
  }

  const updated = dirichletUpdate(alphas, observedBaselineUnits, config.mixForgetting);

  const next = new Map();
  for (const [productId, alpha] of updated) {
    const previous = productStates.get(productId);
    const soldToday = (observedBaselineUnits.get(productId) || 0) > 0;
    next.set(productId, {
      alpha,
      units_ewma: config.alpha * (observedBaselineUnits.get(productId) || 0)
        + (1 - config.alpha) * (Number(previous?.units_ewma) || 0),
      observations: (previous?.observations || 0) + (soldToday ? 1 : 0),
      last_sold_date: soldToday ? dateKey : (previous?.last_sold_date || null)
    });
  }
  return next;
}

// --------------------------------------------------------------------------
// Pooled network prior
// --------------------------------------------------------------------------

// Rebuild the empirical-Bayes priors from every cart's state. This is the
// "borrow strength" half of the hierarchy: what one cart cannot establish alone,
// the network establishes jointly, and every cart's prior improves as any cart
// trades.
export function buildNetworkState({ cartStates, productMix, observations }) {
  const states = [...cartStates];
  if (!states.length) return emptyNetworkState();

  const weightedDow = NEUTRAL_WEEK.map((_, dow) => {
    let weightTotal = 0;
    let valueTotal = 0;
    for (const state of states) {
      const weight = Number(state.dow_obs_count[dow]) || 0;
      if (!weight) continue;
      weightTotal += weight;
      valueTotal += weight * (Number(state.dow_index[dow]) || 1);
    }
    return weightTotal > 0 ? valueTotal / weightTotal : 1;
  });

  // Renormalise the pooled profile too, so it is a shape rather than a shape
  // plus a scale that would double-count against mean_level.
  const dowMean = weightedDow.reduce((sum, value) => sum + value, 0) / 7;
  const dowIndex = dowMean > 0 ? weightedDow.map((value) => value / dowMean) : NEUTRAL_WEEK.slice();

  const dowObsCount = NEUTRAL_WEEK.map((_, dow) =>
    states.reduce((sum, state) => sum + (Number(state.dow_obs_count[dow]) || 0), 0));

  // Only carts that have actually traded contribute to the mean level; a cart
  // sitting untouched at zero is not evidence that carts sell nothing.
  const trading = states.filter((state) => state.observations > 0);
  const meanLevel = trading.length
    ? trading.reduce((sum, state) => sum + (Number(state.level) || 0), 0) / trading.length
    : 0;

  const dispersing = states.filter((state) => state.residual_count > 0);
  const dispersion = dispersing.length
    ? dispersing.reduce((sum, state) => sum + (Number(state.dispersion) || 0), 0) / dispersing.length
    : 0;

  return {
    dow_index: dowIndex,
    dow_obs_count: dowObsCount,
    mean_level: meanLevel,
    dispersion,
    product_mix: productMix,
    observations
  };
}

// Network-wide product mix, as shares. Seeds every cart's Dirichlet prior, which
// is how a product that has sold at Hacienda but never at Marassi still gets a
// sensible share at Marassi.
export function buildNetworkProductMix(unitsByProduct) {
  let total = 0;
  for (const units of unitsByProduct.values()) total += Math.max(0, units);
  if (!(total > 0)) return {};

  const mix = {};
  for (const [productId, units] of unitsByProduct) {
    if (units > 0) mix[productId] = Number((units / total).toFixed(6));
  }
  return mix;
}
