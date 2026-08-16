import test from 'node:test';
import assert from 'node:assert/strict';

// `customerRoutes.js` imports `appConfig.js`, which refuses to load without
// Supabase credentials. CI has no secrets, so stand in placeholders and import
// dynamically — a static import would be hoisted above these lines and throw
// before they ran. `linkSocialIdentity` takes its database as a parameter, so
// nothing here opens a connection.
process.env.SUPABASE_URL ||= 'http://supabase.invalid';
process.env.SUPABASE_SERVICE_ROLE_KEY ||= 'test-key';

const { linkSocialIdentity } = await import('./customerRoutes.js');

/*
  Which customer is this?

  Three answers, and getting them wrong is expensive in different ways. Matching
  too eagerly hands one person's order history to another. Matching too little
  strands a returning customer on a fresh empty row and quietly abandons the
  account they already had.

  The `isNewCustomer` flag riding along answers a narrower question — has this
  person ever had an EBTL account — which is what the app reports as an
  acquisition. An email match counts as new: they have ordered here before, but
  anonymously, and today is the first time there is an account to come back to.
*/

// A stand-in for the two supabase calls this function makes: a select chain
// ending in maybeSingle(), and an update chain ending in single(). Records what
// it was asked for so the assertions can check the *query*, not just the answer.
function fakeDb({ selectResults = [], updateResult = null } = {}) {
  const calls = { selects: [], updates: [] };
  const pending = [...selectResults];

  return {
    calls,
    from() {
      const filters = {};
      const chain = {
        select: () => chain,
        eq: (column, value) => {
          filters[column] = value;
          return chain;
        },
        update: (patch) => {
          calls.updates.push({ patch, filters });
          return chain;
        },
        maybeSingle: async () => {
          calls.selects.push({ ...filters });
          return pending.shift() ?? { data: null, error: null };
        },
        single: async () => updateResult ?? { data: null, error: null }
      };

      return chain;
    }
  };
}

const IDENTITY = {
  provider: 'facebook',
  providerUserId: 'fb-123',
  email: 'guest@ebtl.wtf',
  fullName: 'Beach Guest'
};

const ANONYMOUS = { id: 'cus-anon', full_name: null, email: null };

test('a customer who has signed in with this provider before is not new', async () => {
  const existing = { id: 'cus-1', facebook_user_id: 'fb-123' };
  const db = fakeDb({ selectResults: [{ data: existing, error: null }] });

  const result = await linkSocialIdentity({
    identity: IDENTITY,
    currentCustomer: ANONYMOUS,
    db
  });

  assert.equal(result.customer.id, 'cus-1');
  assert.equal(result.isNewCustomer, false);
  // Matched on the provider's own subject ID, which is the only identifier that
  // survives the customer changing their email.
  assert.deepEqual(db.calls.selects, [{ facebook_user_id: 'fb-123' }]);
  assert.equal(db.calls.updates.length, 0);
});

test('an email match adopts the existing row and counts as a registration', async () => {
  const existing = { id: 'cus-2', email: 'guest@ebtl.wtf' };
  const db = fakeDb({
    selectResults: [
      { data: null, error: null },
      { data: existing, error: null }
    ],
    updateResult: { data: { ...existing, facebook_user_id: 'fb-123' }, error: null }
  });

  const result = await linkSocialIdentity({
    identity: IDENTITY,
    currentCustomer: ANONYMOUS,
    db
  });

  // The session moves to the row that already holds their orders, not the
  // throwaway anonymous one this install started with.
  assert.equal(result.customer.id, 'cus-2');
  assert.equal(result.customer.facebook_user_id, 'fb-123');
  assert.equal(result.isNewCustomer, true);
  assert.deepEqual(db.calls.updates[0].patch, { facebook_user_id: 'fb-123' });
});

test('with nothing on file the anonymous row becomes the account', async () => {
  const db = fakeDb({
    updateResult: { data: { id: 'cus-anon', facebook_user_id: 'fb-123' }, error: null }
  });

  const result = await linkSocialIdentity({
    identity: IDENTITY,
    currentCustomer: ANONYMOUS,
    db
  });

  assert.equal(result.customer.id, 'cus-anon');
  assert.equal(result.isNewCustomer, true);
  assert.deepEqual(db.calls.updates[0].patch, {
    facebook_user_id: 'fb-123',
    full_name: 'Beach Guest',
    email: 'guest@ebtl.wtf'
  });
});

test('a name the customer typed at checkout is not overwritten by the provider', async () => {
  // They meant the name they gave the cart, not whatever their Facebook profile
  // happens to carry.
  const named = { id: 'cus-anon', full_name: 'Ali', email: 'ali@ebtl.wtf' };
  const db = fakeDb({ updateResult: { data: named, error: null } });

  await linkSocialIdentity({
    identity: IDENTITY,
    currentCustomer: named,
    db
  });

  assert.deepEqual(db.calls.updates[0].patch, { facebook_user_id: 'fb-123' });
});

test('an identity with no email skips the email lookup entirely', async () => {
  // Apple's private relay and Facebook limited login both routinely withhold it.
  // Looking up `email = null` would match every anonymous row ever created.
  const db = fakeDb({
    updateResult: { data: { id: 'cus-anon' }, error: null }
  });

  const result = await linkSocialIdentity({
    identity: { ...IDENTITY, provider: 'apple', email: null, fullName: null },
    currentCustomer: ANONYMOUS,
    fullName: 'From The Client',
    db
  });

  assert.deepEqual(db.calls.selects, [{ apple_user_id: 'fb-123' }]);
  assert.equal(result.isNewCustomer, true);
  // No email to store, but the name the client forwarded still lands — Apple
  // only sends it on the very first authorisation.
  assert.deepEqual(db.calls.updates[0].patch, {
    apple_user_id: 'fb-123',
    full_name: 'From The Client'
  });
});

test('a failed lookup is raised, not swallowed into a wrong answer', async () => {
  const db = fakeDb({
    selectResults: [{ data: null, error: { code: '42703', message: 'column does not exist' } }]
  });

  await assert.rejects(
    () => linkSocialIdentity({ identity: IDENTITY, currentCustomer: ANONYMOUS, db }),
    (error) => {
      // The route turns 42703 into "sign-in is not available yet", which it can
      // only do if the code reaches it.
      assert.equal(error.code, '42703');
      return true;
    }
  );
});
