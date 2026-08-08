// The nightly update, and the scheduler that drives it.
//
// One run does, in this order and for good reason:
//
//   1. ingest every un-processed business date into the facts tables
//   2. score the forecast that was standing for each of those dates
//   3. record what campaigns did on those dates
//   4. advance cart and product state on BASELINE units
//   5. re-pool the network prior and the campaign effects
//   6. regenerate forecasts for the horizon
//
// Steps 2 and 3 come before step 4 deliberately: both measure the model against
// a day it has not yet seen. Doing them afterwards would score the model on data
// it had already absorbed, and every campaign would appear to have worked
// exactly as planned.

import {
  advanceCartState,
  advanceProductStates,
  buildNetworkProductMix,
  buildNetworkState,
  confidenceFor,
  effectiveDispersion,
  emptyCartState,
  emptyNetworkState,
  forecastCartDay,
  forecastProductShares,
  forecastProductsForDay
} from './model.js';
import { learnedLogUplift, observationFor, poolCampaignEffects } from './campaigns.js';
import { addDays, dateRange, dayOfWeek, todayInCairo, yesterdayInCairo } from './businessDate.js';
import { pinballLoss } from './math.js';
import { config } from './config.js';
import { ingestRange } from './ingest.js';
import * as store from './store.js';

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------

// Realised average price per product, used to turn unit forecasts into EGP.
// Taken from what actually sold rather than from product_variants, so it
// reflects the mix of variants and any discounting that really happened.
function priceMapFrom(productFacts) {
  const units = new Map();
  const revenue = new Map();

  for (const row of productFacts) {
    units.set(row.product_id, (units.get(row.product_id) || 0) + row.units);
    revenue.set(row.product_id, (revenue.get(row.product_id) || 0) + row.revenue);
  }

  const prices = new Map();
  let totalUnits = 0;
  let totalRevenue = 0;
  for (const [productId, unitCount] of units) {
    if (!(unitCount > 0)) continue;
    prices.set(productId, revenue.get(productId) / unitCount);
    totalUnits += unitCount;
    totalRevenue += revenue.get(productId);
  }

  return { prices, meanPrice: totalUnits > 0 ? totalRevenue / totalUnits : 0 };
}

// Seasonal-naive (lag 7) baseline: what the same weekday sold a week ago. MASE
// is defined against this, and it is stored alongside every score so "is the
// model beating last Friday?" is answerable rather than asserted.
function seasonalNaive(factsByCartDate, locationId, dateKey) {
  const previous = factsByCartDate.get(`${locationId}::${addDays(dateKey, -7)}`);
  return previous && previous.traded ? previous.units : null;
}

// --------------------------------------------------------------------------
// Scoring
// --------------------------------------------------------------------------

// Score the forecast that was standing for a date against what happened.
// Returns null when no forecast existed — the first days after install have
// nothing to score, and inventing a score for them would corrupt the accuracy
// series with days the model never actually predicted.
function scoreDate({ locationId, dateKey, actual, factsByCartDate, forecast }) {
  if (!forecast) return null;

  const absError = Math.abs(actual - forecast.expected_units);
  const naive = seasonalNaive(factsByCartDate, locationId, dateKey);

  return {
    location_id: locationId,
    business_date: dateKey,
    horizon_days: forecast.horizon_days || 1,
    forecast_p50: forecast.p50,
    forecast_p90: forecast.p90,
    expected_units: Number(forecast.expected_units.toFixed(4)),
    actual_units: actual,
    abs_error: Number(absError.toFixed(4)),
    naive_forecast: naive,
    naive_abs_error: naive === null ? null : Number(Math.abs(actual - naive).toFixed(4)),
    pinball_loss: Number(pinballLoss(actual, forecast.p90, config.serviceQuantile).toFixed(4)),
    within_p90: actual <= forecast.p90,
    scored_at: new Date().toISOString()
  };
}

// --------------------------------------------------------------------------
// The run
// --------------------------------------------------------------------------

