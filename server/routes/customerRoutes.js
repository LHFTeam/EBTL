import crypto from 'crypto';
import { Router } from 'express';
import { z } from 'zod';
import { isProd, SESSION_SECRET } from '../config/appConfig.js';
import { clean } from '../lib/objectUtils.js';
import { getCookie } from '../lib/session.js';
import { supabase } from '../lib/supabase.js';

export const customerRouter = Router();

const CUSTOMER_COOKIE = 'ebtl_customer';
const CUSTOMER_TOKEN_MAX_AGE_SECONDS = 365 * 24 * 60 * 60;
const BUSINESS_TIME_ZONE = 'Africa/Cairo';
const CURRENCY = 'EGP';
const PAYMENT_PROVIDER = process.env.PAYMENT_PROVIDER || 'payment_gateway';
const PAYMENT_GATEWAY_CHECKOUT_URL = process.env.PAYMENT_GATEWAY_CHECKOUT_URL || '';
const DEFAULT_DELIVERY_FEE = Number(process.env.CUSTOMER_APP_DELIVERY_FEE || 0);
const MAX_CART_ITEM_QTY = 99;

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
    is_active: location.is_active
  };
}

function publicCategory(category) {
  if (!category) return null;

  return {
    id: category.id,
    name: category.name,
    sort_order: category.sort_order
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
  return rows.map((row) => ({
    liquor_type_id: row.liquor_type_id,
    liquor_type_name: row.liquor_types?.name || null,
    liquor_type_image_url: row.liquor_types?.image_url || null,
    required_ml_per_serving: row.required_ml_per_serving,    
    display_instruction: row.display_instruction
  }));
}

function productCardPayload({
  product,
  category,
  variants,
  compatibility,
  recipe,
  recipeItems,
  balancesByIngredientId,
  locationId
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
    description: product.description,
    image_url: product.image_url,
    tags: product.tags || [],
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
    .select('*, products(id,slug,name,image_url,status), product_variants(id,name,serving_count,is_active,vat_rate,price_inc_vat)')
    .eq('cart_id', cartId)
    .order('created_at');
}

function cartTotals(items = []) {
  const subtotalIncVat = money(items.reduce((sum, item) => {
    return sum + Number(item.unit_price_inc_vat_snapshot || 0) * Number(item.quantity || 0);
  }, 0));

  const estimatedVatAmount = money(items.reduce((sum, item) => {
    const vatRate = Number(item.vat_rate_snapshot ?? item.product_variants?.vat_rate ?? 0);
    const lineIncVat = Number(item.unit_price_inc_vat_snapshot || 0) * Number(item.quantity || 0);
    const lineExVat = vatRate > 0 ? lineIncVat / (1 + vatRate) : lineIncVat;

    return sum + (lineIncVat - lineExVat);
  }, 0));

  return {
    subtotal_inc_vat: subtotalIncVat,
    estimated_vat_amount: estimatedVatAmount,
    discount_amount: 0,
    delivery_fee: 0,
    total_amount: subtotalIncVat,
    currency: CURRENCY
  };
}

async function cartSummary(cartId) {
  if (!cartId) {
    return {
      cart_id: null,
      item_count: 0,
      total_quantity: 0,
      subtotal_inc_vat: 0,
      currency: CURRENCY
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
    subtotal_inc_vat: money(subtotal),
    currency: CURRENCY
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

async function loadCatalog({
  locationId = null,
  onlyFeatured = false,
  categoryId = null,
  productIds = [],
  q = '',
  liquorTypeIds = [],
  tags = []
} = {}) {
  let productQuery = supabase
    .from('products')
    .select('*, product_categories(id,name,sort_order)')
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
  
  const products = await productQuery;
  if (products.error) return {
    error: products.error
  };

  let productRows = products.data || [];
  const search = normalizeString(q);

  if (search) {
    productRows = productRows.filter((product) => {
      const haystack = [product.name, product.description, ...(product.tags || [])]
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
          balances: []
        }
      }
    };
  }

  const [variants, compatibility, recipes] = await Promise.all([
    supabase
      .from('product_variants')
      .select('*')
      .in('product_id', catalogProductIds)
      .eq('is_active', true)
      .order('price_inc_vat'),

    supabase
      .from('product_liquor_compatibility')
      .select('*, liquor_types(id,name,image_url,display_order)')
      .in('product_id', catalogProductIds),

    supabase
      .from('recipes')
      .select('*')
      .in('product_id', catalogProductIds)
      .eq('status', 'active')
      .order('version', {
        ascending: false
      })
  ]);  
  
  for (const result of [variants, compatibility, recipes]) {
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
        .select('*, ingredients(id,name,base_unit,is_customer_supplied)')
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
      locationId
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
        balances: balances.data || []
      }
    }
  };
}

async function loadProductDetail(slug, locationId) {
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

  const catalog = await loadCatalog({
    locationId
  });

  if (catalog.error) return {
    error: catalog.error
  };

  const card = catalog.data.cards.find((entry) => entry.id === product.data.id);
  if (!card) return {
    notFound: true
  };

  return {
    data: {
      product: product.data,
      card
    }
  };
}

async function buildCartResponse(customerId, {
  createIfMissing = true,
  locationId = null
} = {}) {
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
        items: [],
        totals: cartTotals([]),
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

  const productIds = [...new Set((items.data || []).map((item) => item.product_id))];
  const catalog = productIds.length
    ? await loadCatalog({
        locationId
      })
    : {
        data: {
          cards: []
        }
      };

  if (catalog.error) return {
    error: catalog.error
  };

  const cardByProductId = new Map((catalog.data.cards || []).map((card) => [card.id, card]));

  const responseItems = (items.data || []).map((item) => {
    const card = cardByProductId.get(item.product_id);
    const variantAvailability = card?.variants?.find((variant) => variant.id === item.variant_id)?.availability;
    const lineTotal = money(Number(item.unit_price_inc_vat_snapshot || 0) * Number(item.quantity || 0));

    return {
      id: item.id,
      product_id: item.product_id,
      variant_id: item.variant_id,
      quantity: item.quantity,
      product: {
        slug: item.products?.slug,
        name: item.products?.name,
        image_url: item.products?.image_url,
        status: item.products?.status
      },
      variant: {
        name: item.product_variants?.name,
        serving_count: item.product_variants?.serving_count,
        is_active: item.product_variants?.is_active
      },
      pricing: {
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

  const totals = cartTotals(items.data || []);
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
        updated_at: cart.data.updated_at
      },
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

async function buildCheckoutQuote({
  customerId,
  cartId,
  locationId,
  fulfillmentType,
  customerAddressId = null,
  customerNotes = null
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

  if (fulfillmentType === 'delivery_to_unit' && !customerAddressId) {
    return {
      badRequest: 'Delivery orders require a customer address.'
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

  const productIds = [...new Set(cartItems.data.map((item) => item.product_id))];

  const productCatalog = await loadCatalog({
    locationId,
    productIds
  });
  
  if (productCatalog.error) return {
    error: productCatalog.error
  };

  const raw = productCatalog.data.raw || {};
  const productById = new Map((raw.products || []).map((product) => [product.id, product]));
  const variantById = new Map((raw.variants || []).map((variant) => [variant.id, variant]));

  const recipesByProductId = new Map();

  for (const productId of productIds) {
    recipesByProductId.set(
      productId,
      pickCurrentRecipe((raw.recipes || []).filter((recipe) => recipe.product_id === productId))
    );
  }

  const recipeItemsByRecipeId = new Map();

  for (const item of raw.recipeItems || []) {
    if (!recipeItemsByRecipeId.has(item.recipe_id)) {
      recipeItemsByRecipeId.set(item.recipe_id, []);
    }

    recipeItemsByRecipeId.get(item.recipe_id).push(item);
  }

  const balancesByIngredientId = new Map(
    (raw.balances || []).map((balance) => [balance.ingredient_id, balance])
  );

  const blockingReasons = [];

  const quoteItems = cartItems.data.map((item) => {
    const product = productById.get(item.product_id);
    const variant = variantById.get(item.variant_id);
    const recipe = recipesByProductId.get(item.product_id);
    const recipeItems = recipeItemsByRecipeId.get(recipe?.id) || [];

    const availability = buildAvailability({
      locationId,
      recipe,
      recipeItems,
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
    const lineTotalIncVat = money(Number(item.unit_price_inc_vat_snapshot || 0) * Number(item.quantity || 0));
    const lineSubtotalExVat = vatRate > 0 ? money(lineTotalIncVat / (1 + vatRate)) : lineTotalIncVat;
    const lineVatAmount = money(lineTotalIncVat - lineSubtotalExVat);

    return {
      cart_item_id: item.id,
      product_id: item.product_id,
      variant_id: item.variant_id,
      recipe_id: recipe?.id || null,
      product_name: product?.name || item.products?.name,
      variant_name: variant?.name || item.product_variants?.name,
      quantity: item.quantity,
      serving_count: variant?.serving_count || item.product_variants?.serving_count,
      unit_price_inc_vat: money(item.unit_price_inc_vat_snapshot),
      vat_rate: vatRate,
      line_subtotal_ex_vat: lineSubtotalExVat,
      line_vat_amount: lineVatAmount,
      line_total: lineTotalIncVat,
      is_available: availability.is_orderable,
      blocking_reason: availability.reason
    };
  });

  const subtotalExVat = money(quoteItems.reduce((sum, item) => sum + item.line_subtotal_ex_vat, 0));
  const vatAmount = money(quoteItems.reduce((sum, item) => sum + item.line_vat_amount, 0));
  const discountAmount = 0;
  const deliveryFee = fulfillmentType === 'delivery_to_unit' ? money(DEFAULT_DELIVERY_FEE) : 0;
  const totalAmount = money(subtotalExVat + vatAmount - discountAmount + deliveryFee);

  return {
    data: {
      quote: {
        cart_id: cartId,
        location_id: locationId,
        fulfillment_type: fulfillmentType,
        customer_address_id: customerAddressId,
        customer_notes: customerNotes,
        items: quoteItems,
        totals: {
          subtotal_ex_vat: subtotalExVat,
          vat_amount: vatAmount,
          discount_amount: discountAmount,
          delivery_fee: deliveryFee,
          total_amount: totalAmount,
          currency: CURRENCY
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

function createPaymentGatewayPayload({
  order,
  payment
}) {
  if (!PAYMENT_GATEWAY_CHECKOUT_URL) {
    return {
      required: true,
      provider: PAYMENT_PROVIDER,
      payment_id: payment.id,
      payment_url: null,
      status: payment.status,
      gateway_configured: false,
      message: 'Payment gateway checkout URL is not configured yet.'
    };
  }

  const url = new URL(PAYMENT_GATEWAY_CHECKOUT_URL);

  url.searchParams.set('order_id', order.id);
  url.searchParams.set('order_number', order.order_number || '');
  url.searchParams.set('payment_id', payment.id);
  url.searchParams.set('amount', String(order.total_amount));
  url.searchParams.set('currency', CURRENCY);

  return {
    required: true,
    provider: PAYMENT_PROVIDER,
    payment_id: payment.id,
    payment_url: url.toString(),
    status: payment.status,
    gateway_configured: true
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

  if (customer) {
    const cart = await getActiveCart(customer.id, {
      createIfMissing: false
    });

    if (cart.error) return res.status(400).json({
      error: cart.error.message
    });

    summary = await cartSummary(cart.data?.id || null);
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
    featuredCocktails: catalog.data.cards,
    categories: (categories.data || []).map(publicCategory),
    liquorTypes: (liquorTypes.data || []).map(publicLiquorType),
    cartSummary: summary
  });
});

customerRouter.get('/customer/cocktail-finder/options', async (_req, res) => {
  const [liquorTypes, categories, products] = await Promise.all([
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
      .from('products')
      .select('tags')
      .eq('status', 'active')
  ]);

  for (const result of [liquorTypes, categories, products]) {
    if (result.error) return res.status(400).json({
      error: result.error.message
    });
  }

  const tags = [...new Set((products.data || []).flatMap((product) => product.tags || []))].sort();

  res.json({
    liquorTypes: (liquorTypes.data || []).map(publicLiquorType),
    categories: (categories.data || []).map(publicCategory),
    tags,
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
    tags: parsed.data.tags || []
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

  const total = results.length;
  results = results.slice((page - 1) * pageSize, page * pageSize);

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
    location_id: optionalUuid
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid cocktail detail request.'
  });

  const detail = await loadProductDetail(req.params.slug, parsed.data.location_id || null);

  if (detail.error) return res.status(400).json({
    error: detail.error.message
  });

  if (detail.notFound) return res.status(404).json({
    error: 'Cocktail not found.'
  });

  const customer = await findCustomerFromRequest(req);

  let cartContext = {
    cart_id: null,
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

      cartContext = {
        cart_id: cart.data.id,
        quantities_by_variant: Object.fromEntries((items.data || []).map((item) => [item.variant_id, item.quantity])),
        total_quantity: (items.data || []).reduce((sum, item) => sum + Number(item.quantity || 0), 0)
      };
    }
  }

  const relatedCatalog = await loadCatalog({
    locationId: parsed.data.location_id || null,
    categoryId: detail.data.product.category_id || null
  });

  if (relatedCatalog.error) return res.status(400).json({
    error: relatedCatalog.error.message
  });

  res.json({
    cocktail: {
      ...detail.data.card,
      servingGuidance: {
        default_serving_count: detail.data.card.variants?.[0]?.serving_count || 1,
        customer_supplies_liquor: true,
        note: 'You bring the bottle. We bring the magic.'
      }
    },
    cartContext,
    relatedCocktails: (relatedCatalog.data.cards || [])
      .filter((card) => card.id !== detail.data.product.id)
      .slice(0, 6)
      .map((card) => ({
        id: card.id,
        slug: card.slug,
        name: card.name,
        image_url: card.image_url,
        starting_price_inc_vat: card.price.starting_price_inc_vat
      }))
  });
});

customerRouter.get('/customer/cart', async (req, res) => {
  const parsed = z.object({
    location_id: optionalUuid
  }).safeParse(req.query);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid cart request.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const cart = await buildCartResponse(ensured.customer.id, {
    createIfMissing: true,
    locationId: parsed.data.location_id || null
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
    product_id: uuid,
    variant_id: uuid,
    quantity: z.coerce.number().int().positive().max(MAX_CART_ITEM_QTY).default(1),
    location_id: optionalUuid
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid cart item.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const cart = await getActiveCart(ensured.customer.id, {
    createIfMissing: true
  });

  if (cart.error) return res.status(400).json({
    error: cart.error.message
  });

  const variant = await supabase
    .from('product_variants')
    .select('*, products(id,name,slug,image_url,status)')
    .eq('id', parsed.data.variant_id)
    .eq('product_id', parsed.data.product_id)
    .eq('is_active', true)
    .maybeSingle();

  if (variant.error) return res.status(400).json({
    error: variant.error.message
  });

  if (!variant.data || variant.data.products?.status !== 'active') {
    return res.status(400).json({
      error: 'This item is not available.'
    });
  }

  if (parsed.data.location_id) {
    const catalog = await loadCatalog({
      locationId: parsed.data.location_id
    });

    if (catalog.error) return res.status(400).json({
      error: catalog.error.message
    });

    const productCard = catalog.data.cards.find((card) => card.id === parsed.data.product_id);
    const availability = productCard?.variants?.find((item) => item.id === parsed.data.variant_id)?.availability;

    if (!availability?.is_orderable) {
      return res.status(400).json({
        error: availability?.reason || 'Item is not available at this beach cart.'
      });
    }
  }

  const existingItem = await supabase
    .from('cart_items')
    .select('*')
    .eq('cart_id', cart.data.id)
    .eq('variant_id', parsed.data.variant_id)
    .maybeSingle();

  if (existingItem.error) return res.status(400).json({
    error: existingItem.error.message
  });

  const nextQuantity = existingItem.data
    ? Math.min(MAX_CART_ITEM_QTY, Number(existingItem.data.quantity || 0) + parsed.data.quantity)
    : parsed.data.quantity;

  const unitPrice = variantPriceIncVat(variant.data);
  const vatRate = Number(variant.data.vat_rate || 0);

  const saved = existingItem.data
    ? await supabase
        .from('cart_items')
        .update({
          quantity: nextQuantity
        })
        .eq('id', existingItem.data.id)
        .select('*, products(name,slug,image_url), product_variants(name,serving_count)')
        .single()
    : await supabase
        .from('cart_items')
        .insert({
          cart_id: cart.data.id,
          product_id: parsed.data.product_id,
          variant_id: parsed.data.variant_id,
          quantity: parsed.data.quantity,
          unit_price_inc_vat_snapshot: unitPrice,
          vat_rate_snapshot: vatRate
        })
        .select('*, products(name,slug,image_url), product_variants(name,serving_count)')
        .single();

  if (saved.error) return res.status(400).json({
    error: saved.error.message
  });

  const summary = await cartSummary(cart.data.id);

  res.json({
    session: sessionPayload(ensured.customer.id, ensured.token),
    cart: summary,
    addedItem: {
      id: saved.data.id,
      product_id: saved.data.product_id,
      variant_id: saved.data.variant_id,
      quantity: saved.data.quantity,
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
    }
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
    paymentMethods: [
      {
        value: 'payment_gateway',
        label: 'Card payment'
      }
    ]
  });
});

customerRouter.post('/customer/checkout/quote', async (req, res) => {
  const parsed = z.object({
    cart_id: uuid,
    location_id: uuid,
    fulfillment_type: z.enum(['pickup_at_cart', 'delivery_to_unit']),
    customer_address_id: uuid.nullable().optional(),
    requested_fulfillment_at: z.string().nullable().optional(),
    promo_code: z.string().nullable().optional(),
    customer_notes: z.string().nullable().optional()
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid checkout quote request.'
  });

  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const quote = await buildCheckoutQuote({
    customerId: ensured.customer.id,
    cartId: parsed.data.cart_id,
    locationId: parsed.data.location_id,
    fulfillmentType: parsed.data.fulfillment_type,
    customerAddressId: parsed.data.customer_address_id || null,
    customerNotes: parsed.data.customer_notes || null
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

customerRouter.post('/customer/orders', async (req, res) => {
  const parsed = z.object({
    cart_id: uuid,
    location_id: uuid,
    fulfillment_type: z.enum(['pickup_at_cart', 'delivery_to_unit']),
    customer_address_id: uuid.nullable().optional(),
    requested_fulfillment_at: z.string().nullable().optional(),
    customer_notes: z.string().nullable().optional(),
    payment_method: z.literal('payment_gateway').default('payment_gateway'),
    idempotency_key: z.string().min(8).max(120)
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid order request.'
  });

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
      payment: createPaymentGatewayPayload({
        order: existingPayment.data.orders,
        payment: existingPayment.data
      }),
      nextScreen: 'order_confirmation'
    });
  }

  const quote = await buildCheckoutQuote({
    customerId: ensured.customer.id,
    cartId: parsed.data.cart_id,
    locationId: parsed.data.location_id,
    fulfillmentType: parsed.data.fulfillment_type,
    customerAddressId: parsed.data.customer_address_id || null,
    customerNotes: parsed.data.customer_notes || null
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

  const orderInsert = await supabase
    .from('orders')  
    .insert({
      customer_id: ensured.customer.id,
      location_id: parsed.data.location_id,
      customer_address_id: parsed.data.customer_address_id || null,
      order_channel: 'app',
      fulfillment_type: parsed.data.fulfillment_type,
      status: 'pending_payment',
      payment_status: 'pending',
      requested_fulfillment_at: parsed.data.requested_fulfillment_at || null,
      subtotal_ex_vat: quote.data.quote.totals.subtotal_ex_vat,
      vat_amount: quote.data.quote.totals.vat_amount,
      discount_amount: quote.data.quote.totals.discount_amount,
      delivery_fee: quote.data.quote.totals.delivery_fee,
      total_amount: quote.data.quote.totals.total_amount,
      customer_notes: parsed.data.customer_notes || null
    })
    .select('*, locations(id,name,type,compound_name,beach_name), customer_addresses(*)')
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
    unit_price_inc_vat_snapshot: item.unit_price_inc_vat,
    vat_rate_snapshot: item.vat_rate,
    line_total: item.line_total
  }));

  const orderItems = await supabase
    .from('order_items')
    .insert(orderItemsPayload)
    .select();

  if (orderItems.error) {
    await supabase
      .from('orders')
      .delete()
      .eq('id', orderInsert.data.id);

    return res.status(400).json({
      error: orderItems.error.message
    });
  }

  const payment = await supabase
    .from('payments')
    .insert({
      order_id: orderInsert.data.id,
      provider: PAYMENT_PROVIDER,
      amount: quote.data.quote.totals.total_amount,
      currency: CURRENCY,
      status: 'pending',
      idempotency_key: parsed.data.idempotency_key,
      raw_payload: {
        payment_method: parsed.data.payment_method,
        gateway_configured: Boolean(PAYMENT_GATEWAY_CHECKOUT_URL)
      }
    })
    .select()
    .single();

  if (payment.error) {
    await supabase
      .from('orders')
      .delete()
      .eq('id', orderInsert.data.id);

    return res.status(400).json({
      error: payment.error.message
    });
  }

  await supabase
    .from('cart_items')
    .delete()
    .eq('cart_id', parsed.data.cart_id);

  await supabase
    .from('carts')
    .update({
      status: 'converted'
    })
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
      location: publicLocation(orderInsert.data.locations),
      address: orderInsert.data.customer_addresses,
      totals: quote.data.quote.totals
    },
    items: orderItems.data,
    payment: createPaymentGatewayPayload({
      order: orderInsert.data,
      payment: payment.data
    }),
    nextScreen: 'order_confirmation'
  });
});

customerRouter.get('/customer/orders/:orderId', async (req, res) => {
  const ensured = await ensureCustomer(req, res);
  if (!ensured) return;

  const order = await supabase
    .from('orders')
    .select('*, locations(id,name,type,compound_name,beach_name), customer_addresses(*)')
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

  const statusOrder = [
    'pending_payment',
    'confirmed',
    'preparing',
    'ready',
    'out_for_delivery',
    'completed'
  ];

  const currentStatusIndex = statusOrder.indexOf(order.data.status);

  const timeline = statusOrder.map((status, index) => ({
    status,
    label: status.split('_').map((word) => word[0].toUpperCase() + word.slice(1)).join(' '),
    completed: currentStatusIndex >= index,
    timestamp: status === order.data.status ? order.data.updated_at : null
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

customerRouter.patch('/customer/me', async (req, res) => {
  const parsed = z.object({
    full_name: z.string().min(1).nullable().optional(),
    phone: z.string().min(5).nullable().optional(),
    email: z.string().email().nullable().optional(),
    birthday: z.string().nullable().optional(),
    marketing_opt_in: z.boolean().optional()
  }).safeParse(req.body);

  if (!parsed.success) return res.status(400).json({
    error: 'Invalid customer profile.'
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
    session: sessionPayload(ensured.customer.id, ensured.token),
    customer: updated.data
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
