import crypto from 'crypto';
import { Router } from 'express';
import { z } from 'zod';
import { ACTIVE_PAYMENT_PROVIDER, isDemoPaymentMode, isProd, PAYMENT_MODE, SESSION_SECRET } from '../config/appConfig.js';
import { clean } from '../lib/objectUtils.js';
import { getCookie } from '../lib/session.js';
import {
  createGeideaSession,
  extractGeideaCallbackFields,
  extractGeideaSavedCard,
  formatGeideaAmount,
  geideaCallbackIsSuccess,
  geideaCheckoutConfig,
  geideaIsConfigured,
  verifyGeideaCallbackSignature
} from '../lib/geidea.js';
import {
  constructStripeEvent,
  createStripeEphemeralKey,
  createStripePaymentIntent,
  extractStripeAmount,
  extractStripeSavedCard,
  resolveStripeCustomerId,
  stripeCheckoutConfig,
  stripeIsConfigured,
  stripeMinorUnits
} from '../lib/stripe.js';
import { supabase } from '../lib/supabase.js';
import { publicNotification, registerCustomerPushToken } from '../lib/notifications.js';

export const customerRouter = Router();

const CUSTOMER_COOKIE = 'ebtl_customer';
const CUSTOMER_TOKEN_MAX_AGE_SECONDS = 365 * 24 * 60 * 60;
const BUSINESS_TIME_ZONE = 'Africa/Cairo';
const CURRENCY = 'EGP';
const PAYMENT_PROVIDER = 'geidea';
const STRIPE_PAYMENT_PROVIDER = 'stripe';
const DEMO_PAYMENT_PROVIDER = 'demo';

// The live provider backing this deployment's checkout ('geidea' or 'stripe').
const LIVE_PAYMENT_PROVIDER = ACTIVE_PAYMENT_PROVIDER;
const isStripeProvider = LIVE_PAYMENT_PROVIDER === STRIPE_PAYMENT_PROVIDER;

function liveProviderIsConfigured() {
  return isStripeProvider ? stripeIsConfigured() : geideaIsConfigured();
}

// Collapse whatever method key the client sent onto the canonical key for the
// active provider, so a generic 'payment_gateway' works regardless of provider.
function normalizeCheckoutPaymentMethod(method) {
  if (isDemoPaymentMode) return 'demo_checkout';

  if (isStripeProvider) return 'stripe_payment_sheet';

  return method === 'payment_gateway' ? 'geidea_card' : method;
}

// The client routes on nextScreen to decide which payment UI to present.
function gatewayNextScreen(provider) {
  if (provider === DEMO_PAYMENT_PROVIDER) return 'order_confirmed';
  if (provider === STRIPE_PAYMENT_PROVIDER) return 'stripe_payment';
  return 'geidea_payment';
}
const EGYPT_MOBILE_SIMPLE_RE = /^0\d{10}$/;
const MAX_CART_ITEM_QTY = 99;
const FULFILLMENT_TYPES = ['pickup_at_cart', 'delivery_to_unit'];
const CUSTOMER_PROFILE_ORDER_LIMIT = 5;
const CUSTOMER_PROFILE_AVATAR_ASSET = 'assets/images/profile/default-profile.webp';
const CUSTOMER_GENDER_VALUES = ['male', 'female'];

const uuid = z.string().uuid();
const optionalUuid = uuid.optional();

const uuidArrayFromQuery = z.preprocess((value) => {
  if (Array.isArray(value)) return value.flatMap((entry) => String(entry).split(','));
  if (typeof value === 'string') return value.split(',').map((entry) => entry.trim()).filter(Boolean);
  return [];
}, z.array(uuid));

function sign(value) {
  return crypto.createHmac('sha256', SESSION_SECRET).update(value).digest('base64url');
}

function encodeCustomerToken(customerId) {
  const payload = Buffer.from(JSON.stringify({
    customer_id: customerId,
    exp: Date.now() + CUSTOMER_TOKEN_MAX_AGE_SECONDS * 1000
  })).toString('base64url');

  return `${payload}.${sign(payload)}`;
}

function decodeCustomerToken(token) {
  try {
    if (!token || !token.includes('.')) return null;

    const [payload, signature] = String(token).split('.');
    const expected = sign(payload);

    if (signature.length !== expected.length) return null;
    if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;

    const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (!decoded.customer_id || !decoded.exp || Date.now() > decoded.exp) return null;

    return decoded.customer_id;
  } catch {
    return null;
  }
}

function readCustomerToken(req) {
  const headerToken = req.headers['x-ebtl-customer-token'];
  if (headerToken) return String(headerToken);

  const authHeader = req.headers.authorization || '';
  if (authHeader.toLowerCase().startsWith('bearer ')) return authHeader.slice(7).trim();

  return getCookie(req, CUSTOMER_COOKIE);
}

function setCustomerToken(res, customerId) {
  const token = encodeCustomerToken(customerId);
  const secure = isProd ? '; Secure' : '';

  res.setHeader(
    'Set-Cookie',
    `${CUSTOMER_COOKIE}=${token}; HttpOnly; Path=/; SameSite=Lax; Max-Age=${CUSTOMER_TOKEN_MAX_AGE_SECONDS}${secure}`
  );

  res.setHeader('X-EBTL-Customer-Token', token);

  return token;
}

function sessionPayload(customerId, token) {
  return {
    customer_id: customerId,
    customer_session_token: token,
    token_type: 'Bearer'
  };
}

function cairoParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: BUSINESS_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23'
  }).formatToParts(date);

  return Object.fromEntries(
    parts
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, Number(part.value)])
  );
}

function cairoLocalToUtc({ year, month, day, hour = 0, minute = 0, second = 0 }) {
  const wantedLocalMs = Date.UTC(year, month - 1, day, hour, minute, second);
  const firstGuess = new Date(wantedLocalMs);
  const actualParts = cairoParts(firstGuess);

  const actualLocalMs = Date.UTC(
    actualParts.year,
    actualParts.month - 1,
    actualParts.day,
    actualParts.hour,
    actualParts.minute,
    actualParts.second
  );

  return new Date(firstGuess.getTime() - (actualLocalMs - wantedLocalMs));
}

function startOfTodayCairoUtc() {
  const nowParts = cairoParts(new Date());
  return cairoLocalToUtc({
    year: nowParts.year,
    month: nowParts.month,
    day: nowParts.day
  });
}

function startOfTomorrowCairoUtc() {
  const start = startOfTodayCairoUtc();
  const tomorrowInCairo = cairoParts(new Date(start.getTime() + 36 * 60 * 60 * 1000));

  return cairoLocalToUtc({
    year: tomorrowInCairo.year,
    month: tomorrowInCairo.month,
    day: tomorrowInCairo.day
  });
}

function cartExpiresAtIso() {
  return startOfTomorrowCairoUtc().toISOString();
}

function money(value) {
  return Number(Number(value || 0).toFixed(2));
}

function normalizeString(value) {
  return String(value || '').trim().toLowerCase();
}


function normalizeUuidList(value) {
  const entries = Array.isArray(value) ? value : [];
  return [...new Set(entries.map((entry) => String(entry || '').trim()).filter(Boolean))];
}

function normalizeAdditionQuantity(value) {
  const quantity = Number(value ?? 1);
  if (!Number.isFinite(quantity)) return 1;
  return Math.max(1, Math.min(MAX_CART_ITEM_QTY, Math.floor(quantity)));
}

function normalizeRawCustomization(data = {}) {
  const raw = data.customization && typeof data.customization === 'object'
    ? data.customization
    : {};

  const removedRecipeItemIds = normalizeUuidList(
    raw.removed_recipe_item_ids
      || raw.remove_recipe_item_ids
      || raw.removedRecipeItemIds
      || raw.removeRecipeItemIds
      || data.removed_recipe_item_ids
      || data.remove_recipe_item_ids
      || data.removedRecipeItemIds
      || data.removeRecipeItemIds
      || []
  );

  const rawAdditions = Array.isArray(raw.additions)
    ? raw.additions
    : (Array.isArray(data.additions) ? data.additions : []);

  const additions = rawAdditions.map((entry) => {
    const value = entry && typeof entry === 'object' ? entry : {};
    return {
      addonProductId: value.addon_product_id || value.addonProductId || value.product_id || value.productId || null,
      addonVariantId: value.addon_variant_id || value.addonVariantId || value.variant_id || value.variantId || null,
      quantity: normalizeAdditionQuantity(value.quantity_per_parent ?? value.quantityPerParent ?? value.quantity ?? 1)
    };
  }).filter((entry) => entry.addonVariantId || entry.addonProductId);

  return {
    removedRecipeItemIds,
    additions
  };
}

function customizationHashFor({ removedRecipeItemIds = [], additions = [] } = {}) {
  const payload = {
    removed_recipe_item_ids: [...removedRecipeItemIds].sort(),
    additions: [...additions]
      .map((entry) => ({
        addon_variant_id: entry.addonVariantId || entry.addon_variant_id,
        quantity: normalizeAdditionQuantity(entry.quantity ?? entry.quantity_per_parent)
      }))
      .filter((entry) => entry.addon_variant_id)
      .sort((a, b) => String(a.addon_variant_id).localeCompare(String(b.addon_variant_id)))
  };

  if (!payload.removed_recipe_item_ids.length && !payload.additions.length) return 'base';

  return crypto.createHash('sha256').update(JSON.stringify(payload)).digest('hex');
}

function joinDisplayNames(names = []) {
  const cleanNames = names.map((name) => String(name || '').trim()).filter(Boolean);
  if (!cleanNames.length) return '';
  if (cleanNames.length === 1) return cleanNames[0];
  if (cleanNames.length === 2) return `${cleanNames[0]} and ${cleanNames[1]}`;
  return `${cleanNames.slice(0, -1).join(', ')} and ${cleanNames[cleanNames.length - 1]}`;
}

function customizationSummary({ removedIngredients = [], additions = [] } = {}) {
  const parts = [];
  const removedNames = removedIngredients.map((item) => item.ingredient_name_snapshot || item.name);
  if (removedNames.length) parts.push(`No ${joinDisplayNames(removedNames)}`);

  const additionLabels = additions.map((item) => {
    const name = item.product_name_snapshot || item.name;
    const quantity = Number(item.quantity_per_parent || item.quantity || 1);
    return quantity > 1 ? `${name} x${quantity}` : name;
  });
  if (additionLabels.length) parts.push(`Add ${joinDisplayNames(additionLabels)}`);

  return parts.join('. ') || null;
}

function additionUnitPrice(addition) {
  return money(Number(addition.unit_price_inc_vat_snapshot || addition.price_inc_vat || 0) * Number(addition.quantity_per_parent || addition.quantity || 1));
}

function addonLineTax(addition, parentQuantity = 1) {
  const lineIncVat = money(
    Number(addition.unit_price_inc_vat_snapshot || 0)
    * Number(addition.quantity_per_parent || 1)
    * Number(parentQuantity || 1)
  );
  const vatRate = Number(addition.vat_rate_snapshot || 0);
  const lineExVat = vatRate > 0 ? money(lineIncVat / (1 + vatRate)) : lineIncVat;
  return {
    line_inc_vat: lineIncVat,
    line_ex_vat: lineExVat,
    line_vat_amount: money(lineIncVat - lineExVat)
  };
}

function configuredLineTax(item, fallbackVatRate = 0) {
  const quantity = Number(item.quantity || 1);
  const baseUnitPrice = money(
    item.base_unit_price_inc_vat_snapshot ??
    (Number(item.unit_price_inc_vat_snapshot || 0) - Number(item.customization_total_inc_vat_snapshot || 0))
  );
  const baseVatRate = Number(item.vat_rate_snapshot ?? fallbackVatRate ?? 0);
  const baseLineIncVat = money(baseUnitPrice * quantity);
  const baseLineExVat = baseVatRate > 0 ? money(baseLineIncVat / (1 + baseVatRate)) : baseLineIncVat;

  const addonTotals = (item.cart_item_additions || []).reduce((sum, addition) => {
    const tax = addonLineTax(addition, quantity);
    return {
      line_inc_vat: money(sum.line_inc_vat + tax.line_inc_vat),
      line_ex_vat: money(sum.line_ex_vat + tax.line_ex_vat),
      line_vat_amount: money(sum.line_vat_amount + tax.line_vat_amount)
    };
  }, { line_inc_vat: 0, line_ex_vat: 0, line_vat_amount: 0 });

  const finalLineIncVat = money(Number(item.unit_price_inc_vat_snapshot || 0) * quantity);
  const calculatedLineIncVat = money(baseLineIncVat + addonTotals.line_inc_vat);
  const lineIncVat = Math.abs(finalLineIncVat - calculatedLineIncVat) <= 0.02 ? finalLineIncVat : calculatedLineIncVat;
  const lineExVat = money(baseLineExVat + addonTotals.line_ex_vat);

  return {
    line_inc_vat: lineIncVat,
    line_ex_vat: lineExVat,
    line_vat_amount: money(lineIncVat - lineExVat)
  };
}

function publicRemovedIngredient(row) {
  return {
    id: row.id || null,
    recipe_item_id: row.recipe_item_id || null,
    ingredient_id: row.ingredient_id || null,
    name: row.ingredient_name_snapshot || row.name || null,
    quantity: row.quantity_snapshot ?? row.quantity ?? null,
    unit: row.unit_snapshot || row.unit || null
  };
}

function publicCartAddition(row) {
  return {
    id: row.id || null,
    product_id: row.addon_product_id || null,
    variant_id: row.addon_variant_id || null,
    recipe_id: row.addon_recipe_id || null,
    name: row.product_name_snapshot || null,
    variant_name: row.variant_name_snapshot || null,
    quantity_per_parent: Number(row.quantity_per_parent || 1),
    unit_price_inc_vat: money(row.unit_price_inc_vat_snapshot || 0),
    line_unit_price_inc_vat: additionUnitPrice(row),
    vat_rate: Number(row.vat_rate_snapshot || 0),
    currency: CURRENCY
  };
}

function buildCustomizationPayloadForCartItem(item) {
  const removedIngredients = item.cart_item_removed_ingredients || [];
  const additions = item.cart_item_additions || [];

  return {
    hash: item.customization_hash || 'base',
    summary: item.customization_summary || customizationSummary({ removedIngredients, additions }),
    base_unit_price_inc_vat: money(item.base_unit_price_inc_vat_snapshot ?? item.unit_price_inc_vat_snapshot),
    customization_total_inc_vat: money(item.customization_total_inc_vat_snapshot || 0),
    removed_ingredients: removedIngredients.map(publicRemovedIngredient),
    additions: additions.map(publicCartAddition)
  };
}

function recipeIngredientIsStocked(recipeItem) {
  const ingredient = recipeItem?.ingredients || recipeItem?.ingredient || {};
  return !recipeItem?.is_customer_supplied
    && !ingredient.is_customer_supplied
    && Number(recipeItem?.quantity || 0) > 0;
}

function inventoryComponentsForConfiguredItem({
  item,
  variant,
  recipe,
  recipeItems = [],
  recipeById = new Map(),
  recipeItemsByRecipeId = new Map()
}) {
  const components = [];
  const removedRecipeItemIds = new Set(
    (item.cart_item_removed_ingredients || []).map((row) => row.recipe_item_id)
  );

  const parentServingCount = Number(variant?.serving_count || item.product_variants?.serving_count || 1);
  const parentYieldServings = Math.max(Number(recipe?.yield_servings || 1), 1);

  for (const recipeItem of recipeItems || []) {
    if (removedRecipeItemIds.has(recipeItem.id)) continue;
    if (!recipeIngredientIsStocked(recipeItem)) continue;

    components.push({
      ingredient_id: recipeItem.ingredient_id,
      ingredient_name_snapshot: recipeItem.ingredients?.name || recipeItem.ingredient?.name || 'Ingredient',
      source_type: 'base_recipe',
      source_ref_id: recipeItem.id,
      quantity_per_order_item_unit: parentServingCount * (Number(recipeItem.quantity || 0) / parentYieldServings),
      unit_snapshot: recipeItem.unit || recipeItem.ingredients?.base_unit || recipeItem.ingredient?.base_unit || null
    });
  }

  for (const addition of item.cart_item_additions || []) {
    const addonRecipe = recipeById.get(addition.addon_recipe_id);
    const addonRecipeItems = recipeItemsByRecipeId.get(addition.addon_recipe_id) || [];
    const addonYieldServings = Math.max(Number(addonRecipe?.yield_servings || 1), 1);
    const addonServingCount = Number(addition.serving_count_snapshot || 1);
    const addonQuantity = Number(addition.quantity_per_parent || 1);

    for (const recipeItem of addonRecipeItems) {
      if (!recipeIngredientIsStocked(recipeItem)) continue;

      components.push({
        ingredient_id: recipeItem.ingredient_id,
        ingredient_name_snapshot: recipeItem.ingredients?.name || recipeItem.ingredient?.name || 'Ingredient',
        source_type: 'addon_recipe',
        source_ref_id: recipeItem.id,
        quantity_per_order_item_unit: addonQuantity * addonServingCount * (Number(recipeItem.quantity || 0) / addonYieldServings),
        unit_snapshot: recipeItem.unit || recipeItem.ingredients?.base_unit || recipeItem.ingredient?.base_unit || null
      });
    }
  }

  return components.filter((component) => Number(component.quantity_per_order_item_unit || 0) > 0);
}

function buildAvailabilityForComponents({ locationId, variant, recipe, components = [], balancesByIngredientId, cartQuantity = 1 }) {
  if (!locationId) {
    return {
      is_orderable: false,
      reason: 'Choose a beach cart to check availability.'
    };
  }

  if (!variant?.is_active) {
    return {
      is_orderable: false,
      reason: 'This serving size is currently unavailable.'
    };
  }

  if (!recipe) {
    return {
      is_orderable: false,
      reason: 'This item is not ready for ordering yet.'
    };
  }

  const requiredByIngredientId = new Map();
  for (const component of components) {
    requiredByIngredientId.set(
      component.ingredient_id,
      Number(requiredByIngredientId.get(component.ingredient_id) || 0)
        + Number(cartQuantity || 1) * Number(component.quantity_per_order_item_unit || 0)
    );
  }

  for (const [ingredientId, requiredQty] of requiredByIngredientId.entries()) {
    const balance = balancesByIngredientId.get(ingredientId);
    const availableQty = Number(balance?.quantity_on_hand || 0) - Number(balance?.reserved_quantity || 0);

    if (availableQty + 1e-9 < requiredQty) {
      return {
        is_orderable: false,
        reason: 'Currently unavailable at this beach cart.'
      };
    }
  }

  return {
    is_orderable: true,
    reason: null
  };
}

async function loadCartConfigurationContext({ cartItems = [], locationId = null }) {
  const itemRows = cartItems || [];
  const parentProductIds = itemRows.map((item) => item.product_id).filter(Boolean);
  const addonProductIds = itemRows.flatMap((item) => {
    return (item.cart_item_additions || []).map((addition) => addition.addon_product_id).filter(Boolean);
  });
  const productIds = [...new Set([...parentProductIds, ...addonProductIds])];

  const catalog = productIds.length
    ? await loadCatalog({ locationId, productIds })
    : {
        data: {
          cards: [],
          raw: {
            products: [],
            variants: [],
            recipes: [],
            recipeItems: [],
            balances: []
          }
        }
      };

  if (catalog.error) return { error: catalog.error };

  const raw = catalog.data.raw || {};
  const productById = new Map((raw.products || []).map((product) => [product.id, product]));
  const cardByProductId = new Map((catalog.data.cards || []).map((card) => [card.id, card]));
  const variantById = new Map((raw.variants || []).map((variant) => [variant.id, variant]));

  const currentRecipeByProductId = new Map();
  for (const productId of productIds) {
    currentRecipeByProductId.set(
      productId,
      pickCurrentRecipe((raw.recipes || []).filter((recipe) => recipe.product_id === productId))
    );
  }

  const recipeIds = [...new Set(itemRows.flatMap((item) => {
    const parentRecipeId = item.recipe_id || currentRecipeByProductId.get(item.product_id)?.id || null;
    const addonRecipeIds = (item.cart_item_additions || []).map((addition) => {
      return addition.addon_recipe_id || currentRecipeByProductId.get(addition.addon_product_id)?.id || null;
    });
    return [parentRecipeId, ...addonRecipeIds].filter(Boolean);
  }))];

  const [recipesResult, recipeItemsResult] = recipeIds.length
    ? await Promise.all([
        supabase.from('recipes').select('*').in('id', recipeIds),
        supabase
          .from('recipe_items')
          .select('*, ingredients(id,name,category,base_unit,is_customer_supplied,icon_key)')
          .in('recipe_id', recipeIds)
      ])
    : [{ data: [], error: null }, { data: [], error: null }];

  for (const result of [recipesResult, recipeItemsResult]) {
    if (result.error) return { error: result.error };
  }

  const recipeById = new Map((recipesResult.data || []).map((recipe) => [recipe.id, recipe]));
  const recipeItemsByRecipeId = new Map();
  for (const recipeItem of recipeItemsResult.data || []) {
    const list = recipeItemsByRecipeId.get(recipeItem.recipe_id) || [];
    list.push(recipeItem);
    recipeItemsByRecipeId.set(recipeItem.recipe_id, list);
  }

  const components = itemRows.flatMap((item) => {
    const recipe = recipeById.get(item.recipe_id) || currentRecipeByProductId.get(item.product_id) || null;
    const variant = variantById.get(item.variant_id) || item.product_variants || null;
    const recipeItems = recipeItemsByRecipeId.get(recipe?.id) || [];
    return inventoryComponentsForConfiguredItem({
      item,
      variant,
      recipe,
      recipeItems,
      recipeById,
      recipeItemsByRecipeId
    });
  });

  const stockedIngredientIds = [...new Set(components.map((component) => component.ingredient_id).filter(Boolean))];
  const balances = locationId && stockedIngredientIds.length
    ? await supabase
        .from('inventory_balances')
        .select('ingredient_id,location_id,quantity_on_hand,reserved_quantity')
        .eq('location_id', locationId)
        .in('ingredient_id', stockedIngredientIds)
    : { data: [], error: null };

  if (balances.error) return { error: balances.error };

  return {
    data: {
      raw,
      productById,
      cardByProductId,
      variantById,
      currentRecipeByProductId,
      recipeById,
      recipeItemsByRecipeId,
      balancesByIngredientId: new Map((balances.data || []).map((balance) => [balance.ingredient_id, balance]))
    }
  };
}