export async function runForecastUpdate({ trigger = 'schedule', through = null } = {}) {
  const runId = await store.startRun(trigger);
  const throughDate = through || yesterdayInCairo();

  try {
    const [carts, products, closedWeekdays, campaigns, effects, assumptionsByLocation] = await Promise.all([
      store.loadBeachCarts(),
      store.loadActiveProducts(),
      store.loadClosedWeekdays(),
      store.loadCampaigns(),
      store.loadCampaignEffects(),
      store.loadAssumptions()
    ]);

    const activeCarts = carts.filter((cart) => cart.is_active);
    if (!activeCarts.length) {
      await store.finishRun(runId, { status: 'ok', through_date: throughDate, dates_processed: 0 });
      return { datesProcessed: 0, forecastsWritten: 0, reason: 'no active beach carts' };
    }

    const cartStates = await store.loadCartStates();
    for (const cart of activeCarts) {
      if (!cartStates.has(cart.id)) cartStates.set(cart.id, emptyCartState(cart.id));
    }

    // Where to resume from: the day after the furthest-advanced cart. A cart
    // added later catches up on its own, because its own last_business_date
    // gates its recursion independently.
    const lastProcessed = [...cartStates.values()]
      .map((state) => state.last_business_date)
      .filter(Boolean)
      .sort()
      .pop() || null;

    const earliest = lastProcessed
      ? addDays(lastProcessed, 1)
      : (await store.firstBusinessDate()) || throughDate;

    // Cap the catch-up so a long outage cannot turn a nightly job into an
    // unbounded backfill. Whatever is left is picked up by the next run.
    const capStart = addDays(throughDate, -config.maxCatchUpDays);
    const from = earliest < capStart ? capStart : earliest;
    const dates = dateRange(from, throughDate);

    if (!dates.length) {
      await store.finishRun(runId, { status: 'ok', through_date: throughDate, dates_processed: 0 });
      return { datesProcessed: 0, forecastsWritten: 0, reason: 'already up to date' };
    }

    // ---- 1. Ingest -------------------------------------------------------
    const knownFirstSales = await store.loadFirstSaleDates();
    const ingested = await ingestRange({
      from,
      to: throughDate,
      carts: activeCarts,
      campaigns,
      effects,
      closedWeekdays,
      knownFirstSales
    });

    await store.upsertCartFacts(ingested.cartRows);
    await store.upsertProductFacts(ingested.productRows);

    // History for the seasonal-naive baseline needs a week of lead-in.
    const allCartFacts = await store.loadCartFacts({ from: addDays(from, -8), to: throughDate });
    const allProductFacts = await store.loadProductFacts({ from: addDays(from, -8), to: throughDate });

    const factsByCartDate = new Map();
    for (const row of allCartFacts) factsByCartDate.set(`${row.location_id}::${row.business_date}`, row);

    const productFactsByCartDate = new Map();
    for (const row of allProductFacts) {
      const key = `${row.location_id}::${row.business_date}`;
      if (!productFactsByCartDate.has(key)) productFactsByCartDate.set(key, []);
      productFactsByCartDate.get(key).push(row);
    }

    const productStatesByLocation = await store.loadProductStates();
    for (const cart of activeCarts) {
      if (!productStatesByLocation.has(cart.id)) productStatesByLocation.set(cart.id, new Map());
    }

    let networkState = (await store.loadNetworkState()) || emptyNetworkState();

    const accuracyRows = [];
    const campaignObservations = [];

    // ---- 2-4. Per date, per cart ----------------------------------------
    for (const dateKey of dates) {
      for (const cart of activeCarts) {
        const facts = factsByCartDate.get(`${cart.id}::${dateKey}`);
        if (!facts) continue;

        const cartState = cartStates.get(cart.id);
        const assumption = assumptionsByLocation.get(cart.id)?.get(dayOfWeek(dateKey)) || null;

        // Score before the state absorbs the day. The forecast that was
        // standing for this date is loaded once and used for both the accuracy
        // score and the campaign measurement.
        if (facts.traded) {
          const standing = await store.loadCartForecast(cart.id, dateKey);

          const score = scoreDate({
            locationId: cart.id,
            dateKey,
            actual: facts.units,
            factsByCartDate,
            forecast: standing
          });
          if (score) accuracyRows.push(score);

          // Divide the lift back out to recover what the model expected WITHOUT
          // the campaign — the counterfactual the ratio is measured against.
          const baselineForecast = standing && standing.campaign_uplift > 0
            ? standing.expected_units / standing.campaign_uplift
            : null;

          if (baselineForecast) {
            for (const campaign of campaigns) {
              const observation = observationFor({
                campaign,
                locationId: cart.id,
                dateKey,
                actualUnits: facts.units,
                baselineForecast,
                promoOrderShare: facts.promo_order_share
              });
              // Only campaigns that actually covered this cart-date, and only
              // once the campaign is relevant to it.
              if (observation && dateKey >= campaign.starts_on && dateKey <= campaign.ends_on) {
                const locations = campaign.location_ids || [];
                if (!locations.length || locations.includes(cart.id)) campaignObservations.push(observation);
              }
            }
          }
        }

        // Advance on baseline units — the day with campaign lift divided out.
        const advanced = advanceCartState({
          cartState,
          networkState,
          assumption,
          dateKey,
          baselineUnits: facts.baseline_units,
          traded: facts.traded
        });
        cartStates.set(cart.id, advanced.state);

        if (advanced.applied) {
          const productFacts = productFactsByCartDate.get(`${cart.id}::${dateKey}`) || [];
          const observed = new Map();
          for (const row of productFacts) observed.set(row.product_id, row.baseline_units);

          productStatesByLocation.set(
            cart.id,
            advanceProductStates({
              productStates: productStatesByLocation.get(cart.id),
              observedBaselineUnits: observed,
              dateKey
            })
          );
        }
      }
    }

    // ---- 5. Re-pool priors ----------------------------------------------
    const networkUnits = new Map();
    for (const row of allProductFacts) {
      networkUnits.set(row.product_id, (networkUnits.get(row.product_id) || 0) + row.baseline_units);
    }

    networkState = buildNetworkState({
      cartStates: cartStates.values(),
      productMix: buildNetworkProductMix(networkUnits),
      observations: [...cartStates.values()].reduce((sum, state) => sum + state.observations, 0)
    });

    await store.upsertCampaignObservations(campaignObservations);

    const observationsByCampaign = await store.loadCampaignObservations();
    for (const campaign of campaigns) {
      const rows = observationsByCampaign.get(campaign.id) || [];
      const logUplift = learnedLogUplift(rows);
      if (logUplift !== null || campaign.learned_observations) {
        await store.updateCampaignLearning(campaign.id, logUplift, rows.length);
        campaign.learned_log_uplift = logUplift;
        campaign.learned_observations = rows.length;
      }
    }

    await store.saveCampaignEffects(poolCampaignEffects(campaigns, observationsByCampaign));
    const refreshedEffects = await store.loadCampaignEffects();

    // ---- Persist state ---------------------------------------------------
    await store.saveCartStates(cartStates);
    await store.saveProductStates(productStatesByLocation);
    await store.saveNetworkState(networkState);
    await store.writeCartAccuracy(accuracyRows);

    // ---- 6. Regenerate forecasts ----------------------------------------
    const forecastsWritten = await generateForecasts({
      carts: activeCarts,
      products,
      cartStates,
      productStatesByLocation,
      networkState,
      assumptionsByLocation,
      campaigns,
      effects: refreshedEffects,
      productFacts: allProductFacts,
      cartFacts: allCartFacts
    });

    await store.finishRun(runId, {
      status: 'ok',
      through_date: throughDate,
      dates_processed: dates.length,
      forecasts_written: forecastsWritten
    });

    return { datesProcessed: dates.length, forecastsWritten, from, to: throughDate };
  } catch (error) {
    await store.finishRun(runId, { status: 'failed', error: String(error.message || error) });
    throw error;
  }
}

