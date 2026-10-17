import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DEFAULT_ECONOMY_CONFIG, getEconomyConfig, saveEconomyConfig, computeEconomyStats, handleEconomyAdmin, isTestOrder } from './economy_admin.js';

class MemoryKV {
  constructor() { this.store = new Map(); }
  async get(key) { return this.store.get(key) ?? null; }
  async put(key, value) { this.store.set(key, String(value)); }
  async list({ prefix = '', limit = 1000, cursor = '0' } = {}) {
    const all = [...this.store.keys()].filter(key => key.startsWith(prefix));
    const offset = Number(cursor);
    return { keys: all.slice(offset, offset + limit).map(name => ({ name })),
      list_complete: offset + limit >= all.length, cursor: String(offset + limit) };
  }
}
const NOW = Date.parse('2026-10-16T12:00:00Z');
const environment = () => ({ INSTALLS: new MemoryKV() });
const stats = (env, period = 'month', extra = {}) => computeEconomyStats(env, period, { now: NOW, listUserSummaries: async () => [], ...extra });
async function seedConfig(env, changes = {}) {
  await env.INSTALLS.put('economy_config', JSON.stringify({ ...DEFAULT_ECONOMY_CONFIG, cloudflareMonthlyUsd: 0, domainMonthlyRub: 0, ...changes }));
}
async function order(env, id, changes = {}) {
  await env.INSTALLS.put('pay_order:' + id, JSON.stringify({ orderId: id, status: 'confirmed', amount: 99, tier: 'weekly',
    method: 'sbp', confirmedAt: '2026-10-10T12:00:00Z', ...changes }));
}
async function api(env, path, body, method = 'POST', overrides = {}) {
  const request = new Request('https://test/api/admin/economy/' + path, { method,
    ...(method === 'POST' ? { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) } : {}) });
  const response = await handleEconomyAdmin(request, env, new URL(request.url), { now: NOW, listUserSummaries: async () => [], ...overrides });
  return { status: response.status, data: await response.json() };
}

test('defaults and saved zero settings survive reload and calculations', async () => {
  const env = environment();
  assert.equal((await getEconomyConfig(env)).nikitaSharePercent, 6.7);
  await saveEconomyConfig(env, { cloudflareMonthlyUsd: 0, domainMonthlyRub: 0, reinvestPercent: 0,
    nikitaSharePercent: 0, targetMonthlyProfit: 0 });
  await order(env, 'real', { amount: 1000 });
  const result = await stats(env);
  assert.equal(result.config.nikitaSharePercent, 0);
  assert.equal(result.config.sergeySharePercent, 100);
  assert.equal(result.config.targetMonthlyProfit, 0);
  assert.equal(result.expenses.totalRub, 0);
  assert.equal(result.profit.reinvestRub, 0);
  assert.equal(result.partners.sergey.payoutRub, 1000);
  assert.equal(result.partners.nikita.payoutRub, 0);
  assert.equal(result.breakEven.weeklySubsNeeded, 0);
});

test('settings validate before persistence and support either partner share', async () => {
  const env = environment();
  await saveEconomyConfig(env, { sergeySharePercent: 75.25 });
  assert.equal((await getEconomyConfig(env)).nikitaSharePercent, 24.75);
  for (const update of [{ usdRate: 0 }, { reinvestPercent: 101 }, { nikitaSharePercent: -1 },
    { usdRate: '95' }, { excludeTestOrders: 'false' }, { newKey: true }, { nikitaSharePercent: 30, sergeySharePercent: 80 }]) {
    const response = await api(env, 'settings', update);
    assert.equal(response.status, 400, JSON.stringify(update));
  }
  await assert.rejects(saveEconomyConfig(env, { usdRate: NaN }));
  await assert.rejects(saveEconomyConfig(env, { domainMonthlyRub: Infinity }));
  assert.equal((await getEconomyConfig(env)).sergeySharePercent, 75.25);
  assert.equal((await api(env, 'settings', { extraExpenses: [] })).status, 400);
});