async function validateCocktailCustomization({ customization, productId, recipe, recipeItems = [] }) {
  const removedRecipeItemIds = normalizeUuidList(customization.removedRecipeItemIds || []);
  const recipeItemById = new Map((recipeItems || []).map((item) => [item.id, item]));
  const removedIngredients = [];

  for (const recipeItemId of removedRecipeItemIds) {
    const recipeItem = recipeItemById.get(recipeItemId);
    if (!recipeItem) {
      return {
        badRequest: 'One or more removed ingredients do not belong to this cocktail recipe.'
      };
    }

    removedIngredients.push({
      recipe_item_id: recipeItem.id,
      ingredient_id: recipeItem.ingredient_id,
      ingredient_name_snapshot: recipeItem.ingredients?.name || recipeItem.ingredient?.name || 'Ingredient',
      quantity_snapshot: Number(recipeItem.quantity || 0),
      unit_snapshot: recipeItem.unit || recipeItem.ingredients?.base_unit || recipeItem.ingredient?.base_unit || null
    });
  }

  const requestedAdditions = customization.additions || [];
  const requestedVariantIds = [...new Set(requestedAdditions.map((entry) => entry.addonVariantId).filter(Boolean))];
  const requestedProductIds = [...new Set(requestedAdditions.map((entry) => entry.addonProductId).filter(Boolean))];

  if (!recipe && (removedRecipeItemIds.length || requestedAdditions.length)) {
    return {
      badRequest: 'This cocktail cannot be customized because it does not have an active recipe.'
    };
  }

  if (!requestedAdditions.length) {
    const hash = customizationHashFor({ removedRecipeItemIds, additions: [] });
    const summary = customizationSummary({ removedIngredients, additions: [] });
    return {
      data: {
        hash,
        summary,
        removedIngredients,
        additions: [],
        addonTotalIncVat: 0
      }
    };
  }

  if (!requestedVariantIds.length) {
    return {
      badRequest: 'Each cocktail addition must include an add-on variant.'
    };
  }

  const addonVariants = await supabase
    .from('product_variants')
    .select('*, products(*, product_categories(id,name,slug))')
    .in('id', requestedVariantIds)
    .eq('is_active', true);

  if (addonVariants.error) return { error: addonVariants.error };

  const addonVariantById = new Map((addonVariants.data || []).map((variant) => [variant.id, variant]));
  const normalizedAdditions = [];

  for (const request of requestedAdditions) {
    if (!request.addonVariantId) {
      return {
        badRequest: 'Each cocktail addition must include an add-on variant.'
      };
    }

    const variant = addonVariantById.get(request.addonVariantId);
    const addonProduct = variant?.products || null;

    if (!variant || !addonProduct || addonProduct.status !== 'active' || addonProduct.product_type !== 'add_on') {
      return {
        badRequest: 'One or more additions are not active add-on products.'
      };
    }

    if (request.addonProductId && request.addonProductId !== addonProduct.id) {
      return {
        badRequest: 'One or more add-on variants do not match the selected add-on product.'
      };
    }

    normalizedAdditions.push({
      addonProductId: addonProduct.id,
      addonVariantId: variant.id,
      quantity: normalizeAdditionQuantity(request.quantity),
      product: addonProduct,
      variant
    });
  }

  const addonProductIds = [...new Set(normalizedAdditions.map((entry) => entry.addonProductId))];
  const addonRecipes = addonProductIds.length
    ? await supabase
        .from('recipes')
        .select('*')
        .in('product_id', addonProductIds)
        .eq('status', 'active')
        .order('version', { ascending: false })
    : { data: [], error: null };

  if (addonRecipes.error) return { error: addonRecipes.error };

  const addonRecipeByProductId = new Map();
  for (const productId of addonProductIds) {
    addonRecipeByProductId.set(
      productId,
      pickCurrentRecipe((addonRecipes.data || []).filter((entry) => entry.product_id === productId))
    );
  }

  const missingRecipe = normalizedAdditions.find((entry) => !addonRecipeByProductId.get(entry.addonProductId));
  if (missingRecipe) {
    return {
      badRequest: `${missingRecipe.product.name} cannot be added because it does not have an active recipe.`
    };
  }

  const additions = normalizedAdditions.map((entry) => {
    const addonRecipe = addonRecipeByProductId.get(entry.addonProductId);
    return {
      addon_product_id: entry.addonProductId,
      addon_variant_id: entry.addonVariantId,
      addon_recipe_id: addonRecipe.id,
      quantity_per_parent: entry.quantity,
      product_name_snapshot: entry.product.name,
      variant_name_snapshot: entry.variant.name,
      unit_price_inc_vat_snapshot: variantPriceIncVat(entry.variant),
      vat_rate_snapshot: Number(entry.variant.vat_rate || 0),
      serving_count_snapshot: Number(entry.variant.serving_count || 1)
    };
  });

  const hash = customizationHashFor({ removedRecipeItemIds, additions: normalizedAdditions });
  const summary = customizationSummary({ removedIngredients, additions });
  const addonTotalIncVat = money(additions.reduce((sum, addition) => sum + additionUnitPrice(addition), 0));

  return {
    data: {
      hash,
      summary,
      removedIngredients,
      additions,
      addonTotalIncVat
    }
  };
}

function customizationOptionsPayload({ recipeItems = [], addonCards = [] } = {}) {
  const removableIngredients = (recipeItems || [])
    .map((recipeItem) => {
      const ingredient = recipeItem.ingredients || recipeItem.ingredient || null;
      if (!ingredient) return null;
      return {
        recipe_item_id: recipeItem.id,
        ingredient_id: recipeItem.ingredient_id,
        name: ingredient.name,
        quantity: Number(recipeItem.quantity || 0),
        unit: recipeItem.unit || ingredient.base_unit || null,
        icon_key: ingredient.icon_key || null,
        is_optional: Boolean(recipeItem.is_optional)
      };
    })
    .filter(Boolean)
    .sort((a, b) => a.name.localeCompare(b.name));

  const additions = (addonCards || []).flatMap((card) => {
    return (card.variants || []).map((variant) => ({
      product_id: card.id,
      variant_id: variant.id,
      name: card.name,
      short_description: card.short_description || null,
      image_url: card.image_url || null,
      variant_name: variant.name,
      price_inc_vat: money(variant.price_inc_vat || 0),
      currency: CURRENCY,
      availability: variant.availability || card.availability
    }));
  });

  return {
    can_customize: Boolean(removableIngredients.length || additions.length),
    rules: {
      removals_are_free: true,
      additions_are_paid: true,
      substitutions_allowed: false
    },
    removable_ingredients: removableIngredients,
    additions
  };
}

function publicLocation(location) {
  if (!location) return null;

  return {
    id: location.id,
    name: location.name,
    type: location.type,
    compound_name: location.compound_name,
    beach_name: location.beach_name,
    latitude: location.latitude,
    longitude: location.longitude,
    banner_image_url: location.banner_image_url || null,
    delivery_fee: money(location.delivery_fee || 0),
    is_active: location.is_active
  };
}

function normalizeFulfillmentType(value) {
  return FULFILLMENT_TYPES.includes(value) ? value : 'pickup_at_cart';
}

function parseTimeToMinutes(value) {
  if (!value) return null;

  const [hours, minutes] = String(value).split(':').map(Number);
  if (!Number.isFinite(hours) || !Number.isFinite(minutes)) return null;

  return hours * 60 + minutes;
}

function minutesToTimeString(minutes) {
  const normalized = ((Number(minutes) % 1440) + 1440) % 1440;
  const hours = Math.floor(normalized / 60);
  const mins = normalized % 60;

  return `${String(hours).padStart(2, '0')}:${String(mins).padStart(2, '0')}:00`;
}

function displayClock(minutes) {
  const normalized = ((Number(minutes) % 1440) + 1440) % 1440;
  const hours24 = Math.floor(normalized / 60);
  const mins = normalized % 60;
  const period = hours24 >= 12 ? 'PM' : 'AM';
  const hours12 = hours24 % 12 || 12;

  return `${hours12}:${String(mins).padStart(2, '0')} ${period}`;
}

function cairoTimeContext(date = new Date()) {
  const parts = cairoParts(date);
  const weekday = new Date(Date.UTC(parts.year, parts.month - 1, parts.day)).getUTCDay();

  return {
    ...parts,
    weekday,
    minutes_since_midnight: parts.hour * 60 + parts.minute
  };
}

function publicOpeningHour(row) {
  return {
    day_of_week: Number(row.day_of_week),
    is_closed: Boolean(row.is_closed),
    opens_at: row.opens_at || null,
    closes_at: row.closes_at || null
  };
}

function buildLocationStatus(openingHours = [], now = new Date()) {
  const context = cairoTimeContext(now);
  const rows = (openingHours || [])
    .map(publicOpeningHour)
    .filter((row) => Number.isInteger(row.day_of_week) && row.day_of_week >= 0 && row.day_of_week <= 6);

  const rowsByDay = new Map(rows.map((row) => [row.day_of_week, row]));
  const nowMinutes = context.minutes_since_midnight;

  for (const row of rows) {
    if (row.is_closed) continue;

    const opensAt = parseTimeToMinutes(row.opens_at);
    const closesAt = parseTimeToMinutes(row.closes_at);

    if (opensAt === null || closesAt === null || opensAt === closesAt) continue;

    const closesNextDay = closesAt <= opensAt;
    const isTodayWindow = row.day_of_week === context.weekday && nowMinutes >= opensAt;
    const isYesterdayOvernightWindow = closesNextDay
      && ((row.day_of_week + 1) % 7) === context.weekday
      && nowMinutes < closesAt;

    if ((isTodayWindow && (!closesNextDay ? nowMinutes < closesAt : true)) || isYesterdayOvernightWindow) {
      const closesAtDisplay = displayClock(closesAt);

      return {
        timezone: BUSINESS_TIME_ZONE,
        is_open: true,
        label: `Open now · Closes at ${closesAtDisplay}`,
        current_day_of_week: context.weekday,
        closes_at: minutesToTimeString(closesAt),
        closes_at_display: closesAtDisplay,
        opens_at: null,
        opens_at_display: null,
        next_opening: null
      };
    }
  }

  const today = rowsByDay.get(context.weekday);
  const todayOpensAt = today && !today.is_closed ? parseTimeToMinutes(today.opens_at) : null;

  if (todayOpensAt !== null && nowMinutes < todayOpensAt) {
    const opensAtDisplay = displayClock(todayOpensAt);

    return {
      timezone: BUSINESS_TIME_ZONE,
      is_open: false,
      label: `Closed now · Opens at ${opensAtDisplay}`,
      current_day_of_week: context.weekday,
      closes_at: null,
      closes_at_display: null,
      opens_at: minutesToTimeString(todayOpensAt),
      opens_at_display: opensAtDisplay,
      next_opening: {
        day_of_week: context.weekday,
        opens_at: minutesToTimeString(todayOpensAt),
        opens_at_display: opensAtDisplay
      }
    };
  }

  for (let offset = 1; offset <= 7; offset += 1) {
    const day = (context.weekday + offset) % 7;
    const row = rowsByDay.get(day);
    if (!row || row.is_closed) continue;

    const opensAt = parseTimeToMinutes(row.opens_at);
    if (opensAt === null) continue;

    return {
      timezone: BUSINESS_TIME_ZONE,
      is_open: false,
      label: 'Closed now',
      current_day_of_week: context.weekday,
      closes_at: null,
      closes_at_display: null,
      opens_at: null,
      opens_at_display: null,
      next_opening: {
        day_of_week: day,
        opens_at: minutesToTimeString(opensAt),
        opens_at_display: displayClock(opensAt)
      }
    };
  }

  return {
    timezone: BUSINESS_TIME_ZONE,
    is_open: false,
    label: rows.length ? 'Closed now' : 'Hours unavailable',
    current_day_of_week: context.weekday,
    closes_at: null,
    closes_at_display: null,
    opens_at: null,
    opens_at_display: null,
    next_opening: null
  };
}

async function loadLocationOpeningHours(locationId) {
  if (!locationId) return { data: [] };

  return supabase
    .from('location_opening_hours')
    .select('*')
    .eq('location_id', locationId)
    .order('day_of_week', { ascending: true });
}

async function loadCartLocation(locationId) {
  if (!locationId) return { data: null };

  const location = await supabase
    .from('locations')
    .select('*')
    .eq('id', locationId)
    .eq('type', 'beach_cart')
    .eq('is_active', true)
    .maybeSingle();

  if (location.error) return { error: location.error };

  if (!location.data) {
    return {
      error: new Error('Selected beach cart is not available.')
    };
  }

  const hours = await loadLocationOpeningHours(locationId);
  if (hours.error) return { error: hours.error };

  return {
    data: {
      ...publicLocation(location.data),
      current_status: buildLocationStatus(hours.data || []),
      opening_hours: (hours.data || []).map(publicOpeningHour)
    }
  };
}

function publicCategory(category) {
  if (!category) return null;

  return {
    id: category.id,
    name: category.name,
    slug: category.slug || null,
    image_url: category.image_url || null,
    sort_order: category.sort_order || 0
  };
}

function publicLiquorType(liquorType) {
  if (!liquorType) return null;

  return {
    id: liquorType.id,
    name: liquorType.name,
    image_url: liquorType.image_url || null,
    display_order: liquorType.display_order || 0
  };
}

function variantPriceIncVat(variant) {
  if (variant?.price_inc_vat !== null && variant?.price_inc_vat !== undefined) {
    return money(variant.price_inc_vat);
  }

  return money(Number(variant?.price_ex_vat || 0) * (1 + Number(variant?.vat_rate || 0)));
}

function requiredQtyForRecipeItem({
  recipeItem,
  recipe,
  variant,
  cartQuantity = 1
}) {
  const servingCount = Number(variant?.serving_count || 1);
  const yieldServings = Math.max(Number(recipe?.yield_servings || 1), 1);

  return Number(cartQuantity || 1) * servingCount * (Number(recipeItem.quantity || 0) / yieldServings);
}

function buildAvailability({
  locationId,
  recipe,
  recipeItems = [],
  balancesByIngredientId,
  variant,
  cartQuantity = 1
}) {
  if (!locationId) {
    return {
      is_orderable: false,
      reason: 'Choose a beach cart to check availability.'
    };
  }

  if (!variant?.is_active) {
    return {
      is_orderable: false,
      reason: 'This serving size is currently unavailable.'
    };
  }

  if (!recipe) {
    return {
      is_orderable: false,
      reason: 'This item is not ready for ordering yet.'
    };
  }

  const stockedItems = recipeItems.filter((item) => {
    const ingredient = item.ingredients || item.ingredient || {};
    return !item.is_customer_supplied && !ingredient.is_customer_supplied && Number(item.quantity || 0) > 0;
  });

  for (const item of stockedItems) {
    const requiredQty = requiredQtyForRecipeItem({
      recipeItem: item,
      recipe,
      variant,
      cartQuantity
    });

    const balance = balancesByIngredientId.get(item.ingredient_id);
    const availableQty = Number(balance?.quantity_on_hand || 0) - Number(balance?.reserved_quantity || 0);

    if (availableQty + 1e-9 < requiredQty) {
      return {
        is_orderable: false,
        reason: 'Currently unavailable at this beach cart.'
      };
    }
  }

  return {
    is_orderable: true,
    reason: null
  };
}

function pickCurrentRecipe(recipes) {
  return [...recipes].sort((a, b) => {
    const versionDiff = Number(b.version || 0) - Number(a.version || 0);
    if (versionDiff) return versionDiff;

    return String(b.created_at || '').localeCompare(String(a.created_at || ''));
  })[0] || null;
}

function compatibilityPayload(rows = []) {
  return rows
    .filter((row) => row.liquor_types?.is_active !== false)
    .map((row) => ({
      liquor_type_id: row.liquor_type_id,
      liquor_type_name: row.liquor_types?.name || null,
      liquor_type_image_url: row.liquor_types?.image_url || null,
      liquor_type_display_order: row.liquor_types?.display_order || 0,
      required_ml_per_serving: row.required_ml_per_serving,
      display_instruction: row.display_instruction
    }));
}

function publicProductTag(tag) {
  if (!tag) return null;

  return {
    id: tag.id,
    name: tag.name,
    color_hex: tag.color_hex,
    display_order: tag.display_order || 0
  };
}

function productTagDetails(tagNames = [], productTagsByName = new Map()) {
  return (tagNames || [])
    .map((tagName) => productTagsByName.get(String(tagName).toLowerCase()))
    .filter(Boolean)
    .map(publicProductTag);
}

function pickLatestSingleServingVariant(variants = []) {
  return [...variants]
    .filter((variant) => variant.is_active && Number(variant.serving_count) === 1)
    .sort((a, b) => String(b.created_at || '').localeCompare(String(a.created_at || '')))[0] || null;
}

function publicSelectedLiquor(compatibilityRow) {
  if (!compatibilityRow?.liquor_types) return null;

  return {
    ...publicLiquorType(compatibilityRow.liquor_types),
    required_ml_per_serving: compatibilityRow.required_ml_per_serving,
    display_instruction: compatibilityRow.display_instruction || null
  };
}

function publicCocktailIngredient(recipeItem) {
  const ingredient = recipeItem?.ingredients || recipeItem?.ingredient || null;
  if (!ingredient) return null;

  return {
    id: ingredient.id,
    name: ingredient.name,
    category: ingredient.category || null,
    icon_key: ingredient.icon_key || null,
    is_optional: Boolean(recipeItem.is_optional),
    is_customer_supplied: Boolean(recipeItem.is_customer_supplied || ingredient.is_customer_supplied)
  };
}

function cocktailIngredientsPayload(recipeItems = []) {
  const seen = new Set();

  return (recipeItems || [])
    .map(publicCocktailIngredient)
    .filter(Boolean)
    .filter((ingredient) => {
      if (seen.has(ingredient.id)) return false;
      seen.add(ingredient.id);
      return true;
    })
    .sort((a, b) => Number(a.is_customer_supplied) - Number(b.is_customer_supplied) || a.name.localeCompare(b.name));
}

function selectedVariantPayload({
  variant,
  recipe,
  recipeItems,
  balancesByIngredientId,
  locationId
}) {
  if (!variant) return null;

  const availability = buildAvailability({
    locationId,
    recipe,
    recipeItems,
    balancesByIngredientId,
    variant
  });

  return {
    id: variant.id,
    name: variant.name,
    serving_count: variant.serving_count,
    price_inc_vat: variantPriceIncVat(variant),
    vat_rate: Number(variant.vat_rate || 0),
    currency: CURRENCY,
    availability
  };
}

function singleServingAvailability({ variantPayload, recipe, locationId }) {
  if (variantPayload?.availability) return variantPayload.availability;

  if (!variantPayload) {
    return {
      is_orderable: false,
      reason: 'Single-serving cocktail is currently unavailable.'
    };
  }

  if (!locationId) {
    return {
      is_orderable: false,
      reason: 'Choose a beach cart to check availability.'
    };
  }

  if (!recipe) {
    return {
      is_orderable: false,
      reason: 'This cocktail is not ready for ordering yet.'
    };
  }

  return {
    is_orderable: false,
    reason: 'Currently unavailable.'
  };
}

const STATIC_HOW_TO_MAKE_STEPS = [
  {
    step: 1,
    title: 'Add your liquor over ice'
  },
  {
    step: 2,
    title: 'Pour in your EBTL cocktail mix'
  },
  {
    step: 3,
    title: 'Garnish, sip & enjoy'
  }
];

function cocktailDetailPayload({
  card,
  selectedVariant,
  selectedLiquor,
  recipe,
  recipeItems,
  balancesByIngredientId,
  locationId,
  addonCards = []
}) {
  const variant = selectedVariantPayload({
    variant: selectedVariant,
    recipe,
    recipeItems,
    balancesByIngredientId,
    locationId
  });

  const availability = singleServingAvailability({
    variantPayload: variant,
    recipe,
    locationId
  });

  const ingredients = cocktailIngredientsPayload(recipeItems);

  return {
    id: card.id,
    slug: card.slug,
    name: card.name,
    short_description: card.short_description,
    description: card.description,
    description_format: card.description_format,
    image_url: card.image_url,
    tags: card.tags,
    tag_details: card.tag_details,
    is_featured: card.is_featured,
    display_order: card.display_order,
    category: card.category,

    selected_liquor: selectedLiquor,
    compatible_liquors: card.compatibility,

    variant,
    availability,

    ingredients,
    included_ingredients: ingredients.filter((ingredient) => !ingredient.is_customer_supplied),
    customer_supplied_ingredients: ingredients.filter((ingredient) => ingredient.is_customer_supplied),

    customization: customizationOptionsPayload({
      recipeItems,
      addonCards
    }),

    customer_supplies_liquor: true,
    liquor_not_included: true,

    how_to_make: STATIC_HOW_TO_MAKE_STEPS,

    recipe: recipe
      ? {
          id: recipe.id,
          version: recipe.version,
          yield_servings: recipe.yield_servings
        }
      : null,

    copy: {
      bring_your_bottle_title: selectedLiquor ? 'Bring your bottle' : null,
      bring_your_bottle_name: selectedLiquor?.name || null,
      bottle_note: 'Bottle not included.',
      related_title: selectedLiquor ? `More with ${selectedLiquor.name}` : null
    }
  };
}

function relatedCocktailPayload(card) {
  const singleServingVariant = card.variants?.find((variant) => Number(variant.serving_count) === 1) || null;

  return {
    id: card.id,
    slug: card.slug,
    name: card.name,
    short_description: card.short_description || null,
    image_url: card.image_url,
    tag_details: card.tag_details || [],
    variant: singleServingVariant,
    starting_price_inc_vat: singleServingVariant?.price_inc_vat ?? card.price.starting_price_inc_vat,
    currency: CURRENCY
  };
}

