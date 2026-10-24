import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, exportPKCS8, SignJWT } from 'jose';
import { accountRead, accountRpc, routeAccountRequest } from './account_state.js';
import { notificationRequest } from './notifications.js';
import { handleSupportGetMessages } from './support_chat.js';
import { accountTokenForUserId } from './store_account.js';
import { tokenHash } from './user_auth.js';
import { fixture, identity, request, session } from './fixture-account.mjs';
import worker from './worker.js';

const transient = () => Object.assign(new Error('injected reset'), { retryable: true });
function faultBinding(outcomes) {
  const calls = [], stubs = [];
  return {
    calls, stubs, idFromName: id => id,
    get(id) {
      const stubNumber = stubs.length;
      const stub = { async fetch(input, options) {
        const req = typeof input === 'string' ? new Request(input, options) : input;
        const body = await req.text();
        calls.push({ id, stubNumber, request: req, body });
        const outcome = outcomes[calls.length - 1];
        if (outcome?.error) throw outcome.error;
        return Response.json(outcome?.body || { ok: true });
      } };
      stubs.push(stub);
      return stub;
    },
  };
}

test('only the three private account read RPCs retry and every attempt rebuilds its body', async () => {
  for (const path of ['/_account/read', '/_account/read-many', '/_directory/find']) {
    const namespace = faultBinding([{ error: transient() }, { body: { value: 'current' } }]);
    const body = { key: 'auth_generation:google_123' };
    assert.equal((await accountRpc({ ACCOUNTS: namespace }, 'google_123', path, body)).status, 200);
    assert.equal(namespace.calls.length, 2);
    assert.equal(new Set(namespace.calls.map(call => call.stubNumber)).size, 2);
    assert.deepEqual(namespace.calls.map(call => call.body), [JSON.stringify(body), JSON.stringify(body)]);
  }
  for (const path of ['/_account/write', '/_directory/register', '/_account/metadata', '/_account/reconcile', '/_account/iap-event']) {
    const error = transient(), namespace = faultBinding([{ error }]);
    await assert.rejects(accountRpc({ ACCOUNTS: namespace }, 'google_123', path, {}), caught => caught === error);
    assert.equal(namespace.calls.length, 1, path);
  }
});

test('account route retries only the explicit user read endpoints, never a write after lost response', async () => {
  const authorization = { sessionAccountId: async () => 'google_123', verifyAdminAuth: async () => true };
  for (const path of ['/api/user/status', '/api/user/progress', '/api/user/store/status', '/api/user/store/account-token']) {
    const namespace = faultBinding([{ error: transient() }, {}]);
    assert.equal((await routeAccountRequest(new Request('https://test' + path), { ACCOUNTS: namespace }, authorization)).status, 200);
    assert.equal(namespace.calls.length, 2, path);
    assert.equal(new Set(namespace.calls.map(call => call.request)).size, 2);
    assert.equal(namespace.calls[1].request.headers.get('x-account-id'), 'google_123');
  }
  for (const [path, method, body] of [
    ['/api/user/progress/sync', 'POST', { userId: 'google_123', progress: {} }],
    ['/api/user/purchase', 'POST', { userId: 'google_123' }],
    ['/api/user/pay-intent', 'POST', { userId: 'google_123' }],
    ['/api/user/pay-check', 'POST', { userId: 'google_123' }],
    ['/api/admin/users/grant-premium', 'POST', { userId: 'google_123' }],
    ['/api/admin/users/detail?id=google_123', 'GET'],
    ['/api/user/unknown', 'GET'],
  ]) {
    const error = transient(), namespace = faultBinding([{ error }]);
    const req = new Request('https://test' + path, { method, ...(body ? { body: JSON.stringify(body) } : {}) });
    await assert.rejects(routeAccountRequest(req, { ACCOUNTS: namespace }, authorization), caught => caught === error);
    assert.equal(namespace.calls.length, 1, path);
    if (body) assert.equal(namespace.calls[0].body, JSON.stringify(body));
  }
});

