// Campaign (promotion) lift algebra. Pure functions over plain objects — the
// rows come from store.js, nothing here touches Supabase.
//
// A promotion breaks a naive smoother twice. The campaign day inflates the
// level, so every forecast after it is too high; and the NEXT campaign is not
// anticipated at all, so carts under-stock exactly when demand peaks. Both are
// fixed by the standard retail base-and-lift decomposition (Cooper et al. 1999;
// van Heerde, Leeflang & Wittink 2000): split observed sales into baseline
// demand and promotional uplift, smooth only the baseline, forecast the lift
// separately.
//
// Lift is multiplicative and enters at one of two places depending on scope:
//
//   network / cart -> cart volume:  lambda = level * dow * U
//   product        -> product mix:  share_p proportional to alpha_p * V_p, renormalised
//
// ONE campaign carries ONE uplift number, and its scope decides where that
// number lands. A product campaign that is also expected to grow total volume
// is two campaigns, not one with a split factor — because with this much data a
// single observed ratio cannot be decomposed into "grew the category" and
// "shifted the mix", and guessing the split would be inventing precision. Being
// made to say which one you mean is the honest interface.
//
// Because product shares are renormalised after V is applied, promoting one
// cocktail mechanically takes share from the others: cannibalisation is a
// consequence of the structure rather than a term someone has to remember to
// add.

import { clamp, normaliseShares, shrinkLog } from './math.js';
import { config, discountBucket } from './config.js';

// A campaign covers a cart-date when it is active, the date is inside its
// window, and its location set either names that cart or is empty (= all carts).
export function campaignCoversCart(campaign, locationId, dateKey) {
  if (!campaign.is_active) return false;
  if (dateKey < campaign.starts_on || dateKey > campaign.ends_on) return false;
  const locations = campaign.location_ids || [];
  return locations.length === 0 || locations.includes(locationId);
}

export function campaignsForCartDay(campaigns, locationId, dateKey) {
  return campaigns.filter((campaign) => campaignCoversCart(campaign, locationId, dateKey));
}

// The prior a campaign starts from: the manager's planned uplift when they set
// one, otherwise the pooled estimate for campaigns of this type and discount
// depth, otherwise no lift at all.
//
// Falling back to the pooled effect is what makes the third campaign of a kind
// forecastable. A single campaign never runs for enough days to estimate its own
// lift, but "20-30%-off codes" accumulates evidence across all of them.
export function priorUplift(campaign, effects) {
  const planned = Number(campaign.expected_uplift_pct);
  if (Number.isFinite(planned) && planned !== 0) {
    return clamp(1 + planned / 100, config.minUplift, config.maxUplift);
  }

  const key = effectKey(campaign.campaign_type, campaign.discount_pct);
  const pooled = effects.get(key);
  if (pooled && pooled.observations > 0) {
    return clamp(Math.exp(Number(pooled.log_uplift_mean) || 0), config.minUplift, config.maxUplift);
  }

  return 1;
}

export function effectKey(campaignType, discountPct) {
  return `${campaignType || 'other'}::${discountBucket(discountPct)}`;
}

// The lift actually used for a campaign: measurement shrunk toward the plan.
//
// `campaignPriorObs` days of the campaign genuinely running are needed before
// what was measured outweighs what was planned, so one unusual day cannot
// rewrite the lift. The clamp is the last line of defence — a measured 12x is a
// data problem, not a marketing triumph, and must never reach a stocking number.
export function resolvedUplift(campaign, effects) {
  const prior = priorUplift(campaign, effects);
  const observations = Number(campaign.learned_observations) || 0;

  if (!observations || campaign.learned_log_uplift === null || campaign.learned_log_uplift === undefined) {
    return { uplift: prior, source: 'planned', observations: 0 };
  }

  const learned = Math.exp(Number(campaign.learned_log_uplift));
  const blended = shrinkLog(learned, prior, observations, config.campaignPriorObs);

  return {
    uplift: clamp(blended, config.minUplift, config.maxUplift),
    source: observations >= config.campaignPriorObs ? 'learned' : 'blended',
    observations
  };
}

// Combined volume multiplier for a cart-date. Overlapping campaigns compound,
// then the product is clamped as well: two 3x campaigns must not authorise
// stocking for 9x.
export function cartUplift(campaigns, locationId, dateKey, effects) {
  const active = campaignsForCartDay(campaigns, locationId, dateKey)
    .filter((campaign) => campaign.scope !== 'product');

  let uplift = 1;
  const ids = [];
  for (const campaign of active) {
    uplift *= resolvedUplift(campaign, effects).uplift;
    ids.push(campaign.id);
  }

  return { uplift: clamp(uplift, config.minUplift, config.maxUplift), campaignIds: ids };
}