function productCardPayload({
  product,
  category,
  variants,
  compatibility,
  recipe,
  recipeItems,
  balancesByIngredientId,
  locationId,
  productTagsByName = new Map()
}) {
  const activeVariants = variants.filter((variant) => variant.is_active);

  const variantPayloads = activeVariants.map((variant) => {
    const availability = buildAvailability({
      locationId,
      recipe,
      recipeItems,
      balancesByIngredientId,
      variant
    });

    return {
      id: variant.id,
      name: variant.name,
      serving_count: variant.serving_count,
      price_inc_vat: variantPriceIncVat(variant),
      currency: CURRENCY,
      availability
    };
  });

  const availableVariant = variantPayloads.find((variant) => variant.availability.is_orderable);
  const cheapestVariant = [...variantPayloads].sort((a, b) => a.price_inc_vat - b.price_inc_vat)[0];

  return {
    id: product.id,
    slug: product.slug,
    name: product.name,
    product_type: product.product_type,
    short_description: product.short_description || null,
    description: product.description,
    description_format: 'markdown',
    image_url: product.image_url,
    tags: productTagDetails(product.tags || [], productTagsByName).map((tag) => tag.name),
    tag_details: productTagDetails(product.tags || [], productTagsByName),
    prep_time_minutes: product.prep_time_minutes,    
    is_featured: product.is_featured,
    display_order: product.display_order,
    category: publicCategory(category),
    price: {
      starting_price_inc_vat: cheapestVariant?.price_inc_vat ?? 0,
      currency: CURRENCY
    },
    variants: variantPayloads,
    compatibility: compatibilityPayload(compatibility),
    availability: availableVariant
      ? {
          is_orderable: true,
          reason: null
        }
      : {
          is_orderable: false,
          reason: variantPayloads[0]?.availability?.reason || 'Currently unavailable.'
        }
  };
}

function humanizeStatus(value) {
  return String(value || '')
    .split('_')
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

function addFavoriteFlagToCard(card, favoriteProductIds = new Set()) {
  if (!card) return card;
  return {
    ...card,
    is_favorite: favoriteProductIds.has(card.id)
  };
}

function addFavoriteFlagToRelated(card, favoriteProductIds = new Set()) {
  const payload = relatedCocktailPayload(card);
  return {
    ...payload,
    is_favorite: favoriteProductIds.has(payload.id)
  };
}

function customerProfilePayload(customer) {
  const gender = CUSTOMER_GENDER_VALUES.includes(customer.gender) ? customer.gender : null;

  return {
    id: customer.id,
    full_name: customer.full_name || null,
    phone: customer.phone || null,
    email: customer.email || null,
    birthday: customer.birthday || null,
    gender,
    gender_options: [
      {
        value: 'male',
        label: 'Male'
      },
      {
        value: 'female',
        label: 'Female'
      }
    ],
    marketing_opt_in: Boolean(customer.marketing_opt_in),
    avatar: {
      type: 'local_asset',
      asset_path: CUSTOMER_PROFILE_AVATAR_ASSET,
      image_url: null,
      gender
    },
    completion: {
      has_full_name: Boolean(customer.full_name),
      has_phone: Boolean(customer.phone),
      has_email: Boolean(customer.email),
      has_gender: Boolean(gender),
      missing_fields: [
        !customer.full_name ? 'full_name' : null,
        !customer.phone ? 'phone' : null,
        !customer.email ? 'email' : null
      ].filter(Boolean)
    }
  };
}

function publicProfileOrder(order, orderItems = []) {
  const orderedItems = [...(orderItems || [])].sort((a, b) => {
    return String(a.created_at || '').localeCompare(String(b.created_at || ''));
  });

  const firstItem = orderedItems[0] || null;
  const imageItem = orderedItems.find((item) => item.products?.image_url) || firstItem;
  const totalQuantity = orderedItems.reduce((sum, item) => sum + Number(item.quantity || 0), 0);
  const displayTime = order.requested_fulfillment_at || order.created_at;

  return {
    id: order.id,
    order_number: order.order_number,
    status: order.status,
    status_label: humanizeStatus(order.status),
    payment_status: order.payment_status,
    payment_status_label: humanizeStatus(order.payment_status),
    fulfillment_type: order.fulfillment_type,
    requested_fulfillment_at: order.requested_fulfillment_at || null,
    display_fulfillment_at: displayTime,
    created_at: order.created_at,
    updated_at: order.updated_at,
    total_amount: money(order.total_amount),
    currency: CURRENCY,
    order_image_url: imageItem?.products?.image_url || null,
    primary_item: firstItem ? {
      product_id: firstItem.product_id || firstItem.products?.id || null,
      slug: firstItem.products?.slug || null,
      name: firstItem.product_name_snapshot || firstItem.products?.name || null,
      variant_name: firstItem.variant_name_snapshot || null,
      quantity: Number(firstItem.quantity || 0)
    } : null,
    item_count: orderedItems.length,
    total_quantity: totalQuantity,
    location: publicLocation(order.locations),
    location_name: order.locations?.name || null
  };
}

async function loadCustomerOrdersPreview(customerId, { limit = CUSTOMER_PROFILE_ORDER_LIMIT, offset = 0 } = {}) {
  const safeLimit = Math.min(Math.max(Number(limit) || CUSTOMER_PROFILE_ORDER_LIMIT, 1), 100);
  const safeOffset = Math.max(Number(offset) || 0, 0);

  const orders = await supabase
    .from('orders')
    .select('id,order_number,status,payment_status,fulfillment_type,requested_fulfillment_at,total_amount,created_at,updated_at,locations(id,name,type,compound_name,beach_name,banner_image_url,delivery_fee,is_active)')
    .eq('customer_id', customerId)
    .order('created_at', { ascending: false })
    .range(safeOffset, safeOffset + safeLimit);

  if (orders.error) return { error: orders.error };

  const rows = orders.data || [];
  const hasMore = rows.length > safeLimit;
  const pageRows = rows.slice(0, safeLimit);
  const orderIds = pageRows.map((order) => order.id);

  const items = orderIds.length
    ? await supabase
        .from('order_items')
        .select('order_id,product_id,product_name_snapshot,variant_name_snapshot,quantity,created_at,products(id,slug,name,image_url)')
        .in('order_id', orderIds)
        .order('created_at', { ascending: true })
    : { data: [], error: null };

  if (items.error) return { error: items.error };

  const itemsByOrderId = new Map();
  for (const item of items.data || []) {
    const list = itemsByOrderId.get(item.order_id) || [];
    list.push(item);
    itemsByOrderId.set(item.order_id, list);
  }

  return {
    data: {
      items: pageRows.map((order) => publicProfileOrder(order, itemsByOrderId.get(order.id) || [])),
      has_more: hasMore,
      limit: safeLimit,
      offset: safeOffset
    }
  };
}

async function countRows(tableName, customerId) {
  const result = await supabase
    .from(tableName)
    .select('customer_id', { count: 'exact', head: true })
    .eq('customer_id', customerId);

  return result;
}

async function loadCustomerFavoriteRows(customerId) {
  return supabase
    .from('customer_favorite_products')
    .select('customer_id,product_id,created_at')
    .eq('customer_id', customerId)
    .order('created_at', { ascending: false });
}

async function loadCustomerFavoriteIdSet(customerId) {
  if (!customerId) return new Set();

  const favorites = await loadCustomerFavoriteRows(customerId);
  if (favorites.error) throw favorites.error;

  return new Set((favorites.data || []).map((favorite) => favorite.product_id));
}

async function loadFavoriteProducts(customerId, { locationId = null, page = 1, pageSize = 50 } = {}) {
  const favorites = await loadCustomerFavoriteRows(customerId);
  if (favorites.error) return { error: favorites.error };

  const favoriteRows = favorites.data || [];
  const safePage = Math.max(Number(page) || 1, 1);
  const safePageSize = Math.min(Math.max(Number(pageSize) || 50, 1), 100);
  const pageRows = favoriteRows.slice((safePage - 1) * safePageSize, safePage * safePageSize);
  const productIds = pageRows.map((favorite) => favorite.product_id);

  if (!productIds.length) {
    return {
      data: {
        results: [],
        meta: {
          total: favoriteRows.length,
          page: safePage,
          page_size: safePageSize
        }
      }
    };
  }

  const catalog = await loadCatalog({ locationId, productIds });
  if (catalog.error) return { error: catalog.error };

  const cardById = new Map((catalog.data.cards || []).map((card) => [card.id, card]));
  const favoriteProductIds = new Set(productIds);

  return {
    data: {
      results: pageRows
        .map((favorite) => {
          const card = cardById.get(favorite.product_id);
          if (!card) return null;
          return {
            ...addFavoriteFlagToCard(card, favoriteProductIds),
            favorite_created_at: favorite.created_at
          };
        })
        .filter(Boolean),
      meta: {
        total: favoriteRows.length,
        page: safePage,
        page_size: safePageSize
      }
    }
  };
}

async function validateFavoriteProduct(productId) {
  const product = await supabase
    .from('products')
    .select('id,slug,name,status,product_type')
    .eq('id', productId)
    .eq('status', 'active')
    .eq('product_type', 'cocktail')
    .maybeSingle();

  if (product.error) return { error: product.error };
  if (!product.data) return { notFound: true };

  return { data: product.data };
}

function profileQuickLinks({ addressCount = 0, favoriteCount = 0, unreadNotifications = 0 } = {}) {
  return [
    {
      key: 'addresses',
      title: 'Addresses',
      subtitle: 'Manage your delivery addresses',
      endpoint: '/api/customer/addresses',
      enabled: true,
      count: addressCount
    },
    {
      key: 'payment_methods',
      title: 'Payment Methods',
      subtitle: 'Saved cards coming soon',
      endpoint: null,
      enabled: false,
      placeholder: true
    },
    {
      key: 'favorite_cocktails',
      title: 'Favorite Cocktails',
      subtitle: 'Your saved cocktail picks',
      endpoint: '/api/customer/favorites',
      enabled: true,
      count: favoriteCount
    },
    {
      key: 'promo_codes',
      title: 'Promo Codes',
      subtitle: 'View available offers',
      endpoint: null,
      enabled: false,
      placeholder: true
    },
    {
      key: 'notifications',
      title: 'Notifications',
      subtitle: unreadNotifications > 0 ? `${unreadNotifications} unread` : 'Order updates and pickup alerts',
      endpoint: '/api/customer/notifications',
      enabled: true,
      placeholder: false,
      count: unreadNotifications
    }
  ];
}

const customerProfileUpdateSchema = z.object({
  full_name: z.preprocess(
    (value) => value === '' ? null : value,
    z.string().trim().min(1).max(120).nullable().optional()
  ),
  phone: z.preprocess(
    (value) => value === '' ? null : value,
    z.string().trim().regex(EGYPT_MOBILE_SIMPLE_RE, 'Use an Egyptian mobile number that starts with 0 and has 11 digits.').nullable().optional()
  ),
  email: z.preprocess(
    (value) => value === '' ? null : value,
    z.string().trim().email().max(254).nullable().optional()
  ),
  birthday: z.preprocess(
    (value) => value === '' ? null : value,
    z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Birthday must use YYYY-MM-DD format.').nullable().optional()
  ),
  gender: z.preprocess(
    (value) => {
      if (value === '' || value === null) return null;
      if (typeof value === 'string') return value.trim().toLowerCase();
      return value;
    },
    z.enum(['male', 'female']).nullable().optional()
  ),
  marketing_opt_in: z.boolean().optional()
});

async function handleCustomerProfileUpdate(req, res) {
  const parsed = customerProfileUpdateSchema.safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid customer profile.',
    details: parsed.error.issues.map((issue) => ({
      path: issue.path.join('.'),
      message: issue.message
    }))
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const updated = await supabase
    .from('customers')
    .update(clean(parsed.data))
    .eq('id', ensured.customer.id)
    .select()
    .single();

  if (updated.error) return res.status(400).json({
    error: updated.error.message
  });

  res.json({
    session: sessionPayload(updated.data.id, setCustomerToken(res, updated.data.id)),
    customer: customerProfilePayload(updated.data)
  });
}

async function handleAddCustomerFavorite(req, res) {
  const parsed = z.object({
    product_id: uuid.optional(),
    cocktail_id: uuid.optional(),
    productId: uuid.optional(),
    cocktailId: uuid.optional()
  }).transform((data) => ({
    product_id: data.product_id || data.cocktail_id || data.productId || data.cocktailId
  })).refine((data) => Boolean(data.product_id), {
    message: 'product_id is required.'
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid favorite request.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const product = await validateFavoriteProduct(parsed.data.product_id);
  if (product.error) return res.status(400).json({ error: product.error.message });
  if (product.notFound) return res.status(404).json({ error: 'Cocktail not found.' });

  const favorite = await supabase
    .from('customer_favorite_products')
    .upsert({
      customer_id: ensured.customer.id,
      product_id: parsed.data.product_id
    }, { onConflict: 'customer_id,product_id' })
    .select('customer_id,product_id,created_at')
    .single();

  if (favorite.error) return res.status(400).json({
    error: favorite.error.message
  });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    favorite: {
      ...favorite.data,
      product: product.data
    },
    is_favorite: true
  });
}

async function findCustomerFromRequest(req) {
  const customerId = decodeCustomerToken(readCustomerToken(req));
  if (!customerId) return null;

  const customer = await supabase
    .from('customers')
    .select('*')
    .eq('id', customerId)
    .maybeSingle();

  if (customer.error || !customer.data) return null;

  return customer.data;
}

async function ensureCustomer(req, res) {
  const existing = await findCustomerFromRequest(req);

  if (existing) {
    const token = setCustomerToken(res, existing.id);
    return {
      customer: existing,
      token
    };
  }

  const created = await supabase
    .from('customers')
    .insert({})
    .select()
    .single();

  if (created.error) {
    res.status(400).json({
      error: created.error.message
    });
    return null;
  }

  const token = setCustomerToken(res, created.data.id);

  return {
    customer: created.data,
    token
  };
}

async function expireOldActiveCarts(customerId) {
  const todayStartIso = startOfTodayCairoUtc().toISOString();

  await supabase
    .from('carts')
    .update({
      status: 'abandoned'
    })
    .eq('customer_id', customerId)
    .eq('status', 'active')
    .lt('created_at', todayStartIso);
}

async function getActiveCart(customerId, { createIfMissing = true } = {}) {
  await expireOldActiveCarts(customerId);

  const existing = await supabase
    .from('carts')
    .select('*')
    .eq('customer_id', customerId)
    .eq('status', 'active')
    .order('created_at', {
      ascending: false
    })
    .limit(1)
    .maybeSingle();

  if (existing.error) return {
    error: existing.error
  };

  if (existing.data || !createIfMissing) return {
    data: existing.data
  };

  const created = await supabase
    .from('carts')
    .insert({
      customer_id: customerId,
      selected_liquor_type_ids: [],
      status: 'active',
      expires_at: cartExpiresAtIso()
    })
    .select()
    .single();

  return created;
}

async function cartItemsForCart(cartId) {
  return supabase
    .from('cart_items')
    .select(`
      *,
      products(id,slug,name,image_url,status,product_type),
      product_variants(id,name,serving_count,is_active,vat_rate,price_inc_vat),
      cart_item_removed_ingredients(*),
      cart_item_additions(*)
    `)
    .eq('cart_id', cartId)
    .order('created_at');
}

function cartTotals(items = [], {
  fulfillmentType = 'pickup_at_cart',
  deliveryFee = 0,
  discountAmount = 0
} = {}) {
  const itemCount = items.length;

  const totalQuantity = items.reduce((sum, item) => {
    return sum + Number(item.quantity || 0);
  }, 0);

  const subtotalIncVat = money(items.reduce((sum, item) => {
    return sum + Number(item.unit_price_inc_vat_snapshot || 0) * Number(item.quantity || 0);
  }, 0));

  const estimatedVatAmount = money(items.reduce((sum, item) => {
    const vatRate = Number(item.vat_rate_snapshot ?? item.product_variants?.vat_rate ?? 0);
    const tax = configuredLineTax(item, vatRate);
    return sum + tax.line_vat_amount;
  }, 0));

  const appliedDeliveryFee = fulfillmentType === 'delivery_to_unit' ? money(deliveryFee) : 0;
  const appliedDiscountAmount = money(Math.min(Math.max(Number(discountAmount || 0), 0), subtotalIncVat + appliedDeliveryFee));

  return {
    item_count: itemCount,
    total_quantity: totalQuantity,
    subtotal_inc_vat: subtotalIncVat,
    estimated_vat_amount: estimatedVatAmount,
    discount_amount: appliedDiscountAmount,
    delivery_fee: appliedDeliveryFee,
    total_amount: money(Math.max(subtotalIncVat + appliedDeliveryFee - appliedDiscountAmount, 0)),
    currency: CURRENCY
  };
}

async function cartSummary(cartId, { fulfillmentType = 'pickup_at_cart' } = {}) {
  if (!cartId) {
    return {
      cart_id: null,
      item_count: 0,
      total_quantity: 0,
      ...cartTotals([], { fulfillmentType })
    };
  }

  const items = await supabase
    .from('cart_items')
    .select('quantity,unit_price_inc_vat_snapshot')
    .eq('cart_id', cartId);

  if (items.error) throw items.error;

  const itemCount = items.data?.length || 0;
  const totalQuantity = (items.data || []).reduce((sum, item) => sum + Number(item.quantity || 0), 0);

  const subtotal = (items.data || []).reduce((sum, item) => {
    return sum + Number(item.quantity || 0) * Number(item.unit_price_inc_vat_snapshot || 0);
  }, 0);

  return {
    cart_id: cartId,
    item_count: itemCount,
    total_quantity: totalQuantity,
    ...cartTotals(items.data || [], { fulfillmentType })
  };
}

async function loadServiceLocations() {
  const result = await supabase
    .from('locations')
    .select('*')
    .eq('type', 'beach_cart')
    .eq('is_active', true)
    .order('compound_name')
    .order('name');

  return result;
}

async function loadShopSettings() {
  const settings = await supabase
    .from('shop_settings')
    .select('*')
    .eq('id', true)
    .maybeSingle();

  if (settings.error) return { error: settings.error };

  return {
    data: settings.data || { banner_image_url: null }
  };
}

async function loadVisibleShopCategories() {
  const [categories, products] = await Promise.all([
    supabase
      .from('product_categories')
      .select('*')
      .eq('is_active', true)
      .order('sort_order')
      .order('name'),
    supabase
      .from('products')
      .select('category_id')
      .eq('status', 'active')
      .not('category_id', 'is', null)
  ]);

  if (categories.error) return { error: categories.error };
  if (products.error) return { error: products.error };

  const productCountsByCategoryId = new Map();

  for (const product of products.data || []) {
    productCountsByCategoryId.set(
      product.category_id,
      (productCountsByCategoryId.get(product.category_id) || 0) + 1
    );
  }

  return {
    data: (categories.data || []).map((category) => ({
      ...publicCategory(category),
      product_count: productCountsByCategoryId.get(category.id) || 0
    }))
  };
}

function categoryIdentifierMatches(category, identifier) {
  const cleanIdentifier = normalizeString(identifier);
  if (!cleanIdentifier) return false;

  const candidates = [
    category.id,
    category.slug,
    category.name
  ]
    .map(normalizeString)
    .filter(Boolean);

  return candidates.includes(cleanIdentifier);
}

async function loadCategoryByIdentifier(identifier) {
  const categories = await supabase
    .from('product_categories')
    .select('*')
    .eq('is_active', true)
    .order('sort_order')
    .order('name');

  if (categories.error) return { error: categories.error };

  const category = (categories.data || []).find((entry) => {
    return categoryIdentifierMatches(entry, identifier);
  });

  return { data: category || null };
}

async function loadCatalog({
  locationId = null,
  onlyFeatured = false,
  categoryId = null,
  productIds = [],
  productTypes = [],
  q = '',
  liquorTypeIds = [],
  tags = []
} = {}) {
  let productQuery = supabase
    .from('products')
    .select('*, product_categories(id,name,slug,image_url,sort_order)')
    .eq('status', 'active')
    .order('display_order', {
      ascending: true
    })
    .order('name', {
      ascending: true
    });

  if (onlyFeatured) productQuery = productQuery.eq('is_featured', true);
  if (categoryId) productQuery = productQuery.eq('category_id', categoryId);
  if (Array.isArray(productIds) && productIds.length) {
    productQuery = productQuery.in('id', productIds);
  }
  if (Array.isArray(productTypes) && productTypes.length) {
    productQuery = productQuery.in('product_type', productTypes);
  }
  
  const products = await productQuery;
  if (products.error) return {
    error: products.error
  };

  let productRows = products.data || [];
  const search = normalizeString(q);

  if (search) {
    productRows = productRows.filter((product) => {
      const haystack = [product.name, product.short_description, product.description, ...(product.tags || [])]
        .map(normalizeString)
        .join(' ');

      return haystack.includes(search);
    });
  }

  if (tags.length) {
    const wantedTags = tags.map(normalizeString);

    productRows = productRows.filter((product) => {
      const productTags = (product.tags || []).map(normalizeString);
      return wantedTags.every((tag) => productTags.includes(tag));
    });
  }

  const catalogProductIds = productRows.map((product) => product.id);

  if (!catalogProductIds.length) {
    return {
      data: {
        cards: [],
        raw: {
          products: [],
          variants: [],
          compatibility: [],
          recipes: [],
          recipeItems: [],
          balances: [],
          productTags: []
        }
      }
    };
  }

  const [variants, compatibility, recipes, productTags] = await Promise.all([
    supabase
      .from('product_variants')
      .select('*')
      .in('product_id', catalogProductIds)
      .eq('is_active', true)
      .order('price_inc_vat'),

    supabase
      .from('product_liquor_compatibility')
      .select('*, liquor_types(id,name,image_url,display_order,is_active)')
      .in('product_id', catalogProductIds),

    supabase
      .from('recipes')
      .select('*')
      .in('product_id', catalogProductIds)
      .eq('status', 'active')
      .order('version', {
        ascending: false
      }),

    supabase
      .from('product_tags')
      .select('*')
      .eq('is_active', true)
      .order('display_order')
      .order('name')
  ]);  
    
  for (const result of [variants, compatibility, recipes, productTags]) {
    if (result.error) return {
      error: result.error
    };
  }

  if (liquorTypeIds.length) {
    const compatibleProductIds = new Set(
      (compatibility.data || [])
        .filter((row) => liquorTypeIds.includes(row.liquor_type_id))
        .map((row) => row.product_id)
    );

    productRows = productRows.filter((product) => compatibleProductIds.has(product.id));
  }

  const currentRecipeByProductId = new Map();

  for (const product of productRows) {
    currentRecipeByProductId.set(
      product.id,
      pickCurrentRecipe((recipes.data || []).filter((recipe) => recipe.product_id === product.id))
    );
  }

  const recipeIds = [...currentRecipeByProductId.values()]
    .filter(Boolean)
    .map((recipe) => recipe.id);

  const recipeItems = recipeIds.length
    ? await supabase
        .from('recipe_items')
        .select('*, ingredients(id,name,category,base_unit,is_customer_supplied,icon_key)')
        .in('recipe_id', recipeIds)
    : {
        data: [],
        error: null
      };

  if (recipeItems.error) return {
    error: recipeItems.error
  };

  const stockedIngredientIds = [...new Set(
    (recipeItems.data || [])
      .filter((item) => !item.is_customer_supplied && !item.ingredients?.is_customer_supplied)
      .map((item) => item.ingredient_id)
  )];

  const balances = locationId && stockedIngredientIds.length
    ? await supabase
        .from('inventory_balances')
        .select('ingredient_id,location_id,quantity_on_hand,reserved_quantity')
        .eq('location_id', locationId)
        .in('ingredient_id', stockedIngredientIds)
    : {
        data: [],
        error: null
      };

  if (balances.error) return {
    error: balances.error
  };

  const balancesByIngredientId = new Map(
    (balances.data || []).map((balance) => [balance.ingredient_id, balance])
  );

  const productTagsByName = new Map(
    (productTags.data || []).map((tag) => [String(tag.name).toLowerCase(), tag])
  );

  const cards = productRows.map((product) => {
    const productVariants = (variants.data || []).filter((variant) => variant.product_id === product.id);
    const productCompatibility = (compatibility.data || []).filter((row) => row.product_id === product.id);
    const recipe = currentRecipeByProductId.get(product.id);
    const items = (recipeItems.data || []).filter((item) => item.recipe_id === recipe?.id);

    return productCardPayload({
      product,
      category: product.product_categories,
      variants: productVariants,
      compatibility: productCompatibility,
      recipe,
      recipeItems: items,
      balancesByIngredientId,
      locationId,
      productTagsByName
    });
  });

  return {
    data: {
      cards,
      raw: {
        products: productRows,
        variants: variants.data || [],
        compatibility: compatibility.data || [],
        recipes: recipes.data || [],
        recipeItems: recipeItems.data || [],
        balances: balances.data || [],
        productTags: productTags.data || []
      }
    }
  };
}

async function loadProductDetail({ slug, locationId = null, liquorTypeId = null }) {
  const product = await supabase
    .from('products')
    .select('*, product_categories(id,name,sort_order)')
    .eq('slug', slug)
    .eq('status', 'active')
    .maybeSingle();

  if (product.error) return {
    error: product.error
  };

  if (!product.data) return {
    notFound: true
  };

  const [catalog, addonCatalog] = await Promise.all([
    loadCatalog({
      locationId,
      productIds: [product.data.id]
    }),
    loadCatalog({
      locationId,
      productTypes: ['add_on']
    })
  ]);

  if (catalog.error) return {
    error: catalog.error
  };

  if (addonCatalog.error) return {
    error: addonCatalog.error
  };

  const card = catalog.data.cards.find((entry) => entry.id === product.data.id);
  if (!card) return {
    notFound: true
  };

  const raw = catalog.data.raw || {};
  const recipe = pickCurrentRecipe((raw.recipes || []).filter((entry) => entry.product_id === product.data.id));
  const recipeItems = (raw.recipeItems || []).filter((item) => item.recipe_id === recipe?.id);
  const balancesByIngredientId = new Map(
    (raw.balances || []).map((balance) => [balance.ingredient_id, balance])
  );

  const selectedVariant = pickLatestSingleServingVariant(
    (raw.variants || []).filter((variant) => variant.product_id === product.data.id)
  );

  let selectedCompatibility = null;

  if (liquorTypeId) {
    selectedCompatibility = (raw.compatibility || []).find((row) => {
      return row.product_id === product.data.id
        && row.liquor_type_id === liquorTypeId
        && row.liquor_types?.is_active !== false;
    });

    if (!selectedCompatibility) return {
      badRequest: 'Selected liquor is not compatible with this cocktail.'
    };
  }

  return {
    data: {
      product: product.data,
      card,
      selectedVariant,
      selectedLiquor: publicSelectedLiquor(selectedCompatibility),
      recipe,
      recipeItems,
      balancesByIngredientId,
      addonCards: addonCatalog.data.cards || []
    }
  };
}

async function buildCartResponse(customerId, {
  createIfMissing = true,
  locationId = null,
  fulfillmentType = 'pickup_at_cart'
} = {}) {
  const normalizedFulfillmentType = normalizeFulfillmentType(fulfillmentType);
  const selectedLocation = await loadCartLocation(locationId);

  if (selectedLocation.error) return {
    error: selectedLocation.error
  };
  const cart = await getActiveCart(customerId, {
    createIfMissing
  });

  if (cart.error) return {
    error: cart.error
  };

  if (!cart.data) {
    return {
      data: {
        cart: null,
        selected_location: selectedLocation.data,
        items: [],
        totals: cartTotals([], {
          fulfillmentType: normalizedFulfillmentType,
          deliveryFee: selectedLocation.data?.delivery_fee || 0
        }),
        checkoutReadiness: {
          can_checkout: false,
          blocking_reasons: ['Cart is empty.']
        }
      }
    };
  }

  const items = await cartItemsForCart(cart.data.id);
  if (items.error) return {
    error: items.error
  };

  const context = await loadCartConfigurationContext({
    cartItems: items.data || [],
    locationId
  });

  if (context.error) return {
    error: context.error
  };

  const {
    productById,
    cardByProductId,
    variantById,
    currentRecipeByProductId,
    recipeById,
    recipeItemsByRecipeId,
    balancesByIngredientId
  } = context.data;

  const responseItems = (items.data || []).map((item) => {
    const card = cardByProductId.get(item.product_id);
    const product = productById.get(item.product_id);
    const variant = variantById.get(item.variant_id) || item.product_variants;
    const recipe = recipeById.get(item.recipe_id) || currentRecipeByProductId.get(item.product_id) || null;
    const recipeItems = recipeItemsByRecipeId.get(recipe?.id) || [];
    const inventoryComponents = inventoryComponentsForConfiguredItem({
      item,
      variant,
      recipe,
      recipeItems,
      recipeById,
      recipeItemsByRecipeId
    });
    const variantAvailability = buildAvailabilityForComponents({
      locationId,
      recipe,
      components: inventoryComponents,
      balancesByIngredientId,
      variant,
      cartQuantity: item.quantity
    });
    const lineTotal = money(Number(item.unit_price_inc_vat_snapshot || 0) * Number(item.quantity || 0));
    const customization = buildCustomizationPayloadForCartItem(item);

    return {
      id: item.id,
      product_id: item.product_id,
      variant_id: item.variant_id,
      recipe_id: recipe?.id || item.recipe_id || null,
      quantity: item.quantity,
      product: {
        slug: item.products?.slug || product?.slug,
        name: item.products?.name || product?.name,
        image_url: item.products?.image_url || product?.image_url,
        status: item.products?.status || product?.status
      },
      variant: {
        name: item.product_variants?.name || variant?.name,
        serving_count: item.product_variants?.serving_count || variant?.serving_count,
        is_active: item.product_variants?.is_active ?? variant?.is_active
      },
      customization,
      pricing: {
        base_unit_price_inc_vat: customization.base_unit_price_inc_vat,
        customization_total_inc_vat: customization.customization_total_inc_vat,
        unit_price_inc_vat: money(item.unit_price_inc_vat_snapshot),
        line_total_inc_vat: lineTotal,
        currency: CURRENCY
      },
      compatibility: card?.compatibility || [],
      availability: variantAvailability || {
        is_orderable: false,
        reason: 'Choose a beach cart to check availability.'
      }
    };
  });

  const totals = cartTotals(items.data || [], {
    fulfillmentType: normalizedFulfillmentType,
    deliveryFee: selectedLocation.data?.delivery_fee || 0
  });
  const blockingReasons = [];

  if (!responseItems.length) blockingReasons.push('Cart is empty.');

  for (const item of responseItems) {
    if (!item.availability.is_orderable) {
      blockingReasons.push(`${item.product.name}: ${item.availability.reason}`);
    }
  }

  return {
    data: {
      cart: {
        id: cart.data.id,
        selected_liquor_type_ids: cart.data.selected_liquor_type_ids || [],
        status: cart.data.status,
        expires_at: cart.data.expires_at || cartExpiresAtIso(),
        created_at: cart.data.created_at,
        updated_at: cart.data.updated_at,
        fulfillment_type: normalizedFulfillmentType
      },
      selected_location: selectedLocation.data,
      items: responseItems,
      totals,
      checkoutReadiness: {
        can_checkout: blockingReasons.length === 0,
        blocking_reasons: blockingReasons
      }
    }
  };
}

async function validateBeachCart(locationId, res) {
  const location = await supabase
    .from('locations')
    .select('*')
    .eq('id', locationId)
    .eq('type', 'beach_cart')
    .eq('is_active', true)
    .maybeSingle();

  if (location.error) {
    res.status(400).json({
      error: location.error.message
    });
    return null;
  }

  if (!location.data) {
    res.status(400).json({
      error: 'Selected beach cart is not available.'
    });
    return null;
  }

  return location.data;
}


function normalizePromoCode(value) {
  return String(value || '').trim().toUpperCase();
}

function isSimpleEgyptianMobile(value) {
  return EGYPT_MOBILE_SIMPLE_RE.test(String(value || '').trim());
}

function publicPromotion(promotion, discountAmount = 0) {
  if (!promotion) return null;

  return {
    id: promotion.id,
    code: promotion.code,
    name: promotion.name,
    discount_type: promotion.discount_type,
    discount_value: money(promotion.discount_value),
    discount_amount: money(discountAmount),
    currency: CURRENCY
  };
}

function promotionDateIsActive(promotion, now = new Date()) {
  const nowMs = now.getTime();

  if (promotion.starts_at && new Date(promotion.starts_at).getTime() > nowMs) return false;
  if (promotion.ends_at && new Date(promotion.ends_at).getTime() < nowMs) return false;

  return true;
}

function calculatePromotionDiscount(promotion, { subtotalIncVat, deliveryFee }) {
  if (!promotion) return 0;

  const discountValue = Number(promotion.discount_value || 0);

  if (promotion.discount_type === 'percentage') {
    return money(Math.min(subtotalIncVat, subtotalIncVat * (discountValue / 100)));
  }

  if (promotion.discount_type === 'fixed_amount') {
    return money(Math.min(subtotalIncVat, discountValue));
  }

  if (promotion.discount_type === 'free_delivery') {
    return money(deliveryFee);
  }

  return 0;
}

async function resolvePromotion({ promoCode, customerId, subtotalIncVat, deliveryFee }) {
  const code = normalizePromoCode(promoCode);
  if (!code) return { data: { promotion: null, discountAmount: 0 } };

  const promotion = await supabase
    .from('promotions')
    .select('*')
    .ilike('code', code)
    .eq('is_active', true)
    .maybeSingle();

  if (promotion.error) return { error: promotion.error };

  if (!promotion.data) return { badRequest: 'Promotion code was not found or is no longer active.' };

  if (!promotionDateIsActive(promotion.data)) {
    return { badRequest: 'Promotion code is not active right now.' };
  }

  if (money(subtotalIncVat) < money(promotion.data.min_order_value || 0)) {
    return { badRequest: `Promotion requires a minimum order value of EGP ${money(promotion.data.min_order_value)}.` };
  }

  if (promotion.data.usage_limit) {
    const redemptions = await supabase
      .from('promotion_redemptions')
      .select('id', { count: 'exact', head: true })
      .eq('promotion_id', promotion.data.id);

    if (redemptions.error) return { error: redemptions.error };

    if (Number(redemptions.count || 0) >= Number(promotion.data.usage_limit)) {
      return { badRequest: 'Promotion code usage limit has been reached.' };
    }
  }

  const discountAmount = calculatePromotionDiscount(promotion.data, {
    subtotalIncVat,
    deliveryFee
  });

  if (discountAmount <= 0) {
    return { badRequest: 'Promotion code does not apply to this checkout.' };
  }

  return {
    data: {
      promotion: publicPromotion(promotion.data, discountAmount),
      rawPromotion: promotion.data,
      discountAmount
    }
  };
}

function createGeideaPaymentPayload({ order, payment, sessionId = null, paymentMethod = null }) {
  const config = geideaCheckoutConfig();
  const rawPayload = payment?.raw_payload || {};

  return {
    required: true,
    provider: payment?.provider || PAYMENT_PROVIDER,
    payment_id: payment?.id || '',
    payment_method: paymentMethod || rawPayload.payment_method || 'geidea_card',
    status: payment?.status || order?.payment_status || 'pending',
    amount: money(payment?.amount ?? order?.total_amount ?? 0),
    currency: payment?.currency || CURRENCY,
    order_reference: order?.order_number || order?.id || '',
    geidea: {
      ...config,
      session_id: sessionId || rawPayload.geidea_session_id || ''
    }
  };
}

function createStripePaymentPayload({ order, payment, stripeSession = null }) {
  const config = stripeCheckoutConfig();
  const rawPayload = payment?.raw_payload || {};

  return {
    required: true,
    provider: payment?.provider || STRIPE_PAYMENT_PROVIDER,
    payment_id: payment?.id || '',
    payment_method: rawPayload.payment_method || 'stripe_payment_sheet',
    status: payment?.status || order?.payment_status || 'pending',
    amount: money(payment?.amount ?? order?.total_amount ?? 0),
    currency: payment?.currency || CURRENCY,
    order_reference: order?.order_number || order?.id || '',
    stripe: {
      configured: config.configured,
      is_test: config.is_test,
      publishable_key: config.publishable_key,
      merchant_display_name: config.merchant_display_name,
      merchant_country: config.merchant_country,
      apple_pay_merchant_id: config.apple_pay_merchant_id,
      google_pay_enabled: config.google_pay_enabled,
      // Present only on the fresh place-order response; polling responses omit
      // the secrets because the sheet has already been presented by then.
      payment_intent_id: stripeSession?.payment_intent_id || rawPayload.stripe_payment_intent_id || '',
      client_secret: stripeSession?.client_secret || rawPayload.stripe_client_secret || '',
      customer_id: stripeSession?.customer_id || rawPayload.stripe_customer_id || '',
      ephemeral_key_secret: stripeSession?.ephemeral_key_secret || rawPayload.stripe_ephemeral_key_secret || ''
    }
  };
}

function createDemoPaymentPayload({ order, payment }) {
  return {
    required: false,
    provider: DEMO_PAYMENT_PROVIDER,
    payment_id: payment?.id || '',
    payment_method: 'demo_checkout',
    status: payment?.status || order?.payment_status || 'paid',
    amount: money(payment?.amount ?? order?.total_amount ?? 0),
    currency: payment?.currency || CURRENCY,
    order_reference: order?.order_number || order?.id || '',
    geidea: {
      ...geideaCheckoutConfig(),
      configured: false,
      session_id: ''
    }
  };
}

function createCheckoutPaymentPayload({ order, payment, sessionId = null, paymentMethod = null, stripeSession = null }) {
  if (payment?.provider === DEMO_PAYMENT_PROVIDER || PAYMENT_MODE === 'demo') {
    return createDemoPaymentPayload({ order, payment });
  }

  if (payment?.provider === STRIPE_PAYMENT_PROVIDER || (isStripeProvider && !payment?.provider)) {
    return createStripePaymentPayload({ order, payment, stripeSession });
  }

  return createGeideaPaymentPayload({ order, payment, sessionId, paymentMethod });
}

async function recordPromotionRedemptionIfNeeded({ order, payment }) {
  const promotion = payment?.raw_payload?.promotion;
  if (!promotion?.id || !order?.id) return null;

  const existing = await supabase
    .from('promotion_redemptions')
    .select('id')
    .eq('promotion_id', promotion.id)
    .eq('order_id', order.id)
    .maybeSingle();

  if (existing.error) throw existing.error;
  if (existing.data) return existing.data;

  const inserted = await supabase
    .from('promotion_redemptions')
    .insert({
      promotion_id: promotion.id,
      customer_id: order.customer_id || null,
      order_id: order.id,
      discount_amount: money(promotion.discount_amount || order.discount_amount || 0)
    })
    .select()
    .single();

  if (inserted.error) throw inserted.error;
  return inserted.data;
}

async function recordGeideaSavedCardIfNeeded({ customerId, payload }) {
  const savedCard = extractGeideaSavedCard(payload);
  if (!customerId || !savedCard?.token_id) return null;

  const upserted = await supabase
    .from('customer_payment_methods')
    .upsert({
      customer_id: customerId,
      provider: PAYMENT_PROVIDER,
      provider_token_id: savedCard.token_id,
      provider_agreement_id: savedCard.agreement_id || null,
      agreement_type: savedCard.agreement_type || 'Unscheduled',
      card_brand: savedCard.card_brand || null,
      cardholder_name: savedCard.cardholder_name || null,
      masked_card_number: savedCard.masked_card_number || null,
      expiry_month: savedCard.expiry_month || null,
      expiry_year: savedCard.expiry_year || null,
      is_active: true,
      raw_payload: savedCard
    }, { onConflict: 'provider,provider_token_id' })
    .select()
    .single();

  if (upserted.error) throw upserted.error;
  return upserted.data;
}

async function recordStripeSavedCardIfNeeded({ customerId, paymentIntent }) {
  const savedCard = extractStripeSavedCard(paymentIntent);
  if (!customerId || !savedCard?.payment_method_id) return null;

  const upserted = await supabase
    .from('customer_payment_methods')
    .upsert({
      customer_id: customerId,
      provider: STRIPE_PAYMENT_PROVIDER,
      provider_token_id: savedCard.payment_method_id,
      provider_agreement_id: savedCard.customer_id || null,
      agreement_type: 'off_session',
      card_brand: savedCard.card_brand || null,
      cardholder_name: savedCard.cardholder_name || null,
      masked_card_number: savedCard.masked_card_number || null,
      expiry_month: savedCard.expiry_month || null,
      expiry_year: savedCard.expiry_year || null,
      is_active: true,
      raw_payload: savedCard
    }, { onConflict: 'provider,provider_token_id' })
    .select()
    .single();

  if (upserted.error) throw upserted.error;
  return upserted.data;
}

// Most recent Stripe customer id we already created for this shopper, so saved
// cards stay attached to one Stripe customer across orders.
async function findExistingStripeCustomerId(customerId) {
  if (!customerId) return null;

  const existing = await supabase
    .from('customer_payment_methods')
    .select('provider_agreement_id')
    .eq('customer_id', customerId)
    .eq('provider', STRIPE_PAYMENT_PROVIDER)
    .not('provider_agreement_id', 'is', null)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existing.error) return null;
  return existing.data?.provider_agreement_id || null;
}