test('notifications retry named reads but never publishing or the mutating GET alarm', async () => {
  for (const path of ['/client?app=ru&platform=android', '/admin', '/updates?app=ru', '/updates/admin']) {
    const namespace = faultBinding([{ error: transient() }, {}]);
    assert.equal((await notificationRequest({ NOTIFICATIONS: namespace }, path)).status, 200);
    assert.equal(namespace.calls.length, 2);
  }
  for (const [path, method] of [['/publish', 'POST'], ['/config', 'POST'], ['/alarm', 'GET'], ['/unknown', 'GET']]) {
    const error = transient(), namespace = faultBinding([{ error }]);
    await assert.rejects(notificationRequest({ NOTIFICATIONS: namespace }, path, method, method === 'POST' ? {} : undefined), caught => caught === error);
    assert.equal(namespace.calls.length, 1, path);
  }
});

test('support list resets obtain a fresh stub, while legacy seed writes are never retried', async () => {
  const message = { id: 'reply', ts: 2000, text: 'reply' };
  const namespace = faultBinding([{ error: transient() }, { body: { initialized: true, messages: [message] } }]);
  const response = await handleSupportGetMessages(new Request('https://test/api/support/messages?clientId=fixture'), { SUPPORT: namespace });
  assert.deepEqual((await response.json()).messages, [message]);
  assert.equal(namespace.calls.length, 2);
  assert.equal(new Set(namespace.calls.map(call => call.stubNumber)).size, 2);
  const error = transient(), uninitialized = faultBinding([{ body: { initialized: false, messages: [] } }, { error }]);
  await assert.rejects(handleSupportGetMessages(new Request('https://test/api/support/messages?clientId=fixture'), {
    SUPPORT: uninitialized, INSTALLS: { get: async () => [] },
  }), caught => caught === error);
  assert.deepEqual(uninitialized.calls.map(call => new URL(call.request.url).pathname), ['/list', '/seed']);
  assert.notEqual(uninitialized.calls[0].stubNumber, uninitialized.calls[1].stubNumber);
});

const { privateKey } = await generateKeyPair('ES256', { extractable: true });
const appleCredentials = {
  APPLE_IAP_PRIVATE_KEY: await exportPKCS8(privateKey),
  APPLE_IAP_KEY_ID: 'fixture-key', APPLE_IAP_ISSUER_ID: 'fixture-issuer',
};
const purchase = { store: 'appstore', country: 'ru', productId: 'u.pdd.pddApp.premium.week', transactionId: '123', userId: 'google_123' };

test('unavailable or corrupt authoritative reads never become empty progress or overwrite paid profiles', async () => {
  const originalFetch = globalThis.fetch;
  const transaction = {
    bundleId: 'ru.pdd.pddApp', productId: purchase.productId, transactionId: '123',
    originalTransactionId: '100', environment: 'Production', expiresDate: Date.now() + 7 * 86400000,
    appAccountToken: await accountTokenForUserId('google_123'),
  };
  const signedTransactionInfo = await new SignJWT(transaction).setProtectedHeader({ alg: 'ES256' }).sign(privateKey);
  globalThis.fetch = async url => {
    assert.equal(new URL(String(url)).hostname, 'api.storekit.apple.com');
    return Response.json({ signedTransactionInfo });
  };
  try {
    for (const corruption of ['io', 'json']) for (const [path, body, key] of [
      ['/api/user/progress?userId=google_123', undefined, 'user_progress:google_123'],
      ['/api/user/progress/sync', { userId: 'google_123', progress: { answers: {} } }, 'user_progress:google_123'],
      ['/api/user/sync', { id: 'google_123' }, 'user:google_123'],
      ['/api/user/purchase', purchase, 'user:google_123'],
    ]) {
      const { env, states } = fixture();
      Object.assign(env, appleCredentials, { PURCHASE_CLAIMS: { idFromName: id => id, get: () => ({ fetch: async () => Response.json({ ok: true }) }) } });
      const user = { ...identity(), isPremium: true, premiumSource: 'admin_grant', premiumExpiresAt: '2030-01-01T00:00:00.000Z',
        entitlements: { admin_grant: { expiresAt: '2030-01-01T00:00:00.000Z' }, web: { expiresAt: '2029-01-01T00:00:00.000Z' } } };
      const progress = { answers: { q1: { correct: true, ts: 1000 } }, settings: { soundEnabled: false } };
      await env.INSTALLS.put('user:google_123', JSON.stringify(user));
      await env.INSTALLS.put('user_progress:google_123', JSON.stringify(progress));
      const token = await session(env);
      // Import the durable records first, then fail only the requested primary
      // document. Authentication itself remains available in this fault model.
      await accountRpc(env, 'google_123', '/_account/read-many', { keys: ['user:google_123', 'user_progress:google_123'] });
      const storage = states.get('google_123'), stored = storage.get.bind(storage);
      const beforeProfile = await env.INSTALLS.get('user:google_123');
      const beforeProgress = await env.INSTALLS.get('user_progress:google_123');
      let failures = 0;
      if (corruption === 'io') storage.get = async name => {
        if (name === 'doc:' + key) { failures++; throw transient(); }
        return stored(name);
      };
      else storage.data.set('doc:' + key, { key, value: '{invalid json', options: {}, epoch: '1' });
      const primaryBefore = structuredClone(storage.data.get('doc:' + key));
      const response = await worker.fetch(request(path, body, token), env);
      assert.equal(response.status, corruption === 'io' ? 503 : 500, corruption + ' ' + path);
      const result = await response.json();
      assert.equal(result.ok, undefined, corruption + ' ' + path);
      assert.equal(await env.INSTALLS.get('user:google_123'), beforeProfile, corruption + ' ' + path);
      assert.equal(await env.INSTALLS.get('user_progress:google_123'), beforeProgress, corruption + ' ' + path);
      assert.deepEqual(storage.data.get('doc:' + key), primaryBefore, corruption + ' ' + path);
      if (corruption === 'io') assert.equal(failures, body === undefined ? 3 : 1, path);
    }
  } finally { globalThis.fetch = originalFetch; }
});