test('expense CRUD supports frequency, currency, dates and legacy inputs', async () => {
  const env = environment();
  await seedConfig(env);
  const added = await api(env, 'expenses/add', { title: 'Хостинг', amount: 10, currency: 'USD', frequency: 'monthly', date: '2026-10-01' });
  assert.equal(added.status, 200);
  const id = added.data.expense.id;
  assert.equal(added.data.expense.currency, 'USD');
  assert.equal((await stats(env)).expenses.extraExpensesRub, 950);
  const edited = await api(env, 'expenses/update', { id, title: 'Сервис', amount: 5, frequency: 'yearly', endDate: '2027-10-01' });
  assert.equal(edited.status, 200);
  assert.equal(edited.data.expense.id, id);
  assert.equal(edited.data.expense.createdAt, added.data.expense.createdAt);
  assert.equal(edited.data.expense.date, '2026-10-01');
  assert.equal((await stats(env)).expenses.extraExpensesRub, 475);
  const deleted = await api(env, 'expenses/delete', { id });
  assert.equal(deleted.status, 200);
  assert.equal((await stats(env)).expenses.extraExpensesRub, 0);
  assert.equal((await api(env, 'expenses/update', { id, title: 'Missing' })).status, 404);
  assert.equal((await api(env, 'expenses/delete', { id })).status, 404);
  const legacy = await api(env, 'expenses/add', { title: 'Разовый', amountRub: 1200, monthly: false });
  assert.equal(legacy.status, 200);
  assert.equal(legacy.data.expense.frequency, 'once');
  const legacyEdit = await api(env, 'expenses/update', { id: legacy.data.expense.id, amountRub: 1500, monthly: true });
  assert.equal(legacyEdit.data.expense.amount, 1500);
  assert.equal(legacyEdit.data.expense.frequency, 'monthly');
});

test('expense validation rejects impossible dates and invalid values without saving', async () => {
  const env = environment();
  const base = { title: 'Расход', amount: 99, frequency: 'once', currency: 'RUB', date: '2026-10-01' };
  for (const patch of [{ title: '' }, { amount: 0 }, { amount: -1 }, { amount: '99' }, { currency: 'EUR' },
    { frequency: 'daily' }, { date: '2026-02-30' }, { date: 'wrong' }, { date: '2026-13-01' },
    { endDate: '2026-09-01' }, { date: '2026-10-01<script>' }]) {
    assert.equal((await api(env, 'expenses/add', { ...base, ...patch })).status, 400, JSON.stringify(patch));
  }
  assert.deepEqual((await getEconomyConfig(env)).extraExpenses, []);
  assert.equal((await api(env, 'expenses/add', [])).status, 400);
});

test('monthly due dates clamp to month end and return to their original day', async () => {
  const env = environment();
  await seedConfig(env, { extraExpenses: [{ id: 'month-end', title: 'Подписка', amount: 100, currency: 'RUB', frequency: 'monthly', date: '2026-01-31' }] });
  const february = await stats(env, 'month', { now: Date.parse('2026-02-28T12:00:00Z') });
  assert.equal(february.expenses.extraExpensesRub, 100);
  const beforeMarchDue = await stats(env, 'month', { now: Date.parse('2026-03-30T12:00:00Z') });
  assert.equal(beforeMarchDue.expenses.extraExpensesRub, 0);
  const march = await stats(env, 'all', { now: Date.parse('2026-03-31T12:00:00Z') });
  assert.equal(march.expenses.extraExpensesRub, 300);
  assert.equal(march.expenses.extraList[0].occurrences, 3);
});

test('yearly expenses clamp leap days and respect inclusive end dates', async () => {
  const env = environment();
  await seedConfig(env, { extraExpenses: [{ id: 'yearly', title: 'Годовая', amount: 1200, frequency: 'yearly', date: '2024-02-29', endDate: '2026-02-28' }] });
  const result = await stats(env, 'all', { now: Date.parse('2027-03-01T12:00:00Z') });
  assert.equal(result.expenses.extraExpensesRub, 3600);
  assert.equal(result.expenses.monthlyRub, 0);
  assert.equal(result.expenses.extraList[0].occurrences, 3);
});

