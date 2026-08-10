// Rolling-origin evaluation (Tashman 2000).
//
// Walk the history forward one day at a time. At each origin, forecast the next
// day using only what was known before it, score, then let the state absorb the
// day and move on. Every score is genuinely out of sample, which a single
// train/test split over a series this short could not give.
//
// This runs entirely in memory against the facts tables and writes nothing.
// It is safe to run against production at any time, and it is the honest answer
// to "is this model any good?" — which, at 84 units of history, it very
// probably is not yet. Measuring and showing that is the point.

import {
  advanceCartState,
  baselineCartUnits,
  buildNetworkProductMix,
  buildNetworkState,
  effectiveDispersion,
  emptyCartState,
  emptyNetworkState
} from './model.js';
import { countQuantile, mase, mean, pinballLoss } from './math.js';
import { addDays, dateRange, dayOfWeek } from './businessDate.js';
import { cartUplift } from './campaigns.js';
import { config } from './config.js';
import * as store from './store.js';

export async function runBacktest({ from = null, to = null } = {}) {
  const [carts, campaigns, effects, assumptionsByLocation] = await Promise.all([
    store.loadBeachCarts(),
    store.loadCampaigns(),
    store.loadCampaignEffects(),
    store.loadAssumptions()
  ]);

  const activeCarts = carts.filter((cart) => cart.is_active);
  const cartFacts = await store.loadCartFacts({ from, to });
  const productFacts = await store.loadProductFacts({ from, to });

  if (!cartFacts.length) {
    return { evaluated: 0, reason: 'no demand facts — run the forecast job first' };
  }

  const factsByCartDate = new Map();
  for (const row of cartFacts) factsByCartDate.set(`${row.location_id}::${row.business_date}`, row);

  const dates = [...new Set(cartFacts.map((row) => row.business_date))].sort();
  const window = dateRange(dates[0], dates[dates.length - 1]);

  const cartStates = new Map();
  for (const cart of activeCarts) cartStates.set(cart.id, emptyCartState(cart.id));

  const networkUnits = new Map();
  for (const row of productFacts) {
    networkUnits.set(row.product_id, (networkUnits.get(row.product_id) || 0) + row.baseline_units);
  }
  let networkState = emptyNetworkState();

  const perCart = new Map();
  const absErrors = [];
  const naiveAbsErrors = [];
  const pinballLosses = [];
  let covered = 0;
  let evaluated = 0;

  for (const dateKey of window) {
    for (const cart of activeCarts) {
      const facts = factsByCartDate.get(`${cart.id}::${dateKey}`);
      if (!facts || !facts.traded) continue;

      const cartState = cartStates.get(cart.id);
      const assumption = assumptionsByLocation.get(cart.id)?.get(dayOfWeek(dateKey)) || null;

      // Forecast from state that has NOT yet seen this day.
      const baseline = baselineCartUnits({ cartState, networkState, assumption, dow: dayOfWeek(dateKey) });
      const { uplift } = cartUplift(campaigns, cart.id, dateKey, effects);
      const expected = Math.max(0, baseline * uplift);
      const dispersion = effectiveDispersion(cartState, networkState);
      const p90 = countQuantile(expected, dispersion, config.serviceQuantile);

      // Only score once the cart has something to forecast from. Scoring the
      // very first observation would be scoring a state of zero, which measures
      // the seeding rule rather than the model.
      if (cartState.observations > 0) {
        const actual = facts.units;
        const previous = factsByCartDate.get(`${cart.id}::${addDays(dateKey, -7)}`);
        const naive = previous && previous.traded ? previous.units : null;

        absErrors.push(Math.abs(actual - expected));
        if (naive !== null) naiveAbsErrors.push(Math.abs(actual - naive));
        pinballLosses.push(pinballLoss(actual, p90, config.serviceQuantile));
        if (actual <= p90) covered += 1;
        evaluated += 1;

        const bucket = perCart.get(cart.id) || { name: cart.name, abs: [], naive: [], pinball: [], covered: 0, n: 0 };
        bucket.abs.push(Math.abs(actual - expected));
        if (naive !== null) bucket.naive.push(Math.abs(actual - naive));
        bucket.pinball.push(pinballLoss(actual, p90, config.serviceQuantile));
        if (actual <= p90) bucket.covered += 1;
        bucket.n += 1;
        perCart.set(cart.id, bucket);
      }

      const advanced = advanceCartState({
        cartState,
        networkState,
        assumption,
        dateKey,
        baselineUnits: facts.baseline_units,
        traded: true
      });
      cartStates.set(cart.id, advanced.state);
    }

    // Re-pool after each day, exactly as the nightly job does, so the backtest
    // exercises the same shrinkage path rather than an idealised one.
    networkState = buildNetworkState({
      cartStates: cartStates.values(),
      productMix: buildNetworkProductMix(networkUnits),
      observations: [...cartStates.values()].reduce((sum, state) => sum + state.observations, 0)
    });
  }

  const overallMase = mase(absErrors, naiveAbsErrors);

  return {
    evaluated,
    window: { from: window[0], to: window[window.length - 1] },
    mae: Number(mean(absErrors).toFixed(4)),
    mase: overallMase === null ? null : Number(overallMase.toFixed(4)),
    // A MASE at or above 1 means the model is not beating "same weekday last
    // week". At this sample size that is the expected result, and it is
    // reported rather than hidden — a forecast nobody can check is worse than
    // no forecast.
    beats_seasonal_naive: overallMase === null ? null : overallMase < 1,
    pinball_loss: Number(mean(pinballLosses).toFixed(4)),
    p90_coverage: evaluated ? Number((covered / evaluated).toFixed(4)) : null,
    // Coverage should sit near the service quantile. Materially below it means
    // the dispersion estimate is too tight and the stocking number is optimistic.
    p90_coverage_target: config.serviceQuantile,
    by_cart: [...perCart.entries()].map(([locationId, bucket]) => {
      const cartMase = mase(bucket.abs, bucket.naive);
      return {
        location_id: locationId,
        location_name: bucket.name,
        evaluated: bucket.n,
        mae: Number(mean(bucket.abs).toFixed(4)),
        mase: cartMase === null ? null : Number(cartMase.toFixed(4)),
        pinball_loss: Number(mean(bucket.pinball).toFixed(4)),
        p90_coverage: bucket.n ? Number((bucket.covered / bucket.n).toFixed(4)) : null
      };
    })
  };
}