// Per-product mix multipliers for a cart-date. A product-scoped campaign with no
// products listed targets the whole menu, which after renormalisation is a no-op
// — correctly, since lifting everything equally shifts nothing.
export function productUplifts(campaigns, locationId, dateKey, effects) {
  const active = campaignsForCartDay(campaigns, locationId, dateKey)
    .filter((campaign) => campaign.scope === 'product');

  const uplifts = new Map();
  for (const campaign of active) {
    const { uplift } = resolvedUplift(campaign, effects);
    for (const productId of campaign.product_ids || []) {
      uplifts.set(productId, (uplifts.get(productId) || 1) * uplift);
    }
  }
  return uplifts;
}

// Apply mix multipliers and renormalise. The renormalisation is the whole point:
// shares must still sum to 1, so lifting the targeted products necessarily
// lowers everything else.
export function applyProductUplifts(shares, uplifts) {
  if (!uplifts.size) return shares;

  const lifted = new Map();
  for (const [productId, share] of shares) {
    lifted.set(productId, share * (uplifts.get(productId) || 1));
  }
  return normaliseShares(lifted);
}

// Divide the lift back out of an observed day, so the smoother learns the
// baseline rather than the promotion. Without this the campaign permanently
// raises the cart's level and every subsequent ordinary day is over-forecast.
export function deflateToBaseline(units, uplift) {
  const factor = uplift > 0 ? uplift : 1;
  return units / factor;
}

// Record what a campaign day actually did, as a ratio to the forecast the model
// made BEFORE it saw that day. Measuring against a number the day helped set
// would flatter the model into believing every campaign worked exactly as
// planned.
//
// A campaign nobody redeemed produced no lift and must not be scored as a failed
// one: a promo-code campaign with zero promo orders is skipped, not recorded as
// a ratio near 1 that would drag the pooled estimate down.
export function observationFor({ campaign, locationId, dateKey, actualUnits, baselineForecast, promoOrderShare }) {
  if (!(baselineForecast > 0)) return null;
  if (campaign.campaign_type === 'promo_code' && !(promoOrderShare > 0)) return null;

  return {
    campaign_id: campaign.id,
    location_id: locationId,
    business_date: dateKey,
    actual_units: Math.round(actualUnits),
    baseline_forecast: Number(baselineForecast.toFixed(4)),
    ratio: Number((actualUnits / baselineForecast).toFixed(5)),
    promo_order_share: Number((promoOrderShare || 0).toFixed(4))
  };
}

// Geometric mean of a campaign's observed ratios — the arithmetic mean of logs.
// Ratios are averaged in log space so that a day at 0.5x and a day at 2.0x
// average to 1.0x rather than 1.25x.
export function learnedLogUplift(observations) {
  const logs = observations
    .map((row) => Number(row.ratio))
    .filter((ratio) => Number.isFinite(ratio) && ratio > 0)
    .map((ratio) => Math.log(ratio));

  if (!logs.length) return null;
  return logs.reduce((sum, value) => sum + value, 0) / logs.length;
}

// Pool every campaign's observations into per-(type, bucket) priors, so the next
// campaign of a familiar shape starts from evidence instead of from 1.
export function poolCampaignEffects(campaigns, observationsByCampaign) {
  const buckets = new Map();

  for (const campaign of campaigns) {
    const rows = observationsByCampaign.get(campaign.id) || [];
    if (!rows.length) continue;

    const key = effectKey(campaign.campaign_type, campaign.discount_pct);
    const bucket = buckets.get(key) || { logs: [], campaignType: campaign.campaign_type || 'other', discountBucketKey: discountBucket(campaign.discount_pct) };

    for (const row of rows) {
      const ratio = Number(row.ratio);
      if (Number.isFinite(ratio) && ratio > 0) bucket.logs.push(Math.log(ratio));
    }
    buckets.set(key, bucket);
  }

  const effects = [];
  for (const bucket of buckets.values()) {
    if (!bucket.logs.length) continue;
    const logMean = bucket.logs.reduce((sum, value) => sum + value, 0) / bucket.logs.length;

    // Clamp so a pooled prior can never sit outside the range a resolved uplift
    // is allowed to take, then round TOWARD ZERO to six decimals — the column is
    // numeric(10,6), and ordinary rounding at the boundary lands just outside
    // the clamp (exp of a rounded-up log(5) is 5.0000004). Truncating toward
    // zero always moves the multiplier toward 1, which is inside the range from
    // either side.
    const bounded = clamp(Math.exp(logMean), config.minUplift, config.maxUplift);
    const boundedLog = Math.trunc(Math.log(bounded) * 1e6) / 1e6;

    effects.push({
      campaign_type: bucket.campaignType,
      discount_bucket: bucket.discountBucketKey,
      log_uplift_mean: boundedLog,
      observations: bucket.logs.length
    });
  }
  return effects;
}
