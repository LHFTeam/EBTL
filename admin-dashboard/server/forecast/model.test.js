import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  advanceCartState,
  advanceProductStates,
  baselineCartUnits,
  buildNetworkProductMix,
  buildNetworkState,
  confidenceFor,
  effectiveDowIndex,
  effectiveLevel,
  emptyCartState,
  emptyNetworkState,
  forecastCartDay,
  forecastProductShares,
  posteriorAlphas
} from './model.js';
import { addDays, dateRange, dayOfWeek, daysBetween } from './businessDate.js';
import { config } from './config.js';

const CART = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';
const MOJITO = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const NEGRONI = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const UNSOLD = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

function feed(state, days, { network = emptyNetworkState(), assumption = null } = {}) {
  let current = state;
  for (const [dateKey, units] of days) {
    current = advanceCartState({
      cartState: current,
      networkState: network,
      assumption,
      dateKey,
      baselineUnits: units,
      traded: true
    }).state;
  }
  return current;
}

describe('business dates', () => {
  it('treats Sunday as day 0, matching location_opening_hours', () => {
    assert.equal(dayOfWeek('2026-08-02'), 0);
    assert.equal(dayOfWeek('2026-08-07'), 5);
  });

  it('adds and subtracts days across month boundaries', () => {
    assert.equal(addDays('2026-08-31', 1), '2026-09-01');
    assert.equal(addDays('2026-03-01', -1), '2026-02-28');
  });

  it('survives the Cairo DST transition', () => {
    // Egypt moves the clocks in late April; arithmetic done at midnight could
    // round into the neighbouring day.
    assert.equal(addDays('2026-04-24', 1), '2026-04-25');
    assert.equal(daysBetween('2026-04-24', '2026-04-25'), 1);
  });

  it('returns an empty range when the end precedes the start', () => {
    // This is what makes "catch up to yesterday" a no-op on a day already done,
    // rather than an error.
    assert.deepEqual(dateRange('2026-08-07', '2026-08-06'), []);
    assert.equal(dateRange('2026-08-01', '2026-08-07').length, 7);
  });
});

describe('cold start', () => {
  it('reports the network mean for a cart that has never traded', () => {
    // Marassi has two orders in its entire life. Without this it would forecast
    // near zero forever.
    const network = { ...emptyNetworkState(), mean_level: 12, observations: 40 };
    assert.equal(effectiveLevel(emptyCartState(CART), network), 12);
  });

  it('claims a flat week until weekdays have been seen', () => {
    // The model must not invent a weekend effect from two Fridays.
    const factors = effectiveDowIndex(emptyCartState(CART), emptyNetworkState());
    for (const factor of factors) assert.ok(Math.abs(factor - 1) < 1e-12);
  });

  it('uses the manager assumption when there is no history', () => {
    const expected = baselineCartUnits({
      cartState: emptyCartState(CART),
      networkState: emptyNetworkState(),
      assumption: { expected_units: 40, prior_strength_days: 14 },
      dow: 5
    });
    assert.equal(expected, 40);
  });

  it('lets real trading overtake the assumption', () => {
    const state = feed(emptyCartState(CART), dateRange('2026-06-01', '2026-08-01').map((d) => [d, 10]));
    const expected = baselineCartUnits({
      cartState: state,
      networkState: emptyNetworkState(),
      assumption: { expected_units: 40, prior_strength_days: 14 },
      dow: dayOfWeek('2026-08-02')
    });
    // 60 days of selling ~10 must not still be reporting the manager's 40.
    assert.ok(expected < 20, `expected the data to win, got ${expected}`);
  });

  it('labels a thin estimate as low confidence', () => {
    assert.equal(confidenceFor(0), 'low');
    assert.equal(confidenceFor(config.confidenceMediumDays), 'medium');
    assert.equal(confidenceFor(config.confidenceHighDays), 'high');
  });
});

