import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { sanitizeAnalyticsEvent } from './worker.js';
import { TrafficState, trafficRequest } from './traffic_state.js';
import { StatsBuffer } from './stats_buffer.js';
import { TelegramQueue } from './telegram_queue.js';
import { signSession } from './user_auth.js';
import { PurchaseClaims } from './purchase_claims.js';
import { generateKeyPair, exportPKCS8, SignJWT } from 'jose';

class Storage {
  data = new Map(); alarm = null;
  async get(k) { return structuredClone(this.data.get(k)); }
  async put(k, v) {
    if (typeof k === 'object') for (const [key, value] of Object.entries(k)) this.data.set(key, structuredClone(value));
    else this.data.set(k, structuredClone(v));
  }
  async delete(k) { for (const key of Array.isArray(k) ? k : [k]) this.data.delete(key); }
  async list({ prefix = '', limit = Infinity } = {}) {
    return new Map([...this.data].filter(([k]) => k.startsWith(prefix)).sort(([a], [b]) => a.localeCompare(b)).slice(0, limit).map(([k, v]) => [k, structuredClone(v)]));
  }
  async getAlarm() { return this.alarm; }
  async setAlarm(at) { this.alarm = at; }
  async deleteAlarm() { this.alarm = null; }
  async transaction(fn) {
    const previous = structuredClone(this.data);
    try { return await fn(this); } catch (e) { this.data = previous; throw e; }
  }
}
class KV {
  data = new Map(); failKey = null; writes = [];
  async get(key) { return this.data.get(key) ?? null; }
  async put(key, value) {
    this.writes.push(key);
    if (key === this.failKey) throw new Error('temporary KV failure');
    this.data.set(key, value);
  }
  async delete(key) { this.data.delete(key); }
}
function namespace(Class, env) {
  const objects = new Map();
  return {
    objects, idFromName: name => name,
    get(name) {
      if (!objects.has(name)) {
        const state = { storage: new Storage() };
        objects.set(name, { state, object: new Class(state, env) });
      }
      const record = objects.get(name);
      return { fetch: (url, options) => record.object.fetch(new Request(url, options)) };
    },
  };
}
function setup() {
  const env = { INSTALLS: new KV(), SHARED_SECRET: 'test-key', SESSION_SECRET: 'session-test', BOT_TOKEN: 'test-only', CHAT_ID: '-100test' };
  env.STATS = namespace(StatsBuffer, env);
  env.TELEGRAM = namespace(TelegramQueue, env);
  env.TRAFFIC = namespace(TrafficState, env);
  return env;
}
async function alarm(record) { record.state.storage.alarm = null; return record.object.alarm(); }
const queued = async (record, prefix = 'q:') => record.state.storage.list({ prefix });

test('store labels survive sanitation; arbitrary unsafe sources remain rejected', () => {
  for (const source of ['App Store', 'Google Play']) assert.equal(sanitizeAnalyticsEvent({ source }).source, source);
  assert.equal(sanitizeAnalyticsEvent({ source: '__proto__' }).source, 'direct');
  assert.equal(sanitizeAnalyticsEvent({ source: '<script>' }).source, 'direct');
});

