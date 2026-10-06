import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, exportPKCS8, SignJWT } from 'jose';
import { verifyStorePurchase, refreshStoreEntitlement } from './store_verification.js';
import worker from './worker.js';
import { signSession } from './user_auth.js';
const { privateKey } = await generateKeyPair('ES256', { extractable: true });
const env = { APPLE_IAP_PRIVATE_KEY: await exportPKCS8(privateKey), APPLE_IAP_KEY_ID: 'test-key', APPLE_IAP_ISSUER_ID: 'test-issuer' };
const body = { store: 'appstore', country: 'ru', productId: 'u.pdd.pddApp.premium.week', transactionId: '123' };
const transaction = (overrides = {}) => ({ bundleId: 'ru.pdd.pddApp', productId: body.productId, transactionId: '123', originalTransactionId: '100', environment: 'Production', expiresDate: Date.now() + 7 * 86400000, ...overrides });
async function signed(data) { return new SignJWT(data).setProtectedHeader({ alg: 'ES256' }).sign(privateKey); }
async function withApple(callback, run) { const original = globalThis.fetch; globalThis.fetch = callback; try { return await run(); } finally { globalThis.fetch = original; } }
test('production Apple payment verifies and preserves exact expiry', async () => {
  const data = transaction();
  await withApple(async url => { assert.equal(String(url), 'https://api.storekit.apple.com/inApps/v1/transactions/123'); return Response.json({ signedTransactionInfo: await signed(data) }); }, async () => {
    const result = await verifyStorePurchase(body, env, 'apple_test');
    assert.equal(result.active, true); assert.equal(result.expiresAt, new Date(data.expiresDate).toISOString()); assert.equal(result.key, 'appstore:100');
  });
});
test('production not found falls back to sandbox', async () => {
  const hosts = [];
  await withApple(async url => { hosts.push(new URL(url).hostname); if (hosts.length === 1) return Response.json({ errorCode: 4040010 }, { status: 404 }); return Response.json({ signedTransactionInfo: await signed(transaction({ environment: 'Sandbox' })) }); }, async () => assert.equal((await verifyStorePurchase(body, env, 'apple_test')).active, true));
  assert.deepEqual(hosts, ['api.storekit.apple.com', 'api.storekit-sandbox.apple.com']);
});
test('explicit sandbox validates sandbox environment', async () => {
  await withApple(async url => { assert.equal(new URL(url).hostname, 'api.storekit-sandbox.apple.com'); return Response.json({ signedTransactionInfo: await signed(transaction({ environment: 'Sandbox' })) }); }, async () => assert.equal((await verifyStorePurchase(body, { ...env, APPLE_IAP_ENVIRONMENT: 'sandbox' }, 'apple_test')).active, true));
});
test('Apple authentication and temporary failures do not fall back or grant', async () => {
  for (const status of [401, 403, 429, 500]) { let calls = 0; await withApple(async () => { calls++; return new Response('', { status }); }, async () => assert.rejects(verifyStorePurchase(body, env, 'apple_test'))); assert.equal(calls, 1); }
});
test('wrong bundle, product, transaction, environment and invalid expiry fail closed', async () => {
  for (const changes of [{ bundleId: 'other' }, { productId: 'other' }, { transactionId: '999' }, { environment: 'Sandbox' }, { expiresDate: null }, { originalTransactionId: undefined }]) {
    await withApple(async () => Response.json({ signedTransactionInfo: await signed(transaction(changes)) }), async () => assert.rejects(verifyStorePurchase(body, env, 'apple_test')));
  }
});
test('expired and refunded transactions do not grant access', async () => {
  for (const changes of [{ expiresDate: Date.now() - 1000 }, { revocationDate: Date.now() }]) {
    await withApple(async url => new URL(url).pathname.includes('/subscriptions/') ? statusResponse(transaction(changes), 2) : Response.json({ signedTransactionInfo: await signed(transaction(changes)) }), async () => assert.equal((await verifyStorePurchase(body, env, 'apple_test')).active, false));
  }
});
test('purchase endpoint grants access, restore is idempotent, another account is rejected', async () => {
  const records = new Map(), owners = new Map();
  const e = { ...env, SHARED_SECRET: 'test-secret', SESSION_SECRET: 'test-session', INSTALLS: { get: async k => records.get(k) ?? null, put: async (k, v) => records.set(k, v) }, PURCHASE_CLAIMS: { idFromName: k => k, get: k => ({ fetch: async (_, options) => { const { userId } = JSON.parse(options.body); if (owners.has(k) && owners.get(k) !== userId) return new Response('', { status: 403 }); owners.set(k, userId); return Response.json({ ok: true }); } }) } };
  const data = transaction();
  const purchase = async id => {
    const token = await signSession(e, { user: { id, provider: 'apple', email: 'test@example.com' }, expiresAt: Date.now() + 60000, generation: '' });
    return worker.fetch(new Request('https://test/api/user/purchase', { method: 'POST', headers: { 'content-type': 'application/json', 'x-install-secret': e.SHARED_SECRET, authorization: `Bearer ${token}` }, body: JSON.stringify({ ...body, userId: id }) }), e);
  };
  await withApple(async () => Response.json({ signedTransactionInfo: await signed(data) }), async () => {
    for (let i = 0; i < 2; i++) { const response = await purchase('apple_test'); assert.equal(response.status, 200); const result = await response.json(); assert.equal(result.isPremium, true); assert.equal(result.premiumExpiresAt, new Date(data.expiresDate).toISOString()); }
    assert.equal((await purchase('apple_other')).status, 403); assert.equal(JSON.parse(records.get('user:apple_test')).verifiedPurchase.transactionId, '123'); assert.equal(records.has('user:apple_other'), false);
  });
});