function stripeCheckoutMethods() {
  const config = stripeCheckoutConfig();

  return [
    {
      key: 'stripe_payment_sheet',
      label: 'Credit / Debit Card',
      provider: STRIPE_PAYMENT_PROVIDER,
      enabled: config.configured,
      setup_required: !config.configured,
      sdk: config
    }
  ];
}

function geideaCheckoutMethods() {
  const config = geideaCheckoutConfig();

  return [
    {
      key: 'geidea_card',
      label: 'Credit / Debit Card',
      provider: 'geidea',
      enabled: config.configured,
      setup_required: !config.configured,
      sdk: config
    },
    {
      key: 'geidea_apple_pay',
      label: 'Apple Pay',
      provider: 'geidea',
      enabled: config.configured && Boolean(config.apple_pay_merchant_id),
      setup_required: !config.configured || !config.apple_pay_merchant_id,
      sdk: config
    }
  ];
}

function checkoutPaymentMethods() {
  if (isDemoPaymentMode) {
    return [
      {
        key: 'demo_checkout',
        label: 'Demo Checkout',
        provider: DEMO_PAYMENT_PROVIDER,
        enabled: true,
        setup_required: false,
        mode: 'demo',
        message: 'Demo mode skips the payment gateway and confirms the order immediately.'
      }
    ];
  }

  return isStripeProvider ? stripeCheckoutMethods() : geideaCheckoutMethods();
}

