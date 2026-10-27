import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { flushBufferedStats } from './worker.js';
import { StatsBuffer } from './stats_buffer.js';
import { usageSnapshot } from './usage_analytics.js';
import { ANALYTICS_CLIENT_JS, ANALYTICS_VIEW_HTML } from './analytics_ui.js';

class Storage {
  data = new Map(); alarm = null;
  async get(k) { return structuredClone(this.data.get(k)); }
  async put(k, v) { this.data.set(k, structuredClone(v)); }
  async delete(k) { for (const key of Array.isArray(k) ? k : [k]) this.data.delete(key); }
  async list({ prefix = '', limit = Infinity } = {}) {
    return new Map([...this.data].filter(([k]) => k.startsWith(prefix)).sort().slice(0, limit));
  }
  async getAlarm() { return this.alarm; }
  async setAlarm(at) { this.alarm = at; }
  async deleteAlarm() { this.alarm = null; }
  async transaction(fn) { return fn(this); }
}
function setup() {
  const kv = new Map(), writes = [], state = { storage: new Storage() };
  const env = { SHARED_SECRET: 'test', ADMIN_PASSWORD: 'pw', INSTALLS: {
    get: async k => kv.get(k) ?? null,
    list: async () => ({ keys: [], list_complete: true }),
    put: async (k, v) => { writes.push(k); kv.set(k, v); },
  } };
  const buffer = new StatsBuffer(state, env);
  env.STATS = { idFromName: s => s, get: () => ({ fetch: (u, o) => buffer.fetch(new Request(u, o)) }) };
  const post = (body, secret = 'test') => worker.fetch(new Request('https://w.test/api/usage', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-install-secret': secret }, body: JSON.stringify(body),
  }), env);
  const body = { installId: 'a'.repeat(32), platform: 'android', events: [{ id: 'b'.repeat(32), feature: 'tickets', ts: Date.now() }] };
  return { env, buffer, state, kv, writes, post, body };
}

test('usage acceptance is durable, repeated delivery counts once and uses only day KV writes', async () => {
  const { post, body, buffer, state, kv, writes } = setup();
  assert.equal((await post(body)).status, 200);
  assert.equal((await post(body)).status, 200);
  assert.equal((await state.storage.list({ prefix: 'q:' })).size, 1);
  assert.equal(writes.length, 0);
  assert.equal(await buffer.flush(), true);
  assert.equal(writes.length, 1);
  assert.ok(writes[0].startsWith('day:'));
  const saved = JSON.parse([...kv.values()][0]);
  assert.equal(saved.usage.tickets.starts, 1);
  assert.equal(Object.keys(saved.usage.tickets.installations).length, 1);
  assert.ok(!JSON.stringify(saved).includes(body.installId));
  assert.equal(saved.installs, 0);
  assert.equal((await post(body)).status, 200);
  assert.equal((await state.storage.list({ prefix: 'q:' })).size, 0);
});

test('current Flutter iOS payload is accepted and stored with canonical platform', async () => {
  const { post, body, state, writes } = setup();
  const response = await post({ ...body, platform: 'iOS' });
  assert.equal(response.status, 200);
  const queued = [...(await state.storage.list({ prefix: 'q:' })).values()];
  assert.equal(queued.length, 1);
  assert.equal(queued[0].platform, 'ios');
  assert.equal(queued[0].feature, body.events[0].feature);
  assert.equal(writes.length, 0);
});

test('platform compatibility does not accept unknown names or write rejected batches', async () => {
  const { post, body, state, writes } = setup();
  for (const platform of ['IOS', 'macOS', 'Android', 'unknown', '', null]) {
    const response = await post({ ...body, platform });
    assert.equal(response.status, 400, String(platform));
    assert.equal((await response.json()).error, 'bad usage batch');
  }
  assert.equal((await state.storage.list({ prefix: 'q:' })).size, 0);
  assert.equal(state.storage.data.size, 0);
  assert.equal(writes.length, 0);
});

