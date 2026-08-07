import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  clamp,
  countQuantile,
  dirichletShares,
  dirichletUpdate,
  mase,
  mean,
  normaliseShares,
  pinballLoss,
  renormaliseSeasonal,
  shrink,
  shrinkLog,
  shrinkWeight,
  wintersStep
} from './math.js';

describe('shrinkage', () => {
  it('returns exactly the prior with no observations', () => {
    // The property the whole model leans on: with no data it reports the prior
    // rather than an estimate built from nothing.
    assert.equal(shrink(100, 5, 0, 8), 5);
    assert.equal(shrinkWeight(0, 8), 0);
  });

  it('converges on the estimate as observations accumulate', () => {
    assert.ok(shrink(100, 5, 1000, 8) > 99);
    assert.ok(shrinkWeight(1000, 8) > 0.99);
  });

  it('splits evenly when observations equal the shrink constant', () => {
    assert.equal(shrinkWeight(8, 8), 0.5);
    assert.equal(shrink(10, 20, 8, 8), 15);
  });

  it('is monotonic in the number of observations', () => {
    const weights = [0, 1, 2, 4, 8, 16, 32].map((n) => shrinkWeight(n, 8));
    for (let i = 1; i < weights.length; i += 1) {
      assert.ok(weights[i] > weights[i - 1], `weight should increase at n=${i}`);
    }
  });

  it('averages multiplicative factors geometrically', () => {
    // 0.5x and 2.0x must average to 1.0x, not 1.25x — an arithmetic mean of
    // ratios would bias every campaign uplift upward.
    assert.ok(Math.abs(shrinkLog(0.5, 2, 1, 1) - 1) < 1e-12);
  });

  it('never returns a negative multiplier', () => {
    assert.ok(shrinkLog(0.01, 4, 3, 5) > 0);
    assert.ok(shrinkLog(0, 2, 5, 5) > 0);
  });
});

describe('seasonal factors', () => {
  it('renormalises to a mean of exactly 1', () => {
    // Without this, multiplicative Holt-Winters lets level and seasonality
    // absorb each other and drift.
    const factors = renormaliseSeasonal([2, 1, 1, 1, 1, 1, 1]);
    assert.ok(Math.abs(mean(factors) - 1) < 1e-12);
  });

  it('preserves the relative shape', () => {
    const factors = renormaliseSeasonal([4, 2, 2, 2, 2, 2, 2]);
    assert.ok(Math.abs(factors[0] / factors[1] - 2) < 1e-12);
  });

  it('falls back to a flat week when handed nonsense', () => {
    assert.deepEqual(renormaliseSeasonal([0, 0, 0, 0, 0, 0, 0]), [1, 1, 1, 1, 1, 1, 1]);
    const withNaN = renormaliseSeasonal([Number.NaN, 1, 1, 1, 1, 1, 1]);
    assert.ok(withNaN.every((value) => Number.isFinite(value) && value > 0));
  });

  it('seeds the level from the first observation instead of smoothing from zero', () => {
    const step = wintersStep({
      level: 0,
      seasonal: [1, 1, 1, 1, 1, 1, 1],
      dow: 3,
      value: 20,
      seasonalFactor: 1,
      alpha: 0.15,
      gamma: 0.05
    });
    // Smoothing from zero would give 3, and take a dozen days to climb.
    assert.equal(step.level, 20);
  });
});