async function buildCheckoutQuote({
  customerId,
  cartId,
  locationId,
  fulfillmentType,
  customerAddressId = null,
  addressText = null,
  customerNotes = null,
  promoCode = null,
  requireCustomerDetails = false
}) {
  const location = await supabase
    .from('locations')
    .select('*')
    .eq('id', locationId)
    .eq('type', 'beach_cart')
    .eq('is_active', true)
    .maybeSingle();

  if (location.error) return {
    error: location.error
  };

  if (!location.data) return {
    badRequest: 'Selected beach cart is not available.'
  };

  const activeCart = await getActiveCart(customerId, {
    createIfMissing: false
  });

  if (activeCart.error) return {
    error: activeCart.error
  };

  if (!activeCart.data || activeCart.data.id !== cartId) {
    return {
      badRequest: 'Cart is no longer active.'
    };
  }

  if (requireCustomerDetails && fulfillmentType === 'delivery_to_unit' && !String(addressText || '').trim() && !customerAddressId) {
    return {
      badRequest: 'Delivery orders require an address.'
    };
  }

  let address = null;

  if (customerAddressId) {
    const addressResult = await supabase
      .from('customer_addresses')
      .select('*')
      .eq('id', customerAddressId)
      .eq('customer_id', customerId)
      .maybeSingle();

    if (addressResult.error) return {
      error: addressResult.error
    };

    if (!addressResult.data) return {
      badRequest: 'Selected address was not found.'
    };

    address = addressResult.data;
  }

  const cartItems = await cartItemsForCart(cartId);

  if (cartItems.error) return {
    error: cartItems.error
  };

  if (!cartItems.data?.length) return {
    badRequest: 'Cart is empty.'
  };

  const context = await loadCartConfigurationContext({
    cartItems: cartItems.data,
    locationId
  });

  if (context.error) return {
    error: context.error
  };

  const {
    productById,
    variantById,
    currentRecipeByProductId,
    recipeById,
    recipeItemsByRecipeId,
    balancesByIngredientId
  } = context.data;

  const blockingReasons = [];

  const quoteItems = cartItems.data.map((item) => {
    const product = productById.get(item.product_id);
    const variant = variantById.get(item.variant_id) || item.product_variants;
    const recipe = recipeById.get(item.recipe_id) || currentRecipeByProductId.get(item.product_id) || null;
    const recipeItems = recipeItemsByRecipeId.get(recipe?.id) || [];
    const inventoryComponents = inventoryComponentsForConfiguredItem({
      item,
      variant,
      recipe,
      recipeItems,
      recipeById,
      recipeItemsByRecipeId
    });

    const availability = buildAvailabilityForComponents({
      locationId,
      recipe,
      components: inventoryComponents,
      balancesByIngredientId,
      variant,
      cartQuantity: item.quantity
    });

    if (!product) {
      blockingReasons.push(`${item.products?.name || 'Item'} is no longer available.`);
    }

    if (!availability.is_orderable) {
      blockingReasons.push(`${item.products?.name || product?.name || 'Item'}: ${availability.reason}`);
    }

    const vatRate = Number(item.vat_rate_snapshot ?? variant?.vat_rate ?? 0);
    const tax = configuredLineTax(item, vatRate);
    const customization = buildCustomizationPayloadForCartItem(item);

    return {
      cart_item_id: item.id,
      product_id: item.product_id,
      variant_id: item.variant_id,
      recipe_id: recipe?.id || item.recipe_id || null,
      product_name: product?.name || item.products?.name,
      variant_name: variant?.name || item.product_variants?.name,
      quantity: item.quantity,
      serving_count: variant?.serving_count || item.product_variants?.serving_count,
      base_unit_price_inc_vat: customization.base_unit_price_inc_vat,
      customization_total_inc_vat: customization.customization_total_inc_vat,
      customization_summary: customization.summary,
      customization,
      removed_ingredients: item.cart_item_removed_ingredients || [],
      additions: item.cart_item_additions || [],
      inventory_components: inventoryComponents,
      unit_price_inc_vat: money(item.unit_price_inc_vat_snapshot),
      vat_rate: vatRate,
      line_subtotal_ex_vat: tax.line_ex_vat,
      line_vat_amount: tax.line_vat_amount,
      line_total: tax.line_inc_vat,
      is_available: availability.is_orderable,
      blocking_reason: availability.reason
    };
  });

  const subtotalExVat = money(quoteItems.reduce((sum, item) => sum + item.line_subtotal_ex_vat, 0));
  const vatAmount = money(quoteItems.reduce((sum, item) => sum + item.line_vat_amount, 0));
  const subtotalIncVat = money(subtotalExVat + vatAmount);
  const deliveryFee = fulfillmentType === 'delivery_to_unit' ? money(location.data.delivery_fee || 0) : 0;

  const promotionResult = await resolvePromotion({
    promoCode,
    customerId,
    subtotalIncVat,
    deliveryFee
  });

  if (promotionResult.error) return { error: promotionResult.error };
  if (promotionResult.badRequest) return { badRequest: promotionResult.badRequest };

  const discountAmount = money(promotionResult.data?.discountAmount || 0);
  const totalAmount = money(Math.max(subtotalIncVat + deliveryFee - discountAmount, 0));

  return {
    data: {
      quote: {
        cart_id: cartId,
        location_id: locationId,
        fulfillment_type: fulfillmentType,
        customer_address_id: customerAddressId,
        address_text: addressText ? String(addressText).trim() : null,
        customer_notes: customerNotes,
        promo_code: normalizePromoCode(promoCode) || null,
        promotion: promotionResult.data?.promotion || null,
        raw_promotion: promotionResult.data?.rawPromotion || null,
        items: quoteItems,
        totals: {
          subtotal_ex_vat: subtotalExVat,
          vat_amount: vatAmount,
          subtotal_inc_vat: subtotalIncVat,
          discount_amount: discountAmount,
          delivery_fee: deliveryFee,
          total_amount: totalAmount,
          currency: CURRENCY,
          vat_included: true
        },
        validation: {
          can_place_order: blockingReasons.length === 0,
          blocking_reasons: blockingReasons
        }
      },
      location: location.data,
      address
    }
  };
}

customerRouter.post('/customer/session', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    customer: ensured.customer
  });
});

customerRouter.get('/customer/home', async (req, res) => {
  const parsed = z.object({
    location_id: optionalUuid
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid home request.'
  });

  const [locations, categories, liquorTypes, catalog] = await Promise.all([
    loadServiceLocations(),

    supabase
      .from('product_categories')
      .select('*')
      .eq('is_active', true)
      .order('sort_order')
      .order('name'),

    supabase
      .from('liquor_types')
      .select('*')
      .eq('is_active', true)
      .order('display_order')
      .order('name'),

    loadCatalog({
      locationId: parsed.data.location_id || null,
      onlyFeatured: true
    })
  ]);

  for (const result of [locations, categories, liquorTypes, catalog]) {
    if (result.error) return res.status(400).json({
      error: result.error.message
    });
  }

  const customer = await findCustomerFromRequest(req);
  let summary = null;
  let favoriteProductIds = new Set();

  if (customer) {
    const cart = await getActiveCart(customer.id, {
      createIfMissing: false
    });

    if (cart.error) return res.status(400).json({
      error: cart.error.message
    });

    summary = await cartSummary(cart.data?.id || null);

    try {
      favoriteProductIds = await loadCustomerFavoriteIdSet(customer.id);
    } catch (error) {
      return res.status(400).json({ error: error.message });
    }
  }

  res.json({
    serviceAreas: (locations.data || []).map((location) => ({
      ...publicLocation(location),
      is_available: true
    })),
    hero: {
      headline: 'Premium mixers, garnishes, syrups & cocktail ingredients.',
      subheadline: 'You bring the bottle. We bring the magic.',
      image_url: null,
      primary_cta_label: 'Find your cocktail',
      primary_cta_target: 'cocktail_finder'
    },
    featuredCocktails: catalog.data.cards.map((card) => addFavoriteFlagToCard(card, favoriteProductIds)),
    categories: (categories.data || []).map(publicCategory),
    liquorTypes: (liquorTypes.data || []).map(publicLiquorType),
    cartSummary: summary
  });
});

customerRouter.get('/customer/shop', async (req, res) => {
  const parsed = z.object({
    location_id: optionalUuid,
    locationId: optionalUuid
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid shop request.'
  });

  const locationId = parsed.data.location_id || parsed.data.locationId || null;

  const [settings, categories, featuredCocktails, snacksAndMore] = await Promise.all([
    loadShopSettings(),
    loadVisibleShopCategories(),
    loadCatalog({
      locationId,
      onlyFeatured: true,
      productTypes: ['cocktail']
    }),
    loadCatalog({
      locationId,
      onlyFeatured: true,
      productTypes: ['snack', 'essential', 'bundle', 'add_on']
    })
  ]);

  for (const result of [settings, categories, featuredCocktails, snacksAndMore]) {
    if (result.error) return res.status(400).json({
      error: result.error.message
    });
  }

  const customer = await findCustomerFromRequest(req);
  let summary = null;

  if (customer) {
    const cart = await getActiveCart(customer.id, { createIfMissing: false });
    if (cart.error) return res.status(400).json({ error: cart.error.message });
    summary = await cartSummary(cart.data?.id || null);
  }

  res.json({
    banner: {
      image_url: settings.data?.banner_image_url || null
    },
    categories: categories.data,
    sections: {
      featured_cocktails: {
        title: 'Cocktails',
        items: featuredCocktails.data.cards.slice(0, 8)
      },
      snacks_and_more: {
        title: 'Snacks and More',
        items: snacksAndMore.data.cards.slice(0, 8)
      }
    },
    cartSummary: summary,
    meta: {
      location_id: locationId,
      product_counts: {
        featured_cocktails: featuredCocktails.data.cards.length,
        snacks_and_more: snacksAndMore.data.cards.length
      }
    }
  });
});

customerRouter.get('/customer/shop/categories/:identifier/products', async (req, res) => {
  const parsed = z.object({
    location_id: optionalUuid,
    locationId: optionalUuid,
    sort: z.enum(['display_order', 'price_asc', 'prep_time']).optional(),
    page: z.coerce.number().int().positive().optional(),
    page_size: z.coerce.number().int().positive().max(100).optional()
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid category products request.'
  });

  const category = await loadCategoryByIdentifier(req.params.identifier);
  if (category.error) return res.status(400).json({ error: category.error.message });
  if (!category.data) return res.status(404).json({ error: 'Category not found.' });

  const page = parsed.data.page || 1;
  const pageSize = parsed.data.page_size || 24;
  const locationId = parsed.data.location_id || parsed.data.locationId || null;

  const catalog = await loadCatalog({
    locationId,
    categoryId: category.data.id
  });

  if (catalog.error) return res.status(400).json({ error: catalog.error.message });

  let results = [...catalog.data.cards];

  if (!parsed.data.sort || parsed.data.sort === 'display_order') {
    results.sort((a, b) => Number(a.display_order || 0) - Number(b.display_order || 0) || a.name.localeCompare(b.name));
  }

  if (parsed.data.sort === 'price_asc') {
    results.sort((a, b) => Number(a.price.starting_price_inc_vat || 0) - Number(b.price.starting_price_inc_vat || 0));
  }

  if (parsed.data.sort === 'prep_time') {
    results.sort((a, b) => Number(a.prep_time_minutes || 0) - Number(b.prep_time_minutes || 0));
  }

  const total = results.length;
  const pagedResults = results.slice((page - 1) * pageSize, page * pageSize);

  res.json({
    category: publicCategory(category.data),
    results: pagedResults,
    meta: {
      total,
      page,
      page_size: pageSize,
      has_more: page * pageSize < total,
      location_id: locationId,
      sort: parsed.data.sort || 'display_order'
    }
  });
});

customerRouter.get('/customer/cocktail-finder/options', async (_req, res) => {
  const [liquorTypes, categories, productTags] = await Promise.all([
    supabase
      .from('liquor_types')
      .select('*')
      .eq('is_active', true)
      .order('display_order')
      .order('name'),

    supabase
      .from('product_categories')
      .select('*')
      .eq('is_active', true)
      .order('sort_order')
      .order('name'),

    supabase
      .from('product_tags')
      .select('*')
      .eq('is_active', true)
      .order('display_order')
      .order('name')
  ]);

  for (const result of [liquorTypes, categories, productTags]) {
    if (result.error) return res.status(400).json({
      error: result.error.message
    });
  }

  const productTagOptions = (productTags.data || []).map(publicProductTag);

  res.json({
    liquorTypes: (liquorTypes.data || []).map(publicLiquorType),
    categories: (categories.data || []).map(publicCategory),
    tags: productTagOptions.map((tag) => tag.name),
    productTags: productTagOptions,
    sortOptions: [
      {
        value: 'featured',
        label: 'Featured'
      },
      {
        value: 'price_asc',
        label: 'Price: Low to High'
      },
      {
        value: 'prep_time',
        label: 'Fastest to Prepare'
      }
    ]
  });
});


customerRouter.get('/customer/cocktails', async (req, res) => {
  const parsed = z.object({
    location_id: optionalUuid,
    category_id: optionalUuid,
    q: z.string().optional(),
    liquor_type_ids: uuidArrayFromQuery.optional(),
    tags: z.preprocess((value) => {
      if (Array.isArray(value)) return value.flatMap((entry) => String(entry).split(','));
      if (typeof value === 'string') return value.split(',').map((entry) => entry.trim()).filter(Boolean);
      return [];
    }, z.array(z.string())).optional(),
    sort: z.enum(['featured', 'price_asc', 'prep_time']).optional(),
    page: z.coerce.number().int().positive().optional(),
    page_size: z.coerce.number().int().positive().max(100).optional()
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid cocktail search request.'
  });

  const page = parsed.data.page || 1;
  const pageSize = parsed.data.page_size || 50;

  const catalog = await loadCatalog({
    locationId: parsed.data.location_id || null,
    categoryId: parsed.data.category_id || null,
    q: parsed.data.q || '',
    liquorTypeIds: parsed.data.liquor_type_ids || [],
    tags: parsed.data.tags || [],
    // The cocktail finder must only surface cocktails, never snacks,
    // essentials, bundles or add-ons that may share tags/filters.
    productTypes: ['cocktail']
  });

  if (catalog.error) return res.status(400).json({
    error: catalog.error.message
  });

  let results = [...catalog.data.cards];

  if (parsed.data.sort === 'featured') {
    results.sort((a, b) => {
      return Number(b.is_featured) - Number(a.is_featured)
        || Number(a.display_order || 0) - Number(b.display_order || 0);
    });
  }

  if (parsed.data.sort === 'price_asc') {
    results.sort((a, b) => {
      return Number(a.price.starting_price_inc_vat || 0) - Number(b.price.starting_price_inc_vat || 0);
    });
  }

  if (parsed.data.sort === 'prep_time') {
    results.sort((a, b) => {
      return Number(a.prep_time_minutes || 0) - Number(b.prep_time_minutes || 0);
    });
  }


  const customer = await findCustomerFromRequest(req);
  let favoriteProductIds = new Set();

  if (customer) {
    try {
      favoriteProductIds = await loadCustomerFavoriteIdSet(customer.id);
    } catch (error) {
      return res.status(400).json({ error: error.message });
    }
  }

  const total = results.length;
  results = results
    .slice((page - 1) * pageSize, page * pageSize)
    .map((card) => addFavoriteFlagToCard(card, favoriteProductIds));

  res.json({  
    filters_applied: {
      liquor_type_ids: parsed.data.liquor_type_ids || [],
      category_id: parsed.data.category_id || null,
      q: parsed.data.q || null,
      location_id: parsed.data.location_id || null,
      sort: parsed.data.sort || null
    },
    results,
    meta: {
      total,
      page,
      page_size: pageSize
    }
  });
});

customerRouter.get('/customer/cocktails/:slug', async (req, res) => {
  const parsed = z.object({
    location_id: optionalUuid,
    liquor_type_id: optionalUuid
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid cocktail detail request.'
  });

  const locationId = parsed.data.location_id || null;
  const liquorTypeId = parsed.data.liquor_type_id || null;

  const detail = await loadProductDetail({
    slug: req.params.slug,
    locationId,
    liquorTypeId
  });

  if (detail.error) return res.status(400).json({
    error: detail.error.message
  });

  if (detail.badRequest) return res.status(400).json({
    error: detail.badRequest
  });

  if (detail.notFound) return res.status(404).json({
    error: 'Cocktail not found.'
  });

  const customer = await findCustomerFromRequest(req);

  let cartContext = {
    cart_id: null,
    selected_variant_id: detail.data.selectedVariant?.id || null,
    quantity_for_selected_variant: 0,
    quantities_by_variant: {},
    total_quantity: 0
  };

  if (customer) {
    const cart = await getActiveCart(customer.id, {
      createIfMissing: false
    });

    if (cart.error) return res.status(400).json({
      error: cart.error.message
    });

    if (cart.data) {
      const items = await supabase
        .from('cart_items')
        .select('variant_id,quantity')
        .eq('cart_id', cart.data.id)
        .eq('product_id', detail.data.product.id);

      if (items.error) return res.status(400).json({
        error: items.error.message
      });

      const quantitiesByVariant = (items.data || []).reduce((acc, item) => {
        acc[item.variant_id] = Number(acc[item.variant_id] || 0) + Number(item.quantity || 0);
        return acc;
      }, {});

      cartContext = {
        cart_id: cart.data.id,
        selected_variant_id: detail.data.selectedVariant?.id || null,
        quantity_for_selected_variant: detail.data.selectedVariant?.id
          ? Number(quantitiesByVariant[detail.data.selectedVariant.id] || 0)
          : 0,
        quantities_by_variant: quantitiesByVariant,
        total_quantity: (items.data || []).reduce((sum, item) => sum + Number(item.quantity || 0), 0)
      };
    }
  }

  const relatedCatalog = liquorTypeId
    ? await loadCatalog({
        locationId,
        liquorTypeIds: [liquorTypeId]
      })
    : {
        data: {
          cards: []
        }
      };

  if (relatedCatalog.error) return res.status(400).json({
    error: relatedCatalog.error.message
  });

  let favoriteProductIds = new Set();

  if (customer) {
    try {
      favoriteProductIds = await loadCustomerFavoriteIdSet(customer.id);
    } catch (error) {
      return res.status(400).json({ error: error.message });
    }
  }

  const cocktail = cocktailDetailPayload({
    card: detail.data.card,
    selectedVariant: detail.data.selectedVariant,
    selectedLiquor: detail.data.selectedLiquor,
    recipe: detail.data.recipe,
    recipeItems: detail.data.recipeItems,
    balancesByIngredientId: detail.data.balancesByIngredientId,
    locationId,
    addonCards: detail.data.addonCards
  });

  res.json({
    cocktail: {
      ...cocktail,
      is_favorite: favoriteProductIds.has(cocktail.id)
    },
    cartContext,
    relatedCocktails: (relatedCatalog.data.cards || [])
      .filter((card) => card.id !== detail.data.product.id)
      .slice(0, 6)
      .map((card) => addFavoriteFlagToRelated(card, favoriteProductIds))
  });
});

customerRouter.get('/customer/profile', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const [ordersPreview, addressesCount, favoritesCount, unreadNotificationsCount] = await Promise.all([
    loadCustomerOrdersPreview(ensured.customer.id, { limit: CUSTOMER_PROFILE_ORDER_LIMIT }),
    countRows('customer_addresses', ensured.customer.id),
    countRows('customer_favorite_products', ensured.customer.id),
    supabase
      .from('customer_notifications')
      .select('id', { count: 'exact', head: true })
      .eq('customer_id', ensured.customer.id)
      .is('read_at', null)
  ]);

  for (const result of [ordersPreview, addressesCount, favoritesCount, unreadNotificationsCount]) {
    if (result.error) return res.status(400).json({ error: result.error.message });
  }

  const addressCount = Number(addressesCount.count || 0);
  const favoriteCount = Number(favoritesCount.count || 0);
  const unreadNotifications = Number(unreadNotificationsCount.count || 0);

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    customer: customerProfilePayload(ensured.customer),
    recent_orders: {
      title: 'My Orders',
      limit: CUSTOMER_PROFILE_ORDER_LIMIT,
      has_more: ordersPreview.data.has_more,
      view_all_endpoint: '/api/customer/orders',
      items: ordersPreview.data.items
    },
    quick_links: profileQuickLinks({ addressCount, favoriteCount, unreadNotifications }),
    payment_methods: {
      enabled: false,
      placeholder: true,
      provider_managed: true,
      saved_count: 0,
      message: 'Saved payment methods will be enabled after the payment processor stored-card contract is finalized.'
    },
    favorites: {
      enabled: true,
      count: favoriteCount,
      endpoint: '/api/customer/favorites'
    },
    promo_codes: {
      enabled: false,
      navigation_only: true,
      placeholder: true
    },
    notifications: {
      enabled: true,
      navigation_only: true,
      placeholder: false,
      unread_count: unreadNotifications,
      endpoint: '/api/customer/notifications'
    },
    brand_message: {
      title: 'You bring the bottle.',
      accent: 'We bring the magic.'
    }
  });
});

customerRouter.patch('/customer/profile', handleCustomerProfileUpdate);

customerRouter.get('/customer/orders', async (req, res) => {
  const parsed = z.object({
    limit: z.coerce.number().int().positive().max(100).optional(),
    offset: z.coerce.number().int().min(0).optional()
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid orders request.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const orders = await loadCustomerOrdersPreview(ensured.customer.id, {
    limit: parsed.data.limit || 20,
    offset: parsed.data.offset || 0
  });

  if (orders.error) return res.status(400).json({
    error: orders.error.message
  });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    orders: orders.data.items,
    meta: {
      limit: orders.data.limit,
      offset: orders.data.offset,
      has_more: orders.data.has_more
    }
  });
});


customerRouter.get('/customer/notifications', async (req, res) => {
  const parsed = z.object({
    limit: z.coerce.number().int().positive().max(100).optional(),
    unread_only: z.preprocess((value) => value === 'true' || value === true, z.boolean().optional())
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid notifications request.' });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  let query = supabase
    .from('customer_notifications')
    .select('*, orders(order_number)')
    .eq('customer_id', ensured.customer.id)
    .order('created_at', { ascending: false })
    .limit(parsed.data.limit || 50);

  if (parsed.data.unread_only) query = query.is('read_at', null);

  const notifications = await query;
  if (notifications.error) return res.status(400).json({ error: notifications.error.message });

  const unreadCount = await supabase
    .from('customer_notifications')
    .select('id', { count: 'exact', head: true })
    .eq('customer_id', ensured.customer.id)
    .is('read_at', null);

  if (unreadCount.error) return res.status(400).json({ error: unreadCount.error.message });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    notifications: (notifications.data || []).map(publicNotification),
    unread_count: Number(unreadCount.count || 0)
  });
});