test('periods count only due recurring and dated one-off expenses', async () => {
  const env = environment();
  await seedConfig(env, { extraExpenses: [
    { id: 'm', title: 'Monthly', amount: 100, frequency: 'monthly', date: '2026-09-20' },
    { id: 'old', title: 'Old', amount: 200, frequency: 'once', date: '2026-09-20' },
    { id: 'new', title: 'New', amount: 300, frequency: 'once', date: '2026-10-10' },
    { id: 'future', title: 'Future', amount: 400, frequency: 'once', date: '2026-10-20' },
    { id: 'ended', title: 'Ended', amount: 50, frequency: 'monthly', date: '2026-08-01', endDate: '2026-09-01' },
  ] });
  const month = await stats(env);
  assert.equal(month.expenses.totalRub, 300);
  assert.equal(month.expenses.recurringRub, 0);
  assert.equal(month.expenses.oneOffRub, 300);
  assert.equal(month.expenses.monthlyRub, 100);
  const rolling = await stats(env, '30d');
  assert.equal(rolling.expenses.totalRub, 600);
  assert.equal(rolling.expenses.extraList.find(item => item.id === 'm').occurrences, 1);
  const all = await stats(env, 'all');
  assert.equal(all.expenses.totalRub, 700);
});

test('legacy stored expenses retain original dates and monthly meaning', async () => {
  const env = environment();
  await seedConfig(env, { extraExpenses: [{ id: 'legacy', title: 'Legacy', amountRub: 50, monthly: true, createdAt: '2026-08-01T12:00:00Z' }] });
  const result = await stats(env, 'all');
  assert.equal(result.expenses.extraList[0].frequency, 'monthly');
  assert.equal(result.expenses.extraList[0].date, '2026-08-01');
  assert.equal(result.expenses.extraExpensesRub, 150);
});

test('infrastructure is a period-aware monthly budget with explicit metadata', async () => {
  const env = environment();
  await seedConfig(env, { cloudflareMonthlyUsd: 5, domainMonthlyRub: 67 });
  const month = await stats(env);
  assert.equal(month.expenses.monthlyRub, 542);
  assert.equal(month.expenses.cloudflare.rub, 245.16); // 475 × 16 / 31
  assert.equal(month.expenses.domain.rub, 34.58);
  assert.equal(month.expenses.totalRub, 279.74);
  assert.equal(month.periodInfo.infrastructureBasis, 'prorated_monthly_budget');
  await order(env, 'history', { confirmedAt: '2026-09-01T12:00:00Z' });
  const all = await stats(env, 'all');
  assert.equal(all.periodInfo.from, '2026-09-01');
  assert.equal(all.expenses.totalRub, 821.74);
  assert.equal(all.periodInfo.allTimeStartBasis, 'earliest_known_record');
});

test('all-time AI expense is explicit and excluded from selected-period totals', async () => {
  const env = environment();
  await seedConfig(env);
  await env.INSTALLS.put('ai_stats_cost_usd', '2');
  await env.INSTALLS.put('ai_stats_total_req', '40');
  const month = await stats(env);
  assert.equal(month.expenses.ai.rub, 190);
  assert.equal(month.expenses.ai.scope, 'all');
  assert.equal(month.expenses.ai.includedInTotal, false);
  assert.equal(month.expenses.totalRub, 0);
  const all = await stats(env, 'all');
  assert.equal(all.expenses.ai.includedInTotal, true);
  assert.equal(all.expenses.totalRub, 190);
  const fresh = await stats(environment(), 'all');
  assert.equal(fresh.expenses.ai.usd, 0);
  assert.equal(fresh.expenses.ai.available, false);
});

