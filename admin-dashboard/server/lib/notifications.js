import crypto from 'crypto';
import { supabase } from './supabase.js';

const PUSH_PROVIDER = String(process.env.PUSH_PROVIDER || 'none').trim().toLowerCase();
const PUSH_ENABLED = String(process.env.PUSH_NOTIFICATIONS_ENABLED || 'false').trim().toLowerCase() === 'true';
const FCM_PROJECT_ID = process.env.FCM_PROJECT_ID || '';
const FCM_CLIENT_EMAIL = process.env.FCM_SERVICE_ACCOUNT_CLIENT_EMAIL || '';
const FCM_PRIVATE_KEY = String(process.env.FCM_SERVICE_ACCOUNT_PRIVATE_KEY || '').replace(/\\n/g, '\n');
const EXPO_ACCESS_TOKEN = process.env.EXPO_ACCESS_TOKEN || '';

let cachedFcmToken = null;
let cachedFcmTokenExpiresAt = 0;

function asString(value, fallback = '') {
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function base64Url(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function tokenHash(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

function cleanPushData(data = {}) {
  return Object.fromEntries(
    Object.entries(data || {})
      .filter(([, value]) => value !== null && value !== undefined)
      .map(([key, value]) => [key, typeof value === 'string' ? value : JSON.stringify(value)])
  );
}

async function getFcmAccessToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedFcmToken && cachedFcmTokenExpiresAt - 60 > now) return cachedFcmToken;

  if (!FCM_CLIENT_EMAIL || !FCM_PRIVATE_KEY) {
    throw new Error('FCM service account is not configured.');
  }

  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claimSet = base64Url(JSON.stringify({
    iss: FCM_CLIENT_EMAIL,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now
  }));
  const signingInput = `${header}.${claimSet}`;
  const signature = crypto
    .createSign('RSA-SHA256')
    .update(signingInput)
    .sign(FCM_PRIVATE_KEY, 'base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${signingInput}.${signature}`
    }).toString()
  });

  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.access_token) {
    throw new Error(body.error_description || body.error || `FCM OAuth failed with HTTP ${response.status}.`);
  }

  cachedFcmToken = body.access_token;
  cachedFcmTokenExpiresAt = now + Number(body.expires_in || 3600);
  return cachedFcmToken;
}

async function sendFcmPush({ token, title, body, data }) {
  if (!FCM_PROJECT_ID) throw new Error('FCM_PROJECT_ID is not configured.');
  const accessToken = await getFcmAccessToken();

  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data: cleanPushData(data),
        android: {
          priority: 'HIGH',
          notification: { channel_id: 'orders' }
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1
            }
          }
        }
      }
    })
  });

  const responseBody = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(responseBody.error?.message || `FCM push failed with HTTP ${response.status}.`);
  }

  return responseBody;
}

async function sendExpoPush({ token, title, body, data }) {
  const headers = { 'Content-Type': 'application/json' };
  if (EXPO_ACCESS_TOKEN) headers.Authorization = `Bearer ${EXPO_ACCESS_TOKEN}`;

  const response = await fetch('https://exp.host/--/api/v2/push/send', {
    method: 'POST',
    headers,
    body: JSON.stringify({ to: token, title, body, data, sound: 'default' })
  });

  const responseBody = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(responseBody.errors?.[0]?.message || `Expo push failed with HTTP ${response.status}.`);
  }

  return responseBody;
}

export function publicNotification(row) {
  return {
    id: row.id,
    type: row.type,
    title: row.title,
    body: row.body,
    data: row.data || {},
    order_id: row.order_id || null,
    order_number: row.orders?.order_number || row.data?.order_number || null,
    read_at: row.read_at || null,
    created_at: row.created_at
  };
}

