import test from 'node:test';
import assert from 'node:assert/strict';
import { handlePlategaBalances } from './economy_platega.js';
import { handleEconomyAdmin, computeEconomyStats, DEFAULT_ECONOMY_CONFIG } from './economy_admin.js';
import worker from './worker.js';

const NOW = Date.parse('2026-11-04T14:30:00Z');
const credentials = { PLATEGA_MERCHANT_ID: crypto.randomUUID(), PLATEGA_SECRET: crypto.randomUUID() };
const providerBalances = [{ currency: 'RUB', amount: 123.45 }, { currency: 'USDT', amount: 8.23456789, frozenBalance: 1.5 }];
const request = (method = 'GET') => new Request('https://admin.example/api/admin/economy/platega', { method });

test('unconfigured Platega does not call the provider or report an updated balance', async () => {
  for (const env of [{}, { PLATEGA_MERCHANT_ID: credentials.PLATEGA_MERCHANT_ID }, { PLATEGA_SECRET: credentials.PLATEGA_SECRET }]) {
    const response = await handlePlategaBalances(env, { fetch() { assert.fail('provider must not be called'); } });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, configured: false, updatedAt: null, balances: [] });
  }
});

test('balance read makes one credentialed GET, preserves currencies and strips unrelated provider fields', async () => {
  let calls = 0;
  const response = await handlePlategaBalances(credentials, { now: NOW, fetch: async (url, options) => {
    calls++;
    assert.equal(url, 'https://app.platega.io/balance/all');
    assert.equal(options.method, 'GET');
    assert.equal(options.redirect, 'manual', 'credentials cannot follow an upstream redirect');
    assert.equal(options.body, undefined);
    assert.ok(options.signal instanceof AbortSignal);
    assert.equal(options.headers['X-MerchantId'], credentials.PLATEGA_MERCHANT_ID);
    assert.equal(options.headers['X-Secret'], credentials.PLATEGA_SECRET);
    return Response.json(providerBalances.map(row => ({ ...row, email: 'private@example.invalid', secret: credentials.PLATEGA_SECRET })));
  } });
  assert.equal(calls, 1);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await response.json(), { ok: true, configured: true, updatedAt: new Date(NOW).toISOString(), balances: providerBalances });
});

test('documented empty balances and negative balance amounts remain explicit valid values', async () => {
  for (const rows of [[], [{ currency: 'RUB', amount: -10 }], [{ currency: 'USDT', amount: 0, frozenBalance: 0 }]]) {
    const response = await handlePlategaBalances(credentials, { fetch: async () => Response.json(rows) });
    assert.equal(response.status, 200);
    assert.deepEqual((await response.json()).balances, rows);
  }
});

test('malformed responses fail without replacing balances by zero or accepting invented envelopes', async () => {
  const badResponses = [null, {}, { balances: providerBalances }, { amount: 10, currency: 'RUB' },
    [null], [[]], [{ amount: '10', currency: 'RUB' }], [{ amount: 10, currency: 'rub' }],
    [{ amount: 10, currency: '<script>' }], [{ amount: 10 }], [{ currency: 'RUB' }],
    [{ amount: 10, currency: 'USDT', frozenBalance: null }], [{ amount: 10, currency: 'USDT', frozenBalance: -1 }],
    [{ amount: 10, currency: 'RUB', frozenBalance: 1 }], [{ amount: 1, currency: 'RUB' }, { amount: 2, currency: 'RUB' }]];
  for (const body of badResponses) {
    const response = await handlePlategaBalances(credentials, { fetch: async () => Response.json(body) });
    assert.equal(response.status, 502, JSON.stringify(body));
    const result = await response.json();
    assert.equal(result.ok, false);
    assert.equal(result.code, 'platega_invalid_response');
    assert.equal(Object.hasOwn(result, 'balances'), false);
    assert.equal(Object.hasOwn(result, 'updatedAt'), false);
  }
  for (const amount of [NaN, Infinity, -Infinity]) {
    const response = await handlePlategaBalances(credentials, { fetch: async () => ({ ok: true, status: 200, json: async () => [{ amount, currency: 'USDT' }] }) });
    assert.equal(response.status, 502);
  }
  const invalidJson = await handlePlategaBalances(credentials, { fetch: async () => new Response('private internal response') });
  assert.equal(invalidJson.status, 502);
  assert.equal((await invalidJson.text()).includes('private internal response'), false);
});