async function statusResponse(data, status = 1, renewal) {
  return Response.json({ environment: data.environment, bundleId: data.bundleId,
    data: [{ lastTransactions: [{ originalTransactionId: data.originalTransactionId, status,
      signedTransactionInfo: await signed(data), ...(renewal ? { signedRenewalInfo: await signed(renewal) } : {}) }] }] });
}
test('restoring an expired period finds the renewed subscription and records latest transaction', async () => {
  const old = transaction({ expiresDate: Date.now() - 1000 });
  const renewed = transaction({ transactionId: '124' });
  await withApple(async url => new URL(url).pathname.includes('/subscriptions/') ? statusResponse(renewed) : Response.json({ signedTransactionInfo: await signed(old) }), async () => {
    const result = await verifyStorePurchase(body, env, 'apple_test');
    assert.equal(result.active, true); assert.equal(result.reference.transactionId, '124');
    assert.equal(result.expiresAt, new Date(renewed.expiresDate).toISOString());
  });
});
test('refresh uses current subscription status, respects expiry/refund and preserves admin grant on errors', async () => {
  const old = transaction(), renewed = transaction({ transactionId: '124', expiresDate: Date.now() + 90 * 86400000 });
  for (const status of [1, 2, 3, 5]) {
    const user = { id: 'apple_test', isPremium: true, premiumSource: 'appstore', verifiedPurchase: body };
    await withApple(async url => new URL(url).pathname.includes('/subscriptions/') ? statusResponse(renewed, status) : Response.json({ signedTransactionInfo: await signed(old) }), async () => {
      await refreshStoreEntitlement({ ...env, INSTALLS: { put: async () => {} } }, user);
      assert.equal(user.isPremium, status === 1); assert.equal(user.verifiedPurchase.transactionId, '124');
    });
  }
  const grant = { id: 'apple_test', isPremium: true, premiumSource: 'admin_grant', premiumExpiresAt: '2030-01-01', verifiedPurchase: body };
  await withApple(async () => { throw new Error('must not query store for an admin grant'); }, async () => {
    await refreshStoreEntitlement(env, grant); assert.equal(grant.isPremium, true); assert.equal(grant.premiumExpiresAt, '2030-01-01');
  });
});
test('grace period uses the verified grace expiry', async () => {
  const old = transaction(), expired = transaction({ expiresDate: Date.now() - 1000 });
  const grace = Date.now() + 86400000;
  await withApple(async url => new URL(url).pathname.includes('/subscriptions/') ? statusResponse(expired, 4, { originalTransactionId: '100', environment: 'Production', gracePeriodExpiresDate: grace }) : Response.json({ signedTransactionInfo: await signed(old) }), async () => {
    const result = await verifyStorePurchase(body, env, 'apple_test', { refresh: true });
    assert.equal(result.active, true); assert.equal(result.expiresAt, new Date(grace).toISOString());
  });
});
test('temporary status failure preserves existing entitlement without extending it', async () => {
  const user = { id: 'apple_test', isPremium: true, premiumSource: 'appstore', premiumExpiresAt: '2030-01-01', verifiedPurchase: body };
  await withApple(async url => new URL(url).pathname.includes('/subscriptions/') ? new Response('', { status: 503 }) : Response.json({ signedTransactionInfo: await signed(transaction()) }), async () => {
    await refreshStoreEntitlement(env, user); assert.equal(user.isPremium, true); assert.equal(user.premiumExpiresAt, '2030-01-01');
  });
});
test('status polling refreshes renewed subscription without restarting the app', async () => {
  const records = new Map();
  const old = transaction({ expiresDate: Date.now() - 1000 }), renewed = transaction({ transactionId: '124' });
  const e = { ...env, SHARED_SECRET: 'test-secret', SESSION_SECRET: 'test-session', INSTALLS: { get: async k => records.get(k) ?? null, put: async (k, v) => records.set(k, v) } };
  records.set('user:apple_test', JSON.stringify({ id: 'apple_test', isPremium: true, premiumSource: 'appstore', premiumExpiresAt: new Date(old.expiresDate).toISOString(), verifiedPurchase: body }));
  const token = await signSession(e, { user: { id: 'apple_test', email: 'test@example.com' }, expiresAt: Date.now() + 60000, generation: '' });
  await withApple(async url => new URL(url).pathname.includes('/subscriptions/') ? statusResponse(renewed) : Response.json({ signedTransactionInfo: await signed(old) }), async () => {
    const response = await worker.fetch(new Request('https://test/api/user/status', { headers: { 'x-install-secret': e.SHARED_SECRET, authorization: `Bearer ${token}` } }), e);
    assert.equal(response.status, 200);
    const data = await response.json();
    assert.equal(data.isPremium, true); assert.equal(data.premiumExpiresAt, new Date(renewed.expiresDate).toISOString());
    assert.equal(JSON.parse(records.get('user:apple_test')).verifiedPurchase.transactionId, '124');
  });
});

test('Apple renewal status is read even outside grace period', async () => {
  for (const value of [0, 1, undefined]) {
    const data = transaction();
    await withApple(async url => new URL(url).pathname.includes('/subscriptions/')
      ? statusResponse(data, 1, { originalTransactionId: '100', environment: 'Production', autoRenewStatus: value })
      : Response.json({ signedTransactionInfo: await signed(data) }), async () => {
      const result = await verifyStorePurchase(body, env, 'apple_test', { refresh: true });
      assert.equal(result.autoRenewEnabled, value === 1 ? true : value === 0 ? false : null);
      assert.equal(result.active, true);
    });
  }
});
