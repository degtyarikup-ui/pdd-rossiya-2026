import test from 'node:test';
import assert from 'node:assert/strict';
import { setImmediate as turn, setTimeout as pause } from 'node:timers/promises';
import worker from './worker.js';
import { computeEconomyStats, DEFAULT_ECONOMY_CONFIG } from './economy_admin.js';
import { AI_DEFAULT_MODEL } from './ai_models.js';
import { userSummary } from './user_store.js';

// Reads stay pending until the test releases a whole network round trip. Reverse
// completion order exercises stable output without timing-based assertions.
class DelayedKV {
  constructor(entries = []) {
    this.data = new Map(entries);
    this.data.set('economy_fx_usd_v1',JSON.stringify({rubPerUsd:95,effectiveDate:new Date().toISOString().slice(0,10),requestedDay:new Date().toISOString().slice(0,10),checkedAt:new Date().toISOString()}));
    this.metadata = new Map();
    this.pending = [];
    this.reads = [];
    this.waves = [];
    this.active = 0;
    this.maxActive = 0;
    this.failures = new Set();
  }
  read(key, value) {
    this.reads.push(key);
    this.maxActive = Math.max(this.maxActive, ++this.active);
    return new Promise((resolve, reject) => this.pending.push({ key, release: () => {
      this.active--;
      if (this.failures.has(key)) reject(new Error('fixture read failure'));
      else resolve(value());
    } }));
  }
  get(key) { return this.read(key, () => this.data.get(key) ?? null); }
  list({ prefix = '', cursor = '0', limit = 1000 } = {}) {
    return this.read('list:' + prefix, () => {
      const keys = [...this.data.keys()].filter(key => key.startsWith(prefix));
      const offset = Number(cursor);
      return { keys: keys.slice(offset, offset + limit).map(name => ({ name, metadata: this.metadata.get(name) })),
        list_complete: offset + limit >= keys.length, cursor: String(offset + limit) };
    });
  }
  put() { assert.fail('admin reads must not write current metadata records'); }
  delete() { assert.fail('admin reads must not delete records'); }
  async finish(promise) {
    let done = false, result, error;
    promise.then(value => { done = true; result = value; }, reason => { done = true; error = reason; });
    for (let i = 0; i < 1000 && !done; i++) {
      await turn();
      if (done) break;
      const batch = this.pending.splice(0);
      // WebCrypto and the atomic authentication boundary can finish between KV waves.
      if (!batch.length) { await pause(1); continue; }
      this.waves.push(batch.map(item => item.key));
      for (const item of batch.reverse()) item.release();
    }
    assert.ok(done, 'request exceeded the read-round limit');
    if (error) throw error;
    return result;
  }
  count(key) { return this.reads.filter(value => value === key).length; }
}

const NOW = Date.parse('2026-11-04T12:00:00Z');
const json = JSON.stringify;
const dayKey = date => new Date(Number(date) + 3 * 3600000).toISOString().slice(0, 10);
const config = json({ ...DEFAULT_ECONOMY_CONFIG, cloudflareEnabled: false, domainEnabled: false });
const envFor = kv => ({ INSTALLS: kv, ADMIN_PASSWORD: crypto.randomUUID() });
const request = (env, path) => worker.fetch(new Request('https://admin.example' + path,
  { headers: { Authorization: 'Bearer ' + env.ADMIN_PASSWORD } }), env, { waitUntil() {} });
const purchase = (id, transactionId = id, productId = 'weekly') => ({ id, name: id,
  premiumSource: 'appstore', isPremium: true, premiumExpiresAt: '2027-01-01T00:00:00Z',
  purchasedAt: '2026-11-02T12:00:00Z', verifiedPurchase: { store: 'appstore', transactionId, productId } });