test('provider HTTP and network failures return safe errors, with no balances or credentials', async () => {
  for (const [status, code] of [[401, 'platega_auth'], [403, 'platega_auth'], [429, 'platega_rate_limited'], [500, 'platega_unavailable'], [404, 'platega_unavailable'], [302, 'platega_unavailable']]) {
    const response = await handlePlategaBalances(credentials, { fetch: async () => new Response(credentials.PLATEGA_SECRET, { status }) });
    assert.equal(response.status, 503);
    const result = await response.json();
    assert.equal(result.code, code);
    assert.equal(Object.hasOwn(result, 'balances'), false);
    assert.equal(JSON.stringify(result).includes(credentials.PLATEGA_SECRET), false);
  }
  for (const name of ['AbortError', 'TimeoutError', 'TypeError']) {
    const error = new Error(credentials.PLATEGA_SECRET);
    error.name = name;
    const response = await handlePlategaBalances(credentials, { fetch: async () => { throw error; } });
    assert.equal(response.status, 503);
    const result = await response.json();
    assert.equal(result.code, name === 'TypeError' ? 'platega_unavailable' : 'platega_timeout');
    assert.equal(JSON.stringify(result).includes(credentials.PLATEGA_SECRET), false);
    assert.equal(Object.hasOwn(result, 'updatedAt'), false);
  }
});

test('the route is read-only and does not change the ledger or profit', async () => {
  const config = JSON.stringify({ ...DEFAULT_ECONOMY_CONFIG, cloudflareEnabled: false, domainEnabled: false });
  const env = { ...credentials, INSTALLS: {
    async get(key) { return key === 'economy_config' ? config : null; },
    async list() { return { keys: [], list_complete: true }; },
    async put() { assert.fail('balances must not write the ledger'); },
  } };
  const before = await computeEconomyStats(env, 'month', { now: NOW, fx: {rubPerUsd:95,effectiveDate:'2026-11-04'} });
  const get = request();
  const response = await handleEconomyAdmin(get, env, new URL(get.url), { now: NOW, fetch: async () => Response.json(providerBalances) });
  assert.equal(response.status, 200);
  assert.deepEqual(await computeEconomyStats(env, 'month', { now: NOW, fx: {rubPerUsd:95,effectiveDate:'2026-11-04'} }), before);
  for (const method of ['POST', 'DELETE', 'PUT']) {
    const req = request(method);
    const denied = await handleEconomyAdmin(req, env, new URL(req.url), { fetch() { assert.fail('unsupported method reached provider'); } });
    assert.equal(denied.status, 404);
  }
});

test('full Worker route rejects anonymous clients before any provider call and allows authenticated reads', async () => {
  const adminPassword = crypto.randomUUID();
  let calls = 0;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    calls++;
    assert.equal(String(url), 'https://app.platega.io/balance/all');
    assert.equal(options.method, 'GET');
    return Response.json(providerBalances);
  };
  try {
    const env = { ...credentials, ADMIN_PASSWORD: adminPassword, INSTALLS: { async get() { return null; }, async put() { assert.fail('unexpected KV write'); } } };
    const anonymous = await worker.fetch(request(), env, { waitUntil() {} });
    assert.equal(anonymous.status, 401);
    assert.equal(calls, 0);
    const wrong = new Request(request(), { headers: { Authorization: 'Bearer wrong' } });
    assert.equal((await worker.fetch(wrong, env, { waitUntil() {} })).status, 401);
    assert.equal(calls, 0);
    const authorized = new Request(request(), { headers: { Authorization: `Bearer ${adminPassword}` } });
    const response = await worker.fetch(authorized, env, { waitUntil() {} });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.deepEqual(body.balances, providerBalances);
    assert.equal(body.configured, true);
    assert.equal(calls, 1);
    for (const secret of [credentials.PLATEGA_SECRET, credentials.PLATEGA_MERCHANT_ID, adminPassword]) assert.equal(JSON.stringify(body).includes(secret), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
