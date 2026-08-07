import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  applyProductUplifts,
  campaignCoversCart,
  deflateToBaseline,
  effectKey,
  learnedLogUplift,
  observationFor,
  poolCampaignEffects,
  productUplifts,
  cartUplift,
  resolvedUplift
} from './campaigns.js';
import { advanceCartState, emptyCartState, emptyNetworkState } from './model.js';
import { config, discountBucket } from './config.js';

const CART = '11111111-1111-1111-1111-111111111111';
const OTHER_CART = '22222222-2222-2222-2222-222222222222';
const MOJITO = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const NEGRONI = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

function campaign(overrides = {}) {
  return {
    id: 'c1',
    name: 'Test',
    campaign_type: 'social',
    scope: 'network',
    starts_on: '2026-08-01',
    ends_on: '2026-08-07',
    discount_pct: null,
    expected_uplift_pct: 40,
    learned_log_uplift: null,
    learned_observations: 0,
    is_active: true,
    location_ids: [],
    product_ids: [],
    ...overrides
  };
}

describe('campaign coverage', () => {
  it('covers every cart when no locations are listed', () => {
    assert.equal(campaignCoversCart(campaign(), CART, '2026-08-03'), true);
    assert.equal(campaignCoversCart(campaign(), OTHER_CART, '2026-08-03'), true);
  });

  it('covers only the listed carts when locations are set', () => {
    const scoped = campaign({ location_ids: [CART] });
    assert.equal(campaignCoversCart(scoped, CART, '2026-08-03'), true);
    assert.equal(campaignCoversCart(scoped, OTHER_CART, '2026-08-03'), false);
  });

  it('respects the window at both ends, inclusively', () => {
    assert.equal(campaignCoversCart(campaign(), CART, '2026-08-01'), true);
    assert.equal(campaignCoversCart(campaign(), CART, '2026-08-07'), true);
    assert.equal(campaignCoversCart(campaign(), CART, '2026-07-31'), false);
    assert.equal(campaignCoversCart(campaign(), CART, '2026-08-08'), false);
  });

  it('ignores an inactive campaign', () => {
    assert.equal(campaignCoversCart(campaign({ is_active: false }), CART, '2026-08-03'), false);
  });
});

describe('resolved uplift', () => {
  it('uses the planned uplift before anything has been measured', () => {
    const resolved = resolvedUplift(campaign({ expected_uplift_pct: 40 }), new Map());
    assert.ok(Math.abs(resolved.uplift - 1.4) < 1e-9);
    assert.equal(resolved.source, 'planned');
  });

  it('falls back to the pooled effect when no plan was entered', () => {
    // This is what makes the third campaign of a kind forecastable: a single
    // campaign never runs long enough to estimate its own lift.
    const effects = new Map([[effectKey('social', null), { log_uplift_mean: Math.log(1.6), observations: 12 }]]);
    const resolved = resolvedUplift(campaign({ expected_uplift_pct: 0 }), effects);
    assert.ok(Math.abs(resolved.uplift - 1.6) < 1e-6);
  });

  it('sits between plan and measurement while evidence is thin', () => {
    const partial = resolvedUplift(
      campaign({ expected_uplift_pct: 40, learned_log_uplift: Math.log(2), learned_observations: 1 }),
      new Map()
    );
    assert.ok(partial.uplift > 1.4 && partial.uplift < 2);
    assert.equal(partial.source, 'blended');
  });

  it('lets measurement take over once the campaign has run long enough', () => {
    const learned = resolvedUplift(
      campaign({ expected_uplift_pct: 40, learned_log_uplift: Math.log(2), learned_observations: 200 }),
      new Map()
    );
    assert.ok(Math.abs(learned.uplift - 2) < 0.02);
    assert.equal(learned.source, 'learned');
  });

  it('clamps an absurd measurement', () => {
    // A measured 40x is a data problem, not a marketing triumph, and must never
    // reach a stocking number.
    const wild = resolvedUplift(
      campaign({ expected_uplift_pct: 0, learned_log_uplift: Math.log(40), learned_observations: 500 }),
      new Map()
    );
    assert.ok(wild.uplift <= config.maxUplift);
  });

  it('applies no lift at all when nothing is planned or known', () => {
    assert.equal(resolvedUplift(campaign({ expected_uplift_pct: 0 }), new Map()).uplift, 1);
  });
});