test('status GET replay after a committed refresh preserves exact expiry and other Premium sources', async () => {
  const { env } = fixture();
  Object.assign(env, appleCredentials);
  const oldExpiry = new Date(Date.now() + 86400000).toISOString();
  const expiry = new Date(Date.now() + 90 * 86400000).toISOString();
  const grantExpiry = '2030-01-01T00:00:00.000Z';
  const reference = { store: 'appstore', country: 'ru', productId: purchase.productId, transactionId: '123' };
  await env.INSTALLS.put('user:google_123', JSON.stringify({
    ...identity(), isPremium: true, premiumSource: 'admin_grant', premiumExpiresAt: grantExpiry,
    entitlements: { admin_grant: { expiresAt: grantExpiry }, appstore: { expiresAt: oldExpiry } },
    verifiedPurchase: reference,
  }));
  const token = await session(env);
  const transaction = {
    bundleId: 'ru.pdd.pddApp', productId: purchase.productId, transactionId: '123',
    originalTransactionId: '100', environment: 'Production', expiresDate: Date.parse(expiry),
    appAccountToken: await accountTokenForUserId('google_123'),
  };
  const signedTransactionInfo = await new SignJWT(transaction).setProtectedHeader({ alg: 'ES256' }).sign(privateKey);
  const originalFetch = globalThis.fetch, originalGet = env.ACCOUNTS.get.bind(env.ACCOUNTS);
  let attempts = 0, storeReads = 0;
  globalThis.fetch = async input => {
    storeReads++;
    const url = new URL(String(input));
    assert.equal(url.hostname, 'api.storekit.apple.com');
    return url.pathname.includes('/subscriptions/')
      ? Response.json({ environment: 'Production', bundleId: 'ru.pdd.pddApp', data: [{ lastTransactions: [{ originalTransactionId: '100', status: 1, signedTransactionInfo }] }] })
      : Response.json({ signedTransactionInfo });
  };
  env.ACCOUNTS.get = id => ({ fetch: async (input, options) => {
    const response = await originalGet(id).fetch(input, options);
    if (new URL(typeof input === 'string' ? input : input.url).pathname === '/api/user/status' && ++attempts === 1) throw transient();
    return response;
  } });
  try {
    const response = await worker.fetch(request('/api/user/status', undefined, token), env);
    assert.equal(response.status, 200);
    assert.equal(attempts, 2);
    assert.equal(storeReads, 2, 'only the first committed attempt queries transaction and subscription');
    const user = JSON.parse(await accountRead(env, 'google_123', 'user:google_123'));
    assert.equal(user.entitlements.appstore.expiresAt, expiry);
    assert.equal(user.entitlements.admin_grant.expiresAt, grantExpiry);
    assert.equal(user.premiumExpiresAt, grantExpiry);
    assert.equal((await response.json()).isPremium, true);
  } finally { globalThis.fetch = originalFetch; }
});

