import crypto from 'crypto';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { SOCIAL_AUTH } from '../config/appConfig.js';

/*
  Verifies the credential the customer app got from Facebook, Google or Apple.

  Nothing here trusts the client. The app tells us which provider and which kind
  of token it holds, and every one of those claims is checked against the
  provider itself before a customer row is touched.

  Three of the four paths are ordinary OIDC: fetch the provider's published
  signing keys, verify the JWT, check the issuer and audience. The fourth —
  Facebook with App Tracking Transparency consent — is an OAuth access token
  instead, which is not self-describing, so it has to be handed back to Meta's
  /debug_token to learn whether it was minted for our app at all.

  ## Why the nonce matters

  An id_token proves "this person signed in with Google". It does not prove they
  signed in *to our app*, and a token lifted from another app's traffic would
  otherwise verify perfectly here. So the app generates a random value per
  attempt, hands the provider its SHA-256, and sends us the raw value; we hash
  it and require the digest to match the token's `nonce` claim. Only the client
  that started the flow knows the pre-image.

  Facebook's classic path carries no nonce. /debug_token binding the token to
  our own app ID is what stands in for it there.

  ## Email is optional

  Apple's private relay and Facebook's limited login both routinely withhold it.
  A verified identity with no email is a normal outcome, not a failure.
*/

const FACEBOOK_GRAPH = 'https://graph.facebook.com/v21.0';

const JWT_PROVIDERS = {
  facebook: {
    jwksUri: 'https://www.facebook.com/.well-known/oauth/openid/jwks/',
    issuer: 'https://www.facebook.com',
    audiences: () => (SOCIAL_AUTH.facebookAppId ? [SOCIAL_AUTH.facebookAppId] : [])
  },
  google: {
    jwksUri: 'https://www.googleapis.com/oauth2/v3/certs',
    // Google has issued tokens under both spellings for years and still does.
    issuer: ['https://accounts.google.com', 'accounts.google.com'],
    audiences: () => SOCIAL_AUTH.googleClientIds
  },
  apple: {
    jwksUri: 'https://appleid.apple.com/auth/keys',
    issuer: 'https://appleid.apple.com',
    audiences: () => SOCIAL_AUTH.appleBundleIds
  }
};

export const SOCIAL_PROVIDERS = Object.keys(JWT_PROVIDERS);

/// Carries the status the route should answer with, so a bad token reads as 401
/// and a deployment that has not been given its credentials reads as 503.
export class SocialAuthError extends Error {
  constructor(message, status = 401) {
    super(message);
    this.name = 'SocialAuthError';
    this.status = status;
  }
}

// Key sets are cached per provider for the lifetime of the process — createRemoteJWKSet
// handles the refresh and rate limiting itself, but only if we keep the instance.
const jwkSets = new Map();

function jwkSetFor(provider) {
  if (!jwkSets.has(provider)) {
    jwkSets.set(provider, createRemoteJWKSet(new URL(JWT_PROVIDERS[provider].jwksUri)));
  }

  return jwkSets.get(provider);
}