describe('cart-level uplift', () => {
  it('compounds overlapping campaigns but keeps the product bounded', () => {
    const campaigns = [
      campaign({ id: 'a', expected_uplift_pct: 300 }),
      campaign({ id: 'b', expected_uplift_pct: 300 })
    ];
    const { uplift, campaignIds } = cartUplift(campaigns, CART, '2026-08-03', new Map());
    assert.equal(campaignIds.length, 2);
    assert.ok(uplift <= config.maxUplift, 'two 4x campaigns must not authorise 16x');
  });

  it('excludes product-scoped campaigns from the volume lift', () => {
    // A product campaign shifts the mix. Letting it also raise volume would
    // double-count an effect nobody measured.
    const campaigns = [campaign({ scope: 'product', product_ids: [MOJITO], expected_uplift_pct: 100 })];
    assert.equal(cartUplift(campaigns, CART, '2026-08-03', new Map()).uplift, 1);
  });
});

describe('product-level uplift', () => {
  it('lifts targeted products and takes the share from the rest', () => {
    const campaigns = [campaign({ scope: 'product', product_ids: [MOJITO], expected_uplift_pct: 100 })];
    const uplifts = productUplifts(campaigns, CART, '2026-08-03', new Map());

    const shares = new Map([[MOJITO, 0.2], [NEGRONI, 0.8]]);
    const lifted = applyProductUplifts(shares, uplifts);

    assert.ok(lifted.get(MOJITO) > shares.get(MOJITO), 'targeted product should gain share');
    assert.ok(lifted.get(NEGRONI) < shares.get(NEGRONI), 'cannibalisation should fall out of renormalisation');
    assert.ok(Math.abs([...lifted.values()].reduce((s, v) => s + v, 0) - 1) < 1e-12);
  });

  it('changes nothing when every product is lifted equally', () => {
    const shares = new Map([[MOJITO, 0.25], [NEGRONI, 0.75]]);
    const uplifts = new Map([[MOJITO, 2], [NEGRONI, 2]]);
    const lifted = applyProductUplifts(shares, uplifts);

    assert.ok(Math.abs(lifted.get(MOJITO) - 0.25) < 1e-12);
    assert.ok(Math.abs(lifted.get(NEGRONI) - 0.75) < 1e-12);
  });

  it('leaves shares untouched when there are no product campaigns', () => {
    const shares = new Map([[MOJITO, 0.4], [NEGRONI, 0.6]]);
    assert.equal(applyProductUplifts(shares, new Map()), shares);
  });
});

describe('base and lift decomposition', () => {
  it('recovers the baseline exactly', () => {
    assert.ok(Math.abs(deflateToBaseline(14, 1.4) - 10) < 1e-12);
  });

  it('treats a zero or missing uplift as no lift rather than dividing by zero', () => {
    assert.equal(deflateToBaseline(10, 0), 10);
  });

  it('leaves cart state identical to a no-campaign run', () => {
    // The property that protects the whole model. Inflating a day by a known
    // lift and then dividing it back out must leave the smoother exactly where
    // it would have been — otherwise a promotion permanently raises the level
    // and every ordinary day afterwards is over-forecast.
    const network = emptyNetworkState();
    const days = [
      { date: '2026-08-01', baseline: 12 },
      { date: '2026-08-02', baseline: 9 },
      { date: '2026-08-03', baseline: 15 }
    ];

    let quiet = emptyCartState(CART);
    for (const day of days) {
      quiet = advanceCartState({
        cartState: quiet,
        networkState: network,
        assumption: null,
        dateKey: day.date,
        baselineUnits: day.baseline,
        traded: true
      }).state;
    }

    let promoted = emptyCartState(CART);
    for (const day of days) {
      const uplift = 1.75;
      const observed = day.baseline * uplift;
      promoted = advanceCartState({
        cartState: promoted,
        networkState: network,
        assumption: null,
        dateKey: day.date,
        baselineUnits: deflateToBaseline(observed, uplift),
        traded: true
      }).state;
    }

    assert.ok(Math.abs(quiet.level - promoted.level) < 1e-9);
    assert.deepEqual(
      quiet.dow_index.map((v) => v.toFixed(9)),
      promoted.dow_index.map((v) => v.toFixed(9))
    );
  });
});