test('weekly SBP clients are not classified as tests by price, name or email substring', async () => {
  const env = environment();
  await seedConfig(env);
  await order(env, 'client', { name: 'Сергей', email: 'sergei@example.com' });
  await order(env, 'test', { isTest: true });
  await order(env, 'owner', { accountEmail: 'mojomaker.play@gmail.com' });
  const result = await stats(env);
  assert.equal(result.revenue.grossRub, 99);
  assert.equal(result.revenue.ordersCount, 1);
  assert.equal(result.receipts.length, 3);
  assert.equal(isTestOrder({ amount: 99, method: 2, tier: 'weekly', name: 'Сергей', userId: 'contest' }), false);
  assert.equal(isTestOrder({ environment: 'Sandbox' }), true);
  await saveEconomyConfig(env, { excludeTestOrders: false });
  assert.equal((await stats(env)).revenue.grossRub, 297);
});

test('revenue and receipts both honor period and exclude future payments', async () => {
  const env = environment();
  await seedConfig(env);
  await order(env, 'old', { confirmedAt: '2026-09-20T12:00:00Z', amount: 200 });
  await order(env, 'current', { amount: 300 });
  await order(env, 'future', { confirmedAt: '2026-10-17T12:00:00Z', amount: 500 });
  await order(env, 'invalid', { confirmedAt: 'not-a-date', amount: 900 });
  const month = await stats(env);
  assert.equal(month.revenue.grossRub, 300);
  assert.deepEqual(month.receipts.map(item => item.id), ['current']);
  assert.equal((await stats(env, '30d')).revenue.grossRub, 500);
  assert.equal((await stats(env, 'all')).revenue.grossRub, 500);
});

test('manual revenue CRUD includes other income, dates and missing-record errors', async () => {
  const env = environment();
  await seedConfig(env);
  const added = await api(env, 'revenues/add', { title: 'Выплата', amountRub: 1000, store: 'other', date: '2026-10-01' });
  assert.equal(added.status, 200);
  const id = added.data.revenue.id;
  assert.equal((await stats(env)).revenue.grossRub, 1000);
  assert.equal((await stats(env)).revenue.otherRub, 1000);
  const updated = await api(env, 'revenues/update', { id, amountRub: 1200, store: 'appstore', date: '2026-09-01' });
  assert.equal(updated.status, 200);
  assert.equal((await stats(env)).revenue.grossRub, 0);
  assert.equal((await stats(env, 'all')).revenue.appstoreRub, 0);
  assert.equal((await stats(env, 'all')).receipts[0].includedInRevenue, false);
  assert.equal((await api(env, 'revenues/delete', { id })).status, 200);
  assert.equal((await api(env, 'revenues/delete', { id })).status, 404);
  const base = { title: 'Выплата', amountRub: 100, store: 'appstore', date: '2026-10-01' };
  for (const patch of [{ amountRub: 0 }, { date: '2026-02-30' }, { date: '2099-01-01' }, { store: '__proto__' }]) {
    assert.equal((await api(env, 'revenues/add', { ...base, ...patch })).status, 400);
  }
});

test('estimated store sales do not duplicate actual store payouts', async () => {
  const env = environment();
  await seedConfig(env, { manualRevenues: [{ id: 'payout', title: 'Apple payout', amountRub: 250, store: 'appstore', date: '2026-10-12' }] });
  const user = { id: 'apple-user', name: 'Маргарита', isPremium: true, premiumSource: 'appstore',
    purchasedAt: '2026-10-10T12:00:00Z', storeVerifiedAt: NOW, premiumExpiresAt: '2027-01-10T12:00:00Z',
    verifiedPurchase: { productId: 'ru.pdd.pddApp.sub.3months', transactionId: 'apple-tx' } };
  await env.INSTALLS.put('user:' + user.id, JSON.stringify(user));
  const result = await stats(env, 'month', { listUserSummaries: async () => [user, { ...user, id: 'duplicate-user' }, { id: 'free', isPremium: false }] });
  assert.equal(result.revenue.grossRub, 290);
  assert.equal(result.revenue.appstoreRub, 290);
  assert.equal(result.revenue.estimatedStoresRub, 290);
  assert.equal(result.revenue.estimatesIncludedInGross, true);
  assert.equal(result.receipts.length, 2);
  assert.equal(result.estimatedReceipts.length, 1);
  assert.equal(result.receipts.find(row => row.type === 'manual').includedInRevenue, false);
  assert.equal(result.estimatedReceipts[0].includedInRevenue, true);
  assert.equal(result.estimatedReceipts[0].dateBasis, 'purchase');
});