test('economy reads 24 orders and 16 store profiles in bounded rounds with stable totals and receipt order', async t => {
  const kv = new DelayedKV([['economy_config', config]]);
  for (let i = 0; i < 24; i++) kv.data.set('pay_order:' + i, json({ orderId: String(i), amount: 100,
    status: 'confirmed', confirmedAt: '2026-11-03T12:00:00Z' }));
  const users = Array.from({ length: 16 }, (_, i) => purchase('buyer-' + i));
  // Same store transaction on two profiles: source order, not completion order,
  // determines which receipt wins. A later duplicate must not change its price.
  users[1].verifiedPurchase = { ...users[0].verifiedPurchase, productId: '3month' };
  for (const user of users) kv.data.set('user:' + user.id, json(user));
  const summaries = users.map(({ verifiedPurchase, ...summary }) => summary);
  summaries.push({ id: 'free', premiumSource: 'admin_grant' });
  const result = await kv.finish(computeEconomyStats(envFor(kv), 'month', { now: NOW, fx: {rubPerUsd:95,effectiveDate:'2026-11-04'}, listUserSummaries: async () => summaries }));
  assert.equal(kv.maxActive, 8);
  assert.equal(kv.waves.length, 7, '1 metadata + 3 orders + 2 profiles + 1 AI round');
  assert.equal(kv.reads.length, 46);
  assert.equal(kv.count('user:free'), 0);
  for (const key of kv.reads) assert.equal(kv.count(key), 1, key);
  assert.deepEqual(result.receipts.filter(row => row.storeKey === 'web').map(row => row.id), Array.from({ length: 24 }, (_, i) => String(i)));
  assert.equal(result.revenue.ordersCount, 24);
  assert.equal(result.revenue.webRub, 2400);
  assert.equal(result.revenue.appstoreRub, 15 * 99);
  assert.equal(result.expenses.paymentFeesRub, 192);
  assert.equal(result.profit.operatingRub, 2400 + 15 * 99 - 192);
  assert.equal(result.estimatedReceipts[0].customer, 'buyer-0');
  t.diagnostic('24 orders + 16 store profiles: 46 storage operations, 7 delayed read rounds; previous serial path required 43 rounds. Peak in flight: 8.');
});

test('economy skips full profiles supplied by the caller and isolates corrupt or rejected records', async () => {
  const full = purchase('full');
  const missing = { ...purchase('missing'), verifiedPurchase: undefined };
  delete missing.verifiedPurchase;
  const broken = { ...missing, id: 'broken' };
  const kv = new DelayedKV([['economy_config', config], ['pay_order:bad-json', '{'],
    ['pay_order:failed', '{}'], ['pay_order:good', json({ orderId: 'good', amount: 100, status: 'confirmed', confirmedAt: '2026-11-03' })],
    ['user:broken', '{']]);
  kv.failures.add('pay_order:failed');
  kv.failures.add('user:missing');
  const result = await kv.finish(computeEconomyStats(envFor(kv), 'month', { now: NOW, fx: {rubPerUsd:95,effectiveDate:'2026-11-04'},
    listUserSummaries: async () => [full, missing, broken] }));
  assert.equal(kv.count('user:full'), 0);
  assert.equal(kv.count('user:missing'), 1);
  assert.equal(kv.count('user:broken'), 1);
  assert.equal(result.revenue.webRub, 100);
  assert.equal(result.revenue.appstoreRub, 297);
  assert.deepEqual(result.estimatedReceipts.map(row => row.id), ['full', 'missing', 'broken']);
});

test('AI model and five counters load in one round and retain existing partial-error defaults', async t => {
  for (const failure of [null, 'ai_stats_prompt_tokens']) {
    const kv = new DelayedKV([['ai_config_model', AI_DEFAULT_MODEL], ['ai_stats_total_req', '12'],
      ['ai_stats_today_req_' + dayKey(Date.now()), '3'], ['ai_stats_prompt_tokens', '100'],
      ['ai_stats_candidate_tokens', '40'], ['ai_stats_cost_usd', '1.25']]);
    if (failure) kv.failures.add(failure);
    const response = await kv.finish(request(envFor(kv), '/api/admin/ai/stats'));
    assert.equal(response.status, 200);
    const { stats } = await response.json();
    assert.equal(kv.maxActive, 6);
    assert.equal(kv.waves.length, 1);
    assert.equal(kv.reads.length, 6);
    assert.equal(stats.totalRequests, 12);
    assert.equal(stats.todayRequests, 3);
    assert.equal(stats.activeModel, AI_DEFAULT_MODEL);
    assert.equal(stats.totalTokens, failure ? 0 : 140);
    assert.equal(stats.costUsd, failure ? 0.18 : 1.25);
  }
  t.diagnostic('AI dashboard: 6 delayed reads in 1 round instead of 6, including unchanged partial-failure fallback.');
});

