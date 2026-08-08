// The module's HTTP surface, mounted at /api by server/app.js.
//
// Follows the conventions in the rest of the server: plain Express handlers,
// zod safeParse at the top, requireArea for RBAC. All reads and writes go
// through store.js.

import { Router } from 'express';
import { z } from 'zod';
import { requireArea } from '../middleware/auth.js';
import { MODEL_VERSION, campaignScopes, campaignTypes, config } from './config.js';
import { addDays, dateRange, isValidDateKey, todayInCairo } from './businessDate.js';
import { mase, mean } from './math.js';
import { resolvedUplift } from './campaigns.js';
import { rebuildForecastState, runForecastUpdate } from './job.js';
import { runBacktest } from './backtest.js';
import * as store from './store.js';

export const forecastRouter = Router();

const AREA = 'forecast';
const CAMPAIGN_AREA = 'forecast-campaigns';

function fail(res, error) {
  console.error('Forecast API error', error);
  return res.status(400).json({ error: String(error.message || error) });
}

// --------------------------------------------------------------------------
// Forecast
// --------------------------------------------------------------------------

// The next N days for one cart or all of them, cart totals with their product
// breakdown.
//
// Every row carries sample_size and confidence alongside the numbers. That is
// deliberate and not decoration: a forecast built from two observations must
// never reach a screen looking like one built from two hundred.
forecastRouter.get('/forecast', requireArea(AREA), async (req, res) => {
  const parsed = z.object({
    location_id: z.string().uuid().optional(),
    days: z.coerce.number().int().min(1).max(60).optional(),
    products: z.coerce.number().int().min(1).max(200).optional()
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid forecast query.' });

  try {
    const days = parsed.data.days || 7;
    const productLimit = parsed.data.products || 15;
    const from = todayInCairo();
    const to = addDays(from, days - 1);

    const [carts, products, forecasts, latestRun] = await Promise.all([
      store.loadBeachCarts(),
      store.loadActiveProducts(),
      store.loadForecastRange({ from, to, locationId: parsed.data.location_id }),
      store.latestRun()
    ]);

    const productNames = new Map(products.map((product) => [product.id, product]));
    const campaigns = await store.loadCampaigns();
    const campaignNames = new Map(campaigns.map((campaign) => [campaign.id, campaign.name]));

    const productsByCartDate = new Map();
    for (const row of forecasts.products) {
      const key = `${row.location_id}::${row.business_date}`;
      if (!productsByCartDate.has(key)) productsByCartDate.set(key, []);
      productsByCartDate.get(key).push(row);
    }

    const cartRows = forecasts.carts.map((row) => {
      const items = (productsByCartDate.get(`${row.location_id}::${row.business_date}`) || [])
        .sort((a, b) => Number(b.expected_units) - Number(a.expected_units))
        .slice(0, productLimit)
        .map((item) => ({
          product_id: item.product_id,
          name: productNames.get(item.product_id)?.name || 'Unknown product',
          product_type: productNames.get(item.product_id)?.product_type || null,
          mix_share: Number(item.mix_share),
          expected_units: Number(item.expected_units),
          p50: item.p50,
          p90: item.p90,
          expected_revenue: Number(item.expected_revenue),
          campaign_uplift: Number(item.campaign_uplift)
        }));

      return {
        location_id: row.location_id,
        location_name: carts.find((cart) => cart.id === row.location_id)?.name || 'Unknown cart',
        business_date: row.business_date,
        horizon_days: row.horizon_days,
        expected_units: Number(row.expected_units),
        p50: row.p50,
        p90: row.p90,
        expected_orders: Number(row.expected_orders),
        expected_revenue: Number(row.expected_revenue),
        campaign_uplift: Number(row.campaign_uplift),
        campaigns: (row.campaign_ids || []).map((id) => ({ id, name: campaignNames.get(id) || 'Campaign' })),
        confidence: row.confidence,
        sample_size: row.sample_size,
        products: items
      };
    });

    res.json({
      range: { from, to, days, time_zone: 'Africa/Cairo' },
      carts: carts.filter((cart) => cart.is_active).map((cart) => ({ id: cart.id, name: cart.name })),
      forecasts: cartRows,
      model: {
        version: MODEL_VERSION,
        service_quantile: config.serviceQuantile,
        horizon_days: config.forecastHorizonDays
      },
      last_run: latestRun,
      server_time: new Date().toISOString()
    });
  } catch (error) {
    return fail(res, error);
  }
});

// --------------------------------------------------------------------------
// Accuracy
// --------------------------------------------------------------------------

// Recorded night-by-night scores plus a full rolling-origin backtest.
//
// MASE is reported against seasonal-naive, and `beats_seasonal_naive` is stated
// outright. With very little history it will read false, which is the honest
// answer and the reason this endpoint exists at all.
forecastRouter.get('/forecast/accuracy', requireArea(AREA), async (req, res) => {
  const parsed = z.object({
    location_id: z.string().uuid().optional(),
    days: z.coerce.number().int().min(7).max(365).optional()
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid accuracy query.' });

  try {
    const days = parsed.data.days || 90;
    const to = todayInCairo();
    const from = addDays(to, -days);

    const [scores, backtest] = await Promise.all([
      store.loadCartAccuracy({ from, to, locationId: parsed.data.location_id }),
      runBacktest({ from, to })
    ]);

    const absErrors = scores.map((row) => row.abs_error);
    const naiveErrors = scores.map((row) => row.naive_abs_error).filter((value) => value !== null);
    const liveMase = mase(absErrors, naiveErrors);

    res.json({
      range: { from, to },
      recorded: {
        scored_days: scores.length,
        mae: scores.length ? Number(mean(absErrors).toFixed(4)) : null,
        mase: liveMase === null ? null : Number(liveMase.toFixed(4)),
        pinball_loss: scores.length ? Number(mean(scores.map((row) => row.pinball_loss)).toFixed(4)) : null,
        p90_coverage: scores.length
          ? Number((scores.filter((row) => row.within_p90).length / scores.length).toFixed(4))
          : null,
        rows: scores
      },
      backtest,
      server_time: new Date().toISOString()
    });
  } catch (error) {
    return fail(res, error);
  }
});

// --------------------------------------------------------------------------
// Planning assumptions
// --------------------------------------------------------------------------

forecastRouter.get('/forecast/assumptions', requireArea(AREA), async (_req, res) => {
  try {
    const [carts, assumptions] = await Promise.all([store.loadBeachCarts(), store.loadAssumptions()]);

    res.json({
      carts: carts.filter((cart) => cart.is_active).map((cart) => ({ id: cart.id, name: cart.name })),
      assumptions: [...assumptions.entries()].flatMap(([locationId, byDow]) =>
        [...byDow.entries()].map(([dayOfWeek, row]) => ({ location_id: locationId, day_of_week: dayOfWeek, ...row }))),
      default_prior_strength_days: config.levelPriorDays
    });
  } catch (error) {
    return fail(res, error);
  }
});

// Written as a whole week for one cart, not row by row. A weekday profile is
// one judgement, and saving it in pieces invites a half-updated week that
// nobody notices.
forecastRouter.put('/forecast/assumptions', requireArea(AREA), async (req, res) => {
  const parsed = z.object({
    location_id: z.string().uuid(),
    rows: z.array(z.object({
      day_of_week: z.number().int().min(0).max(6),
      expected_units: z.number().min(0).nullable().optional(),
      expected_orders: z.number().min(0).nullable().optional(),
      prior_strength_days: z.number().int().min(1).max(365).optional(),
      notes: z.string().max(500).nullable().optional()
    })).min(1).max(7)
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid assumptions payload.' });

  try {
    await store.upsertAssumptions(parsed.data.rows.map((row) => ({
      location_id: parsed.data.location_id,
      day_of_week: row.day_of_week,
      expected_units: row.expected_units ?? null,
      expected_orders: row.expected_orders ?? null,
      prior_strength_days: row.prior_strength_days ?? config.levelPriorDays,
      notes: row.notes ?? null,
      updated_by: req.user?.employee_id || null,
      updated_at: new Date().toISOString()
    })));

    res.json({ ok: true });
  } catch (error) {
    return fail(res, error);
  }
});

// --------------------------------------------------------------------------
// Campaigns
// --------------------------------------------------------------------------

const campaignBody = z.object({
  name: z.string().min(1).max(200),
  campaign_type: z.enum(campaignTypes),
  scope: z.enum(campaignScopes),
  starts_on: z.string().refine(isValidDateKey, 'starts_on must be YYYY-MM-DD'),
  ends_on: z.string().refine(isValidDateKey, 'ends_on must be YYYY-MM-DD'),
  promotion_id: z.string().uuid().nullable().optional(),
  discount_pct: z.number().min(0).max(100).nullable().optional(),
  expected_uplift_pct: z.number().gt(-100).max(400).optional(),
  expected_promo_order_share: z.number().min(0).max(1).nullable().optional(),
  is_active: z.boolean().optional(),
  notes: z.string().max(2000).nullable().optional(),
  location_ids: z.array(z.string().uuid()).optional(),
  product_ids: z.array(z.string().uuid()).optional()
}).refine((value) => value.ends_on >= value.starts_on, {
  message: 'ends_on must not precede starts_on'
});

forecastRouter.get('/forecast/campaigns', requireArea(CAMPAIGN_AREA), async (_req, res) => {
  try {
    const [campaigns, effects, carts, products] = await Promise.all([
      store.loadCampaigns(),
      store.loadCampaignEffects(),
      store.loadBeachCarts(),
      store.loadActiveProducts()
    ]);

    res.json({
      campaigns: campaigns.map((campaign) => {
        // Show the plan and the measurement side by side. A lift the model is
        // still taking on trust must be distinguishable from one it has seen.
        const resolved = resolvedUplift(campaign, effects);
        return {
          ...campaign,
          resolved_uplift: Number(resolved.uplift.toFixed(4)),
          uplift_source: resolved.source,
          learned_uplift: campaign.learned_log_uplift === null
            ? null
            : Number(Math.exp(campaign.learned_log_uplift).toFixed(4))
        };
      }),
      carts: carts.filter((cart) => cart.is_active).map((cart) => ({ id: cart.id, name: cart.name })),
      products: products.map((product) => ({ id: product.id, name: product.name, product_type: product.product_type })),
      campaign_types: campaignTypes,
      scopes: campaignScopes
    });
  } catch (error) {
    return fail(res, error);
  }
});

forecastRouter.post('/forecast/campaigns', requireArea(CAMPAIGN_AREA), async (req, res) => {
  const parsed = campaignBody.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.issues[0]?.message || 'Invalid campaign.' });

  const { location_ids: locationIds, product_ids: productIds, ...fields } = parsed.data;

  try {
    const campaign = await store.createCampaign(fields, { locationIds: locationIds || [], productIds: productIds || [] });
    res.status(201).json(campaign);
  } catch (error) {
    return fail(res, error);
  }
});

forecastRouter.patch('/forecast/campaigns/:id', requireArea(CAMPAIGN_AREA), async (req, res) => {
  const idParsed = z.string().uuid().safeParse(req.params.id);
  if (!idParsed.success) return res.status(400).json({ error: 'Invalid campaign id.' });

  const parsed = campaignBody.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.issues[0]?.message || 'Invalid campaign.' });

  const { location_ids: locationIds, product_ids: productIds, ...fields } = parsed.data;

  try {
    if (Object.keys(fields).length) await store.updateCampaign(idParsed.data, fields);
    if (locationIds || productIds) {
      await store.replaceCampaignScope(idParsed.data, { locationIds, productIds });
    }
    res.json({ ok: true });
  } catch (error) {
    return fail(res, error);
  }
});

forecastRouter.delete('/forecast/campaigns/:id', requireArea(CAMPAIGN_AREA), async (req, res) => {
  const parsed = z.string().uuid().safeParse(req.params.id);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid campaign id.' });

  try {
    await store.deleteCampaign(parsed.data);
    res.json({ ok: true });
  } catch (error) {
    return fail(res, error);
  }
});

// --------------------------------------------------------------------------
// Operations
// --------------------------------------------------------------------------

forecastRouter.get('/forecast/status', requireArea(AREA), async (_req, res) => {
  try {
    const [latest, states] = await Promise.all([store.latestRun(), store.loadCartStates()]);
    res.json({
      last_run: latest,
      model_version: MODEL_VERSION,
      carts: [...states.values()].map((state) => ({
        location_id: state.location_id,
        observations: state.observations,
        last_business_date: state.last_business_date,
        level: state.level,
        dow_index: state.dow_index
      }))
    });
  } catch (error) {
    return fail(res, error);
  }
});

// Run the nightly update now. Safe to call repeatedly: a date already absorbed
// is gated out by last_business_date, so a second run is a no-op rather than a
// second helping of the same day.
forecastRouter.post('/forecast/run', requireArea(AREA), async (req, res) => {
  const parsed = z.object({
    through: z.string().refine(isValidDateKey).optional()
  }).safeParse(req.body || {});

  if (!parsed.success) return res.status(400).json({ error: 'Invalid run payload.' });

  try {
    res.json(await runForecastUpdate({ trigger: 'manual', through: parsed.data.through }));
  } catch (error) {
    return fail(res, error);
  }
});

// Throw away every derived number and replay from the orders. The escape hatch
// that keeps a recursive model auditable — restricted to admins because it
// rewrites the whole accuracy history along with the state.
forecastRouter.post('/forecast/rebuild', requireArea(AREA), async (req, res) => {
  if (req.user?.role !== 'admin') return res.status(403).json({ error: 'Rebuilding the forecast requires an admin.' });

  try {
    res.json(await rebuildForecastState());
  } catch (error) {
    return fail(res, error);
  }
});

// Read-only evaluation over whatever history exists. Writes nothing, so it is
// safe to run against production at any time.
forecastRouter.get('/forecast/backtest', requireArea(AREA), async (req, res) => {
  const parsed = z.object({
    from: z.string().refine(isValidDateKey).optional(),
    to: z.string().refine(isValidDateKey).optional()
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid backtest range.' });

  try {
    res.json(await runBacktest(parsed.data));
  } catch (error) {
    return fail(res, error);
  }
});

// Kept for callers that want the module's own view of the horizon without
// re-deriving it from config on the client.
forecastRouter.get('/forecast/horizon', requireArea(AREA), (_req, res) => {
  const from = todayInCairo();
  res.json({ from, dates: dateRange(from, addDays(from, config.forecastHorizonDays - 1)) });
});