test('future and invalid store purchase dates do not break or inflate stats', async () => {
  const env = environment();
  await seedConfig(env);
  const users = [
    { id: 'missing', isPremium: true, premiumSource: 'appstore' },
    { id: 'invalid', isPremium: true, premiumSource: 'googleplay', purchasedAt: 'invalid' },
    { id: 'future', isPremium: true, premiumSource: 'appstore', purchasedAt: '2026-10-17T12:00:00Z' },
  ];
  const result = await stats(env, 'all', { listUserSummaries: async () => users });
  assert.equal(result.estimatedReceipts.length, 0);
  assert.equal(result.revenue.grossRub, 0);
});

test('positive profit distributes only after expenses and reserve, payouts sum exactly', async () => {
  const env = environment();
  await seedConfig(env, { reinvestPercent: 15, extraExpenses: [{ id: 'once', title: 'Покупка', amount: 50.01, date: '2026-10-01', frequency: 'once' }] });
  await order(env, 'income', { amount: 1000 });
  const result = await stats(env);
  assert.equal(result.profit.operatingRub, 949.99);
  assert.equal(result.profit.reinvestRub, 142.5);
  assert.equal(result.profit.distributableNetRub, 807.49);
  assert.equal(Math.round((result.partners.sergey.payoutRub + result.partners.nikita.payoutRub) * 100), 80749);
  assert.equal(result.breakEven.isProfitable, true);
});

test('paginated web receipts are all included', async () => {
  const env = environment();
  await seedConfig(env);
  for (let index = 0; index < 1002; index++) await order(env, String(index), { amount: 1 });
  const result = await stats(env);
  assert.equal(result.revenue.grossRub, 1002);
  assert.equal(result.receipts.length, 1002);
});

test('unknown period, malformed JSON and unsupported routes return errors', async () => {
  const env = environment();
  assert.equal((await api(env, 'stats?period=unknown', undefined, 'GET')).status, 400);
  assert.equal((await api(env, 'unknown', {})).status, 404);
  const request = new Request('https://test/api/admin/economy/settings', { method: 'POST', body: '{' });
  assert.equal((await handleEconomyAdmin(request, env, new URL(request.url))).status, 400);
  assert.equal((await api({}, 'expenses/add', { title: 'Example', amount: 10 })).status, 503);
});


test('Moscow month boundary scopes payments and date-only entries to the same calendar day', async () => {
  const env = environment();
  const midnight = Date.parse('2026-10-31T21:10:00Z'); // 1 ноября 00:10 МСК
  await seedConfig(env, { cloudflareMonthlyUsd: 0, domainMonthlyRub: 30,
    extraExpenses: [{ id: 'november', title: 'Расход', amount: 10, frequency: 'monthly', date: '2026-11-01' }],
    manualRevenues: [{ id: 'nov-income', title: 'Поступление', amountRub: 20, store: 'other', date: '2026-11-01' }] });
  await order(env, 'october', { amount: 100, confirmedAt: '2026-10-31T20:59:59Z' });
  await order(env, 'november', { amount: 200, confirmedAt: '2026-10-31T21:00:00Z' });
  const result = await stats(env, 'month', { now: midnight });
  assert.equal(result.periodInfo.from, '2026-11-01');
  assert.equal(result.periodInfo.to, '2026-11-01');
  assert.equal(result.periodInfo.timeZone, 'Europe/Moscow');
  assert.equal(result.revenue.grossRub, 220);
  assert.equal(result.expenses.domain.rub, 1);
  assert.equal(result.expenses.extraExpensesRub, 10);
  const revenue = await api(env, 'revenues/add', { title: 'Сегодня', amountRub: 5, date: '2026-11-01' }, 'POST', { now: midnight });
  assert.equal(revenue.status, 200);
  assert.equal((await stats(env, 'month', { now: midnight })).revenue.grossRub, 225);
  const tomorrow = await api(env, 'revenues/add', { title: 'Завтра', amountRub: 5, date: '2026-11-02' }, 'POST', { now: midnight });
  assert.equal(tomorrow.status, 400);
});

