import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, exportJWK, exportPKCS8, SignJWT } from 'jose';
import worker from './worker.js';
import { handleAuth, readSession, revokeUserSessions, verifyIdentity, tokenHash, signSession } from './user_auth.js';
import { googleEntitlement, verifyStorePurchase, claimPurchase } from './store_verification.js';
import { PurchaseClaims } from './purchase_claims.js';
class KV {
  data = new Map();
  async get(k) { return this.data.get(k) ?? null; }
  async put(k, v) { this.data.set(k, String(v)); }
  async delete(k) { this.data.delete(k); }
}
const env = () => ({ INSTALLS: new KV(), SHARED_SECRET: 'test-key', SESSION_SECRET: 'session-test-secret' });
const request = (path, body, token, key = 'test-key') => new Request('https://app.test' + path, {
  method: body === undefined ? 'GET' : 'POST',
  headers: { 'content-type': 'application/json', ...(key ? { 'x-install-secret': key } : {}), ...(token ? { authorization: 'Bearer ' + token } : {}) },
  ...(body === undefined ? {} : { body: JSON.stringify(body) }),
});
async function login(e) {
  const response = await handleAuth(request('/api/auth/session', {}), e, async () => ({ id: 'google_123', name: 'Test', email: 'test@example.com', provider: 'google', createdAt: new Date().toISOString() }));
  assert.equal(response.status, 200); return response.json();
}
test('session issuing fails closed without key or valid identity', async () => {
  assert.equal((await handleAuth(request('/api/auth/session', {}, null, null), env())).status, 403);
  assert.equal((await handleAuth(request('/api/auth/session', { provider: 'debug', credential: 'debug_tester' }), env())).status, 401);
  const e = env(); delete e.SHARED_SECRET;
  assert.equal((await handleAuth(request('/api/auth/session', {}), e)).status, 403);
});
test('OAuth verifies signature, audience, issuer, expiry', async () => {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const jwk = { ...await exportJWK(publicKey), kid: 'test-key', alg: 'RS256', use: 'sig' };
  const original = globalThis.fetch;
  globalThis.fetch = async url => { assert.equal(String(url), 'https://www.googleapis.com/oauth2/v3/certs'); return Response.json({ keys: [jwk] }); };
  try {
    const make = (aud = 'test-client', iss = 'https://accounts.google.com', exp = '5m') => new SignJWT({ email: 'test@example.com', email_verified: true })
      .setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setSubject('123').setAudience(aud).setIssuer(iss).setIssuedAt().setExpirationTime(exp).sign(privateKey);
    const good = await make();
    assert.equal((await verifyIdentity({ provider: 'google', credential: good }, { GOOGLE_CLIENT_IDS: 'test-client' })).id, 'google_123');
    for (const bad of [await make('wrong'), await make('test-client', 'https://evil.example'), await make('test-client', 'https://accounts.google.com', '-5m'), good.slice(0, -20) + 'invalid']) {
      await assert.rejects(verifyIdentity({ provider: 'google', credential: bad }, { GOOGLE_CLIENT_IDS: 'test-client' }));
    }
  } finally { globalThis.fetch = original; }
});
test('Yandex checks the OAuth client', async () => {
  const original = globalThis.fetch; globalThis.fetch = async () => Response.json({ id: '123', client_id: 'another-client' });
  try { await assert.rejects(verifyIdentity({ provider: 'yandex', credential: 'token' }, {})); }
  finally { globalThis.fetch = original; }
});
test('private APIs reject anonymous and cross-account requests', async () => {
  const e = env(), session = await login(e);
  for (const [path, body] of [
    ['/api/user/progress?userId=google_123', undefined], ['/api/user/status?id=google_123', undefined], ['/api/user/delete', { userId: 'google_123' }],
    ['/api/user/sync', { id: 'google_123' }], ['/api/user/purchase', { userId: 'google_123' }], ['/api/game/score', { userId: 'google_123', score: 100 }],
  ]) {
    assert.equal((await worker.fetch(request(path, body), e)).status, 401, path);
    assert.equal((await worker.fetch(request(path.replace('google_123', 'google_other'), body === undefined ? undefined : { ...body, userId: 'google_other' }, session.token), e)).status, 403, path);
  }
  assert.equal((await worker.fetch(request('/api/user/progress?userId=google_123', undefined, session.token), e)).status, 200);
});
test('self-deletion removes profile, progress and current score and revokes access', async () => {
  const e = env(), session = await login(e), id = 'google_123';
  const boardResponse = await worker.fetch(request('/api/game/leaderboard'), e);
  const { week } = await boardResponse.json();
  await e.INSTALLS.put('user:' + id, JSON.stringify({ id, email: 'test@example.com', isPremium: true }));
  await e.INSTALLS.put('user_email:test@example.com', id);
  await e.INSTALLS.put('user_progress:' + id, JSON.stringify({ game: { best: 100 }, favorites: [1] }));
  await e.INSTALLS.put('users_list', JSON.stringify([id, 'other']));
  await e.INSTALLS.put('game_lb:' + week, JSON.stringify({ [id]: { score: 100 }, other: { score: 50 } }));
  const response = await worker.fetch(request('/api/user/delete', { userId: id }, session.token), e);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true, deleted: id });
  for (const key of ['user:' + id, 'user_progress:' + id, 'user_email:test@example.com']) {
    assert.equal(await e.INSTALLS.get(key), null, key);
  }
  assert.deepEqual(JSON.parse(await e.INSTALLS.get('users_list')), ['other']);
  assert.deepEqual(JSON.parse(await e.INSTALLS.get('game_lb:' + week)), { other: { score: 50 } });
  assert.equal(await readSession(request('/api/user/progress', undefined, session.token), e), null);
});
test('profile sync cannot forge identity or premium', async () => {
  const e = env(), session = await login(e);
  const response = await worker.fetch(request('/api/user/sync', { id: 'google_123', email: 'victim@example.com', provider: 'apple', isPremium: true, premiumExpiresAt: '2099-01-01T00:00:00Z' }, session.token), e);
  assert.equal(response.status, 200);
  const data = await response.json(); assert.equal(data.user.email, 'test@example.com'); assert.equal(data.user.provider, 'google'); assert.equal(data.isPremium, false);
});
test('expired, revoked and logged-out sessions are denied', async () => {
  const e = env(), session = await login(e);
  assert.ok(await readSession(request('/api/user/progress', undefined, session.token), e));
  await revokeUserSessions(e, 'google_123');
  assert.equal(await readSession(request('/api/user/progress', undefined, session.token), e), null);
  // Signed sessions: no KV write on sign-in; forged or tampered tokens fail.
  const fresh = await login(e);
  assert.ok(fresh.token.startsWith('v1.'));
  const [v, payload, sig] = fresh.token.split('.');
  const forgedSig = v + '.' + payload + '.' + (sig[0] === 'a' ? 'b' : 'a') + sig.slice(1);
  assert.equal(await readSession(request('/api/user/progress', undefined, forgedSig), e), null);
  const other = JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/'))); other.user.id = 'google_victim';
  const tampered = v + '.' + btoa(JSON.stringify(other)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '') + '.' + sig;
  assert.equal(await readSession(request('/api/user/progress', undefined, tampered), e), null);
  const expired = await signSession(e, { user: { id: 'google_123' }, expiresAt: Date.now() - 1, generation: '' });
  assert.equal(await readSession(request('/api/user/progress', undefined, expired), e), null);
  // Without the session secret no sessions are issued at all.
  const noSecret = { ...e, SESSION_SECRET: undefined };
  assert.equal((await handleAuth(request('/api/auth/session', {}), noSecret, async () => ({ id: 'google_123' }))).status, 503);
});
const productId = 'ru.pdd.pddapp.premium.week';
const subscription = (state = 'ACTIVE') => ({ subscriptionState: 'SUBSCRIPTION_STATE_' + state, lineItems: [{ productId, expiryTime: '2030-01-01T00:00:00Z' }] });
test('replayed restore preserves store expiry rather than extending it', () => {
  const data = subscription();
  assert.equal(googleEntitlement(data, productId, Date.parse('2026-01-01')).expiresAt, googleEntitlement(data, productId, Date.parse('2027-01-01')).expiresAt);
  assert.equal(googleEntitlement(data, productId, Date.parse('2031-01-01')).active, false);
});
test('subscription lifecycle states enforce entitlement', () => {
  for (const state of ['ON_HOLD', 'PENDING', 'PAUSED', 'EXPIRED', 'PENDING_PURCHASE_CANCELED']) assert.equal(googleEntitlement(subscription(state), productId).active, false);
  for (const state of ['ACTIVE', 'CANCELED', 'IN_GRACE_PERIOD']) assert.equal(googleEntitlement(subscription(state), productId).active, true);
  assert.throws(() => googleEntitlement(subscription(), 'wrong-product'));
});
test('unconfigured store and unknown product cannot grant premium', async () => {
  await assert.rejects(verifyStorePurchase({ store: 'googleplay', country: 'ru', productId, purchaseToken: 'token', expiresAt: '2099-01-01' }, {}, 'google_123'));
  await assert.rejects(verifyStorePurchase({ store: 'googleplay', country: 'ru', productId: 'fake', purchaseToken: 'token' }, {}, 'google_123'));
  const e = env(), session = await login(e);
  const response = await worker.fetch(request('/api/user/purchase', { userId: 'google_123', store: 'googleplay', country: 'ru', productId, purchaseToken: 'token', expiresAt: '2099-01-01' }, session.token), e);
  assert.equal(response.status, 503); assert.equal(await e.INSTALLS.get('user:google_123'), null);
});
test('Google verification ignores supplied expiry and validates account binding', async () => {
  const { privateKey } = await generateKeyPair('RS256', { extractable: true });
  const e = { GOOGLE_PLAY_SERVICE_ACCOUNT: JSON.stringify({ client_email: 'test@service.example', private_key: await exportPKCS8(privateKey) }) };
  const original = globalThis.fetch; let accountId = await tokenHash('google_123');
  globalThis.fetch = async url => {
    if (String(url) === 'https://oauth2.googleapis.com/token') return Response.json({ access_token: 'test-server-token', expires_in: 3600 });
    assert.ok(String(url).startsWith('https://androidpublisher.googleapis.com/androidpublisher/v3/applications/ru.pdd.pdd_app/purchases/subscriptionsv2/tokens/'));
    return Response.json({ ...subscription(), externalAccountIdentifiers: { obfuscatedExternalAccountId: accountId } });
  };
  try {
    const body = { store: 'googleplay', country: 'ru', productId, purchaseToken: 'receipt', expiresAt: '2099-01-01' };
    assert.equal((await verifyStorePurchase(body, e, 'google_123')).expiresAt, '2030-01-01T00:00:00.000Z');
    accountId = 'wrong-account'; await assert.rejects(verifyStorePurchase(body, e, 'google_123'), /another account/);
  } finally { globalThis.fetch = original; }
});
test('concurrent receipt claims cannot transfer ownership', async () => {
  const data = new Map(); let queue = Promise.resolve();
  const txn = { get: async k => data.get(k), put: async (k, v) => data.set(k, v) };
  const object = new PurchaseClaims({ storage: { transaction: fn => { const next = queue.then(() => fn(txn)); queue = next.catch(() => {}); return next; } } });
  const e = { PURCHASE_CLAIMS: { idFromName: k => k, get: () => ({ fetch: (url, options) => object.fetch(new Request(url, options)) }) } };
  const result = await Promise.allSettled([claimPurchase(e, 'google_a', { key: 'same' }), claimPurchase(e, 'google_b', { key: 'same' })]);
  assert.equal(result.filter(r => r.status === 'fulfilled').length, 1); assert.equal(result.filter(r => r.status === 'rejected').length, 1);
  await claimPurchase(e, 'google_a', { key: 'same' });
});

test('status lookup by email cannot reveal another account', async () => {
  const e = env(), session = await login(e);
  assert.equal((await worker.fetch(request('/api/user/status?email=victim@example.com', undefined, session.token), e)).status, 403);
});