export async function registerCustomerPushToken({ customerId, token, platform = 'unknown', deviceId = null }) {
  const cleanToken = asString(token).trim();
  if (!cleanToken) return { error: new Error('Push token is required.') };

  const result = await supabase
    .from('customer_push_tokens')
    .upsert({
      customer_id: customerId,
      token: cleanToken,
      token_hash: tokenHash(cleanToken),
      platform: asString(platform, 'unknown').slice(0, 40),
      device_id: deviceId ? asString(deviceId).slice(0, 120) : null,
      is_active: true,
      last_registered_at: new Date().toISOString()
    }, { onConflict: 'customer_id,token_hash' })
    .select('id,platform,is_active,last_registered_at')
    .single();

  return result.error ? { error: result.error } : { data: result.data };
}

export async function createCustomerNotification({ customerId, orderId = null, type, title, body, data = {}, dedupeKey = null }) {
  if (!customerId) return { data: null, push: [] };

  const payload = {
    customer_id: customerId,
    order_id: orderId,
    type,
    title,
    body,
    data,
    dedupe_key: dedupeKey
  };

  const inserted = await (dedupeKey
    ? supabase.from('customer_notifications').upsert(payload, { onConflict: 'dedupe_key' }).select('*, orders(order_number)').single()
    : supabase.from('customer_notifications').insert(payload).select('*, orders(order_number)').single());

  if (inserted.error) return { error: inserted.error };

  const push = await sendPushToCustomer({
    customerId,
    title,
    body,
    data: {
      ...data,
      notification_id: inserted.data.id,
      notification_type: type,
      order_id: orderId || data.order_id || ''
    }
  });

  return { data: inserted.data, push };
}

export async function sendPushToCustomer({ customerId, title, body, data = {} }) {
  if (!PUSH_ENABLED || PUSH_PROVIDER === 'none') return [{ status: 'skipped', reason: 'Push notifications are disabled.' }];

  const tokens = await supabase
    .from('customer_push_tokens')
    .select('id,token,platform')
    .eq('customer_id', customerId)
    .eq('is_active', true);

  if (tokens.error) return [{ status: 'error', reason: tokens.error.message }];

  const results = [];
  for (const tokenRow of tokens.data || []) {
    try {
      const providerResult = PUSH_PROVIDER === 'expo'
        ? await sendExpoPush({ token: tokenRow.token, title, body, data })
        : await sendFcmPush({ token: tokenRow.token, title, body, data });

      results.push({ token_id: tokenRow.id, status: 'sent', provider: PUSH_PROVIDER, provider_result: providerResult });

      await supabase
        .from('customer_push_tokens')
        .update({ last_used_at: new Date().toISOString() })
        .eq('id', tokenRow.id);
    } catch (error) {
      results.push({ token_id: tokenRow.id, status: 'error', provider: PUSH_PROVIDER, reason: error.message });
    }
  }

  return results;
}

export async function notifyOrderReadyForPickup({ order, previousStatus = null }) {
  if (!order?.customer_id) return { data: null, push: [] };
  if (!['ready', 'completed'].includes(order.status)) return { data: null, push: [] };
  if (previousStatus && ['ready', 'completed'].includes(previousStatus)) return { data: null, push: [] };

  const orderNumber = order.order_number || 'your order';
  const isDelivery = order.fulfillment_type === 'delivery_to_unit';
  return createCustomerNotification({
    customerId: order.customer_id,
    orderId: order.id,
    type: 'order_ready_for_pickup',
    title: isDelivery
      ? 'Your order is ready'
      : `Your order #${String(orderNumber).replace(/^#/, '')} is ready for pickup!`,
    body: isDelivery
      ? `${orderNumber} is ready and will be sent to your unit.`
      : 'Please head to your EBTL cart to pick up your order before the ice melts!',
    dedupeKey: `order:${order.id}:ready_for_pickup`,
    data: {
      order_id: order.id,
      order_number: order.order_number || null,
      status: order.status,
      previous_status: previousStatus || null
    }
  });
}
