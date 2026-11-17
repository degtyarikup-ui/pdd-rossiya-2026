import test from 'node:test';
import assert from 'node:assert/strict';
import { premiumRevenueSnapshot, recordPremiumDailyPurchase, recordPremiumTransaction, premiumTransactionId, PREMIUM_HISTORY_KEY } from './premium_revenue_analytics.js';
import worker, { flushBufferedStats, executeAccountEffect } from './worker.js';
import { generateKeyPair, exportPKCS8 } from 'jose';

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
const FX = { source: 'CBR', rubPerUsd: 80, rubPerUnit: { RUB: 1, USD: 80, EUR: 100, GBP: 120, KZT: 0.2 },
  effectiveDate: '2026-11-17', requestedDay: '2026-11-17', checkedAt: new Date(NOW).toISOString() };
const env = () => { const INSTALLS = new MemoryKV(); INSTALLS.data.set('economy_fx_usd_v1', JSON.stringify(FX)); return { INSTALLS }; };
const days = (data = {}) => ['2026-11-15', '2026-11-16', '2026-11-17'].map(date => ({ date, data: data[date] ?? null }));
const order = async (e, id, values = {}) => e.INSTALLS.put('pay_order:' + id, JSON.stringify({ orderId: id, txId: id, app: 'ru', status: 'confirmed', amount: 99, currency: 'RUB', confirmedAt: '2026-11-17T12:00:00Z', ...values }));
const snapshot = async (e, data = days(), app = 'all') => {
  if (e.INSTALLS?.data) for (const day of data) if (day.data) e.INSTALLS.data.set('day:' + day.date, JSON.stringify(day.data));
  return premiumRevenueSnapshot(e, data, app, NOW);
};
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

const transaction = async (method, id, patch = {}) => ({ id: await premiumTransactionId(method, id), method, app: 'ru',
  purchasedAt: '2026-11-15T21:00:00Z', checkedAt: '2026-11-17T12:00:00Z', paid: true, isTest: false, refunded: false,
  money: { currency: 'USD', milliunits: 1990 }, ...patch });
const restore = (e, transactions, values = {}) => e.INSTALLS.put(PREMIUM_HISTORY_KEY, JSON.stringify({ version: 1,
  importedAt: '2026-11-17T12:00:00Z', replaceLegacyBefore: { appstore: '2026-11-17T12:00:00Z', googleplay: '2026-11-17T12:00:00Z' },
  transactions, ...values }));

test('restored exact transactions replace old anonymous store sums and use purchase Moscow day', async () => {
  const e = env(), legacy = {};
  record(legacy, 'appstore', { currency: 'USD', milliunits: 1990 });
  const a = await transaction('appstore', 'private-apple-order'), b = await transaction('googleplay', 'private-google-order', { money: { currency: 'EUR', milliunits: 2490 } });
  await restore(e, [a, a, b, await transaction('appstore', 'sandbox', { isTest: true }), await transaction('appstore', 'refund', { refunded: true }), await transaction('googleplay', 'pending', { paid: false })]);
  const result = await snapshot(e, days({ '2026-11-17': legacy }));
  assert.equal(result.totals.purchases, 2);
  assert.deepEqual(result.totals.amounts, { USD: 1990, EUR: 2490 });
  assert.equal(result.timeline[1].purchases, 2);
  assert.equal(result.timeline[2].purchases, 0, 'restoring does not move old purchases onto today');
  assert.doesNotMatch(JSON.stringify(result), /private-apple-order|private-google-order/);
});

test('live/imported transaction deduplication uses latest verified state including later refunds', async () => {
  const e = env(), day = {}, imported = await transaction('appstore', 'same');
  await restore(e, [imported]);
  recordPremiumTransaction(day, { ...imported, checkedAt: '2026-11-17T14:00:00Z' });
  let result = await snapshot(e, days({ '2026-11-16': day }));
  assert.equal(result.totals.purchases, 1);
  recordPremiumTransaction(day, { ...imported, refunded: true, checkedAt: '2026-11-17T14:30:00Z' });
  result = await snapshot(e, days({ '2026-11-16': day }));
  assert.equal(result.totals.purchases, 0);
  recordPremiumTransaction(day, { ...imported, checkedAt: '2026-11-17T13:00:00Z' });
  result = await snapshot(e, days({ '2026-11-16': day }));
  assert.equal(result.totals.purchases, 0, 'a late stale restore cannot resurrect a known refund');
});

