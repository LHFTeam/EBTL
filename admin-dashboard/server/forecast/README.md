# Demand forecasting module

Forecasts units sold **per product, per beach cart, per day**, and updates itself
every night after Cairo midnight from the previous day's sales.

Self-contained by design. Everything it owns is in this folder plus tables
prefixed `forecast_`. Removing it is deleting this folder and the two lines that
mount it in `server/app.js` and `server/index.js`; nothing else in the schema or
the server depends on it.

## Read this first: what the numbers mean today

At the time of writing the business had sold **84 units in total**, across 11
trading days and 2 carts, with 21 of 69 active products having ever sold once.
Cart × product × weekday is roughly 966 cells. Fitting those cells from 84
observations is not possible, and any model that appears to do it is reporting
noise.

So this module is built around **shrinkage** rather than fitting. Every estimate
is pulled toward a pooled prior with weight `n/(n+k)`: at `n=0` it returns the
prior exactly, and it converges on the data as evidence accumulates —
continuously, with no thresholds and no "insufficient data" branch. The
consequence is that forecasts are honest but blunt right now (wide intervals,
`confidence: low`, weekday factors near 1.0), and they sharpen on their own.
**No code changes when the data arrives.**

Every forecast carries its `sample_size` and `confidence`, and the UI shows them
next to the number. That is deliberate: the failure mode to avoid is a figure
built on two observations looking like one built on two hundred.

## The model

```
units(cart, date, product) = level × dow[weekday] × U(campaigns) × share(product)
```

| Level | What | Method |
|---|---|---|
| 1. Cart volume | expected units for a cart on a date | Holt-Winters multiplicative (Winters 1960), factors renormalised to mean 1 each update (Archibald & Koehler 2003); level and weekday factors shrunk toward the pooled network profile and the manager's planning assumption |
| 2. Product mix | each product's share of that volume | Dirichlet–multinomial conjugate update with exponential forgetting; prior seeded from the network-wide mix (empirical Bayes) |
| 2.5 Campaigns | promotional lift | multiplicative base-and-lift decomposition (Cooper et al. 1999; van Heerde et al. 2000), lift learned in log space and pooled by campaign type × discount depth |
| 3. Uncertainty | P50 and P90 | Negative binomial (Poisson–Gamma), dispersion from Pearson residuals, quantiles by exact PMF summation |

**Why the mix instead of per-product time series.** Croston/SBA/TSB are the
standard intermittent-demand methods and would be right if each product were its
own series. They are not used here because the only series smoothed is the cart
total — comparatively dense — and product-level intermittency is absorbed by the
mix and the count distribution. With 2 carts and 21 ever-sold products, a
per-series method has nothing to fit. TSB is worth revisiting once individual
products have multi-month histories of their own.

**P90 is a newsvendor critical fractile**, not a confidence bound: at 0.9 you are
asserting a stockout costs about 9× carrying a spare kit. A cart cannot restock
mid-day, which is what justifies a quantile that high. Configurable via
`FORECAST_SERVICE_QUANTILE`.

**Quantiles do not add.** `Σ P90(product)` is much larger than `P90(cart)` — it
describes a day where every product simultaneously hits its 90th percentile,
which does not happen. Cart and product quantiles are each computed from their
own distribution. Expectations *do* add, so cart revenue is summed from products.

## Campaigns

`promotions` is a promo-*code* engine with no product or location scoping, and
`spotlight_banners` has no date range — neither can express "20% off Mojitos at
Hacienda this weekend", nor be replayed historically. Rather than extend the
promo engine (which would mean touching checkout and payment paths for a
reporting feature), campaigns live in `forecast_campaigns`, decoupled from the
money path.

**A campaign recorded here changes forecasts only. It grants no discount.**

One campaign carries one uplift number, and its `scope` decides where it lands:

- `network` / `cart` → **volume**: raises the cart's expected units.
- `product` → **mix**: raises the targeted products' shares. Because shares are
  renormalised, this necessarily takes share from everything else, so
  cannibalisation falls out of the structure rather than needing its own term.

A product push that should *also* grow total volume is two campaigns. That is
intentional: one observed ratio cannot be decomposed into "grew the category" and
"shifted the mix", and being made to say which you mean beats guessing a split.

Both directions are handled:

- **Backward** — a campaign day's lift is divided back out before the smoother
  sees it, so a promotion never permanently inflates the baseline.
- **Forward** — a scheduled campaign multiplies the forecast for the days it
  covers, so carts are stocked *before* it runs.

Lift is measured as `actual / baseline_forecast`, where the forecast was made
before the model saw that day. Measuring against a number the day helped set
would flatter every campaign into looking exactly as planned.

**Exposure is asymmetric, deliberately.** Backwards, what matters is that a code
was *used*, not that it existed — a code nobody redeemed produced no lift and is
skipped rather than scored as a failure. Forwards, redemption share is unknowable,
so the campaign's planned exposure is used instead.

