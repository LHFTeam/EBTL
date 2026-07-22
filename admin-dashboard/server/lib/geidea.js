import crypto from 'crypto';

const GEIDEA_PROVIDER = 'geidea';
const GEIDEA_MERCHANT_PUBLIC_KEY = process.env.GEIDEA_MERCHANT_PUBLIC_KEY || '';
const GEIDEA_API_PASSWORD = process.env.GEIDEA_API_PASSWORD || '';

const GEIDEA_BASE_URL = String(process.env.GEIDEA_BASE_URL || '').replace(/\/+$/, '');
const GEIDEA_CREATE_SESSION_URL =
  process.env.GEIDEA_CREATE_SESSION_URL ||
  (GEIDEA_BASE_URL ? `${GEIDEA_BASE_URL}/payment-intent/api/v2/direct/session` : '');

const GEIDEA_CALLBACK_URL = process.env.GEIDEA_CALLBACK_URL || '';
const GEIDEA_RETURN_URL = process.env.GEIDEA_RETURN_URL || '';
const GEIDEA_APPLE_PAY_MERCHANT_ID = process.env.GEIDEA_APPLE_PAY_MERCHANT_ID || '';
const GEIDEA_REGION = process.env.GEIDEA_REGION || 'egy';
const GEIDEA_LANGUAGE = process.env.GEIDEA_LANGUAGE || 'en';
const GEIDEA_IS_SANDBOX = String(process.env.GEIDEA_IS_SANDBOX || 'true').toLowerCase() !== 'false';

function asObject(value) {
  return value && typeof value === 'object' ? value : {};
}

function nestedGet(source, path) {
  return String(path).split('.').reduce((current, part) => {
    if (current === null || current === undefined) return undefined;
    return current[part];
  }, source);
}

function deepClean(value) {
  if (Array.isArray(value)) {
    return value
      .map((item) => deepClean(item))
      .filter((item) => item !== undefined);
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value)
        .map(([key, item]) => [key, deepClean(item)])
        .filter(([, item]) => item !== undefined)
    );
  }

  return value === undefined ? undefined : value;
}

function firstValue(source, paths) {
  for (const path of paths) {
    const value = nestedGet(source, path);
    if (value !== null && value !== undefined && value !== '') return value;
  }

  return null;
}

function sha256Base64(value, secret) {
  return crypto
    .createHmac('sha256', secret)
    .update(value)
    .digest('base64');
}

function normalizeExpiryYear(value) {
  if (value === null || value === undefined || value === '') return null;
  const number = Number(value);
  if (!Number.isFinite(number)) return null;
  if (number > 0 && number < 100) return 2000 + number;
  return number;
}

function extractPaymentMethodObject(payload) {
  const body = asObject(payload);
  const order = asObject(body.order);
  const result = asObject(body.result);
  const transaction = Array.isArray(body.transactions) && body.transactions.length
    ? asObject(body.transactions[body.transactions.length - 1])
    : {};

  return asObject(
    body.paymentMethod ||
    order.paymentMethod ||
    result.paymentMethod ||
    transaction.paymentMethod ||
    body.payment_method ||
    order.payment_method ||
    result.payment_method ||
    transaction.payment_method
  );
}

export function geideaIsConfigured() {
  return Boolean(
    GEIDEA_MERCHANT_PUBLIC_KEY &&
    GEIDEA_API_PASSWORD &&
    GEIDEA_CREATE_SESSION_URL &&
    GEIDEA_CALLBACK_URL
  );
}

export function geideaCheckoutConfig() {
  return {
    provider: GEIDEA_PROVIDER,
    configured: geideaIsConfigured(),
    is_sandbox: GEIDEA_IS_SANDBOX,
    region: GEIDEA_REGION,
    language: GEIDEA_LANGUAGE,
    apple_pay_merchant_id: GEIDEA_APPLE_PAY_MERCHANT_ID || null,
    callback_url_configured: Boolean(GEIDEA_CALLBACK_URL),
    create_session_url_configured: Boolean(GEIDEA_CREATE_SESSION_URL)
  };
}

export function formatGeideaAmount(value) {
  return Number(value || 0).toFixed(2);
}

