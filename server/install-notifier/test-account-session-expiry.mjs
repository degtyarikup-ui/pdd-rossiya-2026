import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { accountRead, accountWrite } from './account_state.js';
import { readSession, signSession, tokenHash } from './user_auth.js';
import { fixture, identity, request } from './fixture-account.mjs';

const userId = 'google_123';
const revokedKey = async token => 'revoked_session:' + userId + ':' + await tokenHash(token);
const signed = (env, expiresAt) => signSession(env, { user: identity(), expiresAt, generation: '' });

test('verified signed-session expiry reaches private read-many and bounds a missing revocation record', async () => {
  const { env, states } = fixture();
  const expiresAt = Date.now() + 3600000;
  const token = await signed(env, expiresAt), calls = [];
  const originalGet = env.ACCOUNTS.get.bind(env.ACCOUNTS);
  env.ACCOUNTS.get = id => ({ fetch: async (input, options) => {
    const incoming = typeof input === 'string' ? new Request(input, options) : input;
    calls.push({ path: new URL(incoming.url).pathname, body: await incoming.clone().json() });
    return originalGet(id).fetch(incoming);
  } });

  const session = await readSession(request('/api/user/status', undefined, token), env);
  assert.equal(session.expiresAt, expiresAt);
  const rpc = calls.find(call => call.path === '/_account/read-many');
  assert.equal(rpc.body.options.sessionExpiresAt, expiresAt);
  const storage = states.get(userId);
  const negative = await storage.get('doc:' + await revokedKey(token));
  assert.equal(negative.value, null);
  assert.equal(negative.expiresAt, expiresAt);
  assert.ok(await storage.getAlarm());
  assert.equal((await storage.get('doc:auth_generation:' + userId)).expiresAt, undefined);
});

test('routed account authorization bounds its negative revocation cache using signed expiry', async () => {
  const { env, states } = fixture();
  const expiresAt = Date.now() + 3600000;
  const token = await signed(env, expiresAt);
  const response = await worker.fetch(request('/api/user/progress?userId=' + userId, undefined, token), env);
  assert.equal(response.status, 200);
  const record = await states.get(userId).get('doc:' + await revokedKey(token));
  assert.equal(record.value, null);
  assert.equal(record.expiresAt, expiresAt);
});

test('legacy verified session passes its stored expiry and expired credentials allocate no account', async () => {
  const { env, states } = fixture();
  const expiresAt = Date.now() + 3600000, token = 'a'.repeat(64);
  await env.INSTALLS.put('auth_session:' + await tokenHash(token), JSON.stringify({ user: identity(), expiresAt, generation: '' }));
  assert.equal((await readSession(request('/api/user/status', undefined, token), env)).expiresAt, expiresAt);
  assert.equal((await states.get(userId).get('doc:' + await revokedKey(token))).expiresAt, expiresAt);

  const expired = fixture();
  const expiredToken = await signed(expired.env, Date.now() - 1);
  assert.equal(await readSession(request('/api/user/status', undefined, expiredToken), expired.env), null);
  assert.equal(expired.states.size, 0);
  const validToken = await signed(expired.env, Date.now() + 3600000);
  const tampered = validToken.slice(0, -1) + (validToken.endsWith('0') ? '1' : '0');
  assert.equal(await readSession(request('/api/user/status', undefined, tampered), expired.env), null);
  assert.equal(expired.states.size, 0, 'unverified session metadata must never reach account storage');
});

test('reading an old permanent negative revocation record repairs its expiry and survives restart', async () => {
  const { env, states, restart } = fixture();
  const expiresAt = Date.now() + 3600000, token = await signed(env, expiresAt);
  await accountRead(env, userId, 'auth_generation:' + userId);
  const key = await revokedKey(token), storage = states.get(userId);
  await storage.put('doc:' + key, { key, value: null, options: {}, epoch: '1' });
  assert.ok(await readSession(request('/api/user/status', undefined, token), env));
  assert.equal((await storage.get('doc:' + key)).expiresAt, expiresAt);
  restart(userId);
  assert.ok(await readSession(request('/api/user/status', undefined, token), env));
  assert.equal((await storage.get('doc:' + key)).expiresAt, expiresAt);
});

test('a hintless private read never creates a permanent missing-revocation document', async () => {
  const { env, states } = fixture();
  const key = 'revoked_session:' + userId + ':' + 'c'.repeat(64);
  assert.equal(await accountRead(env, userId, key), null);
  assert.equal(await states.get(userId).get('doc:' + key), undefined);
});

test('imported active revocation retains its absolute expiry and rejects the credential', async () => {
  const { env, states } = fixture();
  const expiresAt = Date.now() + 3600000, token = await signed(env, expiresAt), key = await revokedKey(token);
  await env.INSTALLS.put(key, String(expiresAt));
  assert.equal(await readSession(request('/api/user/status', undefined, token), env), null);
  const record = await states.get(userId).get('doc:' + key);
  assert.equal(record.value, String(expiresAt));
  assert.equal(record.expiresAt, expiresAt);
});