**Post-promotion dip** (`pull_forward_ratio`) exists as a hook and defaults to
**0**. The effect is real and documented (Macé & Neslin 2004), but at this sample
size it is not identifiable and a fabricated number would be worse than none.

## Files

| File | Role |
|---|---|
| `config.js` | every tunable, with the reasoning for each default |
| `businessDate.js` | Cairo business-date helpers (dates are `'YYYY-MM-DD'` strings throughout, never `Date`) |
| `math.js` | pure primitives: shrinkage, Winters step, Dirichlet, NB quantiles, pinball, MASE |
| `campaigns.js` | pure lift algebra |
| `model.js` | the state machine over `math.js` |
| `store.js` | **the only file that touches Supabase** |
| `ingest.js` | orders → demand facts |
| `job.js` | the nightly run and the scheduler |
| `backtest.js` | rolling-origin evaluation (read-only) |
| `routes.js` | the HTTP surface |
| `index.js` | the module's public exports |
| `*.test.js` | `node:test`, no dependencies — `npm test` |

`math.js`, `campaigns.js` and `model.js` are pure: no I/O, no clock. That is what
makes them testable against results worked out by hand.

## The nightly run

Ordering matters and is not arbitrary:

1. ingest un-processed dates into the facts tables
2. **score** the forecast that was standing for each date
3. **record** what campaigns did on those dates
4. advance cart and product state — on **baseline** units
5. re-pool the network prior and the campaign effects
6. regenerate forecasts for the horizon

Steps 2 and 3 come before 4 because both measure the model against a day it has
not yet absorbed.

**Idempotency.** `forecast_cart_state.last_business_date` gates the recursion, so
a date already applied is skipped. Exponential smoothing is order-dependent — a
double-applied day corrupts the level silently — so this is what makes the job
safe to run twice. Facts and forecasts are upserts on their keys.

**Missed nights self-heal.** The scheduler polls (default every 15 min) for the
Cairo date rolling over rather than firing a timer at midnight, because a
one-shot timer silently skips a night whenever the process is restarting or
deploying. Outstanding days are replayed in order, capped by
`FORECAST_MAX_CATCH_UP_DAYS`.

**Rebuild.** `POST /api/forecast/rebuild` (admin only) clears derived state and
replays everything from the orders. A recursive model you cannot replay is one
you cannot audit.

## Accuracy

Scored against a **seasonal-naive (lag-7)** baseline using **MASE** (Hyndman &
Koehler 2006) — not MAPE, which is undefined on the zero-demand days that
dominate this dataset. The baseline's own error is stored alongside, so "is this
beating last Friday?" is answerable rather than asserted. The P90 is scored by
**pinball loss**, and P90 coverage should sit near 0.9 — materially below means
the dispersion estimate is too tight.

`backtest.js` does rolling-origin evaluation (Tashman 2000) in memory and writes
nothing, so it is safe against production at any time.

**Expect MASE ≥ 1 today.** The model very likely does not beat seasonal-naive
yet, and the UI says so outright. That is the intended behaviour: a forecast
nobody can check is worse than no forecast.

## Endpoints

All under `requireArea('forecast')`, except campaign CRUD
(`requireArea('forecast-campaigns')`) and rebuild (admin only).

```
GET    /api/forecast?location_id&days&products
GET    /api/forecast/accuracy?location_id&days
GET    /api/forecast/backtest?from&to
GET    /api/forecast/status
GET    /api/forecast/horizon
GET    /api/forecast/assumptions
PUT    /api/forecast/assumptions
GET    /api/forecast/campaigns
POST   /api/forecast/campaigns
PATCH  /api/forecast/campaigns/:id
DELETE /api/forecast/campaigns/:id
POST   /api/forecast/run
POST   /api/forecast/rebuild
```

## Known limitations

1. **Trading days are inferred.** `cart_daily_openings` is empty in production,
   so "was the cart open?" falls back to `location_opening_hours.is_closed` plus
   a first-sale cutoff (leading zeros before a cart ever sold are treated as
   absence, not zero demand — the standard treatment for intermittent series).
   Populating `cart_daily_openings` would remove the inference entirely.
2. **Stockouts are censored demand.** Sales are a lower bound when a product was
   unavailable, and history cannot be reconstructed —
   `v_product_location_availability` is current-state only.
3. **Campaign lift is prior-dominated** until campaigns accumulate. The UI
   distinguishes planned from measured.
4. **One instance.** The scheduler assumes Render's single web service. Scaling
   out would have both instances run the job; the date gate makes that harmless,
   but it should become an advisory lock.

## Schema

`db/migrations/20260807171440_forecast_module.sql` — 16 tables, all prefixed
`forecast_`. Applied to Supabase already; the file is the record, and re-running
it is safe.