customerRouter.patch('/customer/notifications/:notificationId/read', async (req, res) => {
  const parsed = z.object({ notificationId: uuid }).safeParse(req.params);
  if (!parsed.success) return res.status(400).json({ error: 'Invalid notification request.' });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const updated = await supabase
    .from('customer_notifications')
    .update({ read_at: new Date().toISOString() })
    .eq('id', parsed.data.notificationId)
    .eq('customer_id', ensured.customer.id)
    .select('*, orders(order_number)')
    .maybeSingle();

  if (updated.error) return res.status(400).json({ error: updated.error.message });
  if (!updated.data) return res.status(404).json({ error: 'Notification not found.' });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    notification: publicNotification(updated.data)
  });
});

customerRouter.post('/customer/notifications/read-all', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const updated = await supabase
    .from('customer_notifications')
    .update({ read_at: new Date().toISOString() })
    .eq('customer_id', ensured.customer.id)
    .is('read_at', null);

  if (updated.error) return res.status(400).json({ error: updated.error.message });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    unread_count: 0
  });
});

customerRouter.post('/customer/push-tokens', async (req, res) => {
  const parsed = z.object({
    token: z.string().trim().min(10).max(4096),
    platform: z.string().trim().max(40).optional(),
    device_id: z.string().trim().max(120).nullable().optional()
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({ error: 'Invalid push token request.' });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const registered = await registerCustomerPushToken({
    customerId: ensured.customer.id,
    token: parsed.data.token,
    platform: parsed.data.platform || 'unknown',
    deviceId: parsed.data.device_id || null
  });

  if (registered.error) return res.status(400).json({ error: registered.error.message });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    push_token: registered.data
  });
});

customerRouter.get('/customer/favorites', async (req, res) => {
  const parsed = z.object({
    location_id: optionalUuid,
    locationId: optionalUuid,
    page: z.coerce.number().int().positive().optional(),
    page_size: z.coerce.number().int().positive().max(100).optional()
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid favorites request.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const favorites = await loadFavoriteProducts(ensured.customer.id, {
    locationId: parsed.data.location_id || parsed.data.locationId || null,
    page: parsed.data.page || 1,
    pageSize: parsed.data.page_size || 50
  });

  if (favorites.error) return res.status(400).json({
    error: favorites.error.message
  });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    ...favorites.data
  });
});

customerRouter.post('/customer/favorites', handleAddCustomerFavorite);

customerRouter.post('/customer/favorites/:productId', async (req, res) => {
  req.body = {
    ...req.body,
    product_id: req.params.productId
  };

  return handleAddCustomerFavorite(req, res);
});

customerRouter.delete('/customer/favorites/:productId', async (req, res) => {
  const parsed = z.object({ productId: uuid }).safeParse(req.params);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid favorite request.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const deleted = await supabase
    .from('customer_favorite_products')
    .delete()
    .eq('customer_id', ensured.customer.id)
    .eq('product_id', parsed.data.productId);

  if (deleted.error) return res.status(400).json({
    error: deleted.error.message
  });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    ok: true,
    product_id: parsed.data.productId,
    is_favorite: false
  });
});

customerRouter.get('/customer/cart', async (req, res) => {
  const parsed = z.object({
    location_id: optionalUuid,
    locationId: optionalUuid,
    fulfillment_type: z.enum(FULFILLMENT_TYPES).optional(),
    fulfillmentType: z.enum(FULFILLMENT_TYPES).optional()
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid cart request.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const cart = await buildCartResponse(ensured.customer.id, {
    createIfMissing: true,
    locationId: parsed.data.location_id || parsed.data.locationId || null,
    fulfillmentType: parsed.data.fulfillment_type || parsed.data.fulfillmentType || 'pickup_at_cart'
  });

  if (cart.error) return res.status(400).json({
    error: cart.error.message
  });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    ...cart.data
  });
});

customerRouter.post('/customer/cart/items', async (req, res) => {
  const parsed = z.object({
    // Customer-app preferred names.
    cocktail_id: uuid.optional(),
    selected_quantity: z.coerce.number().int().positive().max(MAX_CART_ITEM_QTY).optional(),
    location_id: uuid.optional(),
    selected_liquor_type_id: uuid.nullable().optional(),

    // Customization payload. Removals are recipe item IDs. Additions are active add-on variants.
    customization: z.any().optional(),
    removed_recipe_item_ids: z.array(uuid).optional(),
    remove_recipe_item_ids: z.array(uuid).optional(),
    removedRecipeItemIds: z.array(uuid).optional(),
    removeRecipeItemIds: z.array(uuid).optional(),
    additions: z.array(z.any()).optional(),

    // Backwards-compatible aliases used by the current API and by camelCase Flutter code.
    product_id: uuid.optional(),
    cocktailId: uuid.optional(),
    productId: uuid.optional(),
    variant_id: uuid.optional(),
    variantId: uuid.optional(),
    quantity: z.coerce.number().int().positive().max(MAX_CART_ITEM_QTY).optional(),
    selectedQuantity: z.coerce.number().int().positive().max(MAX_CART_ITEM_QTY).optional(),
    locationId: uuid.optional(),
    selectedLiquorTypeId: uuid.nullable().optional()
  }).superRefine((data, ctx) => {
    const productId = data.cocktail_id || data.cocktailId || data.product_id || data.productId;
    const variantId = data.variant_id || data.variantId;
    const selectedQuantity = data.selected_quantity ?? data.selectedQuantity ?? data.quantity ?? 1;
    const locationId = data.location_id || data.locationId;

    if (!productId) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['cocktail_id'],
        message: 'cocktail_id is required.'
      });
    }

    if (!variantId) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['variant_id'],
        message: 'variant_id is required.'
      });
    }

    if (!selectedQuantity) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['selected_quantity'],
        message: 'selected_quantity is required.'
      });
    }

    if (!locationId) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['location_id'],
        message: 'location_id is required.'
      });
    }

    if (data.quantity !== undefined && data.selected_quantity !== undefined && data.quantity !== data.selected_quantity) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['selected_quantity'],
        message: 'Send either quantity or selected_quantity, not conflicting values.'
      });
    }

    if (data.selectedQuantity !== undefined && data.selected_quantity !== undefined && data.selectedQuantity !== data.selected_quantity) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['selectedQuantity'],
        message: 'Send either selectedQuantity or selected_quantity, not conflicting values.'
      });
    }

    if (data.quantity !== undefined && data.selectedQuantity !== undefined && data.quantity !== data.selectedQuantity) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['selectedQuantity'],
        message: 'Send either quantity or selectedQuantity, not conflicting values.'
      });
    }
  }).transform((data) => ({
    productId: data.cocktail_id || data.cocktailId || data.product_id || data.productId,
    variantId: data.variant_id || data.variantId,
    selectedQuantity: data.selected_quantity ?? data.selectedQuantity ?? data.quantity ?? 1,
    locationId: data.location_id || data.locationId,
    selectedLiquorTypeId: data.selected_liquor_type_id || data.selectedLiquorTypeId || null,
    customization: normalizeRawCustomization(data)
  })).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid cart item.',
    details: parsed.error.issues.map((issue) => ({
      path: issue.path.join('.'),
      message: issue.message
    }))
  });

  const location = await validateBeachCart(parsed.data.locationId, res);
  if (!location) return;

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const cart = await getActiveCart(ensured.customer.id, {
    createIfMissing: true
  });

  if (cart.error) return res.status(400).json({
    error: cart.error.message
  });

  const catalog = await loadCatalog({
    locationId: parsed.data.locationId,
    productIds: [parsed.data.productId]
  });

  if (catalog.error) return res.status(400).json({
    error: catalog.error.message
  });

  const raw = catalog.data.raw || {};
  const product = (raw.products || []).find((entry) => entry.id === parsed.data.productId);
  const variant = (raw.variants || []).find((entry) => entry.id === parsed.data.variantId);
  const recipe = pickCurrentRecipe((raw.recipes || []).filter((entry) => entry.product_id === parsed.data.productId));
  const recipeItems = (raw.recipeItems || []).filter((entry) => entry.recipe_id === recipe?.id);

  if (!product || product.status !== 'active') {
    return res.status(400).json({
      error: 'This item is not available.'
    });
  }

  if (!variant || variant.product_id !== parsed.data.productId || !variant.is_active) {
    return res.status(400).json({
      error: 'This serving size is not available.'
    });
  }

  const isCocktail = product.product_type === 'cocktail';
  const hasCustomization = Boolean(
    parsed.data.customization.removedRecipeItemIds.length
    || parsed.data.customization.additions.length
  );

  if (!isCocktail && parsed.data.selectedLiquorTypeId) {
    return res.status(400).json({
      error: 'Selected liquor can only be sent for cocktails.'
    });
  }

  if (!isCocktail && hasCustomization) {
    return res.status(400).json({
      error: 'Only cocktails can be customized.'
    });
  }

  if (isCocktail && parsed.data.selectedLiquorTypeId) {
    const selectedLiquorCompatibility = (raw.compatibility || []).find((entry) => {
      return entry.product_id === parsed.data.productId
        && entry.liquor_type_id === parsed.data.selectedLiquorTypeId
        && entry.liquor_types?.is_active !== false;
    });

    if (!selectedLiquorCompatibility) {
      return res.status(400).json({
        error: 'Selected liquor is not compatible with this cocktail.'
      });
    }
  }

  const validatedCustomization = isCocktail
    ? await validateCocktailCustomization({
        customization: parsed.data.customization,
        productId: parsed.data.productId,
        recipe,
        recipeItems
      })
    : {
        data: {
          hash: 'base',
          summary: null,
          removedIngredients: [],
          additions: [],
          addonTotalIncVat: 0
        }
      };

  if (validatedCustomization.error) return res.status(400).json({
    error: validatedCustomization.error.message
  });

  if (validatedCustomization.badRequest) return res.status(400).json({
    error: validatedCustomization.badRequest
  });

  const customization = validatedCustomization.data;

  const existingItem = await supabase
    .from('cart_items')
    .select('*')
    .eq('cart_id', cart.data.id)
    .eq('variant_id', parsed.data.variantId)
    .eq('customization_hash', customization.hash)
    .maybeSingle();

  if (existingItem.error) return res.status(400).json({
    error: existingItem.error.message
  });

  const nextQuantity = existingItem.data
    ? Number(existingItem.data.quantity || 0) + parsed.data.selectedQuantity
    : parsed.data.selectedQuantity;

  if (nextQuantity > MAX_CART_ITEM_QTY) {
    return res.status(400).json({
      error: `You can add up to ${MAX_CART_ITEM_QTY} of the same item.`
    });
  }

  const temporaryItem = {
    product_id: parsed.data.productId,
    variant_id: parsed.data.variantId,
    product_variants: variant,
    recipe_id: recipe?.id || null,
    quantity: nextQuantity,
    cart_item_removed_ingredients: customization.removedIngredients,
    cart_item_additions: customization.additions
  };

  const addonRecipeIds = [...new Set(customization.additions.map((addition) => addition.addon_recipe_id).filter(Boolean))];
  const addonRecipeRows = addonRecipeIds.length
    ? await supabase.from('recipes').select('*').in('id', addonRecipeIds)
    : { data: [], error: null };
  if (addonRecipeRows.error) return res.status(400).json({ error: addonRecipeRows.error.message });

  const addonRecipeItemRows = addonRecipeIds.length
    ? await supabase
        .from('recipe_items')
        .select('*, ingredients(id,name,category,base_unit,is_customer_supplied,icon_key)')
        .in('recipe_id', addonRecipeIds)
    : { data: [], error: null };
  if (addonRecipeItemRows.error) return res.status(400).json({ error: addonRecipeItemRows.error.message });

  const recipeById = new Map([[recipe?.id, recipe], ...(addonRecipeRows.data || []).map((entry) => [entry.id, entry])].filter(([id]) => Boolean(id)));
  const recipeItemsByRecipeId = new Map([[recipe?.id, recipeItems]].filter(([id]) => Boolean(id)));
  for (const recipeItem of addonRecipeItemRows.data || []) {
    const list = recipeItemsByRecipeId.get(recipeItem.recipe_id) || [];
    list.push(recipeItem);
    recipeItemsByRecipeId.set(recipeItem.recipe_id, list);
  }

  const inventoryComponents = inventoryComponentsForConfiguredItem({
    item: temporaryItem,
    variant,
    recipe,
    recipeItems,
    recipeById,
    recipeItemsByRecipeId
  });

  const stockedIngredientIds = [...new Set(inventoryComponents.map((component) => component.ingredient_id).filter(Boolean))];
  const balances = stockedIngredientIds.length
    ? await supabase
        .from('inventory_balances')
        .select('ingredient_id,location_id,quantity_on_hand,reserved_quantity')
        .eq('location_id', parsed.data.locationId)
        .in('ingredient_id', stockedIngredientIds)
    : { data: [], error: null };

  if (balances.error) return res.status(400).json({
    error: balances.error.message
  });

  const availability = buildAvailabilityForComponents({
    locationId: parsed.data.locationId,
    recipe,
    components: inventoryComponents,
    balancesByIngredientId: new Map((balances.data || []).map((balance) => [balance.ingredient_id, balance])),
    variant,
    cartQuantity: nextQuantity
  });

  if (!availability.is_orderable) {
    return res.status(400).json({
      error: availability.reason || 'Item is not available at this beach cart.'
    });
  }

  if (parsed.data.selectedLiquorTypeId) {
    const selectedLiquorTypeIds = Array.isArray(cart.data.selected_liquor_type_ids)
      ? cart.data.selected_liquor_type_ids
      : [];

    if (!selectedLiquorTypeIds.includes(parsed.data.selectedLiquorTypeId)) {
      const updatedCart = await supabase
        .from('carts')
        .update({
          selected_liquor_type_ids: [...selectedLiquorTypeIds, parsed.data.selectedLiquorTypeId]
        })
        .eq('id', cart.data.id)
        .select()
        .single();

      if (updatedCart.error) return res.status(400).json({
        error: updatedCart.error.message
      });
    }
  }

  const baseUnitPrice = variantPriceIncVat(variant);
  const unitPrice = money(baseUnitPrice + customization.addonTotalIncVat);
  const vatRate = Number(variant.vat_rate || 0);

  const saved = existingItem.data
    ? await supabase
        .from('cart_items')
        .update({
          quantity: nextQuantity
        })
        .eq('id', existingItem.data.id)
        .eq('cart_id', cart.data.id)
        .select('*, products(name,slug,image_url), product_variants(name,serving_count), cart_item_removed_ingredients(*), cart_item_additions(*)')
        .single()
    : await supabase
        .from('cart_items')
        .insert({
          cart_id: cart.data.id,
          product_id: parsed.data.productId,
          variant_id: parsed.data.variantId,
          recipe_id: recipe?.id || null,
          quantity: parsed.data.selectedQuantity,
          base_unit_price_inc_vat_snapshot: baseUnitPrice,
          customization_total_inc_vat_snapshot: customization.addonTotalIncVat,
          customization_hash: customization.hash,
          customization_summary: customization.summary,
          unit_price_inc_vat_snapshot: unitPrice,
          vat_rate_snapshot: vatRate
        })
        .select('*, products(name,slug,image_url), product_variants(name,serving_count), cart_item_removed_ingredients(*), cart_item_additions(*)')
        .single();

  if (saved.error) return res.status(400).json({
    error: saved.error.message
  });

  if (!existingItem.data) {
    const removedPayload = customization.removedIngredients.map((removed) => ({
      ...removed,
      cart_item_id: saved.data.id
    }));

    const additionsPayload = customization.additions.map((addition) => ({
      ...addition,
      cart_item_id: saved.data.id
    }));

    const childInserts = [];
    if (removedPayload.length) childInserts.push(supabase.from('cart_item_removed_ingredients').insert(removedPayload));
    if (additionsPayload.length) childInserts.push(supabase.from('cart_item_additions').insert(additionsPayload));

    const childResults = await Promise.all(childInserts);
    const childError = childResults.find((result) => result.error)?.error;

    if (childError) {
      await supabase.from('cart_items').delete().eq('id', saved.data.id);
      return res.status(400).json({
        error: childError.message
      });
    }
  }

  const refreshedCart = await buildCartResponse(ensured.customer.id, {
    createIfMissing: false,
    locationId: parsed.data.locationId
  });

  if (refreshedCart.error) return res.status(400).json({
    error: refreshedCart.error.message
  });

  const refreshedItem = refreshedCart.data.items.find((entry) => entry.id === saved.data.id) || null;

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    action: {
      type: existingItem.data ? 'quantity_incremented' : 'item_added',
      added_quantity: parsed.data.selectedQuantity,
      final_quantity: saved.data.quantity,
      location: publicLocation(location)
    },
    addedItem: refreshedItem || {
      id: saved.data.id,
      product_id: saved.data.product_id,
      cocktail_id: saved.data.product_id,
      variant_id: saved.data.variant_id,
      quantity: saved.data.quantity,
      customization: buildCustomizationPayloadForCartItem(saved.data),
      unit_price_inc_vat_snapshot: money(saved.data.unit_price_inc_vat_snapshot),
      line_total_inc_vat: money(saved.data.unit_price_inc_vat_snapshot * saved.data.quantity),
      product: {
        name: saved.data.products?.name,
        slug: saved.data.products?.slug,
        image_url: saved.data.products?.image_url
      },
      variant: {
        name: saved.data.product_variants?.name,
        serving_count: saved.data.product_variants?.serving_count
      }
    },
    ...refreshedCart.data
  });
});

customerRouter.patch('/customer/cart/items/:itemId', async (req, res) => {
  const parsed = z.object({
    quantity: z.coerce.number().int().min(0).max(MAX_CART_ITEM_QTY)
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid quantity.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const cart = await getActiveCart(ensured.customer.id, {
    createIfMissing: false
  });

  if (cart.error) return res.status(400).json({
    error: cart.error.message
  });

  if (!cart.data) return res.status(404).json({
    error: 'Cart not found.'
  });

  const current = await supabase
    .from('cart_items')
    .select('*')
    .eq('id', req.params.itemId)
    .eq('cart_id', cart.data.id)
    .maybeSingle();

  if (current.error) return res.status(400).json({
    error: current.error.message
  });

  if (!current.data) return res.status(404).json({
    error: 'Cart item not found.'
  });

  if (parsed.data.quantity === 0) {
    const deleted = await supabase
      .from('cart_items')
      .delete()
      .eq('id', req.params.itemId)
      .eq('cart_id', cart.data.id)
      .select()
      .single();

    if (deleted.error) return res.status(400).json({
      error: deleted.error.message
    });

    return res.json({
      removed_item_id: req.params.itemId,
      cartSummary: await cartSummary(cart.data.id)
    });
  }

  const updated = await supabase
    .from('cart_items')
    .update({
      quantity: parsed.data.quantity
    })
    .eq('id', req.params.itemId)
    .eq('cart_id', cart.data.id)
    .select()
    .single();

  if (updated.error) return res.status(400).json({
    error: updated.error.message
  });

  res.json({
    item: {
      id: updated.data.id,
      quantity: updated.data.quantity,
      unit_price_inc_vat_snapshot: money(updated.data.unit_price_inc_vat_snapshot),
      line_total_inc_vat: money(updated.data.unit_price_inc_vat_snapshot * updated.data.quantity)
    },
    cartSummary: await cartSummary(cart.data.id)
  });
});

customerRouter.delete('/customer/cart/items/:itemId', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const cart = await getActiveCart(ensured.customer.id, {
    createIfMissing: false
  });

  if (cart.error) return res.status(400).json({
    error: cart.error.message
  });

  if (!cart.data) return res.status(404).json({
    error: 'Cart not found.'
  });

  const deleted = await supabase
    .from('cart_items')
    .delete()
    .eq('id', req.params.itemId)
    .eq('cart_id', cart.data.id)
    .select()
    .maybeSingle();

  if (deleted.error) return res.status(400).json({
    error: deleted.error.message
  });

  res.json({
    removed_item_id: req.params.itemId,
    cartSummary: await cartSummary(cart.data.id)
  });
});

customerRouter.delete('/customer/cart', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const cart = await getActiveCart(ensured.customer.id, {
    createIfMissing: false
  });

  if (cart.error) return res.status(400).json({
    error: cart.error.message
  });

  if (!cart.data) return res.json({
    cart_id: null,
    cleared: true
  });

  const deleted = await supabase
    .from('cart_items')
    .delete()
    .eq('cart_id', cart.data.id);

  if (deleted.error) return res.status(400).json({
    error: deleted.error.message
  });

  res.json({
    cart_id: cart.data.id,
    cleared: true
  });
});


customerRouter.get('/customer/checkout', async (req, res) => {
  const parsed = z.object({
    location_id: uuid.optional(),
    locationId: uuid.optional(),
    fulfillment_type: z.enum(['pickup_at_cart', 'delivery_to_unit']).optional(),
    fulfillmentType: z.enum(['pickup_at_cart', 'delivery_to_unit']).optional(),
    promo_code: z.string().nullable().optional(),
    promoCode: z.string().nullable().optional()
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid checkout request.'
  });

  const locationId = parsed.data.location_id || parsed.data.locationId;

  if (!locationId) return res.status(400).json({
    error: 'location_id is required.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const cart = await getActiveCart(ensured.customer.id, {
    createIfMissing: false
  });

  if (cart.error) return res.status(400).json({
    error: cart.error.message
  });

  if (!cart.data) return res.status(400).json({
    error: 'Cart is empty.'
  });

  const fulfillmentType = parsed.data.fulfillment_type || parsed.data.fulfillmentType || 'delivery_to_unit';

  const quote = await buildCheckoutQuote({
    customerId: ensured.customer.id,
    cartId: cart.data.id,
    locationId,
    fulfillmentType,
    promoCode: parsed.data.promo_code || parsed.data.promoCode || null,
    requireCustomerDetails: false
  });

  if (quote.error) return res.status(400).json({
    error: quote.error.message
  });

  if (quote.badRequest) return res.status(400).json({
    error: quote.badRequest
  });

  const location = await loadCartLocation(locationId);

  if (location.error) return res.status(400).json({
    error: location.error.message
  });

  const itemWarnings = quote.data.quote.items
    .filter((item) => !item.is_available)
    .map((item) => ({
      cart_item_id: item.cart_item_id,
      product_id: item.product_id,
      product_name: item.product_name,
      reason: item.blocking_reason || 'Currently unavailable at this beach cart.'
    }));

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    checkout: {
      cart_id: cart.data.id,
      cart_expires_at: cart.data.expires_at || cartExpiresAtIso(),
      location: location.data,
      fulfillment: {
        type: fulfillmentType,
        delivery_fee: quote.data.quote.totals.delivery_fee,
        currency: CURRENCY
      },
      customer: {
        id: ensured.customer.id,
        phone: ensured.customer.phone || null
      },
      requirements: {
        customer_phone: {
          required: true,
          validation: '^0[0-9]{10}$',
          helper_text: 'Egyptian mobile number, 11 digits, starting with 0.'
        },
        address: {
          required: fulfillmentType === 'delivery_to_unit',
          max_length: 500
        },
        promo_code: {
          required: false,
          max_count: 1
        }
      },
      items: quote.data.quote.items,
      item_warnings: itemWarnings,
      summary: quote.data.quote.totals,
      promotion: quote.data.quote.promotion,
      payment_mode: PAYMENT_MODE,
      payment_methods: checkoutPaymentMethods(),
      validation: {
        can_place_order: quote.data.quote.validation.can_place_order && (isDemoPaymentMode || liveProviderIsConfigured()),
        blocking_reasons: [
          ...quote.data.quote.validation.blocking_reasons,
          ...(isDemoPaymentMode || liveProviderIsConfigured() ? [] : ['Payment gateway is not configured yet.'])
        ]
      }
    }
  });
});