export function geideaCreateSessionSignature({ amount, currency, merchantReferenceId, timestamp }) {
  if (!GEIDEA_MERCHANT_PUBLIC_KEY || !GEIDEA_API_PASSWORD) return null;

  return sha256Base64(
    `${GEIDEA_MERCHANT_PUBLIC_KEY}${amount}${currency}${merchantReferenceId}${timestamp}`,
    GEIDEA_API_PASSWORD
  );
}

export function extractGeideaCallbackFields(payload) {
  const body = asObject(payload);
  const order = asObject(body.order);

  return {
    order_id: firstValue(body, ['orderId', 'OrderId', 'order.id', 'order.orderId', 'order.order_id']) || order.id || null,
    amount: firstValue(body, ['orderAmount', 'amount', 'order.amount', 'order.totalAmount']),
    currency: firstValue(body, ['orderCurrency', 'currency', 'order.currency']),
    status: firstValue(body, ['status', 'orderStatus', 'order.status']),
    merchant_reference_id: firstValue(body, [
      'merchantReferenceId',
      'merchantRefrenceId',
      'MerchantReferenceId',
      'MerchantRefrenceId',
      'order.merchantReferenceId',
      'order.merchantRefrenceId'
    ]),
    timestamp: firstValue(body, ['timeStamp', 'timestamp', 'Timestamp']),
    signature: firstValue(body, ['signature', 'Signature']),
    response_code: firstValue(body, ['responseCode', 'ResponseCode']),
    response_message: firstValue(body, ['responseMessage', 'ResponseMessage']),
    detailed_response_code: firstValue(body, ['detailedResponseCode', 'DetailedResponseCode']),
    detailed_response_message: firstValue(body, ['detailedResponseMessage', 'DetailedResponseMessage'])
  };
}

export function extractGeideaSavedCard(payload) {
  const body = asObject(payload);
  const paymentMethod = extractPaymentMethodObject(body);
  const expiryDate = asObject(paymentMethod.expiryDate || paymentMethod.expiry_date);

  const tokenId = firstValue(body, [
    'tokenId',
    'token_id',
    'order.tokenId',
    'order.token_id',
    'result.tokenId',
    'result.token_id'
  ]);

  if (!tokenId) return null;

  return {
    token_id: String(tokenId),
    agreement_id: firstValue(body, [
      'agreementId',
      'agreement_id',
      'order.agreementId',
      'order.agreement_id',
      'result.agreementId',
      'result.agreement_id'
    ]),
    agreement_type: firstValue(body, [
      'agreementType',
      'agreement_type',
      'cofAgreement.type',
      'order.cofAgreement.type'
    ]) || 'Unscheduled',
    card_brand: firstValue(paymentMethod, ['brand', 'cardBrand', 'card_brand']),
    cardholder_name: firstValue(paymentMethod, ['cardholderName', 'cardHolderName', 'cardholder_name']),
    masked_card_number: firstValue(paymentMethod, ['maskedCardNumber', 'masked_card_number', 'cardNumberMasked']),
    expiry_month: expiryDate.month ? Number(expiryDate.month) : null,
    expiry_year: normalizeExpiryYear(expiryDate.year),
    payment_method: paymentMethod
  };
}

export function verifyGeideaCallbackSignature(payload) {
  const fields = extractGeideaCallbackFields(payload);

  if (!fields.signature) {
    return {
      ok: false,
      reason: 'Missing Geidea callback signature.',
      fields
    };
  }

  if (!GEIDEA_MERCHANT_PUBLIC_KEY || !GEIDEA_API_PASSWORD) {
    return {
      ok: false,
      reason: 'Geidea callback verification is not configured.',
      fields
    };
  }

  const expected = sha256Base64(
    `${GEIDEA_MERCHANT_PUBLIC_KEY}${fields.amount || ''}${fields.currency || ''}${fields.order_id || ''}${fields.status || ''}${fields.merchant_reference_id || ''}${fields.timestamp || ''}`,
    GEIDEA_API_PASSWORD
  );

  const received = String(fields.signature);

  if (received.length !== expected.length) {
    return {
      ok: false,
      reason: 'Invalid Geidea callback signature.',
      fields
    };
  }

  const ok = crypto.timingSafeEqual(Buffer.from(received), Buffer.from(expected));

  return {
    ok,
    reason: ok ? null : 'Invalid Geidea callback signature.',
    fields
  };
}