// --------------------------------------------------------------------------
// Forecast generation
// --------------------------------------------------------------------------

export async function generateForecasts({
  carts,
  products,
  cartStates,
  productStatesByLocation,
  networkState,
  assumptionsByLocation,
  campaigns,
  effects,
  productFacts,
  cartFacts
}) {
  const today = todayInCairo();
  const horizon = dateRange(today, addDays(today, config.forecastHorizonDays - 1));
  const activeProductIds = products.map((product) => product.id);
  const { prices, meanPrice } = priceMapFrom(productFacts);

  // Units per order, so a unit forecast can be expressed as an order count for
  // staffing. Measured, not assumed — it differs a lot between carts.
  const unitsPerOrder = new Map();
  for (const cart of carts) {
    const rows = cartFacts.filter((row) => row.location_id === cart.id && row.orders > 0);
    const units = rows.reduce((sum, row) => sum + row.units, 0);
    const orders = rows.reduce((sum, row) => sum + row.orders, 0);
    unitsPerOrder.set(cart.id, orders > 0 ? units / orders : 0);
  }

  const cartRows = [];
  const productRows = [];

  for (const cart of carts) {
    const cartState = cartStates.get(cart.id);
    const productStates = productStatesByLocation.get(cart.id) || new Map();
    const dispersion = effectiveDispersion(cartState, networkState);

    for (const [index, dateKey] of horizon.entries()) {
      const assumption = assumptionsByLocation.get(cart.id)?.get(dayOfWeek(dateKey)) || null;

      const forecast = forecastCartDay({
        cartState,
        networkState,
        assumption,
        campaigns,
        effects,
        locationId: cart.id,
        dateKey,
        horizonDays: index
      });

      const shares = forecastProductShares({
        productStates,
        networkMix: networkState.product_mix,
        activeProductIds,
        campaigns,
        effects,
        locationId: cart.id,
        dateKey
      });

      const rows = forecastProductsForDay({
        cartForecast: forecast,
        shares,
        dispersion,
        priceByProduct: prices,
        meanPrice
      });

      const perOrder = unitsPerOrder.get(cart.id) || 0;

      cartRows.push({
        ...forecast,
        // Expected revenue at cart level is summed from the product forecasts,
        // which is valid because expectations DO add — unlike the quantiles just
        // above, which are each computed from their own distribution.
        expected_revenue: rows.reduce((sum, row) => sum + row.expected_revenue, 0),
        expected_orders: perOrder > 0 ? forecast.expected_units / perOrder : 0,
        confidence: confidenceFor(cartState.observations)
      });
      productRows.push(...rows);
    }
  }

  // Drop anything past the horizon so a shortened horizon leaves no orphans.
  await store.pruneForecastsAfter(horizon[horizon.length - 1]);

  const written = await store.writeCartForecasts(cartRows);
  await store.writeProductForecasts(productRows);
  return written;
}