test('1000 simultaneous store installations preserve unique numbers and all analytics, including retries', async () => {
  const e = setup();
  await e.INSTALLS.put('counter', '200');
  await e.INSTALLS.put('id:old', '17');
  const request = id => new Request('https://test/', { method: 'POST', headers: { 'content-type': 'application/json', 'x-install-secret': e.SHARED_SECRET }, body: JSON.stringify({ country: 'ru', platform: 'ios', source: 'App Store', device: 'iPhone 16', version: '2.1.3+50', install_id: id }) });
  const responses = await Promise.all(Array.from({ length: 1000 }, (_, i) => worker.fetch(request('i' + i), e).then(r => r.json())));
  assert.equal(new Set(responses.map(r => r.number)).size, 1000);
  assert.equal(Math.max(...responses.map(r => r.number)), 1200);
  assert.equal((await worker.fetch(request('i10'), e).then(r => r.json())).duplicate, true);
  assert.equal((await worker.fetch(request('old'), e).then(r => r.json())).number, 17);
  const counter = e.TRAFFIC.objects.get('counter');
  assert.equal((await queued(counter, 'out:')).size, 1000);
  // Failure AFTER stats accepted an event: the durable outbox retries it
  // without enqueuing the same event a second time.
  e.INSTALLS.failKey = 'counter';
  await assert.rejects(alarm(counter));
  e.INSTALLS.failKey = null;
  while ((await queued(counter, 'out:')).size) await alarm(counter);
  const stats = e.STATS.objects.get('main');
  assert.equal((await queued(stats)).size, 1000);
  await alarm(stats);
  const dayKey = [...e.INSTALLS.data.keys()].find(k => k.startsWith('day:'));
  const data = JSON.parse(e.INSTALLS.data.get(dayKey));
  assert.equal(data.installs, 1000);
  assert.equal(data.sources['App Store'].installs, 1000);
});

test('simultaneous scores import the old board, preserve totals and delete through both APIs', async () => {
  const e = setup(), key = 'game_lb:2026-W40';
  await e.INSTALLS.put(key, JSON.stringify({ old: { score: 33, runs: 1, best: 33 } }));
  await Promise.all(Array.from({ length: 300 }, (_, i) => trafficRequest(e, key, 'score', { userId: 'u' + i % 30, score: { delta: 7, newRun: true, runScore: 7 } })));
  const board = await trafficRequest(e, key, 'read');
  assert.equal(board.old.score, 33);
  for (let i = 0; i < 30; i++) { assert.equal(board['u' + i].score, 70); assert.equal(board['u' + i].runs, 10); }
  await trafficRequest(e, key, 'delete', { userId: 'u5' });
  assert.equal((await trafficRequest(e, key, 'read')).u5, undefined);
  assert.equal(e.INSTALLS.writes.filter(k => k === key).length, 1, 'no hot-path KV board writes');
  await alarm(e.TRAFFIC.objects.get(key));
  assert.equal(JSON.parse(await e.INSTALLS.get(key)).u5, undefined);
});

test('registrations use one atomic outbox and durable Telegram deduplication', async () => {
  const e = setup();
  const user = { id: 'apple_test', provider: 'apple', app: 'ru', platform: 'ios', name: 'Test' };
  const body = { installId: user.id, legacyKey: 'notified_reg:' + user.id, registrationUser: user };
  const result = await Promise.all(Array.from({ length: 20 }, () => trafficRequest(e, 'counter:registered_users', 'install', body)));
  assert.equal(result.filter(r => r.isNew).length, 1);
  await alarm(e.TRAFFIC.objects.get('counter:registered_users'));
  assert.equal((await queued(e.STATS.objects.get('main'))).size, 1);
  const queue = e.TELEGRAM.objects.get(e.CHAT_ID);
  assert.equal((await queued(queue)).size, 1);
  const duplicate = await e.TELEGRAM.get(e.CHAT_ID).fetch('https://telegram/enqueue', { method: 'POST', body: JSON.stringify({ text: 'retry', dedupKey: body.legacyKey }) });
  assert.equal((await duplicate.json()).duplicate, true);
  assert.equal((await queued(queue)).size, 1);
});