describe('dirichlet mix', () => {
  it('decays every product and adds what sold', () => {
    const alphas = new Map([['a', 10], ['b', 10]]);
    const updated = dirichletUpdate(alphas, new Map([['a', 5]]), 0.9);
    assert.ok(Math.abs(updated.get('a') - 14) < 1e-12);
    assert.ok(Math.abs(updated.get('b') - 9) < 1e-12);
  });

  it('produces shares that sum to one', () => {
    const shares = dirichletShares(new Map([['a', 3], ['b', 1], ['c', 0.5]]));
    assert.ok(Math.abs([...shares.values()].reduce((s, v) => s + v, 0) - 1) < 1e-12);
  });

  it('keeps a positive share for a product that has never sold', () => {
    // 48 of the 69 active products have never sold. Asserting a hard zero for
    // them would make the forecast unusable for anything new.
    const shares = dirichletShares(new Map([['sold', 20], ['never', 0.2]]));
    assert.ok(shares.get('never') > 0);
  });

  it('spreads evenly rather than dividing by zero when there is nothing at all', () => {
    const shares = dirichletShares(new Map([['a', 0], ['b', 0]]));
    assert.equal(shares.get('a'), 0.5);
    assert.equal(shares.get('b'), 0.5);
  });

  it('renormalises lifted shares back to one', () => {
    const shares = normaliseShares(new Map([['a', 0.6], ['b', 0.6]]));
    assert.ok(Math.abs([...shares.values()].reduce((s, v) => s + v, 0) - 1) < 1e-12);
  });
});

describe('count quantiles', () => {
  it('matches a hand-summed Poisson CDF', () => {
    // Poisson(2): P(0)=.1353, P(1)=.4060, P(2)=.6767, P(3)=.8571, P(4)=.9473
    assert.equal(countQuantile(2, 0, 0.13), 0);
    assert.equal(countQuantile(2, 0, 0.5), 2);
    assert.equal(countQuantile(2, 0, 0.9), 4);
  });

  it('is monotonic in the requested quantile', () => {
    const q50 = countQuantile(6, 0.4, 0.5);
    const q90 = countQuantile(6, 0.4, 0.9);
    const q99 = countQuantile(6, 0.4, 0.99);
    assert.ok(q50 <= q90);
    assert.ok(q90 <= q99);
  });

  it('widens the tail as dispersion rises', () => {
    // The reason a negative binomial is used at all: over-dispersion has to
    // show up in the stocking quantile, not just in the mean.
    const poisson = countQuantile(10, 0, 0.9);
    const overdispersed = countQuantile(10, 1.5, 0.9);
    assert.ok(overdispersed > poisson);
  });

  it('returns zero for zero demand', () => {
    assert.equal(countQuantile(0, 0, 0.9), 0);
    assert.equal(countQuantile(0, 2, 0.9), 0);
  });

  it('never returns a negative count', () => {
    assert.ok(countQuantile(0.01, 3, 0.5) >= 0);
  });
});

describe('scoring', () => {
  it('penalises under-forecasting a P90 nine times as hard', () => {
    // The asymmetry is the entire point of a stocking quantile: running out
    // costs more than carrying one spare.
    const under = pinballLoss(10, 9, 0.9);
    const over = pinballLoss(8, 9, 0.9);
    assert.ok(Math.abs(under - 0.9) < 1e-12);
    assert.ok(Math.abs(over - 0.1) < 1e-12);
    assert.ok(Math.abs(under / over - 9) < 1e-9);
  });

  it('scores a perfect forecast at zero', () => {
    assert.equal(pinballLoss(5, 5, 0.9), 0);
  });

  it('gives MASE exactly 1 when the model matches the naive baseline', () => {
    assert.equal(mase([2, 4, 6], [2, 4, 6]), 1);
  });

  it('gives MASE below 1 when the model beats the baseline', () => {
    assert.ok(mase([1, 1, 1], [2, 2, 2]) < 1);
  });

  it('returns null rather than dividing by zero on a perfect baseline', () => {
    assert.equal(mase([1, 2], [0, 0]), null);
  });
});

describe('clamp', () => {
  it('bounds a value and rejects non-numbers', () => {
    assert.equal(clamp(9, 0.5, 5), 5);
    assert.equal(clamp(0.1, 0.5, 5), 0.5);
    assert.equal(clamp(Number.NaN, 0.5, 5), 0.5);
  });
});