test('rolling period starts at Moscow midnight and includes exactly thirty calendar dates', async () => {
  const env = environment();
  await seedConfig(env);
  await order(env, 'before', { amount: 50, confirmedAt: '2026-09-16T20:59:59Z' });
  await order(env, 'first', { amount: 100, confirmedAt: '2026-09-16T21:00:00Z' });
  const result = await stats(env, '30d');
  assert.equal(result.periodInfo.from, '2026-09-17');
  assert.equal(result.periodInfo.to, '2026-10-16');
  assert.equal(result.revenue.grossRub, 100);
});

test('future legacy manual entries survive reads and unrelated writes without entering revenue', async () => {
  const env = environment();
  await seedConfig(env, { manualRevenues: [{ id: 'future', title: 'Будущая запись', amountRub: 100, store: 'other', date: '2099-01-01' }] });
  assert.equal((await getEconomyConfig(env)).manualRevenues.length, 1);
  await saveEconomyConfig(env, { domainMonthlyRub: 0 });
  assert.equal((await getEconomyConfig(env)).manualRevenues.length, 1);
  assert.equal((await stats(env, 'all')).revenue.grossRub, 0);
  const added = await api(env, 'revenues/add', { title: 'Текущая', amountRub: 50, store: 'other', date: '2026-10-01' });
  assert.equal(added.status, 200);
  assert.equal((await getEconomyConfig(env)).manualRevenues.length, 2);
  assert.equal((await stats(env, 'all')).revenue.grossRub, 50);
});

test('returned and rejected web orders retaining confirmedAt are excluded from receipts and income', async () => {
  const env = environment();
  await seedConfig(env);
  for (const status of ['chargebacked', 'refunded', 'mismatch', 'canceled', 'pending']) await order(env, status, { status, amount: 100 });
  await order(env, 'confirmed', { amount: 200 });
  const result = await stats(env);
  assert.equal(result.revenue.grossRub, 200);
  assert.deepEqual(result.receipts.map(receipt => receipt.id), ['confirmed']);
});


test('legacy ISO dates migrate to the Moscow day while date-only dates stay literal', async () => {
  const env = environment();
  await seedConfig(env, {
    extraExpenses: [{ id: 'legacy-time', title: 'Расход', amountRub: 100, monthly: false, createdAt: '2026-09-30T22:00:00Z' }],
    manualRevenues: [
      { id: 'iso', title: 'ISO', amountRub: 20, store: 'other', date: '2026-09-30T22:00:00Z' },
      { id: 'date-only', title: 'Дата', amountRub: 50, store: 'other', date: '2026-09-30' },
    ],
  });
  const config = await getEconomyConfig(env);
  assert.equal(config.extraExpenses[0].date, '2026-10-01');
  assert.equal(config.manualRevenues[0].date, '2026-10-01');
  assert.equal(config.manualRevenues[1].date, '2026-09-30');
  const now = Date.parse('2026-09-30T22:10:00Z'); // 1 октября 01:10 МСК
  const result = await stats(env, 'month', { now });
  assert.equal(result.revenue.grossRub, 20);
  assert.equal(result.expenses.extraExpensesRub, 100);
  assert.deepEqual(result.receipts.map(receipt => receipt.id), ['iso']);
  await saveEconomyConfig(env, { domainMonthlyRub: 0 });
  assert.equal((await getEconomyConfig(env)).manualRevenues[0].date, '2026-10-01');
});