// --------------------------------------------------------------------------
// Rebuild
// --------------------------------------------------------------------------

// Replay everything from the orders. The escape hatch that keeps a recursive
// model auditable: any state it holds can be reproduced from the facts, so a
// suspect number can be checked rather than argued about.
export async function rebuildForecastState() {
  await store.clearDerivedState();
  return runForecastUpdate({ trigger: 'rebuild' });
}

// --------------------------------------------------------------------------
// Scheduler
// --------------------------------------------------------------------------

// Polls for the Cairo business date rolling over, rather than firing a timer at
// midnight.
//
// A fire-at-midnight timer silently skips a night whenever the process happens
// to be restarting, deploying, or asleep — and on a single Render web service
// that is not rare. Polling plus the last_business_date gate means a missed
// night is indistinguishable from a late one: the next poll catches up whatever
// is outstanding, in order, exactly once.
export function startForecastScheduler({
  intervalMinutes = config.schedulerIntervalMinutes,
  firstRunDelayMs = config.schedulerFirstRunDelayMs
} = {}) {
  let running = false;
  let lastCompletedDate = null;

  async function tick() {
    if (running) return;

    const target = yesterdayInCairo();
    if (lastCompletedDate === target) return;

    running = true;
    try {
      const result = await runForecastUpdate({ trigger: 'schedule' });
      lastCompletedDate = target;
      if (result.datesProcessed) {
        console.log('Forecast updated', {
          through: target,
          dates_processed: result.datesProcessed,
          forecasts_written: result.forecastsWritten
        });
      }
    } catch (error) {
      // Never rethrow into the timer: a failed night must not take the process
      // down, and the next tick will retry from the same un-advanced state.
      console.error('Forecast update failed', error);
    } finally {
      running = false;
    }
  }

  const firstTimer = setTimeout(() => void tick(), firstRunDelayMs);
  firstTimer.unref?.();

  const intervalTimer = setInterval(() => void tick(), intervalMinutes * 60 * 1000);
  intervalTimer.unref?.();

  return {
    stop() {
      clearTimeout(firstTimer);
      clearInterval(intervalTimer);
    }
  };
}