describe('state advance', () => {
  it('ignores a date it has already absorbed', () => {
    // Exponential smoothing is order-dependent, so a double-applied day
    // silently corrupts the level. This gate is what makes the nightly job
    // safe to run twice.
    const once = feed(emptyCartState(CART), [['2026-08-01', 10], ['2026-08-02', 12]]);
    const replayed = advanceCartState({
      cartState: once,
      networkState: emptyNetworkState(),
      assumption: null,
      dateKey: '2026-08-02',
      baselineUnits: 12,
      traded: true
    });

    assert.equal(replayed.applied, false);
    assert.equal(replayed.state.level, once.level);
    assert.equal(replayed.state.observations, once.observations);
  });

  it('skips a day the cart did not trade without counting it as zero demand', () => {
    const before = feed(emptyCartState(CART), [['2026-08-01', 10]]);
    const closed = advanceCartState({
      cartState: before,
      networkState: emptyNetworkState(),
      assumption: null,
      dateKey: '2026-08-02',
      baselineUnits: 0,
      traded: false
    });

    assert.equal(closed.applied, false);
    assert.equal(closed.state.level, before.level, 'a closed day must not drag the level down');
    assert.equal(closed.state.last_business_date, '2026-08-02', 'but the date must still advance');
  });

  it('counts a genuine zero-demand day as evidence', () => {
    const before = feed(emptyCartState(CART), [['2026-08-01', 10]]);
    const after = advanceCartState({
      cartState: before,
      networkState: emptyNetworkState(),
      assumption: null,
      dateKey: '2026-08-02',
      baselineUnits: 0,
      traded: true
    });

    assert.equal(after.applied, true);
    assert.ok(after.state.level < before.level);
  });

  it('keeps weekday factors averaging one however long it runs', () => {
    const days = dateRange('2026-06-01', '2026-08-01')
      .map((date) => [date, dayOfWeek(date) === 5 ? 30 : 8]);
    const state = feed(emptyCartState(CART), days);

    const factorMean = state.dow_index.reduce((sum, value) => sum + value, 0) / 7;
    assert.ok(Math.abs(factorMean - 1) < 1e-9, `factors drifted to mean ${factorMean}`);
  });

  it('eventually finds a real weekday pattern', () => {
    const days = dateRange('2026-01-01', '2026-08-01')
      .map((date) => [date, dayOfWeek(date) === 5 ? 40 : 8]);
    const state = feed(emptyCartState(CART), days);

    assert.ok(state.dow_index[5] > state.dow_index[2], 'Friday should outrank Tuesday after 30 weeks');
  });

  it('tracks a level change without chasing a single spike', () => {
    const steady = feed(emptyCartState(CART), dateRange('2026-06-01', '2026-07-01').map((d) => [d, 10]));
    const spiked = advanceCartState({
      cartState: steady,
      networkState: emptyNetworkState(),
      assumption: null,
      dateKey: '2026-07-02',
      baselineUnits: 100,
      traded: true
    }).state;

    assert.ok(spiked.level > steady.level, 'a big day should move the level');
    assert.ok(spiked.level < 30, 'but one spike must not redefine the cart');
  });
});

describe('product mix', () => {
  it('gives an unsold product a small positive share', () => {
    const alphas = posteriorAlphas({
      productStates: new Map([[MOJITO, { alpha: 30 }]]),
      networkMix: { [MOJITO]: 0.9, [NEGRONI]: 0.1 },
      activeProductIds: [MOJITO, NEGRONI, UNSOLD]
    });

    assert.ok(alphas.get(UNSOLD) > 0, 'a never-sold product must not be asserted at zero');
    assert.ok(alphas.get(MOJITO) > alphas.get(UNSOLD));
  });

  it('lets a cart with its own history outweigh the network prior', () => {
    const alphas = posteriorAlphas({
      productStates: new Map([[NEGRONI, { alpha: 500 }]]),
      networkMix: { [MOJITO]: 0.95, [NEGRONI]: 0.05 },
      activeProductIds: [MOJITO, NEGRONI]
    });
    assert.ok(alphas.get(NEGRONI) > alphas.get(MOJITO));
  });

  it('produces shares summing to one across every active product', () => {
    const shares = forecastProductShares({
      productStates: new Map([[MOJITO, { alpha: 10 }]]),
      networkMix: { [MOJITO]: 0.7, [NEGRONI]: 0.3 },
      activeProductIds: [MOJITO, NEGRONI, UNSOLD],
      campaigns: [],
      effects: new Map(),
      locationId: CART,
      dateKey: '2026-08-03'
    });

    const total = [...shares.values()].reduce((sum, value) => sum + value, 0);
    assert.ok(Math.abs(total - 1) < 1e-12);
    assert.equal(shares.size, 3);
  });

  it('decays a product that stops selling', () => {
    let states = new Map([[MOJITO, { alpha: 100, units_ewma: 5, observations: 10, last_sold_date: '2026-07-01' }]]);
    for (const dateKey of dateRange('2026-07-02', '2026-08-01')) {
      states = advanceProductStates({ productStates: states, observedBaselineUnits: new Map(), dateKey });
    }

    assert.ok(states.get(MOJITO).alpha < 100, 'evidence should fade');
    assert.ok(states.get(MOJITO).alpha > 0, 'but not vanish outright');
    assert.equal(states.get(MOJITO).last_sold_date, '2026-07-01');
  });

  it('records a sale against the day it happened', () => {
    const states = advanceProductStates({
      productStates: new Map(),
      observedBaselineUnits: new Map([[MOJITO, 4]]),
      dateKey: '2026-08-03'
    });

    assert.ok(Math.abs(states.get(MOJITO).alpha - 4) < 1e-12);
    assert.equal(states.get(MOJITO).last_sold_date, '2026-08-03');
    assert.equal(states.get(MOJITO).observations, 1);
  });
});