test('infrastructure flags default to enabled for new and legacy configurations', async () => {
  const env = environment();
  const defaults = await getEconomyConfig(env);
  assert.equal(defaults.cloudflareEnabled, true);
  assert.equal(defaults.domainEnabled, true);
  await env.INSTALLS.put('economy_config', JSON.stringify({ cloudflareMonthlyUsd: 5, domainMonthlyRub: 67 }));
  const legacy = await stats(env);
  assert.equal(legacy.config.cloudflareEnabled, true);
  assert.equal(legacy.config.domainEnabled, true);
  assert.equal(legacy.expenses.monthlyRub, 542);
  assert.equal(legacy.expenses.lines.length, 2);
});

test('deleting builtin expenses disables their budget, preserves the rate and supports restoring', async () => {
  for (const [id, flag, amountKey, amount, source] of [
    ['builtin-cloudflare', 'cloudflareEnabled', 'cloudflareMonthlyUsd', 5, 'cloudflare'],
    ['builtin-domain', 'domainEnabled', 'domainMonthlyRub', 67, 'domain'],
  ]) {
    const env = environment();
    const otherFlag = flag === 'cloudflareEnabled' ? 'domainEnabled' : 'cloudflareEnabled';
    await seedConfig(env, { [amountKey]: amount, [otherFlag]: false,
      extraExpenses: [{ id: 'custom', title: 'Custom', amount: 25, currency: 'RUB', frequency: 'once', date: '2026-10-01' }] });
    const before = await stats(env);
    const previousCost = before.expenses[source].rub;
    assert.ok(previousCost > 0);
    const removed = await api(env, 'expenses/delete', { id });
    assert.equal(removed.status, 200);
    assert.equal(removed.data.id, id);
    const stored = await getEconomyConfig(env);
    assert.equal(stored[flag], false);
    assert.equal(stored[amountKey], amount);
    assert.equal(stored.extraExpenses.length, 1);
    const disabled = await stats(env);
    assert.equal(disabled.expenses.lines.some(line => line.id === id), false);
    assert.equal(disabled.expenses[source].rub, 0);
    assert.equal(disabled.expenses[source].monthlyRub, 0);
    assert.equal(disabled.expenses[source].enabled, false);
    assert.equal(disabled.expenses.monthlyRub, 0);
    assert.equal(disabled.expenses.recurringRub, 0);
    assert.equal(disabled.expenses.totalRub, 25);
    assert.equal(disabled.breakEven.monthlyRub, 0);
    assert.equal((await api(env, 'expenses/delete', { id })).status, 200);
    assert.equal((await api(env, 'settings', { [flag]: true })).status, 200);
    const restored = await stats(env);
    assert.equal(restored.expenses.lines.some(line => line.id === id), true);
    assert.equal(restored.expenses[source].rub, previousCost);
    assert.equal(restored.config[amountKey], amount);
    assert.equal(restored.expenses.extraList.length, 1);
  }
});

test('infrastructure enable settings accept only booleans and failed saves preserve prior flags', async () => {
  const env = environment();
  assert.equal((await api(env, 'settings', { cloudflareEnabled: false, domainEnabled: false })).status, 200);
  for (const key of ['cloudflareEnabled', 'domainEnabled']) {
    for (const value of ['false', 0, 1, null, [], {}]) {
      assert.equal((await api(env, 'settings', { [key]: value })).status, 400);
      assert.equal((await getEconomyConfig(env))[key], false);
    }
  }
  assert.equal((await api(env, 'revenues/delete', { id: 'builtin-cloudflare' })).status, 404);
  assert.equal((await getEconomyConfig(env)).cloudflareEnabled, false);
});