customerRouter.get('/customer/checkout/options', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const [addresses, locations] = await Promise.all([
    supabase
      .from('customer_addresses')
      .select('*')
      .eq('customer_id', ensured.customer.id)
      .order('is_default', {
        ascending: false
      })
      .order('created_at'),

    loadServiceLocations()
  ]);

  for (const result of [addresses, locations]) {
    if (result.error) return res.status(400).json({
      error: result.error.message
    });
  }

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    customer: {
      id: ensured.customer.id,
      full_name: ensured.customer.full_name,
      phone: ensured.customer.phone,
      email: ensured.customer.email,
      marketing_opt_in: ensured.customer.marketing_opt_in
    },
    addresses: addresses.data || [],
    serviceLocations: (locations.data || []).map((location) => ({
      ...publicLocation(location),
      supports_pickup: true,
      supports_delivery: true
    })),
    fulfillmentTypes: [
      {
        value: 'pickup_at_cart',
        label: 'Pickup at cart'
      },
      {
        value: 'delivery_to_unit',
        label: 'Delivery to unit'
      }
    ],
    paymentMode: PAYMENT_MODE,
    paymentMethods: checkoutPaymentMethods()
  });
});

customerRouter.post('/customer/checkout/quote', async (req, res) => {
  const parsed = z.object({
    cart_id: uuid,
    location_id: uuid,
    fulfillment_type: z.enum(['pickup_at_cart', 'delivery_to_unit']),
    customer_address_id: uuid.nullable().optional(),
    address: z.string().trim().min(1).max(500).nullable().optional(),
    requested_fulfillment_at: z.string().nullable().optional(),
    promo_code: z.string().nullable().optional(),
    customer_notes: z.string().nullable().optional()
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid checkout quote request.'
  });

  if (parsed.data.requested_fulfillment_at) {
    return res.status(400).json({
      error: 'Scheduled orders are not supported. Orders are prepared as soon as payment is confirmed.'
    });
  }

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const quote = await buildCheckoutQuote({
    customerId: ensured.customer.id,
    cartId: parsed.data.cart_id,
    locationId: parsed.data.location_id,
    fulfillmentType: parsed.data.fulfillment_type,
    customerAddressId: parsed.data.customer_address_id || null,
    addressText: parsed.data.address || null,
    customerNotes: parsed.data.customer_notes || null,
    promoCode: parsed.data.promo_code || null
  });

  if (quote.error) return res.status(400).json({
    error: quote.error.message
  });

  if (quote.badRequest) return res.status(400).json({
    error: quote.badRequest
  });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    ...quote.data
  });
});


async function handleCustomerPlaceOrder(req, res) {
  const parsed = z.object({
    cart_id: uuid,
    location_id: uuid,
    fulfillment_type: z.enum(['pickup_at_cart', 'delivery_to_unit']),
    address: z.string().trim().min(1).max(500).nullable().optional(),
    customer_address_id: uuid.nullable().optional(),
    customer_phone: z.string().trim().optional(),
    mobile_phone: z.string().trim().optional(),
    phone: z.string().trim().optional(),
    requested_fulfillment_at: z.string().nullable().optional(),
    promo_code: z.string().nullable().optional(),
    customer_notes: z.string().nullable().optional(),
    payment_method: z.enum([
      'geidea_card', 'geidea_apple_pay',
      'stripe_payment_sheet', 'stripe_card',
      'payment_gateway', 'demo_checkout'
    ]),
    save_card: z.boolean().optional().default(false),
    idempotency_key: z.string().min(8).max(120)
  }).transform((data) => ({
    ...data,
    customer_phone: data.customer_phone || data.mobile_phone || data.phone || '',
    payment_method: normalizeCheckoutPaymentMethod(data.payment_method)
  })).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid order request.',
    details: parsed.error.issues.map((issue) => ({
      path: issue.path.join('.'),
      message: issue.message
    }))
  });

  if (parsed.data.requested_fulfillment_at) {
    return res.status(400).json({
      error: 'Scheduled orders are not supported. Orders are prepared as soon as payment is confirmed.'
    });
  }

  if (!isSimpleEgyptianMobile(parsed.data.customer_phone)) {
    return res.status(400).json({
      error: 'Invalid mobile number. Use an Egyptian mobile number that starts with 0 and has 11 digits.'
    });
  }

  if (!isDemoPaymentMode && !liveProviderIsConfigured()) {
    return res.status(503).json({
      error: 'Payment gateway is not configured yet.'
    });
  }

  const method = checkoutPaymentMethods().find((entry) => entry.key === parsed.data.payment_method);

  if (!method?.enabled) {
    return res.status(400).json({
      error: `${method?.label || 'Selected payment method'} is not available yet.`
    });
  }

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const existingPayment = await supabase
    .from('payments')
    .select('*, orders(*)')
    .eq('idempotency_key', parsed.data.idempotency_key)
    .maybeSingle();

  if (existingPayment.error) return res.status(400).json({
    error: existingPayment.error.message
  });

  if (existingPayment.data?.orders) {
    if (existingPayment.data.orders.customer_id !== ensured.customer.id) {
      return res.status(409).json({
        error: 'This idempotency key was already used.'
      });
    }

    const existingItems = await supabase
      .from('order_items')
      .select('*')
      .eq('order_id', existingPayment.data.orders.id)
      .order('created_at');

    if (existingItems.error) return res.status(400).json({
      error: existingItems.error.message
    });

    return res.json({
      session: sessionPayload(ensured.customer.id, ensured.token),
      order: existingPayment.data.orders,
      items: existingItems.data || [],
      payment: createCheckoutPaymentPayload({
        order: existingPayment.data.orders,
        payment: existingPayment.data
      }),
      nextScreen: gatewayNextScreen(existingPayment.data.provider)
    });
  }

  const quote = await buildCheckoutQuote({
    customerId: ensured.customer.id,
    cartId: parsed.data.cart_id,
    locationId: parsed.data.location_id,
    fulfillmentType: parsed.data.fulfillment_type,
    customerAddressId: parsed.data.customer_address_id || null,
    addressText: parsed.data.address || null,
    customerNotes: parsed.data.customer_notes || null,
    promoCode: parsed.data.promo_code || null,
    requireCustomerDetails: true
  });

  if (quote.error) return res.status(400).json({
    error: quote.error.message
  });

  if (quote.badRequest) return res.status(400).json({
    error: quote.badRequest
  });

  const itemsMissingRecipe = quote.data.quote.items.filter((item) => !item.recipe_id);

  if (itemsMissingRecipe.length) {
    return res.status(400).json({
      error: 'Cannot place order. Some cart items do not have an active recipe.',
      blocking_reasons: itemsMissingRecipe.map((item) => {
        return `${item.product_name || 'Item'} does not have an active recipe, so inventory cannot be consumed safely.`;
      })
    });
  }

  if (!quote.data.quote.validation.can_place_order) {
    return res.status(400).json({
      error: 'Cannot place order.',
      blocking_reasons: quote.data.quote.validation.blocking_reasons
    });
  }

  let customerAddressId = parsed.data.customer_address_id || null;
  let customerAddressSnapshot = quote.data.quote.address_text || null;

  if (parsed.data.fulfillment_type === 'delivery_to_unit' && !customerAddressId) {
    const addressInsert = await supabase
      .from('customer_addresses')
      .insert({
        customer_id: ensured.customer.id,
        label: 'Checkout address',
        compound_name: quote.data.location.compound_name || null,
        beach_name: quote.data.location.beach_name || null,
        address: quote.data.quote.address_text,
        is_default: false
      })
      .select()
      .single();

    if (addressInsert.error) return res.status(400).json({
      error: addressInsert.error.message
    });

    customerAddressId = addressInsert.data.id;
    customerAddressSnapshot = addressInsert.data.address;
  } else if (quote.data.address) {
    customerAddressSnapshot = quote.data.address.address || quote.data.address.delivery_notes || null;
  }

  const orderInsert = await supabase
    .from('orders')
    .insert({
      customer_id: ensured.customer.id,
      location_id: parsed.data.location_id,
      customer_address_id: customerAddressId,
      customer_phone_snapshot: parsed.data.customer_phone,
      customer_address_snapshot: customerAddressSnapshot,
      order_channel: 'app',
      fulfillment_type: parsed.data.fulfillment_type,
      status: 'pending_payment',
      payment_status: 'pending',
      requested_fulfillment_at: null,
      subtotal_ex_vat: quote.data.quote.totals.subtotal_ex_vat,
      vat_amount: quote.data.quote.totals.vat_amount,
      discount_amount: quote.data.quote.totals.discount_amount,
      delivery_fee: quote.data.quote.totals.delivery_fee,
      total_amount: quote.data.quote.totals.total_amount,
      customer_notes: parsed.data.customer_notes || null
    })
    .select('*, locations(id,name,type,compound_name,beach_name,banner_image_url,delivery_fee), customer_addresses(*)')
    .single();

  if (orderInsert.error) return res.status(400).json({
    error: orderInsert.error.message
  });

  const orderItemsPayload = quote.data.quote.items.map((item) => ({
    order_id: orderInsert.data.id,
    product_id: item.product_id,
    variant_id: item.variant_id,
    recipe_id: item.recipe_id,
    product_name_snapshot: item.product_name,
    variant_name_snapshot: item.variant_name,
    quantity: item.quantity,
    base_unit_price_inc_vat_snapshot: item.base_unit_price_inc_vat,
    customization_total_inc_vat_snapshot: item.customization_total_inc_vat,
    customization_summary: item.customization_summary,
    unit_price_inc_vat_snapshot: item.unit_price_inc_vat,
    vat_rate_snapshot: item.vat_rate,
    line_total: item.line_total
  }));

  const orderItems = await supabase
    .from('order_items')
    .insert(orderItemsPayload)
    .select();

  if (orderItems.error) {
    await supabase.from('orders').delete().eq('id', orderInsert.data.id);

    return res.status(400).json({
      error: orderItems.error.message
    });
  }

  const orderItemRows = orderItems.data || [];
  const orderRemovedPayload = [];
  const orderAdditionsPayload = [];
  const orderInventoryPayload = [];

  quote.data.quote.items.forEach((quoteItem, index) => {
    const orderItem = orderItemRows[index];
    if (!orderItem) return;

    for (const removed of quoteItem.removed_ingredients || []) {
      orderRemovedPayload.push({
        order_item_id: orderItem.id,
        recipe_item_id: removed.recipe_item_id || null,
        ingredient_id: removed.ingredient_id || null,
        ingredient_name_snapshot: removed.ingredient_name_snapshot || removed.name || 'Ingredient',
        quantity_snapshot: Number(removed.quantity_snapshot ?? removed.quantity ?? 0),
        unit_snapshot: removed.unit_snapshot || removed.unit || null
      });
    }

    for (const addition of quoteItem.additions || []) {
      orderAdditionsPayload.push({
        order_item_id: orderItem.id,
        addon_product_id: addition.addon_product_id || null,
        addon_variant_id: addition.addon_variant_id || null,
        addon_recipe_id: addition.addon_recipe_id || null,
        quantity_per_parent: Number(addition.quantity_per_parent || 1),
        product_name_snapshot: addition.product_name_snapshot || 'Add-on',
        variant_name_snapshot: addition.variant_name_snapshot || null,
        unit_price_inc_vat_snapshot: money(addition.unit_price_inc_vat_snapshot || 0),
        vat_rate_snapshot: Number(addition.vat_rate_snapshot || 0),
        serving_count_snapshot: Number(addition.serving_count_snapshot || 1)
      });
    }

    for (const component of quoteItem.inventory_components || []) {
      orderInventoryPayload.push({
        order_item_id: orderItem.id,
        ingredient_id: component.ingredient_id,
        ingredient_name_snapshot: component.ingredient_name_snapshot || 'Ingredient',
        source_type: component.source_type,
        source_ref_id: component.source_ref_id || null,
        quantity_per_order_item_unit: Number(component.quantity_per_order_item_unit || 0),
        unit_snapshot: component.unit_snapshot || null
      });
    }
  });

  const customizationInserts = [];
  if (orderRemovedPayload.length) customizationInserts.push(supabase.from('order_item_removed_ingredients').insert(orderRemovedPayload));
  if (orderAdditionsPayload.length) customizationInserts.push(supabase.from('order_item_additions').insert(orderAdditionsPayload));
  if (orderInventoryPayload.length) customizationInserts.push(supabase.from('order_item_inventory_components').insert(orderInventoryPayload));

  const customizationResults = await Promise.all(customizationInserts);
  const customizationError = customizationResults.find((result) => result.error)?.error;

  if (customizationError) {
    await supabase.from('orders').delete().eq('id', orderInsert.data.id);

    return res.status(400).json({
      error: customizationError.message
    });
  }

  const payment = await supabase
    .from('payments')
    .insert({
      order_id: orderInsert.data.id,
      provider: isDemoPaymentMode ? DEMO_PAYMENT_PROVIDER : LIVE_PAYMENT_PROVIDER,
      amount: quote.data.quote.totals.total_amount,
      currency: CURRENCY,
      status: isDemoPaymentMode ? 'paid' : 'pending',
      idempotency_key: parsed.data.idempotency_key,
      raw_payload: {
        payment_method: parsed.data.payment_method,
        payment_mode: PAYMENT_MODE,
        demo_confirmed_at: isDemoPaymentMode ? new Date().toISOString() : null,
        save_card: Boolean(parsed.data.save_card),
        promotion: quote.data.quote.promotion
          ? {
              id: quote.data.quote.promotion.id,
              code: quote.data.quote.promotion.code,
              discount_amount: quote.data.quote.promotion.discount_amount
            }
          : null
      }
    })
    .select()
    .single();

  if (payment.error) {
    await supabase.from('orders').delete().eq('id', orderInsert.data.id);

    return res.status(400).json({
      error: payment.error.message
    });
  }

  if (isDemoPaymentMode) {
    const confirmedOrder = await supabase
      .from('orders')
      .update({
        status: 'confirmed',
        payment_status: 'paid',
        requested_fulfillment_at: null
      })
      .eq('id', orderInsert.data.id)
      .eq('status', 'pending_payment')
      .select('*, locations(id,name,type,compound_name,beach_name,banner_image_url,delivery_fee), customer_addresses(*)')
      .single();

    if (confirmedOrder.error) {
      await supabase.from('orders').delete().eq('id', orderInsert.data.id);
      return res.status(400).json({ error: confirmedOrder.error.message });
    }

    if (quote.data.quote.promotion) {
      await recordPromotionRedemptionIfNeeded({
        order: confirmedOrder.data,
        payment: payment.data
      });
    }

    await supabase
      .from('cart_items')
      .delete()
      .eq('cart_id', parsed.data.cart_id);

    await supabase
      .from('carts')
      .update({ status: 'converted' })
      .eq('id', parsed.data.cart_id);

    return res.json({
      session: sessionPayload(ensured.customer.id, ensured.token),
      order: {
        id: confirmedOrder.data.id,
        order_number: confirmedOrder.data.order_number,
        status: confirmedOrder.data.status,
        payment_status: confirmedOrder.data.payment_status,
        fulfillment_type: confirmedOrder.data.fulfillment_type,
        requested_fulfillment_at: null,
        created_at: confirmedOrder.data.created_at,
        customer_phone: confirmedOrder.data.customer_phone_snapshot,
        address: confirmedOrder.data.customer_address_snapshot,
        location: publicLocation(confirmedOrder.data.locations),
        totals: quote.data.quote.totals,
        promotion: quote.data.quote.promotion
      },
      items: orderItems.data,
      payment: createDemoPaymentPayload({
        order: confirmedOrder.data,
        payment: payment.data
      }),
      nextScreen: 'order_confirmed'
    });
  }

  let updatedPayment;
  let paymentPayload;

  if (isStripeProvider) {
    let stripeSession;

    try {
      const existingCustomerId = await findExistingStripeCustomerId(ensured.customer.id);
      const customerId = await resolveStripeCustomerId({
        customer: ensured.customer,
        existingCustomerId
      });

      const intent = await createStripePaymentIntent({
        order: orderInsert.data,
        payment: payment.data,
        customer: ensured.customer,
        customerId,
        saveCard: Boolean(parsed.data.save_card)
      });

      const ephemeralKey = await createStripeEphemeralKey(customerId);

      stripeSession = {
        payment_intent_id: intent.payment_intent_id,
        client_secret: intent.client_secret,
        customer_id: customerId,
        ephemeral_key_secret: ephemeralKey.secret,
        raw_response: intent.raw_response
      };
    } catch (err) {
      await supabase.from('orders').delete().eq('id', orderInsert.data.id);

      return res.status(502).json({
        error: err.message || 'Could not create Stripe payment session.'
      });
    }

    updatedPayment = await supabase
      .from('payments')
      .update({
        provider_payment_id: stripeSession.payment_intent_id,
        raw_payload: {
          ...(payment.data.raw_payload || {}),
          stripe_payment_intent_id: stripeSession.payment_intent_id,
          stripe_client_secret: stripeSession.client_secret,
          stripe_customer_id: stripeSession.customer_id,
          stripe_ephemeral_key_secret: stripeSession.ephemeral_key_secret
        }
      })
      .eq('id', payment.data.id)
      .select()
      .single();

    if (updatedPayment.error) {
      await supabase.from('orders').delete().eq('id', orderInsert.data.id);

      return res.status(400).json({
        error: updatedPayment.error.message
      });
    }

    paymentPayload = createCheckoutPaymentPayload({
      order: orderInsert.data,
      payment: updatedPayment.data,
      stripeSession
    });
  } else {
    let geideaSession;

    try {
      geideaSession = await createGeideaSession({
        order: orderInsert.data,
        payment: payment.data,
        customer: ensured.customer,
        paymentMethod: parsed.data.payment_method,
        saveCard: Boolean(parsed.data.save_card)
      });
    } catch (err) {
      await supabase.from('orders').delete().eq('id', orderInsert.data.id);

      return res.status(502).json({
        error: err.message || 'Could not create Geidea payment session.'
      });
    }

    updatedPayment = await supabase
      .from('payments')
      .update({
        raw_payload: {
          ...(payment.data.raw_payload || {}),
          geidea_session_id: geideaSession.session_id,
          geidea_create_session_request: geideaSession.request_payload,
          geidea_create_session_response: geideaSession.raw_response
        }
      })
      .eq('id', payment.data.id)
      .select()
      .single();

    if (updatedPayment.error) {
      await supabase.from('orders').delete().eq('id', orderInsert.data.id);

      return res.status(400).json({
        error: updatedPayment.error.message
      });
    }

    paymentPayload = createCheckoutPaymentPayload({
      order: orderInsert.data,
      payment: updatedPayment.data,
      sessionId: geideaSession.session_id,
      paymentMethod: parsed.data.payment_method
    });
  }

  await supabase
    .from('cart_items')
    .delete()
    .eq('cart_id', parsed.data.cart_id);

  await supabase
    .from('carts')
    .update({ status: 'converted' })
    .eq('id', parsed.data.cart_id);

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    order: {
      id: orderInsert.data.id,
      order_number: orderInsert.data.order_number,
      status: orderInsert.data.status,
      payment_status: orderInsert.data.payment_status,
      fulfillment_type: orderInsert.data.fulfillment_type,
      requested_fulfillment_at: orderInsert.data.requested_fulfillment_at,
      created_at: orderInsert.data.created_at,
      customer_phone: orderInsert.data.customer_phone_snapshot,
      address: orderInsert.data.customer_address_snapshot,
      location: publicLocation(orderInsert.data.locations),
      totals: quote.data.quote.totals,
      promotion: quote.data.quote.promotion
    },
    items: orderItems.data,
    payment: paymentPayload,
    nextScreen: gatewayNextScreen(LIVE_PAYMENT_PROVIDER)
  });
}

customerRouter.post('/customer/checkout/place-order', handleCustomerPlaceOrder);
customerRouter.post('/customer/orders', handleCustomerPlaceOrder);

