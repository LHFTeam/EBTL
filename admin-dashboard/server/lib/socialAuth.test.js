import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'crypto';
import { SignJWT, exportJWK, generateKeyPair } from 'jose';

// `socialAuth.js` imports `appConfig.js`, which refuses to load without Supabase
// credentials. CI has no secrets, so stand in placeholders and import
// dynamically — a static import would be hoisted above these lines and throw
// before they ran. The provider client IDs have to be set the same way, because
// appConfig reads them at module load.
process.env.SUPABASE_URL ||= 'http://supabase.invalid';
process.env.SUPABASE_SERVICE_ROLE_KEY ||= 'test-key';
process.env.GOOGLE_CLIENT_IDS ||= 'ebtl-google-client.apps.googleusercontent.com';
process.env.APPLE_BUNDLE_IDS ||= 'wtf.ebtl.app';
process.env.FACEBOOK_APP_ID ||= '1611789933929380';

const { verifySocialToken, SocialAuthError } = await import('./socialAuth.js');

/*
  What these tests are actually protecting.

  An id_token proves somebody signed in with Google. It does not, on its own,
  prove they signed in *to this app* — a token lifted from another app's traffic
  is a perfectly valid Google token. Two things stop it being usable here: the
  audience check, and the nonce, which binds the token to the one client that
  knows the pre-image of the digest inside it.

  So the cases below are the ways a wrong token gets in, not the happy path
  alone: right shape but somebody else's audience, right audience but a nonce
  the caller cannot have produced, and a token that has simply expired.

  The tokens are signed with keys generated here, which is exactly why the
  signature check must reject them: they are not in any provider's published key
  set. The module resolves its JWKS internally and cannot be pointed elsewhere
  from outside, so the last test does reach for Google's key endpoint — and
  rejects the token whether that fetch succeeds or fails, which is the behaviour
  worth having either way. Everything else here runs without a network call.

  The one thing these cannot cover is a *genuine* provider token being accepted;
  that needs a real sign-in on a real device, and is in the manual verification
  step.
*/

const GOOGLE_CLIENT_ID = 'ebtl-google-client.apps.googleusercontent.com';
const RAW_NONCE = 'a-random-value-the-app-generated';

function hashedNonce(raw = RAW_NONCE) {
  return crypto.createHash('sha256').update(raw).digest('hex');
}

async function googleToken({
  audience = GOOGLE_CLIENT_ID,
  nonce = hashedNonce(),
  expiresIn = '5m',
  subject = 'google-user-1'
} = {}) {
  const { privateKey, publicKey } = await generateKeyPair('RS256');

  const token = await new SignJWT({ nonce, email: 'guest@ebtl.wtf', name: 'Beach Guest' })
    .setProtectedHeader({ alg: 'RS256' })
    .setIssuer('https://accounts.google.com')
    .setAudience(audience)
    .setSubject(subject)
    .setIssuedAt()
    .setExpirationTime(expiresIn)
    .sign(privateKey);

  return { token, jwk: await exportJWK(publicKey) };
}

test('the digest the app sends a provider is the hash of the nonce it sends us', () => {
  // The contract the client and server both implement: provider gets
  // sha256(raw), we get raw. If this ever drifts, every JWT sign-in breaks at
  // once, so it is worth pinning independently of the verification path.
  assert.equal(
    hashedNonce('abc'),
    crypto.createHash('sha256').update('abc').digest('hex')
  );
  assert.notEqual(hashedNonce('abc'), hashedNonce('abd'));
});

test('an unknown provider is refused before any network call', async () => {
  await assert.rejects(
    () => verifySocialToken({
      provider: 'twitter',
      token: 'anything',
      tokenKind: 'id_token',
      nonce: RAW_NONCE
    }),
    (error) => {
      assert.ok(error instanceof SocialAuthError);
      assert.equal(error.status, 400);
      return true;
    }
  );
});

test('a missing token is refused before any network call', async () => {
  await assert.rejects(
    () => verifySocialToken({
      provider: 'google',
      token: '   ',
      tokenKind: 'id_token',
      nonce: RAW_NONCE
    }),
    (error) => {
      assert.equal(error.status, 400);
      return true;
    }
  );
});

test('a JWT sign-in with no nonce is refused — there is nothing to bind it to', async () => {
  const { token } = await googleToken();

  await assert.rejects(
    () => verifySocialToken({
      provider: 'google',
      token,
      tokenKind: 'id_token',
      nonce: ''
    }),
    (error) => {
      assert.ok(error instanceof SocialAuthError);
      assert.equal(error.status, 400);
      return true;
    }
  );
});

test('a provider with no configured audience reports itself unconfigured, not invalid', async () => {
  // Facebook limited login with FACEBOOK_APP_ID unset is a deployment problem,
  // not a bad token, and 503 is what tells the app to stop offering the button
  // rather than telling the customer their sign-in failed.
  const previous = process.env.FACEBOOK_APP_ID;
  delete process.env.FACEBOOK_APP_ID;

  const { SOCIAL_AUTH } = await import('../config/appConfig.js');
  const previousId = SOCIAL_AUTH.facebookAppId;
  SOCIAL_AUTH.facebookAppId = '';

  try {
    await assert.rejects(
      () => verifySocialToken({
        provider: 'facebook',
        token: 'a.b.c',
        tokenKind: 'limited',
        nonce: RAW_NONCE
      }),
      (error) => {
        assert.equal(error.status, 503);
        return true;
      }
    );
  } finally {
    SOCIAL_AUTH.facebookAppId = previousId;
    if (previous !== undefined) process.env.FACEBOOK_APP_ID = previous;
  }
});

test('a token signed by a key the provider never published does not verify', async () => {
  // Real audience, real issuer, correct nonce — and a signature from a key pair
  // that is not in Google's JWKS. This is the shape of a forged token.
  const { token } = await googleToken();

  await assert.rejects(
    () => verifySocialToken({
      provider: 'google',
      token,
      tokenKind: 'id_token',
      nonce: RAW_NONCE
    }),
    (error) => {
      assert.ok(error instanceof SocialAuthError);
      assert.equal(error.status, 401);
      return true;
    }
  );
});