test('all store sales enter income and profit alongside SBP and other receipts', async () => {
  const env = environment();
  await seedConfig(env, { reinvestPercent: 50, nikitaSharePercent: 10,
    manualRevenues: [{ id: 'other', title: 'Доход', store: 'other', amountRub: 100, date: '2026-10-10' }] });
  await order(env, 'sbp', { amount: 99 });
  const users = ['appstore', 'googleplay', 'rustore'].map(store => ({
    id: store, premiumSource: store, isPremium: true, purchasedAt: '2026-10-10T12:00:00Z',
    verifiedPurchase: { store, transactionId: store + '-tx', productId: 'premium_3months' },
  }));
  users.push({ ...users[0], id: 'duplicate' });
  users.push({ ...users[1], id: 'sandbox', verifiedPurchase: { ...users[1].verifiedPurchase, transactionId: 'sandbox', environment: 'Sandbox' } });
  users.push({ ...users[0], id: 'old', purchasedAt: '2026-09-01T12:00:00Z', verifiedPurchase: { ...users[0].verifiedPurchase, transactionId: 'old' } });
  for (const user of users) await env.INSTALLS.put('user:' + user.id, JSON.stringify(user));
  const result = await stats(env, 'month', { listUserSummaries: async () => users });
  assert.equal(result.revenue.grossRub, 1069);
  assert.equal(result.revenue.includedStoreSalesRub, 870);
  assert.equal(result.revenue.estimatesIncludedInGross, true);
  assert.equal(result.revenue.appstoreRub, 290);
  assert.equal(result.revenue.gplayRub, 290);
  assert.equal(result.revenue.rustoreRub, 290);
  assert.equal(result.receipts.length, 6);
  assert.equal(result.profit.reinvestRub, 534.5);
  assert.equal(result.partners.nikita.payoutRub, 53.45);
  assert.equal(result.partners.sergey.payoutRub, 481.05);
  await saveEconomyConfig(env, { excludeTestOrders: false });
  assert.equal((await stats(env, 'month', { listUserSummaries: async () => users })).revenue.grossRub, 1359);
});

test('store purchase remains counted when another entitlement becomes the main source', async () => {
  const env = environment();
  await seedConfig(env);
  const user = { id: 'mixed', premiumSource: 'web', premiumExpiresAt: '2027-10-10T12:00:00Z', purchasedAt: '2026-10-10T12:00:00Z',
    verifiedPurchase: { store: 'appstore', transactionId: 'mixed-tx', productId: 'premium_week' } };
  await env.INSTALLS.put('user:mixed', JSON.stringify(user));
  const result = await stats(env, 'month', { listUserSummaries: async () => [user] });
  assert.equal(result.revenue.grossRub, 99);
  assert.equal(result.revenue.appstoreRub, 99);
  assert.equal(result.receipts[0].storeKey, 'appstore');
});


test('store payouts remain informational across periods', async () => {
  const env = environment();
  await seedConfig(env, { manualRevenues: [{ id: 'payout', title: 'Apple', store: 'appstore', amountRub: 250, date: '2026-09-20' }] });
  const users = ['appstore', 'googleplay'].map(store => ({ id: store, premiumSource: store,
    purchasedAt: '2026-10-10T12:00:00Z', verifiedPurchase: { store, transactionId: store, productId: 'premium_3months' } }));
  for (const user of users) await env.INSTALLS.put('user:' + user.id, JSON.stringify(user));
  const deps = { listUserSummaries: async () => users };
  assert.equal((await stats(env, 'month', deps)).revenue.grossRub, 580);
  const all = await stats(env, 'all', deps);
  assert.equal(all.revenue.grossRub, 580);
  assert.equal(all.revenue.appstoreRub, 290);
  assert.equal(all.revenue.gplayRub, 290);
  assert.equal(all.revenue.includedStoreSalesRub, 580);
  assert.equal(all.receipts.find(row => row.type === 'manual').includedInRevenue, false);
  assert.equal(all.estimatedReceipts.find(row => row.storeKey === 'googleplay').includedInRevenue, true);
});