function sha256Hex(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function cleanString(value) {
  const text = String(value ?? '').trim();
  return text || null;
}

function assertNonce(claims, rawNonce) {
  const claimed = cleanString(claims.nonce);

  if (!claimed) {
    throw new SocialAuthError('This sign-in is missing its nonce. Please try again.');
  }

  const expected = sha256Hex(rawNonce);

  // Both sides are hex digests of the same length, so a constant-time compare
  // is cheap and removes the question of whether it mattered.
  const claimedBuffer = Buffer.from(claimed);
  const expectedBuffer = Buffer.from(expected);

  if (
    claimedBuffer.length !== expectedBuffer.length ||
    !crypto.timingSafeEqual(claimedBuffer, expectedBuffer)
  ) {
    throw new SocialAuthError('This sign-in could not be matched to this device. Please try again.');
  }
}

async function verifyIdToken({ provider, token, nonce }) {
  const config = JWT_PROVIDERS[provider];
  const audiences = config.audiences();

  if (audiences.length === 0) {
    throw new SocialAuthError(
      `${provider} sign-in is not configured on this server.`,
      503
    );
  }

  let payload;

  try {
    ({ payload } = await jwtVerify(token, jwkSetFor(provider), {
      issuer: config.issuer,
      audience: audiences
    }));
  } catch (error) {
    // jose distinguishes expiry, bad signature and claim mismatches, but the
    // customer can do exactly one thing about all of them.
    throw new SocialAuthError(`Could not verify this ${provider} sign-in. Please try again.`);
  }

  assertNonce(payload, nonce);

  const subject = cleanString(payload.sub);
  if (!subject) {
    throw new SocialAuthError(`${provider} did not identify the account.`);
  }

  return {
    provider,
    providerUserId: subject,
    // Apple sends `email_verified` as the string "true" as often as the boolean.
    email: payload.email_verified === false ? null : cleanString(payload.email),
    fullName: cleanString(payload.name)
  };
}

async function verifyFacebookAccessToken({ token, appId, appSecret }) {
  if (!appId || !appSecret) {
    throw new SocialAuthError('Facebook sign-in is not configured on this server.', 503);
  }

  const appAccessToken = `${appId}|${appSecret}`;

  const debugUrl = new URL(`${FACEBOOK_GRAPH}/debug_token`);
  debugUrl.searchParams.set('input_token', token);
  debugUrl.searchParams.set('access_token', appAccessToken);

  const debugResponse = await fetch(debugUrl).catch(() => null);
  const debugBody = await debugResponse?.json().catch(() => null);
  const data = debugBody?.data;

  if (!debugResponse?.ok || !data) {
    throw new SocialAuthError('Could not verify this Facebook sign-in. Please try again.');
  }

  // The whole point of this call: a token minted for somebody else's Meta app
  // verifies as a real Facebook token but is not a sign-in to EBTL.
  if (!data.is_valid || String(data.app_id) !== String(appId)) {
    throw new SocialAuthError('This Facebook sign-in was not issued for EBTL.');
  }

  const providerUserId = cleanString(data.user_id);
  if (!providerUserId) {
    throw new SocialAuthError('Facebook did not identify the account.');
  }

  const profileUrl = new URL(`${FACEBOOK_GRAPH}/me`);
  profileUrl.searchParams.set('fields', 'id,name,email');
  profileUrl.searchParams.set('access_token', token);

  // The profile read is a nicety — it fills in a name and email we would
  // otherwise leave null. A failure here must not sink an otherwise valid
  // sign-in.
  const profileResponse = await fetch(profileUrl).catch(() => null);
  const profile = profileResponse?.ok ? await profileResponse.json().catch(() => null) : null;

  return {
    provider: 'facebook',
    providerUserId,
    email: cleanString(profile?.email),
    fullName: cleanString(profile?.name)
  };
}

/**
 * Verifies a social sign-in credential and returns the identity behind it.
 *
 * @param {object} input
 * @param {'facebook'|'google'|'apple'} input.provider
 * @param {string} input.token
 * @param {'classic'|'limited'|'id_token'} input.tokenKind
 * @param {string} input.nonce raw (unhashed) nonce the client generated
 * @returns {Promise<{provider: string, providerUserId: string, email: string|null, fullName: string|null}>}
 * @throws {SocialAuthError}
 */
export async function verifySocialToken({ provider, token, tokenKind, nonce }) {
  if (!JWT_PROVIDERS[provider]) {
    throw new SocialAuthError(`Unsupported sign-in provider: ${provider}.`, 400);
  }

  if (!cleanString(token)) {
    throw new SocialAuthError('Missing sign-in token.', 400);
  }

  if (provider === 'facebook' && tokenKind === 'classic') {
    return verifyFacebookAccessToken({
      token,
      appId: SOCIAL_AUTH.facebookAppId,
      appSecret: SOCIAL_AUTH.facebookAppSecret
    });
  }

  if (!cleanString(nonce)) {
    throw new SocialAuthError('Missing sign-in nonce.', 400);
  }

  return verifyIdToken({ provider, token, nonce });
}