test('new revenue observations persist at actual purchase date and leave event counters on confirmation day', async () => {
  const e = env(), sale = await transaction('appstore', 'new-sale');
  await flushBufferedStats(e, [
    { kind: 'premium-revenue', ts: NOW, revenue: sale },
    { kind: 'analytics', ts: NOW, event: { type: 'purchase', app: 'ru', purchaseSource: 'appstore', premiumLedgerTracked: true, premiumMoney: sale.money } },
  ]);
  const purchased = JSON.parse(await e.INSTALLS.get('day:2026-11-16')), confirmed = JSON.parse(await e.INSTALLS.get('day:2026-11-17'));
  assert.equal(purchased.premiumRevenue.apps.ru.transactions[sale.id].money.milliunits, 1990);
  assert.equal(confirmed.purchases, 1);
  assert.equal(confirmed.premiumRevenue.apps.ru.methods.appstore, undefined);
  const result = await premiumRevenueSnapshot(e, days(), 'all', NOW);
  assert.equal(result.totals.purchases, 1);
  assert.equal(result.timeline[1].purchases, 1);
  assert.equal(result.coverage.unverifiedPurchases, 0);
});

test('accounting ignores stale activity-day snapshots and surfaces corrupt history rather than zero', async () => {
  const e = env(), sale = await transaction('appstore', 'fresh'), day = {};
  recordPremiumTransaction(day, sale);
  await e.INSTALLS.put('day:2026-11-16', JSON.stringify(day));
  const stale = days({ '2026-11-16': structuredClone(day) });
  assert.equal((await premiumRevenueSnapshot(e, stale, 'all', NOW)).totals.purchases, 1);
  recordPremiumTransaction(day, { ...sale, refunded: true, checkedAt: '2026-11-17T14:00:00Z' });
  await e.INSTALLS.put('day:2026-11-16', JSON.stringify(day));
  assert.equal((await premiumRevenueSnapshot(e, stale, 'all', NOW)).totals.purchases, 0);
  for (const corrupt of ['null', '42', '[]', '{bad']) {
    await e.INSTALLS.put(PREMIUM_HISTORY_KEY, corrupt);
    await assert.rejects(premiumRevenueSnapshot(e, stale, 'all', NOW));
  }
  e.INSTALLS.data.delete(PREMIUM_HISTORY_KEY);
  for (const corrupt of ['null', '42', '[]']) {
    await e.INSTALLS.put('day:2026-11-16', corrupt);
    await assert.rejects(premiumRevenueSnapshot(e, stale, 'all', NOW));
  }
});

test('historical completeness never conceals newly unverified events on the import day', async () => {
  const e = env(), day = {};
  record(day, 'googleplay', null, { premiumPaid: false });
  await restore(e, [], { coverage: { complete: true, from: '2026-11-15', through: '2026-11-17' } });
  const result = await snapshot(e, days({ '2026-11-17': day }));
  assert.equal(result.coverage.unverifiedPurchases, 1);
});