test('analytics batches independent counters, recent events and store reports; cache stays inside each KV binding', async t => {
  const today = dayKey(Date.now());
  for (const scale of [1, 2]) {
    const kv = new DelayedKV([['counter', '10'], ['counter:by', '20'], ['counter:rs', '30'],
      ['recent_events', json([{ app: 'ru', action: 'install' }, { app: 'by', action: 'install' }])],
      ['store-reports:v1:googleplay', json({ checkedAt: today, days: { [today]: { search: 3 } } })]]);
    for (let i = 0; i < 28; i++) kv.data.set('day:' + dayKey(Date.now() - i * 86400000), json({
      views: 10 * scale, clicks: 5 * scale, installs: scale, sources: { Google: { views: 10 * scale, clicks: 5 * scale, installs: scale } } }));
    const env = envFor(kv);
    const response = await kv.finish(request(env, '/api/admin/stats?days=14&app=ru'));
    assert.equal(response.status, 200);
    const stats = await response.json();
    assert.equal(stats.totals.views, 140 * scale);
    assert.equal(stats.previous.views, 140 * scale);
    assert.equal(stats.totals.grandTotal, 10);
    assert.equal(stats.recent.length, 1);
    assert.deepEqual(stats.storeReports.googleplay.rows, [['search', 3]]);
    assert.equal(kv.reads.filter(key => key.startsWith('day:')).length, 28);
    assert.equal(kv.waves.length, 5, 'four bounded day rounds and one independent metadata round');
    assert.equal(kv.waves.at(-1).length, 6);
    assert.ok(kv.waves.every(wave => wave.filter(key => key.startsWith('day:')).length <= 8));
    const before = kv.reads.length;
    await kv.finish(request(env, '/api/admin/stats?days=14&app=ru'));
    assert.equal(kv.reads.length - before, 8, 'only today/yesterday and six metadata reads repeat');
    assert.equal(kv.count('list:user:'), 1, 'existing analytics summary TTL is retained');
  }
  t.diagnostic('14-day analytics: cold 5 delayed rounds instead of 9; warm refresh 8 get reads. Separate KV bindings never share historical days or user summaries.');
});

test('simultaneous economy, users and analytics share one summary read without caching subsequent financial reads', async () => {
  const user = { id: 'one', provider: 'google', app: 'ru', createdAt: new Date().toISOString() };
  const kv = new DelayedKV([['economy_config', config], ['user:one', json(user)]]);
  kv.metadata.set('user:one', userSummary(user));
  const env = envFor(kv);
  const responses = await kv.finish(Promise.all([
    request(env, '/api/admin/economy/stats'), request(env, '/api/admin/users'), request(env, '/api/admin/stats?days=1'),
  ]));
  assert.ok(responses.every(response => response.status === 200));
  assert.equal(kv.count('list:user:'), 1);
  assert.equal(kv.count('user:one'), 0);
  const added = { ...user, id: 'two' };
  kv.data.set('user:two', json(added));
  kv.metadata.set('user:two', userSummary(added));
  const fresh = await kv.finish(request(env, '/api/admin/economy/stats'));
  assert.equal((await fresh.json()).unitEconomics.totalUsersCount, 2);
  assert.equal(kv.count('list:user:'), 2, 'completed summary reads do not become a financial cache');
  assert.equal(kv.count('economy_config'), 2);
});

test('a failed in-flight summary read is released so the next analytics request retries', async () => {
  const kv = new DelayedKV();
  const env = envFor(kv);
  kv.failures.add('list:user:');
  const originalError = console.error;
  console.error = () => {};
  try {
    const first = await kv.finish(request(env, '/api/admin/stats?days=1'));
    assert.equal(first.status, 200);
    assert.equal((await first.json()).users, undefined);
    kv.failures.delete('list:user:');
    const second = await kv.finish(request(env, '/api/admin/stats?days=1'));
    assert.equal(second.status, 200);
    assert.ok((await second.json()).users);
    assert.equal(kv.count('list:user:'), 2);
  } finally { console.error = originalError; }
});

test('admin authentication rejects all optimized routes before any storage reads', async () => {
  const kv = new DelayedKV();
  const env = envFor(kv);
  for (const path of ['/api/admin/economy/stats', '/api/admin/users', '/api/admin/stats', '/api/admin/ai/stats']) {
    const response = await worker.fetch(new Request('https://admin.example' + path), env, { waitUntil() {} });
    assert.equal(response.status, 401);
  }
  assert.deepEqual(kv.reads, []);
});