test('status refresh recovers a retryable primary commit failure and corrupt JSON fails visibly', async () => {
  const { env, states } = fixture();
  Object.assign(env, appleCredentials);
  const expiry = new Date(Date.now() + 90 * 86400000).toISOString();
  const grantExpiry = '2030-01-01T00:00:00.000Z';
  const originalUser = {
    ...identity(), isPremium: true, premiumSource: 'admin_grant', premiumExpiresAt: grantExpiry,
    entitlements: { admin_grant: { expiresAt: grantExpiry }, appstore: { expiresAt: new Date(Date.now() + 86400000).toISOString() } },
    verifiedPurchase: { store: 'appstore', country: 'ru', productId: purchase.productId, transactionId: '123' },
  };
  await env.INSTALLS.put('user:google_123', JSON.stringify(originalUser));
  const token = await session(env);
  await accountRpc(env, 'google_123', '/_account/read-many', { keys: [
    'user:google_123', 'auth_generation:google_123', 'revoked_session:google_123:' + await tokenHash(token),
  ] });
  const storage = states.get('google_123'), originalTransaction = storage.transaction.bind(storage);
  const primaryBefore = structuredClone(storage.data.get('doc:user:google_123'));
  const error = transient();
  let failedCommit = false, profileCommits = 0;
  storage.transaction = fn => originalTransaction(async txn => {
    let profileChanged = false;
    const value = await fn({ ...txn, put: async (key, record) => {
      if (key === 'doc:user:google_123') profileChanged = true;
      return txn.put(key, record);
    } });
    if (profileChanged) {
      profileCommits++;
      if (!failedCommit) { failedCommit = true; throw error; }
    }
    return value;
  });
  const transaction = {
    bundleId: 'ru.pdd.pddApp', productId: purchase.productId, transactionId: '123',
    originalTransactionId: '100', environment: 'Production', expiresDate: Date.parse(expiry),
    appAccountToken: await accountTokenForUserId('google_123'),
  };
  const signedTransactionInfo = await new SignJWT(transaction).setProtectedHeader({ alg: 'ES256' }).sign(privateKey);
  const originalFetch = globalThis.fetch, originalGet = env.ACCOUNTS.get.bind(env.ACCOUNTS);
  let attempts = 0;
  globalThis.fetch = async input => {
    const url = new URL(String(input));
    assert.equal(url.hostname, 'api.storekit.apple.com');
    return url.pathname.includes('/subscriptions/')
      ? Response.json({ environment: 'Production', bundleId: 'ru.pdd.pddApp', data: [{ lastTransactions: [{ originalTransactionId: '100', status: 1, signedTransactionInfo }] }] })
      : Response.json({ signedTransactionInfo });
  };
  env.ACCOUNTS.get = id => ({ fetch: async (input, options) => {
    attempts++;
    try { return await originalGet(id).fetch(input, options); }
    catch (caught) {
      assert.equal(caught, error);
      assert.deepEqual(storage.data.get('doc:user:google_123'), primaryBefore, 'failed transaction must preserve every prior entitlement');
      assert.equal(await env.INSTALLS.get('user:google_123'), JSON.stringify(originalUser));
      throw caught;
    }
  } });
  try {
    const response = await worker.fetch(request('/api/user/status', undefined, token), env);
    assert.equal(response.status, 200);
    assert.equal(attempts, 2);
    assert.equal(profileCommits, 2);
    const user = JSON.parse(await accountRead(env, 'google_123', 'user:google_123'));
    assert.equal(user.entitlements.appstore.expiresAt, expiry);
    assert.equal(user.entitlements.admin_grant.expiresAt, grantExpiry);
    assert.equal(user.premiumExpiresAt, grantExpiry);
  } finally { globalThis.fetch = originalFetch; }

  storage.transaction = originalTransaction;
  const corrupt = { key: 'user:google_123', value: '{corrupt', options: {}, epoch: '1' };
  storage.data.set('doc:user:google_123', structuredClone(corrupt));
  attempts = 0;
  env.ACCOUNTS.get = id => ({ fetch: async (input, options) => {
    const path = new URL(typeof input === 'string' ? input : input.url).pathname;
    if (path === '/api/user/status') attempts++;
    return originalGet(id).fetch(input, options);
  } });
  const response = await worker.fetch(request('/api/user/status', undefined, token), env);
  assert.equal(response.status, 500);
  assert.deepEqual(await response.json(), { error: 'server unavailable' });
  assert.equal(attempts, 1, 'corrupt JSON is not a retryable infrastructure reset');
  assert.deepEqual(storage.data.get('doc:user:google_123'), corrupt);
});