export function geideaCallbackIsSuccess(fields) {
  return String(fields.response_code || '') === '000'
    && String(fields.response_message || '').toLowerCase() === 'success'
    && String(fields.detailed_response_code || '') === '000'
    && String(fields.detailed_response_message || '').toLowerCase() === 'the operation was successful.';
}

export async function createGeideaSession({
  order,
  payment,
  customer,
  paymentMethod,
  saveCard = false
}) {
  if (!geideaIsConfigured()) {
    throw new Error('Geidea is not configured. Set GEIDEA_MERCHANT_PUBLIC_KEY, GEIDEA_API_PASSWORD, GEIDEA_CREATE_SESSION_URL or GEIDEA_BASE_URL, and GEIDEA_CALLBACK_URL.');
  }

  const amount = formatGeideaAmount(order.total_amount || payment.amount);
  const currency = payment.currency || 'EGP';
  const timestamp = new Date().toISOString();
  const merchantReferenceId = payment.id;

  const signature = geideaCreateSessionSignature({
    amount,
    currency,
    merchantReferenceId,
    timestamp
  });

  const fullName = String(customer?.full_name || '').trim();
  const [firstName, ...lastNameParts] = fullName.split(/\s+/).filter(Boolean);
  const lastName = lastNameParts.join(' ');

  const requestBody = {
    amount,
    currency,
    timestamp,
    merchantReferenceId,
    signature,
    paymentOperation: 'Pay',
    callbackUrl: GEIDEA_CALLBACK_URL,
    returnUrl: GEIDEA_RETURN_URL || undefined,
    initiatedBy: 'Internet',
    language: GEIDEA_LANGUAGE,

    cardOnFile: saveCard ? true : undefined,
    cofAgreement: saveCard
      ? {
          id: customer?.id,
          type: 'Unscheduled'
        }
      : undefined,

    metadata: {
      ebtl_order_id: order.id,
      ebtl_order_number: order.order_number || null,
      ebtl_payment_id: payment.id,
      ebtl_customer_id: customer?.id || null,
      payment_method: paymentMethod,
      save_card: Boolean(saveCard)
    },

    customer: {
      email: customer?.email || undefined,
      phoneNumber: order.customer_phone_snapshot || customer?.phone || undefined,
      firstName: firstName || undefined,
      lastName: lastName || undefined
    },

    order: {
      reference: order.order_number || order.id,
      description: `EBTL order ${order.order_number || order.id}`
    }
  };

  if (paymentMethod === 'geidea_card') {
    requestBody.paymentOptions = {
      hideWallets: ['apple-pay', 'google-pay', 'samsung-pay']
    };
  }

  const cleanRequestBody = deepClean(requestBody);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25000);

  let response;
  let responseText = '';

  try {
    response = await fetch(GEIDEA_CREATE_SESSION_URL, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${Buffer.from(`${GEIDEA_MERCHANT_PUBLIC_KEY}:${GEIDEA_API_PASSWORD}`).toString('base64')}`,
        'Content-Type': 'application/json',
        Accept: 'application/json'
      },
      body: JSON.stringify(cleanRequestBody),
      signal: controller.signal
    });

    responseText = await response.text();
  } finally {
    clearTimeout(timeout);
  }

  let responseBody = null;

  try {
    responseBody = responseText ? JSON.parse(responseText) : null;
  } catch {
    responseBody = { raw: responseText };
  }

  if (!response.ok) {
    throw new Error(responseBody?.message || responseBody?.error || `Geidea create session failed with HTTP ${response.status}.`);
  }

  const sessionId = firstValue(responseBody, [
    'session.id',
    'sessionId',
    'id',
    'data.session.id',
    'data.sessionId',
    'result.session.id',
    'result.sessionId'
  ]);

  if (!sessionId) {
    throw new Error('Geidea create session succeeded but did not return a session id.');
  }

  return {
    session_id: sessionId,
    raw_response: responseBody,
    request_payload: cleanRequestBody
  };
}