test('usage API rejects invalid, future, stale and unsigned batches before accepting any event', async () => {
  const { post, body, state } = setup();
  assert.equal((await post(body, '')).status, 401);
  assert.equal((await post(body, 'wrong')).status, 401);
  for (const invalid of [
    { ...body, installId: '__proto__' }, { ...body, platform: 'fake' },
    { ...body, events: [] }, { ...body, events: Array(51).fill(body.events[0]) },
    { ...body, events: [...body.events, { ...body.events[0], feature: '__proto__' }] },
    { ...body, events: [{ ...body.events[0], ts: Date.now() + 3600000 }] },
    { ...body, events: [{ ...body.events[0], ts: Date.now() - 91 * 86400000 }] },
  ]) assert.equal((await post(invalid)).status, 400);
  assert.equal((await state.storage.list({ prefix: 'q:' })).size, 0);
});

test('usage uniques are a period union, Moscow midnight is respected, raw IDs stay out of admin API', async () => {
  const env = setup().env;
  const ids = ['c'.repeat(32), 'd'.repeat(32)];
  const events = [
    { installation: ids[0], ts: Date.parse('2026-10-08T20:59:00Z'), feature: 'game' },
    { installation: ids[0], ts: Date.parse('2026-10-08T21:01:00Z'), feature: 'game' },
    { installation: ids[1], ts: Date.parse('2026-10-08T21:02:00Z'), feature: 'game' },
  ].map(e => ({ ...e, kind: 'usage', platform: 'android' }));
  await flushBufferedStats(env, events);
  const days = [];
  for (const date of ['2026-10-07', '2026-10-08', '2026-10-09']) days.push({ date, data: JSON.parse(await env.INSTALLS.get('day:' + date) || 'null') });
  const snapshot = usageSnapshot(days);
  assert.deepEqual(snapshot.features.game, { starts: 3, installations: 2 });
  assert.deepEqual(snapshot.timeline.map(d => d.features.game.installations), [null, 1, 2]);
  assert.ok(ids.every(id => !JSON.stringify(snapshot).includes(id)));
  assert.equal(usageSnapshot(days, 'by').features.game.starts, 0);
  const response = await worker.fetch(new Request('https://w.test/api/admin/stats?days=1', { headers: { authorization: 'Bearer pw' } }), env);
  assert.equal(response.status, 200);
  const stats = await response.json();
  assert.ok(stats.usage.features.tickets);
  assert.ok(ids.every(id => !JSON.stringify(stats).includes(id)));
});

test('usage does not replace existing counters when flushed together with other analytics', async () => {
  const { env } = setup();
  await flushBufferedStats(env, [
    { kind: 'analytics', event: { type: 'view', app: 'ru' } },
    { kind: 'usage', feature: 'feed', installation: 'e'.repeat(32) },
  ]);
  const date = new Date(Date.now() + 3 * 3600000).toISOString().slice(0, 10);
  const day = JSON.parse(await env.INSTALLS.get('day:' + date));
  assert.equal(day.views, 1);
  assert.equal(day.usage.feed.starts, 1);
  assert.doesNotThrow(() => new Function(ANALYTICS_CLIENT_JS));
  assert.match(ANALYTICS_VIEW_HTML, /Использование режимов/);
});

for (const feature of ['marathon', 'road_signs', 'parking']) {
  test(`${feature} launches survive ingestion, deduplication and period aggregation`, async () => {
    const { post, body, buffer, kv } = setup();
    body.events[0].feature = feature;
    assert.equal((await post(body)).status, 200);
    assert.equal((await post(body)).status, 200);
    await buffer.flush();
    const days = [...kv].filter(([key]) => key.startsWith('day:'))
      .map(([key, value]) => ({ date: key.slice(4), data: JSON.parse(value) }));
    const snapshot = usageSnapshot(days);
    assert.deepEqual(snapshot.features[feature], { starts: 1, installations: 1 });
    assert.equal(snapshot.timeline[0].features[feature].starts, 1);
  });
}