test('Google durable revenue effects retry missing metadata and fingerprint the final order state', async () => {
  const e = env(), accepted = [], originalFetch = globalThis.fetch;
  const { privateKey } = await generateKeyPair('RS256', { extractable: true });
  e.GOOGLE_PLAY_SERVICE_ACCOUNT = JSON.stringify({ client_email: 'revenue-test@example.invalid', private_key: await exportPKCS8(privateKey) });
  e.STATS = { idFromName: value => value, get: () => ({ fetch: async (_url, options) => { accepted.push(JSON.parse(options.body)); return new Response('ok'); } }) };
  const sale = await transaction('googleplay', 'GPA.1234-5678-9012-34567');
  const effect = { kind: 'stats', item: { kind: 'premium-revenue', id: 'same-before-enrichment', ts: NOW, revenue: { ...sale, purchasedAt: null, money: undefined },
    googleRevenueOrder: { id: 'GPA.1234-5678-9012-34567', country: 'ru' } } };
  let response = null;
  globalThis.fetch = async url => String(url).includes('oauth2.googleapis.com') ? Response.json({ access_token: crypto.randomUUID() })
    : response ? Response.json(response) : new Response('', { status: 503 });
  try {
    await assert.rejects(executeAccountEffect(effect, e), /metadata unavailable/);
    assert.equal(accepted.length, 0, 'failed metadata remains retryable, never permanently accepted without its price');
    response = { state: 'PROCESSED', total: { currencyCode: 'USD', units: '1', nanos: 990000000 }, createTime: '2026-11-15T20:50:00Z', orderHistory: { processedEvent: { eventTime: '2026-11-15T21:00:00Z' } } };
    await executeAccountEffect(effect, e);
    assert.equal(accepted[0].revenue.money.milliunits, 1990);
    assert.equal(accepted[0].revenue.purchasedAt, '2026-11-15T21:00:00.000Z');
    response.state = 'REFUNDED';
    await executeAccountEffect(effect, e);
    assert.equal(accepted[1].revenue.refunded, true);
    assert.notEqual(accepted[0].id, accepted[1].id, 'same subscription reference can observe a later order refund');
    response.state = 'PARTIALLY_REFUNDED';
    response.orderHistory.partialRefundEvents = [{ state: 'PROCESSED_SUCCESSFULLY', refundDetails: { total: { currencyCode: 'USD', units: '0', nanos: 500000000 } } }];
    await executeAccountEffect(effect, e);
    assert.equal(accepted[2].revenue.money.milliunits, 1490);
    assert.notEqual(accepted[0].id, accepted[2].id);
    assert.equal(accepted[2].googleRevenueOrder, undefined, 'raw order lookup hints never enter the stored ledger');
    response.orderHistory.partialRefundEvents[0].refundDetails.total.nanos = 990000000;
    response.orderHistory.partialRefundEvents[0].refundDetails.total.units = '1';
    await executeAccountEffect(effect, e);
    assert.equal(accepted[3].revenue.refunded, true, 'a full remainder refund retracts without retrying forever');
    assert.equal(accepted[3].revenue.money, undefined);
    response = { state: 'REFUNDED', createTime: '2026-11-15T21:00:00Z' };
    await executeAccountEffect(effect, e);
    assert.equal(accepted[4].revenue.refunded, true, 'known refunded status does not require a positive amount');
  } finally { globalThis.fetch = originalFetch; }
});

test('USD view combines native dollars, rubles and other currencies at the Economy rate with reconciled cents', async () => {
  const e = env();
  await order(e, 'weekly', { amount: 99 });
  await order(e, 'quarter', { amount: 290 });
  await restore(e, [
    await transaction('appstore', 'dollars', { money: { currency: 'USD', milliunits: 4990 } }),
    await transaction('appstore', 'euros', { money: { currency: 'EUR', milliunits: 2990 } }),
    await transaction('googleplay', 'tenge', { money: { currency: 'KZT', milliunits: 1790000 } }),
  ]);
  const { usd } = await snapshot(e);
  assert.equal(usd.available, true);
  assert.equal(usd.totals.amountCents, 124 + 363 + 499 + 374 + 448, 'each receipt rounds once to cents');
  assert.equal(usd.methods.find(row => row.key === 'appstore').amountCents, 499 + 374, 'USD never round-trips through RUB');
  assert.equal(usd.totals.purchases, 5);
  assert.equal(usd.totals.averageCheckCents, Math.round(1808 / 5));
  assert.equal(usd.totals.averageDailyCents, Math.round(1808 / 3), 'all selected calendar days count');
  assert.equal(usd.timeline.reduce((sum, row) => sum + row.amountCents, 0), usd.totals.amountCents);
  assert.equal(usd.methods.reduce((sum, row) => sum + row.amountCents, 0), usd.totals.amountCents);
  assert.equal(usd.fx.rubPerUsd, 80);
});

test('missing conversion rates never understate dollar totals, while native USD needs no FX request', async () => {
  const e = env();
  await restore(e, [await transaction('appstore', 'unsupported', { money: { currency: 'XYZ', milliunits: 2990 } })]);
  const missing = (await snapshot(e)).usd;
  assert.equal(missing.available, false);
  assert.equal(missing.totals.amountCents, null);
  assert.equal(missing.totals.averageDailyCents, null);
  const direct = env();
  await restore(direct, [await transaction('appstore', 'dollars')]);
  const originalGet = direct.INSTALLS.get.bind(direct.INSTALLS);
  direct.INSTALLS.get = key => { assert.notEqual(key, 'economy_fx_usd_v1'); return originalGet(key); };
  assert.equal((await snapshot(direct)).usd.totals.amountCents, 199);
});