test('partial KV failure + worker restart replay the persisted totals exactly once, even with stale KV reads', async () => {
  const e = setup(), stub = e.STATS.get('main');
  const enqueue = id => stub.fetch('https://stats/enqueue', { method: 'POST', body: JSON.stringify({ id, kind: 'analytics', ts: Date.parse('2026-10-03T10:00:00Z'), event: { type: 'install', app: 'ru', source: 'App Store' } }) });
  await Promise.all([enqueue('one'), enqueue('two')]);
  const r = e.STATS.objects.get('main');
  e.INSTALLS.failKey = 'recent_events';
  await alarm(r);
  assert.ok(await r.state.storage.get('pending'));
  assert.equal((await queued(r)).size, 2);
  assert.equal(JSON.parse(await e.INSTALLS.get('day:2026-10-03')).installs, 2);
  e.INSTALLS.failKey = null;
  r.object = new StatsBuffer(r.state, e);
  await alarm(r);
  assert.equal((await queued(r)).size, 0);
  assert.equal(JSON.parse(await e.INSTALLS.get('day:2026-10-03')).installs, 2);
  await r.object.fetch(new Request('https://stats/enqueue', { method: 'POST', body: JSON.stringify({ id: 'three', kind: 'analytics', ts: Date.parse('2026-10-03T10:00:00Z'), event: { type: 'install', app: 'ru', source: 'Google Play' } }) }));
  await r.state.storage.put('lastWrite', 0);
  e.INSTALLS.get = async () => null; // stale edge cache must not reset counters
  await alarm(r);
  const day = JSON.parse(e.INSTALLS.data.get('day:2026-10-03'));
  assert.equal(day.installs, 3);
  assert.equal(day.sources['App Store'].installs, 2);
  assert.equal(day.sources['Google Play'].installs, 1);
});

test('Telegram 429 and temporary network failure preserve ordered messages and retry_after', async () => {
  const e = setup(), stub = e.TELEGRAM.get(e.CHAT_ID);
  for (const text of ['first', 'second']) assert.equal((await stub.fetch('https://telegram/enqueue', { method: 'POST', body: JSON.stringify({ text }) })).status, 200);
  const r = e.TELEGRAM.objects.get(e.CHAT_ID), original = globalThis.fetch, sent = [];
  try {
    globalThis.fetch = async () => Response.json({ ok: false, parameters: { retry_after: 90 } }, { status: 429 });
    const before = Date.now(); await alarm(r);
    assert.equal((await queued(r)).size, 2);
    assert.ok(r.state.storage.alarm >= before + 90000);
    globalThis.fetch = async () => { throw new Error('network unavailable'); };
    await alarm(r); assert.equal((await queued(r)).size, 2);
    r.object = new TelegramQueue(r.state, e);
    globalThis.fetch = async (_, opts) => { sent.push(JSON.parse(opts.body).text); return Response.json({ ok: true }); };
    await alarm(r); await alarm(r);
    assert.deepEqual(sent, ['first', 'second']);
    assert.equal((await queued(r)).size, 0);
  } finally { globalThis.fetch = original; }
});

