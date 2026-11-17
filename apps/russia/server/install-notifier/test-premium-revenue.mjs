import test from 'node:test';
import assert from 'node:assert/strict';
import { premiumRevenueSnapshot, recordPremiumDailyPurchase } from './premium_revenue_analytics.js';
import { flushBufferedStats } from './worker.js';

const NOW = Date.parse('2026-11-17T15:00:00Z');
class MemoryKV {
  constructor() { this.data = new Map(); this.reads = 0; this.writes = 0; }
  async get(key) { this.reads++; return this.data.get(key) ?? null; }
  async put(key, value) { this.writes++; this.data.set(key, value); }
  async list({ prefix = '', cursor = '0' }) {
    const keys = [...this.data.keys()].filter(key => key.startsWith(prefix));
    const start = Number(cursor), limit = 2;
    return { keys: keys.slice(start, start + limit).map(name => ({ name })), list_complete: start + limit >= keys.length, cursor: String(start + limit) };
  }
}
const env = () => ({ INSTALLS: new MemoryKV() });
const days = (data = {}) => ['2026-11-15', '2026-11-16', '2026-11-17'].map(date => ({ date, data: data[date] ?? null }));
const order = async (e, id, values = {}) => e.INSTALLS.put('pay_order:' + id, JSON.stringify({ orderId: id, txId: id, app: 'ru', status: 'confirmed', amount: 99, currency: 'RUB', confirmedAt: '2026-11-17T12:00:00Z', ...values }));
const snapshot = (e, data = days(), app = 'all') => premiumRevenueSnapshot(e, data, app, NOW);
function record(day, source, money, values = {}) {
  day.purchases = (day.purchases || 0) + 1;
  recordPremiumDailyPurchase(day, { type: 'purchase', purchaseSource: source, premiumMoney: money, premiumPaid: true, ...values });
}

test('empty history contains every calendar day and zero amounts without a fabricated price', async () => {
  const result = await snapshot(env());
  assert.equal(result.available, true);
  assert.equal(result.timeZone, 'Europe/Moscow');
  assert.deepEqual(result.currencies, ['RUB']);
  assert.deepEqual(result.timeline.map(day => [day.date, day.purchases, day.amounts]), days().map(day => [day.date, 0, {}]));
  assert.deepEqual(result.totals, { purchases: 0, missingAmounts: 0, amounts: {}, pricedPurchases: {} });
});

test('SBP confirmations use Moscow midnight and ignore checkout creation time and future confirmations', async () => {
  const e = env();
  await order(e, 'before', { confirmedAt: '2026-11-15T20:59:59Z' });
  await order(e, 'after', { confirmedAt: '2026-11-15T21:00:00Z', amount: 290, createdAt: '2026-11-10T12:00:00Z' });
  await order(e, 'future', { confirmedAt: '2026-11-17T15:00:01Z' });
  await order(e, 'old', { confirmedAt: '2026-11-14T20:59:59Z' });
  const result = await snapshot(e);
  assert.deepEqual(result.timeline.map(day => day.amounts.RUB || 0), [99000, 290000, 0]);
  assert.equal(result.totals.purchases, 2);
  assert.equal(result.totals.amounts.RUB, 389000);
});

test('test, sandbox, canceled, mismatch and returned orders never become revenue', async () => {
  const e = env();
  for (const [id, values] of Object.entries({
    test: { isTest: true }, sandbox: { environment: 'Sandbox' }, oldTest: { email: 'mojomaker.play@gmail.com' },
    canceled: { status: 'canceled' }, mismatch: { status: 'mismatch' }, refund: { status: 'chargebacked' },
    reversed: { reversed: true }, unpaid: { status: 'pending', confirmedAt: null },
  })) await order(e, id, values);
  await order(e, 'real', { amount: 99, email: 'customer@example.com' });
  const result = await snapshot(e, days({ '2026-11-17': { purchases: 8 } }));
  assert.equal(result.totals.purchases, 1);
  assert.equal(result.totals.amounts.RUB, 99000);
  assert.equal(result.coverage.unverifiedPurchases, 0);
});

test('daily buffered aggregates retain exact currencies and missing amounts, excluding manual grants and sandbox', async () => {
  const day = {};
  record(day, 'appstore', { currency: 'USD', milliunits: 1990 });
  record(day, 'appstore', { currency: 'EUR', milliunits: 2490 });
  record(day, 'googleplay', null);
  record(day, 'appstore', { currency: 'USD', milliunits: 1990 }, { premiumReportExcluded: true });
  recordPremiumDailyPurchase(day, { type: 'purchase', purchaseSource: 'admin_grant', premiumMoney: { currency: 'RUB', milliunits: 999000 } });
  const result = await snapshot(env(), days({ '2026-11-17': day }));
  assert.deepEqual(result.totals, { purchases: 3, missingAmounts: 1, amounts: { USD: 1990, EUR: 2490 }, pricedPurchases: { USD: 1, EUR: 1 } });
  assert.deepEqual(result.currencies, ['EUR', 'USD']);
  assert.equal(result.methods.find(method => method.key === 'googleplay').missingAmounts, 1);
  assert.equal(result.coverage.unverifiedPurchases, 0);
  assert.deepEqual(result.timeline[2].methods.map(method => method.key), ['appstore', 'googleplay']);
});

test('authoritative confirmed orders replace buffered web amounts and deduplicate the same transaction', async () => {
  const e = env(), day = {};
  record(day, 'web', { currency: 'RUB', milliunits: 99000 });
  record(day, 'web', { currency: 'RUB', milliunits: 290000 });
  await order(e, 'a', { txId: 'same' });
  await order(e, 'a-copy', { txId: 'same' });
  await order(e, 'returned', { status: 'chargebacked', amount: 290 });
  const result = await snapshot(e, days({ '2026-11-17': day }));
  assert.equal(result.totals.purchases, 1);
  assert.equal(result.totals.amounts.RUB, 99000);
  assert.equal(result.coverage.unverifiedPurchases, 0);
});