describe('measuring what a campaign did', () => {
  it('records the ratio against the pre-campaign expectation', () => {
    const observation = observationFor({
      campaign: campaign(),
      locationId: CART,
      dateKey: '2026-08-03',
      actualUnits: 15,
      baselineForecast: 10,
      promoOrderShare: 0.5
    });
    assert.ok(Math.abs(observation.ratio - 1.5) < 1e-9);
  });

  it('skips a promo code nobody redeemed', () => {
    // A code that existed but went unused produced no lift, and scoring it as a
    // failed campaign would drag the pooled prior down for every future one.
    const skipped = observationFor({
      campaign: campaign({ campaign_type: 'promo_code' }),
      locationId: CART,
      dateKey: '2026-08-03',
      actualUnits: 8,
      baselineForecast: 10,
      promoOrderShare: 0
    });
    assert.equal(skipped, null);
  });

  it('still records a non-code campaign with no redemptions', () => {
    const observation = observationFor({
      campaign: campaign({ campaign_type: 'event' }),
      locationId: CART,
      dateKey: '2026-08-03',
      actualUnits: 8,
      baselineForecast: 10,
      promoOrderShare: 0
    });
    assert.ok(observation);
  });

  it('skips a day with no baseline to measure against', () => {
    assert.equal(observationFor({
      campaign: campaign(),
      locationId: CART,
      dateKey: '2026-08-03',
      actualUnits: 8,
      baselineForecast: 0,
      promoOrderShare: 1
    }), null);
  });

  it('averages ratios geometrically', () => {
    const logMean = learnedLogUplift([{ ratio: 0.5 }, { ratio: 2 }]);
    assert.ok(Math.abs(Math.exp(logMean) - 1) < 1e-12);
  });

  it('returns null when there is nothing usable to average', () => {
    assert.equal(learnedLogUplift([]), null);
    assert.equal(learnedLogUplift([{ ratio: 0 }, { ratio: -1 }]), null);
  });
});

describe('pooling', () => {
  it('buckets by discount depth', () => {
    assert.equal(discountBucket(null), 'none');
    assert.equal(discountBucket(5), 'lt10');
    assert.equal(discountBucket(15), '10_20');
    assert.equal(discountBucket(25), '20_30');
    assert.equal(discountBucket(60), 'gte50');
  });

  it('pools observations from different campaigns of the same shape', () => {
    const campaigns = [
      campaign({ id: 'a', campaign_type: 'promo_code', discount_pct: 25 }),
      campaign({ id: 'b', campaign_type: 'promo_code', discount_pct: 22 })
    ];
    const observations = new Map([
      ['a', [{ ratio: 1.5 }, { ratio: 1.5 }]],
      ['b', [{ ratio: 1.5 }]]
    ]);

    const effects = poolCampaignEffects(campaigns, observations);
    assert.equal(effects.length, 1, 'both campaigns fall in the 20-30% bucket');
    assert.equal(effects[0].observations, 3);
    assert.ok(Math.abs(Math.exp(effects[0].log_uplift_mean) - 1.5) < 1e-5);
  });

  it('keeps a pooled prior inside the bounds a resolved uplift may take', () => {
    const campaigns = [campaign({ id: 'a', campaign_type: 'social' })];
    const observations = new Map([['a', [{ ratio: 90 }]]]);
    const effects = poolCampaignEffects(campaigns, observations);
    assert.ok(Math.exp(effects[0].log_uplift_mean) <= config.maxUplift + 1e-9);
  });

  it('ignores campaigns with no observations', () => {
    assert.deepEqual(poolCampaignEffects([campaign()], new Map()), []);
  });
});