test('authenticated leaderboard response and deletion retain compatibility with installed clients', async () => {
  const e = setup(), userId = 'apple_test';
  const token = await signSession(e, { user: { id: userId, provider: 'apple', email: '' }, expiresAt: Date.now() + 60000, generation: '' });
  const call = (path, body) => worker.fetch(new Request('https://test' + path, { method: body ? 'POST' : 'GET', headers: { authorization: 'Bearer ' + token, 'x-install-secret': e.SHARED_SECRET, 'content-type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}) }), e);
  const score = await call('/api/game/score', { userId, delta: 14, newRun: true, runScore: 14 });
  assert.equal(score.status, 200); const result = await score.json(); assert.equal(result.weekScore, 14);
  const board = await call('/api/game/leaderboard?userId=' + userId);
  assert.equal((await board.json()).me.score, 14);
  assert.equal((await call('/api/user/delete', { userId })).status, 200);
  assert.equal((await trafficRequest(e, 'game_lb:' + result.week, 'read'))[userId], undefined);
});


test('verified App Store purchase succeeds even when the Telegram queue is unavailable', async () => {
  const e = setup(), userId = 'apple_payment_test';
  const { privateKey } = await generateKeyPair('ES256', { extractable: true });
  Object.assign(e, { APPLE_IAP_PRIVATE_KEY: await exportPKCS8(privateKey), APPLE_IAP_KEY_ID: 'test-key', APPLE_IAP_ISSUER_ID: 'test-issuer' });
  e.PURCHASE_CLAIMS = namespace(PurchaseClaims, e);
  e.TELEGRAM = { idFromName: k => k, get: () => ({ fetch: async () => new Response('unavailable', { status: 503 }) }) };
  const productId = 'u.pdd.pddApp.premium.week';
  const expiresDate = Date.now() + 7 * 86400000;
  const transaction = { bundleId: 'ru.pdd.pddApp', productId, transactionId: '123', originalTransactionId: '100', environment: 'Production', expiresDate };
  const token = await signSession(e, { user: { id: userId, provider: 'apple', email: '' }, expiresAt: Date.now() + 60000, generation: '' });
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async url => {
      assert.equal(new URL(url).hostname, 'api.storekit.apple.com');
      return Response.json({ signedTransactionInfo: await new SignJWT(transaction).setProtectedHeader({ alg: 'ES256' }).sign(privateKey) });
    };
    const response = await worker.fetch(new Request('https://test/api/user/purchase', {
      method: 'POST', headers: { authorization: 'Bearer ' + token, 'x-install-secret': e.SHARED_SECRET, 'content-type': 'application/json' },
      body: JSON.stringify({ userId, store: 'appstore', country: 'ru', productId, transactionId: '123' }),
    }), e);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).isPremium, true);
    assert.equal(JSON.parse(await e.INSTALLS.get('user:' + userId)).premiumExpiresAt, new Date(expiresDate).toISOString());
    assert.equal(await e.INSTALLS.get('notified_purch:123'), null, 'a future restore can retry notification');
  } finally { globalThis.fetch = original; }
});

test('a failed initial KV read retains the queue and schedules retry without resetting totals', async () => {
  const e = setup(), stub = e.STATS.get('main');
  await stub.fetch('https://stats/enqueue', { method: 'POST', body: JSON.stringify({ kind: 'analytics', event: { type: 'view', app: 'ru' } }) });
  const record = e.STATS.objects.get('main'), get = e.INSTALLS.get.bind(e.INSTALLS);
  e.INSTALLS.get = async () => { throw new Error('KV unavailable'); };
  await alarm(record);
  assert.equal((await queued(record)).size, 1);
  assert.equal(e.INSTALLS.writes.length, 0);
  assert.ok(record.state.storage.alarm > Date.now());
  e.INSTALLS.get = get;
  await alarm(record);
  assert.equal((await queued(record)).size, 0);
});


test('updates never increment new installs or totals, with concurrent retries in all countries', async () => {
  for (const country of ['ru', 'by', 'rs']) {
    for (const useTraffic of [true, false]) {
      const e = setup(); if (!useTraffic) delete e.TRAFFIC;
      const counterKey = country === 'ru' ? 'counter' : 'counter:' + country;
      await e.INSTALLS.put(counterKey, '50');
      const call = (id, kind = 'update', version = '2.1.4+51') => worker.fetch(new Request('https://test/', {
        method: 'POST', headers: { 'content-type': 'application/json', 'x-install-secret': e.SHARED_SECRET },
        body: JSON.stringify({ install_id: id, kind, country, platform: 'ios', device: 'iPhone 16', source: 'App Store', version }),
      }), e).then(async r => { assert.equal(r.status, 200); return r.json(); });
      const updates = useTraffic
        ? await Promise.all(Array.from({ length: 50 }, (_, i) => call('update-' + i)))
        : [await call('update-0')];
      for (const update of updates) assert.equal(update.number, null);
      assert.equal((await call('update-0')).duplicate, true);
      for (const version of ['2.1.2+40', '2.1.3', '']) assert.equal((await call('old-' + version, 'update', version)).number, null);
      assert.equal((await call('fresh', 'new')).number, 51);
      assert.equal((await call('fresh', 'update')).duplicate, true);
      if (useTraffic) {
        assert.equal(await trafficRequest(e, counterKey, 'read'), 51);
        const r = e.TRAFFIC.objects.get(counterKey);
        while ((await queued(r, 'out:')).size) await alarm(r);
      } else assert.equal(Number(await e.INSTALLS.get(counterKey)), 51);
      const stats = e.STATS.objects.get('main'); await alarm(stats);
      const dayKey = [...e.INSTALLS.data.keys()].find(k => k.startsWith('day:'));
      const day = JSON.parse(e.INSTALLS.data.get(dayKey));
      assert.equal(day.installs, 1);
      assert.equal(day.returning, useTraffic ? 50 : 1);
      assert.equal(day.unclassified, 3);
      assert.equal(day.apps[country].installs, 1);
      const slotKey = [...e.INSTALLS.data.keys()].find(k => k.startsWith('slot:'));
      const slot = JSON.parse(e.INSTALLS.data.get(slotKey));
      assert.equal(slot.installs, 1);
      assert.equal(slot.unclassified, 3);
    }
  }
});

test('invalid installation IDs cannot inflate counters', async () => {
  const e = setup();
  for (const install_id of [undefined, '', 'x'.repeat(257)]) {
    const r = await worker.fetch(new Request('https://test/', { method: 'POST', headers: { 'content-type': 'application/json', 'x-install-secret': e.SHARED_SECRET }, body: JSON.stringify({ install_id, kind: 'new', country: 'ru', platform: 'ios', source: 'App Store', device: 'iPhone 16' }) }), e);
    assert.equal(r.status, 400);
  }
  assert.equal(e.TRAFFIC.objects.size, 0);
});


test('public ads configuration responds without undefined helpers and filters the saved store rules', async () => {
  const e = setup();
  let response = await worker.fetch(new Request('https://test/api/ads/config'), e);
  assert.equal(response.status, 200); assert.equal((await response.json()).enabled, false);
  await e.INSTALLS.put('ADS_CONFIG', JSON.stringify({ enabled: true, frequency: 5, storeRules: {
    appstore: { enabled: true, mode: 'custom_cards', yandexAdUnitId: '' },
    googleplay: { enabled: true, mode: 'yandex', yandexAdUnitId: 'test-ad-unit' },
  }, promoCards: [{ id: 'ios', platforms: ['ios'], stores: ['appstore'] }, { id: 'android', platforms: ['android'], stores: ['googleplay'] }, { id: 'off', enabled: false }] }));
  response = await worker.fetch(new Request('https://test/api/ads/config?platform=ios&store=appstore'), e);
  assert.equal(response.status, 200); let data = await response.json(); assert.equal(data.enabled, true); assert.equal(data.mode, 'custom_cards'); assert.deepEqual(data.promoCards.map(c => c.id), ['ios']);
  response = await worker.fetch(new Request('https://test/api/ads/config?platform=android&store=googleplay'), e);
  data = await response.json(); assert.equal(data.mode, 'yandex'); assert.deepEqual(data.promoCards.map(c => c.id), ['android']);
  response = await worker.fetch(new Request('https://test/api/ads/config?store=unknown'), e);
  assert.equal((await response.json()).enabled, false);
  await e.INSTALLS.put('ADS_CONFIG', 'invalid json');
  response = await worker.fetch(new Request('https://test/api/ads/config'), e);
  assert.equal(response.status, 200); assert.equal((await response.json()).enabled, false);
});


test('an hourly alarm inherited from the previous deployment is shortened on enqueue', async () => {
  const e = setup(), stub = e.STATS.get('main');
  const record = e.STATS.objects.get('main');
  await record.state.storage.setAlarm(Date.now() + 60 * 60000);
  const before = Date.now();
  await stub.fetch('https://stats/enqueue', { method: 'POST', body: JSON.stringify({ kind: 'analytics', event: { type: 'view', app: 'ru' } }) });
  assert.ok(record.state.storage.alarm <= before + 5 * 60000 + 100);
});