test('logout updates a previously negative record immediately and stale KV cannot authorize it after restart', async () => {
  const { env, states, restart } = fixture();
  const expiresAt = Date.now() + 3600000, token = await signed(env, expiresAt), key = await revokedKey(token);
  assert.ok(await readSession(request('/api/user/status', undefined, token), env));
  assert.equal((await states.get(userId).get('doc:' + key)).value, null);
  assert.equal((await worker.fetch(request('/api/auth/logout', {}, token), env)).status, 200);

  const originalGet = env.INSTALLS.get.bind(env.INSTALLS);
  env.INSTALLS.get = (candidate, options) => candidate === key ? null : originalGet(candidate, options);
  restart(userId);
  assert.equal(await readSession(request('/api/user/status', undefined, token), env), null);
  assert.equal((await states.get(userId).get('doc:' + key)).value, String(expiresAt));
});

test('revocation expiry cleanup preserves generation, deletion and financial tombstones', async () => {
  const { env, states, objects } = fixture();
  const permanent = new Map([
    ['auth_generation:' + userId, 'generation-after-delete'],
    ['account_deleted:' + userId, JSON.stringify({ deletedAt: '2026-10-24T00:00:00Z' })],
    ['payment_ledger:fixture-order', JSON.stringify({ orderId: 'fixture-order', credited: true })],
  ]);
  for (const [key, value] of permanent) await accountWrite(env, userId, key, value);
  const key = 'revoked_session:' + userId + ':' + 'b'.repeat(64), storage = states.get(userId);
  await env.INSTALLS.put(key, String(Date.now() - 1000));
  await storage.put('doc:' + key, { key, value: String(Date.now() - 1000), expiresAt: Date.now() - 1000, options: {}, epoch: '1' });
  await objects.get(userId).expireRecords();
  assert.equal(await storage.get('doc:' + key), undefined);
  await objects.get(userId).flush();
  assert.equal(await env.INSTALLS.get(key), null);
  for (const [persistentKey, value] of permanent) {
    const record = await storage.get('doc:' + persistentKey);
    assert.equal(record.value, value);
    assert.equal(record.expiresAt, undefined);
  }
});

test('cleanup removes historical negative and expired revocation records but retains an active old-format revocation', async () => {
  const { env, states, objects } = fixture();
  await accountRead(env, userId, 'auth_generation:' + userId);
  const storage = states.get(userId), prefix = 'revoked_session:' + userId + ':';
  const negativeKey = prefix + 'd'.repeat(64), expiredKey = prefix + 'e'.repeat(64), activeKey = prefix + 'f'.repeat(64);
  const expiresAt = Date.now() + 3600000;
  for (const [key, value] of [[negativeKey, null], [expiredKey, String(Date.now() - 1000)], [activeKey, String(expiresAt)]]) {
    await storage.put('doc:' + key, { key, value, options: {}, epoch: '1' });
    if (value !== null) await env.INSTALLS.put(key, value);
  }
  assert.equal(await objects.get(userId).expireRecords(), expiresAt);
  assert.equal(await storage.get('doc:' + negativeKey), undefined);
  assert.equal(await storage.get('doc:' + expiredKey), undefined);
  assert.equal((await storage.get('doc:' + activeKey)).value, String(expiresAt));
  await objects.get(userId).flush();
  assert.equal(await env.INSTALLS.get(expiredKey), null);
  assert.equal(await env.INSTALLS.get(activeKey), String(expiresAt));
});

test('old-epoch cleanup markers cannot delete a newer KV revocation during a handoff', async () => {
  const { env, states, objects } = fixture();
  const expiresAt = Date.now() + 3600000, token = await signed(env, expiresAt), key = await revokedKey(token);
  await accountRead(env, userId, 'auth_generation:' + userId);
  const storage = states.get(userId);
  await storage.put('doc:' + key, { key, value: null, options: {}, epoch: '1' });
  await storage.put('projection:' + key, { key, deleted: true, epoch: '1' });
  await env.INSTALLS.put(key, String(expiresAt));
  env.ACCOUNT_STATE_EPOCH = '2';
  await objects.get(userId).expireRecords();
  assert.equal((await storage.get('doc:' + key)).epoch, '1', 'expiry must leave stale source documents for re-import');
  await objects.get(userId).flush();
  assert.equal(await env.INSTALLS.get(key), String(expiresAt));
  assert.equal(await readSession(request('/api/user/status', undefined, token), env), null);
  const record = await storage.get('doc:' + key);
  assert.equal(record.epoch, '2');
  assert.equal(record.value, String(expiresAt));
});