customerRouter.post('/customer/orders/:orderId/payment-result', async (req, res) => {
  const parsed = z.object({
    status: z.enum(['success', 'failure', 'canceled']),
    order_id: z.string().nullable().optional(),
    token_id: z.string().nullable().optional(),
    agreement_id: z.string().nullable().optional(),
    payment_method: z.any().nullable().optional(),
    error: z.object({
      code: z.string().optional(),
      message: z.string().optional(),
      details: z.string().nullable().optional()
    }).nullable().optional(),
    raw_result: z.any().nullable().optional()
  }).safeParse(req.body);

  if (!parsed.success) {
    return res.status(400).json({
      error: 'Invalid Geidea SDK payment result.'
    });
  }

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const order = await supabase
    .from('orders')
    .select('id,order_number,status,payment_status,total_amount,customer_id,updated_at')
    .eq('id', req.params.orderId)
    .eq('customer_id', ensured.customer.id)
    .maybeSingle();

  if (order.error) {
    return res.status(400).json({
      error: order.error.message
    });
  }

  if (!order.data) {
    return res.status(404).json({
      error: 'Order not found.'
    });
  }

  const payment = await supabase
    .from('payments')
    .select('*')
    .eq('order_id', order.data.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (payment.error) {
    return res.status(400).json({
      error: payment.error.message
    });
  }

  if (!payment.data) {
    return res.status(404).json({
      error: 'Payment not found.'
    });
  }

  const providerEventId = crypto
    .createHash('sha256')
    .update(JSON.stringify({
      type: 'flutter_sdk_result',
      payment_id: payment.data.id,
      order_id: order.data.id,
      payload: parsed.data
    }))
    .digest('hex');

  await supabase
    .from('payment_events')
    .upsert({
      provider: 'geidea',
      provider_event_id: providerEventId,
      event_type: 'flutter_sdk_result',
      raw_payload: {
        order_id: order.data.id,
        payment_id: payment.data.id,
        sdk_result: parsed.data
      },
      processed_at: new Date().toISOString()
    }, {
      onConflict: 'provider_event_id',
      ignoreDuplicates: true
    });

  const updatedPayment = await supabase
    .from('payments')
    .update({
      provider_payment_id: parsed.data.order_id || payment.data.provider_payment_id,
      raw_payload: {
        ...(payment.data.raw_payload || {}),
        geidea_flutter_sdk_result: parsed.data
      }
    })
    .eq('id', payment.data.id)
    .select()
    .single();

  if (updatedPayment.error) {
    return res.status(400).json({
      error: updatedPayment.error.message
    });
  }

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    ok: true,
    trusted_payment_confirmation: 'callback',
    message: parsed.data.status === 'success'
      ? 'SDK reported success. The order will be marked paid only after the verified Geidea callback is processed.'
      : 'SDK result was recorded.',
    order_status: order.data.status,
    payment_status: order.data.payment_status,
    payment: createCheckoutPaymentPayload({
      order: order.data,
      payment: updatedPayment.data
    })
  });
});

async function beginPaymentEvent({ provider, providerEventId, eventType, rawPayload }) {
  const inserted = await supabase
    .from('payment_events')
    .insert({
      provider,
      provider_event_id: providerEventId,
      event_type: eventType,
      raw_payload: rawPayload
    })
    .select('id,processed_at')
    .maybeSingle();

  if (!inserted.error) {
    return { event: inserted.data, duplicate: false, resumed: false };
  }

  if (String(inserted.error.code) !== '23505') {
    return { error: inserted.error };
  }

  const existing = await supabase
    .from('payment_events')
    .select('id,processed_at')
    .eq('provider', provider)
    .eq('provider_event_id', providerEventId)
    .maybeSingle();

  if (existing.error) return { error: existing.error };
  if (!existing.data) {
    return { error: new Error('The existing payment event could not be loaded for retry.') };
  }

  return {
    event: existing.data,
    duplicate: Boolean(existing.data.processed_at),
    resumed: !existing.data.processed_at
  };
}

async function markPaymentEventProcessed({ provider, providerEventId }) {
  return supabase
    .from('payment_events')
    .update({ processed_at: new Date().toISOString() })
    .eq('provider', provider)
    .eq('provider_event_id', providerEventId);
}

async function updateProviderPayment({ payment, patch, isSuccess }) {
  let query = supabase
    .from('payments')
    .update({
      ...patch,
      status: isSuccess ? 'paid' : 'failed'
    })
    .eq('id', payment.id);

  if (!isSuccess) query = query.neq('status', 'paid');

  const updated = await query.select().maybeSingle();
  if (updated.error) return { error: updated.error };
  if (updated.data) return { data: updated.data };

  const current = await supabase
    .from('payments')
    .select('*')
    .eq('id', payment.id)
    .single();

  return current.error ? { error: current.error } : { data: current.data };
}

async function updateOrderForPaymentResult({ orderId, isSuccess }) {
  if (isSuccess) {
    const confirmed = await supabase
      .from('orders')
      .update({
        status: 'confirmed',
        payment_status: 'paid'
      })
      .eq('id', orderId)
      .eq('status', 'pending_payment')
      .select()
      .maybeSingle();

    if (confirmed.error) return { error: confirmed.error };
    if (confirmed.data) return { data: confirmed.data };

    const paid = await supabase
      .from('orders')
      .update({ payment_status: 'paid' })
      .eq('id', orderId)
      .select()
      .single();

    return paid.error ? { error: paid.error } : { data: paid.data };
  }

  const failed = await supabase
    .from('orders')
    .update({ payment_status: 'failed' })
    .eq('id', orderId)
    .neq('payment_status', 'paid')
    .select()
    .maybeSingle();

  if (failed.error) return { error: failed.error };
  if (failed.data) return { data: failed.data };

  const current = await supabase
    .from('orders')
    .select('*')
    .eq('id', orderId)
    .single();

  return current.error ? { error: current.error } : { data: current.data };
}

customerRouter.post('/payments/geidea/callback', async (req, res) => {
  const payload = req.body || {};
  const providerEventId = crypto
    .createHash('sha256')
    .update(JSON.stringify(payload))
    .digest('hex');

  const eventClaim = await beginPaymentEvent({
    provider: 'geidea',
    providerEventId,
    eventType: 'callback',
    rawPayload: payload
  });
  if (eventClaim.error) {
    return res.status(500).json({ ok: false, error: eventClaim.error.message });
  }
  if (eventClaim.duplicate) {
    return res.json({ ok: true, duplicate: true });
  }

  const verification = verifyGeideaCallbackSignature(payload);
  const fields = verification.fields || extractGeideaCallbackFields(payload);

  if (!verification.ok) {
    return res.status(400).json({
      ok: false,
      error: verification.reason
    });
  }

  if (!fields.merchant_reference_id) {
    return res.status(400).json({
      ok: false,
      error: 'Geidea callback is missing merchantReferenceId.'
    });
  }

  const payment = await supabase
    .from('payments')
    .select('*, orders(*)')
    .eq('id', fields.merchant_reference_id)
    .maybeSingle();

  if (payment.error) return res.status(400).json({
    ok: false,
    error: payment.error.message
  });

  if (!payment.data?.orders) return res.status(404).json({
    ok: false,
    error: 'Payment was not found for this Geidea callback.'
  });

  const expectedAmount = formatGeideaAmount(payment.data.amount);
  const receivedAmount = formatGeideaAmount(fields.amount);

  if (expectedAmount !== receivedAmount || String(fields.currency || '').toUpperCase() !== String(payment.data.currency || CURRENCY).toUpperCase()) {
    return res.status(400).json({
      ok: false,
      error: 'Geidea callback amount or currency does not match the payment record.'
    });
  }

  const isSuccess = geideaCallbackIsSuccess(fields);
  const updatedPayment = await updateProviderPayment({
    payment: payment.data,
    isSuccess,
    patch: {
      provider_payment_id: fields.order_id || payment.data.provider_payment_id,
      raw_payload: {
        ...(payment.data.raw_payload || {}),
        geidea_callback: payload,
        geidea_callback_fields: fields
      }
    }
  });

  if (updatedPayment.error) return res.status(400).json({
    ok: false,
    error: updatedPayment.error.message
  });

  const updatedOrder = await updateOrderForPaymentResult({
    orderId: payment.data.order_id,
    isSuccess
  });

  if (updatedOrder.error) return res.status(400).json({
    ok: false,
    error: updatedOrder.error.message
  });

  if (isSuccess) {
    await recordPromotionRedemptionIfNeeded({
      order: updatedOrder.data,
      payment: updatedPayment.data
    });
  
    if (payment.data.raw_payload?.save_card) {
      const savedCard = await recordGeideaSavedCardIfNeeded({
        customerId: payment.data.orders.customer_id,
        payload
      });
  
      if (savedCard) {
        await supabase
          .from('payments')
          .update({
            raw_payload: {
              ...(updatedPayment.data.raw_payload || {}),
              saved_payment_method_id: savedCard.id
            }
          })
          .eq('id', updatedPayment.data.id);
      }
    }
  }
  const markedProcessed = await markPaymentEventProcessed({
    provider: 'geidea',
    providerEventId
  });
  if (markedProcessed.error) {
    return res.status(500).json({ ok: false, error: markedProcessed.error.message });
  }

  res.json({
    ok: true,
    payment_status: updatedPayment.data.status,
    order_status: updatedOrder.data.status
  });
});

customerRouter.post('/payments/stripe/webhook', async (req, res) => {
  const verification = constructStripeEvent(req.body, req.headers['stripe-signature']);

  if (!verification.ok) {
    return res.status(400).json({ ok: false, error: verification.reason });
  }

  const event = verification.event;
  const eventId = event?.id;

  // Only PaymentIntent lifecycle events touch order state; acknowledge the rest
  // with 200 so Stripe stops retrying them.
  const handledTypes = new Set(['payment_intent.succeeded', 'payment_intent.payment_failed']);

  if (!eventId || !handledTypes.has(event.type)) {
    return res.json({ ok: true, ignored: true });
  }

  const eventClaim = await beginPaymentEvent({
    provider: STRIPE_PAYMENT_PROVIDER,
    providerEventId: eventId,
    eventType: event.type,
    rawPayload: event
  });
  if (eventClaim.error) {
    return res.status(500).json({ ok: false, error: eventClaim.error.message });
  }
  if (eventClaim.duplicate) {
    return res.json({ ok: true, duplicate: true });
  }

  const paymentIntent = event.data?.object || {};
  const ebtlPaymentId = paymentIntent.metadata?.ebtl_payment_id;

  if (!ebtlPaymentId) {
    const markedProcessed = await markPaymentEventProcessed({
      provider: STRIPE_PAYMENT_PROVIDER,
      providerEventId: eventId
    });
    if (markedProcessed.error) {
      return res.status(500).json({ ok: false, error: markedProcessed.error.message });
    }
    return res.json({ ok: true, ignored: 'missing ebtl_payment_id' });
  }

  const payment = await supabase
    .from('payments')
    .select('*, orders(*)')
    .eq('id', ebtlPaymentId)
    .maybeSingle();

  if (payment.error) return res.status(400).json({ ok: false, error: payment.error.message });

  if (!payment.data?.orders) {
    return res.status(404).json({ ok: false, error: 'Payment was not found for this Stripe event.' });
  }

  // Guard against amount/currency tampering: the PaymentIntent must match the
  // stored payment record.
  const received = extractStripeAmount(paymentIntent);
  const expectedAmount = stripeMinorUnits(payment.data.amount, payment.data.currency);

  if (received.amount !== expectedAmount
    || received.currency !== String(payment.data.currency || CURRENCY).toLowerCase()) {
    return res.status(400).json({
      ok: false,
      error: 'Stripe event amount or currency does not match the payment record.'
    });
  }

  const isSuccess = event.type === 'payment_intent.succeeded';
  const updatedPayment = await updateProviderPayment({
    payment: payment.data,
    isSuccess,
    patch: {
      provider_payment_id: paymentIntent.id || payment.data.provider_payment_id,
      raw_payload: {
        ...(payment.data.raw_payload || {}),
        stripe_event_type: event.type,
        stripe_payment_intent: paymentIntent
      }
    }
  });

  if (updatedPayment.error) return res.status(400).json({ ok: false, error: updatedPayment.error.message });

  const updatedOrder = await updateOrderForPaymentResult({
    orderId: payment.data.order_id,
    isSuccess
  });

  if (updatedOrder.error) return res.status(400).json({ ok: false, error: updatedOrder.error.message });

  if (isSuccess) {
    await recordPromotionRedemptionIfNeeded({
      order: updatedOrder.data,
      payment: updatedPayment.data
    });

    if (payment.data.raw_payload?.save_card) {
      const savedCard = await recordStripeSavedCardIfNeeded({
        customerId: payment.data.orders.customer_id,
        paymentIntent
      });

      if (savedCard) {
        await supabase
          .from('payments')
          .update({
            raw_payload: {
              ...(updatedPayment.data.raw_payload || {}),
              saved_payment_method_id: savedCard.id
            }
          })
          .eq('id', updatedPayment.data.id);
      }
    }
  }

  const markedProcessed = await markPaymentEventProcessed({
    provider: STRIPE_PAYMENT_PROVIDER,
    providerEventId: eventId
  });
  if (markedProcessed.error) {
    return res.status(500).json({ ok: false, error: markedProcessed.error.message });
  }

  res.json({
    ok: true,
    payment_status: updatedPayment.data.status,
    order_status: updatedOrder.data.status
  });
});

customerRouter.get('/customer/orders/:orderId', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const order = await supabase
    .from('orders')
    .select('*, locations(id,name,type,compound_name,beach_name,banner_image_url,delivery_fee), customer_addresses(*)')
    .eq('id', req.params.orderId)
    .eq('customer_id', ensured.customer.id)
    .maybeSingle();

  if (order.error) return res.status(400).json({
    error: order.error.message
  });

  if (!order.data) return res.status(404).json({
    error: 'Order not found.'
  });

  const items = await supabase
    .from('order_items')
    .select('*')
    .eq('order_id', order.data.id)
    .order('created_at');

  if (items.error) return res.status(400).json({
    error: items.error.message
  });

  const payment = await supabase
    .from('payments')
    .select('id,provider,provider_payment_id,amount,currency,status,raw_payload,created_at,updated_at')
    .eq('order_id', order.data.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (payment.error) return res.status(400).json({
    error: payment.error.message
  });

  const statusOrder = [
    'pending_payment',
    'confirmed',
    'preparing',
    'ready',
    'out_for_delivery',
    'completed'
  ];

  const currentStatusIndex = statusOrder.indexOf(order.data.status);

  const statusTimestamps = {
    pending_payment: order.data.created_at,
    confirmed: order.data.confirmed_at,
    preparing: order.data.preparing_at,
    ready: order.data.ready_at,
    completed: order.data.completed_at
  };

  const timeline = statusOrder.map((status, index) => ({
    status,
    label: status.split('_').map((word) => word[0].toUpperCase() + word.slice(1)).join(' '),
    completed: currentStatusIndex >= index,
    timestamp: statusTimestamps[status]
      || (status === order.data.status ? order.data.updated_at : null)
  }));

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    order: {
      id: order.data.id,
      order_number: order.data.order_number,
      status: order.data.status,
      payment_status: order.data.payment_status,
      fulfillment_type: order.data.fulfillment_type,
      requested_fulfillment_at: order.data.requested_fulfillment_at,
      created_at: order.data.created_at,
      confirmed_at: order.data.confirmed_at || null,
      preparing_at: order.data.preparing_at || null,
      ready_at: order.data.ready_at || null,
      completed_at: order.data.completed_at || null,
      customer_phone: order.data.customer_phone_snapshot || null,
      address_text: order.data.customer_address_snapshot || null,
      statusTimeline: timeline,
      location: publicLocation(order.data.locations),
      address: order.data.customer_addresses,
      customer_notes: order.data.customer_notes,
      totals: {
        subtotal_ex_vat: money(order.data.subtotal_ex_vat),
        vat_amount: money(order.data.vat_amount),
        discount_amount: money(order.data.discount_amount),
        delivery_fee: money(order.data.delivery_fee),
        total_amount: money(order.data.total_amount),
        currency: CURRENCY
      }
    },
    items: items.data || [],
    payment: payment.data ? createCheckoutPaymentPayload({
      order: order.data,
      payment: payment.data
    }) : null,
    support: {
      whatsapp_number: process.env.CUSTOMER_SUPPORT_WHATSAPP || null,
      message_template: `Hi EBTL, I need help with order ${order.data.order_number}.`
    }
  });
});

customerRouter.get('/customer/orders/:orderId/status', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const order = await supabase
    .from('orders')
    .select('id,order_number,status,payment_status,updated_at')
    .eq('id', req.params.orderId)
    .eq('customer_id', ensured.customer.id)
    .maybeSingle();

  if (order.error) return res.status(400).json({
    error: order.error.message
  });

  if (!order.data) return res.status(404).json({
    error: 'Order not found.'
  });

  const items = await supabase
    .from('order_items')
    .select('id,prep_status')
    .eq('order_id', order.data.id);

  if (items.error) return res.status(400).json({
    error: items.error.message
  });

  res.json({
    order_id: order.data.id,
    order_number: order.data.order_number,
    status: order.data.status,
    payment_status: order.data.payment_status,
    item_statuses: (items.data || []).map((item) => ({
      order_item_id: item.id,
      prep_status: item.prep_status
    })),
    updated_at: order.data.updated_at
  });
});


customerRouter.get('/customer/orders/:orderId/payment-status', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const order = await supabase
    .from('orders')
    .select('id,order_number,status,payment_status,total_amount,customer_id,updated_at')
    .eq('id', req.params.orderId)
    .eq('customer_id', ensured.customer.id)
    .maybeSingle();

  if (order.error) return res.status(400).json({
    error: order.error.message
  });

  if (!order.data) return res.status(404).json({
    error: 'Order not found.'
  });

  const payment = await supabase
    .from('payments')
    .select('id,provider,provider_payment_id,amount,currency,status,raw_payload,created_at,updated_at')
    .eq('order_id', order.data.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (payment.error) return res.status(400).json({
    error: payment.error.message
  });

  res.json({
    order_id: order.data.id,
    order_number: order.data.order_number,
    order_status: order.data.status,
    payment_status: order.data.payment_status,
    updated_at: order.data.updated_at,
    payment: payment.data ? createCheckoutPaymentPayload({
      order: order.data,
      payment: payment.data
    }) : null
  });
});

customerRouter.get('/customer/me', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    customer: {
      id: ensured.customer.id,
      full_name: ensured.customer.full_name,
      phone: ensured.customer.phone,
      email: ensured.customer.email,
      birthday: ensured.customer.birthday,
      marketing_opt_in: ensured.customer.marketing_opt_in
    }
  });
});

customerRouter.patch('/customer/me', handleCustomerProfileUpdate);

customerRouter.get('/customer/payment-methods', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const paymentMethods = await supabase
    .from('customer_payment_methods')
    .select('id,provider,card_brand,cardholder_name,masked_card_number,expiry_month,expiry_year,is_default,is_active,last_used_at,created_at,updated_at')
    .eq('customer_id', ensured.customer.id)
    .eq('is_active', true)
    .order('is_default', { ascending: false })
    .order('created_at', { ascending: false });

  if (paymentMethods.error) {
    return res.status(400).json({
      error: paymentMethods.error.message
    });
  }

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    payment_methods: paymentMethods.data || []
  });
});

customerRouter.get('/customer/addresses', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const data = await supabase
    .from('customer_addresses')
    .select('*')
    .eq('customer_id', ensured.customer.id)
    .order('is_default', {
      ascending: false
    })
    .order('created_at');

  if (data.error) return res.status(400).json({
    error: data.error.message
  });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    addresses: data.data || []
  });
});

customerRouter.post('/customer/addresses', async (req, res) => {
  const parsed = z.object({
    label: z.string().nullable().optional(),
    compound_name: z.string().nullable().optional(),
    beach_name: z.string().nullable().optional(),
    unit_number: z.string().nullable().optional(),
    building: z.string().nullable().optional(),
    floor: z.string().nullable().optional(),
    delivery_notes: z.string().nullable().optional(),
    latitude: z.coerce.number().nullable().optional(),
    longitude: z.coerce.number().nullable().optional(),
    is_default: z.boolean().optional()
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid address.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  if (parsed.data.is_default) {
    await supabase
      .from('customer_addresses')
      .update({
        is_default: false
      })
      .eq('customer_id', ensured.customer.id);
  }

  const data = await supabase
    .from('customer_addresses')
    .insert({
      ...clean(parsed.data),
      customer_id: ensured.customer.id
    })
    .select()
    .single();

  if (data.error) return res.status(400).json({
    error: data.error.message
  });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    address: data.data
  });
});

customerRouter.patch('/customer/addresses/:id', async (req, res) => {
  const parsed = z.object({
    label: z.string().nullable().optional(),
    compound_name: z.string().nullable().optional(),
    beach_name: z.string().nullable().optional(),
    unit_number: z.string().nullable().optional(),
    building: z.string().nullable().optional(),
    floor: z.string().nullable().optional(),
    delivery_notes: z.string().nullable().optional(),
    latitude: z.coerce.number().nullable().optional(),
    longitude: z.coerce.number().nullable().optional(),
    is_default: z.boolean().optional()
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid address update.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  if (parsed.data.is_default) {
    await supabase
      .from('customer_addresses')
      .update({
        is_default: false
      })
      .eq('customer_id', ensured.customer.id);
  }

  const data = await supabase
    .from('customer_addresses')
    .update(clean(parsed.data))
    .eq('id', req.params.id)
    .eq('customer_id', ensured.customer.id)
    .select()
    .single();

  if (data.error) return res.status(400).json({
    error: data.error.message
  });

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    address: data.data
  });
});

customerRouter.delete('/customer/addresses/:id', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const data = await supabase
    .from('customer_addresses')
    .delete()
    .eq('id', req.params.id)
    .eq('customer_id', ensured.customer.id)
    .select()
    .single();

  if (data.error) return res.status(400).json({
    error: data.error.message
  });

  res.json({
    deleted_address_id: data.data.id
  });
});

customerRouter.post('/customer/events', async (req, res) => {
  const parsed = z.object({
    event_type: z.string().min(1),
    session_id: z.string().nullable().optional(),
    metadata: z.record(z.any()).optional()
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid app event.'
  });

  const customer = await findCustomerFromRequest(req);

  const inserted = await supabase
    .from('app_events')
    .insert({
      customer_id: customer?.id || null,
      session_id: parsed.data.session_id || null,
      event_type: parsed.data.event_type,
      metadata: parsed.data.metadata || {}
    })
    .select('id,created_at')
    .single();

  if (inserted.error) return res.status(400).json({
    error: inserted.error.message
  });

  res.json({
    event: inserted.data
  });
});