test('positive verified money or explicit paid evidence is required for confirmed store purchases', async () => {
  const day = {};
  record(day, 'googleplay', null, { premiumPaid: false });
  record(day, 'googleplay', { currency: 'USD', milliunits: 1990 }, { premiumPaid: false });
  record(day, 'googleplay', null, { premiumPaid: true });
  const result = await snapshot(env(), days({ '2026-11-17': day }));
  assert.equal(result.totals.purchases, 2);
  assert.equal(result.totals.missingAmounts, 1);
  assert.deepEqual(result.totals.amounts, { USD: 1990 });
  assert.equal(result.coverage.unverifiedPurchases, 1);
});

test('unknown historical counters stay outside confirmed totals rather than assuming 99 or 290 rubles', async () => {
  const e = env();
  await order(e, 'known');
  const result = await snapshot(e, days({ '2026-11-17': { purchases: 7 } }));
  assert.equal(result.totals.purchases, 1);
  assert.equal(result.totals.amounts.RUB, 99000);
  assert.equal(result.coverage.unverifiedPurchases, 6);
});

test('invalid price remains a purchase with missing amount and missing confirmation date is not invented', async () => {
  const e = env();
  await order(e, 'missing-price', { amount: null });
  await order(e, 'missing-date', { confirmedAt: null, createdAt: '2026-11-17T12:00:00Z' });
  await order(e, 'fraction', { amount: 99.125 });
  const result = await snapshot(e);
  assert.equal(result.totals.purchases, 2);
  assert.equal(result.totals.missingAmounts, 1);
  assert.equal(result.totals.amounts.RUB, 99125);
  assert.equal(result.coverage.missingDates, 1);
});

test('legacy confirmed orders default to RUB while currencies are never silently converted', async () => {
  const e = env();
  await order(e, 'legacy', { status: undefined, currency: undefined });
  await order(e, 'usd', { amount: 2.99, currency: 'USD' });
  const result = await snapshot(e);
  assert.deepEqual(result.totals.amounts, { RUB: 99000, USD: 2990 });
  assert.deepEqual(result.totals.pricedPurchases, { RUB: 1, USD: 1 });
  assert.deepEqual(result.currencies, ['RUB', 'USD']);
});

test('app filtering applies to both authoritative orders and store aggregates', async () => {
  const e = env(), day = {};
  await order(e, 'ru'); await order(e, 'by', { app: 'by', amount: 290 });
  record(day, 'appstore', { currency: 'USD', milliunits: 2990 }, { app: 'ru' });
  record(day, 'appstore', { currency: 'EUR', milliunits: 2490 }, { app: 'by' });
  const result = await snapshot(e, days({ '2026-11-17': day }), 'ru');
  assert.equal(result.totals.purchases, 2);
  assert.deepEqual(result.totals.amounts, { RUB: 99000, USD: 2990 });
  const by = await snapshot(e, days({ '2026-11-17': day }), 'by');
  assert.deepEqual(by.totals.amounts, { RUB: 290000, EUR: 2490 });
});

test('directory, record and parse failures reject instead of producing a successful zero revenue', async () => {
  for (const INSTALLS of [
    { list: async () => { throw new Error('offline'); } },
    { list: async () => ({ keys: [], list_complete: false }) },
    { list: async () => ({ keys: [{ name: 'pay_order:a' }], list_complete: true }), get: async () => null },
    { list: async () => ({ keys: [{ name: 'pay_order:a' }], list_complete: true }), get: async () => '{broken' },
  ]) await assert.rejects(snapshot({ INSTALLS }));
});

test('daily source totals reconcile with headline totals without exposing customer identities', async () => {
  const e = env(), day = {};
  await order(e, 'customer-secret-id', { email: 'private@example.com', amount: 99 });
  record(day, 'appstore', { currency: 'RUB', milliunits: 290000 });
  record(day, 'googleplay', { currency: 'USD', milliunits: 2990 });
  const result = await snapshot(e, days({ '2026-11-17': day }));
  assert.equal(result.methods.reduce((sum, method) => sum + method.purchases, 0), result.totals.purchases);
  for (const currency of result.currencies) assert.equal(result.methods.reduce((sum, method) => sum + (method.amounts[currency] || 0), 0), result.totals.amounts[currency]);
  assert.equal(JSON.stringify(result).includes('private@example.com'), false);
  assert.equal(JSON.stringify(result).includes('customer-secret-id'), false);
});

test('real stats flush persists prices in the same Moscow day write and preserves existing counters', async () => {
  const e = env();
  await flushBufferedStats(e, [{ id: 'purchase:one', kind: 'analytics', ts: Date.parse('2026-11-16T21:00:00Z'),
    event: { type: 'purchase', app: 'ru', purchaseSource: 'appstore', premiumMoney: { currency: 'USD', milliunits: 1990 } } }]);
  const day = JSON.parse(await e.INSTALLS.get('day:2026-11-17'));
  assert.equal(day.purchases, 1);
  assert.equal(day.premiumRevenue.apps.ru.methods.appstore.amounts.USD, 1990);
  assert.equal([...e.INSTALLS.data.keys()].some(key => key.startsWith('premium_revenue:')), false);
  const result = await snapshot(e, days({ '2026-11-17': day }));
  assert.equal(result.totals.amounts.USD, 1990);
  assert.equal(result.coverage.unverifiedPurchases, 0);
});