describe('pooled network prior', () => {
  it('ignores carts that have never traded when averaging the level', () => {
    // A cart sitting untouched at zero is not evidence that carts sell nothing.
    const network = buildNetworkState({
      cartStates: [
        { ...emptyCartState(CART), level: 20, observations: 30 },
        emptyCartState(OTHER)
      ],
      productMix: {},
      observations: 30
    });
    assert.equal(network.mean_level, 20);
  });

  it('renormalises the pooled weekday shape', () => {
    const network = buildNetworkState({
      cartStates: [{
        ...emptyCartState(CART),
        dow_index: [2, 2, 2, 2, 2, 2, 2],
        dow_obs_count: [5, 5, 5, 5, 5, 5, 5],
        observations: 35
      }],
      productMix: {},
      observations: 35
    });

    const factorMean = network.dow_index.reduce((sum, value) => sum + value, 0) / 7;
    assert.ok(Math.abs(factorMean - 1) < 1e-9, 'the pooled profile is a shape, not a shape plus a scale');
  });

  it('turns unit totals into shares', () => {
    const mix = buildNetworkProductMix(new Map([[MOJITO, 30], [NEGRONI, 10]]));
    assert.ok(Math.abs(mix[MOJITO] - 0.75) < 1e-6);
    assert.ok(Math.abs(mix[NEGRONI] - 0.25) < 1e-6);
  });

  it('returns an empty mix rather than dividing by zero', () => {
    assert.deepEqual(buildNetworkProductMix(new Map()), {});
  });
});

describe('cart-day forecast', () => {
  it('orders the quantiles and reports its own sample size', () => {
    const state = feed(emptyCartState(CART), dateRange('2026-06-01', '2026-08-01').map((d) => [d, 12]));
    const forecast = forecastCartDay({
      cartState: state,
      networkState: emptyNetworkState(),
      assumption: null,
      campaigns: [],
      effects: new Map(),
      locationId: CART,
      dateKey: '2026-08-10',
      horizonDays: 3
    });

    assert.ok(forecast.p90 >= forecast.p50);
    assert.equal(forecast.sample_size, state.observations);
    assert.equal(forecast.campaign_uplift, 1);
    assert.ok(forecast.expected_units > 0);
  });

  it('raises the forecast for a scheduled campaign and leaves other days alone', () => {
    const state = feed(emptyCartState(CART), dateRange('2026-06-01', '2026-08-01').map((d) => [d, 12]));
    const campaigns = [{
      id: 'c1',
      campaign_type: 'social',
      scope: 'network',
      starts_on: '2026-08-10',
      ends_on: '2026-08-11',
      discount_pct: null,
      expected_uplift_pct: 50,
      learned_log_uplift: null,
      learned_observations: 0,
      is_active: true,
      location_ids: [],
      product_ids: []
    }];

    const base = { cartState: state, networkState: emptyNetworkState(), assumption: null, campaigns, effects: new Map(), locationId: CART, horizonDays: 1 };
    const during = forecastCartDay({ ...base, dateKey: '2026-08-10' });
    const after = forecastCartDay({ ...base, dateKey: '2026-08-12' });

    assert.ok(Math.abs(during.campaign_uplift - 1.5) < 1e-9);
    assert.equal(after.campaign_uplift, 1);
    assert.ok(during.expected_units > after.expected_units);
    assert.deepEqual(during.campaign_ids, ['c1']);
  });
});
