import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  DEFAULT_ECONOMY_CONFIG,
  getEconomyConfig,
  saveEconomyConfig,
  computeEconomyStats,
  handleEconomyAdmin,
} from './economy_admin.js';

class MemoryKV {
  constructor() {
    this.store = new Map();
  }
  async get(key) {
    return this.store.get(key) ?? null;
  }
  async put(key, val) {
    this.store.set(key, String(val));
  }
  async delete(key) {
    this.store.delete(key);
  }
  async list({ prefix = '', limit = 1000 } = {}) {
    const keys = [];
    for (const k of this.store.keys()) {
      if (k.startsWith(prefix)) {
        keys.push({ name: k });
        if (keys.length >= limit) break;
      }
    }
    return { keys, list_complete: true };
  }
}

test('дефолтные настройки экономики корректны', async () => {
  const env = { INSTALLS: new MemoryKV() };
  const cfg = await getEconomyConfig(env);
  assert.equal(cfg.usdRate, 95.0);
  assert.equal(cfg.cloudflareMonthlyUsd, 5.0);
  assert.equal(cfg.reinvestPercent, 15.0);
  assert.equal(cfg.nikitaSharePercent, 6.7);
  assert.equal(cfg.sergeySharePercent, 93.3);
});

test('сохранение и обновление настроек в KV', async () => {
  const env = { INSTALLS: new MemoryKV() };
  const updated = await saveEconomyConfig(env, {
    usdRate: 100.0,
    nikitaSharePercent: 10.0,
    reinvestPercent: 20.0,
  });
  assert.equal(updated.usdRate, 100.0);
  assert.equal(updated.nikitaSharePercent, 10.0);
  assert.equal(updated.sergeySharePercent, 90.0);
  assert.equal(updated.reinvestPercent, 20.0);

  const reloaded = await getEconomyConfig(env);
  assert.equal(reloaded.usdRate, 100.0);
  assert.equal(reloaded.nikitaSharePercent, 10.0);
  assert.equal(reloaded.sergeySharePercent, 90.0);
  assert.equal(reloaded.reinvestPercent, 20.0);
});

test('расчёт экономики при отсутствии выручки (только расходы)', async () => {
  const env = { INSTALLS: new MemoryKV() };
  const stats = await computeEconomyStats(env, 'month', {
    listUserSummaries: async () => [],
  });

  // Расходы: Cloudflare $5 (5*95 = 475) + ИИ ~$0.18 (~17.10)
  assert.ok(stats.expenses.totalRub >= 475);
  assert.equal(stats.revenue.grossRub, 0);
  assert.ok(stats.profit.operatingRub < 0);
  assert.equal(stats.profit.reinvestRub, 0);
  assert.equal(stats.partners.sergey.payoutRub, 0);
  assert.equal(stats.partners.nikita.payoutRub, 0);
  assert.equal(stats.breakEven.isProfitable, false);
  assert.ok(stats.breakEven.weeklySubsNeeded >= 5);
  assert.ok(stats.breakEven.threeMonthSubsNeeded >= 2);
});

test('расчёт экономики с выручкой: вычет расходов, 15% реинвестиций и долей 93.3% / 6.7%', async () => {
  const env = { INSTALLS: new MemoryKV() };

  // Добавим подтверждённый заказ в KV
  const order = {
    orderId: 'ord-123',
    status: 'confirmed',
    amount: 10000,
    tier: 'threeMonths',
    createdAt: new Date().toISOString(),
    confirmedAt: new Date().toISOString(),
  };
  await env.INSTALLS.put('pay_order:ord-123', JSON.stringify(order));

  const stats = await computeEconomyStats(env, 'month', {
    listUserSummaries: async () => [
      { id: 'u1', isPremium: true, premiumSource: 'web' },
      { id: 'u2', isPremium: false },
    ],
  });

  assert.equal(stats.revenue.grossRub, 10000);
  assert.equal(stats.revenue.ordersCount, 1);
  assert.ok(stats.profit.operatingRub > 9000);

  // Проверка реинвестиций: ровно 15% от операционной прибыли
  const expectedReinvest = Number(((stats.profit.operatingRub * 0.15)).toFixed(2));
  assert.equal(stats.profit.reinvestRub, expectedReinvest);

  // Распределяемая прибыль = операционная - реинвестиции
  const expectedDistributable = Number((stats.profit.operatingRub - stats.profit.reinvestRub).toFixed(2));
  assert.equal(stats.profit.distributableNetRub, expectedDistributable);

  // Выплаты Сергею (93.3%) и Никите (6.7%)
  const expectedSergey = Number(((expectedDistributable * 0.933)).toFixed(2));
  const expectedNikita = Number(((expectedDistributable * 0.067)).toFixed(2));
  assert.equal(stats.partners.sergey.payoutRub, expectedSergey);
  assert.equal(stats.partners.nikita.payoutRub, expectedNikita);

  assert.equal(stats.breakEven.isProfitable, true);
});

test('тестовая покупка за 99 ₽ исключается из выручки, но доступна в чеках', async () => {
  const env = { INSTALLS: new MemoryKV() };

  // Тестовый заказ от Сергея на 99 ₽
  const testOrder = {
    orderId: 'test-sergei-99',
    status: 'confirmed',
    amount: 99,
    tier: 'weekly',
    method: 'sbp',
    name: 'Сергей',
    accountEmail: 'mojomaker.play@gmail.com',
    createdAt: new Date().toISOString(),
    confirmedAt: new Date().toISOString(),
  };
  await env.INSTALLS.put('pay_order:test-sergei-99', JSON.stringify(testOrder));

  const stats = await computeEconomyStats(env, 'month', {
    listUserSummaries: async () => [],
  });

  // Выручка должна быть 0, так как тестовый заказ 99 ₽ исключён
  assert.equal(stats.revenue.grossRub, 0);
  assert.equal(stats.revenue.ordersCount, 0);

  // При этом в чеках он присутствует с пометкой isTest: true
  assert.equal(stats.receipts.length, 1);
  assert.equal(stats.receipts[0].id, 'test-sergei-99');
  assert.equal(stats.receipts[0].isTest, true);

  // Домен включен в расходы
  assert.equal(stats.expenses.domain.rub, 67.0);
  assert.ok(stats.expenses.totalRub >= 475 + 67);
});

test('API эндпоинты: /api/admin/economy/stats, expenses/add, expenses/delete', async () => {
  const env = { INSTALLS: new MemoryKV() };

  // 1. GET stats
  const reqGet = new Request('https://test/api/admin/economy/stats?period=month');
  const resGet = await handleEconomyAdmin(reqGet, env, new URL(reqGet.url), {
    listUserSummaries: async () => [],
  });
  assert.equal(resGet.status, 200);
  const dataGet = await resGet.json();
  assert.equal(dataGet.ok, true);
  assert.ok(dataGet.config);

  // 2. POST add expense
  const reqAdd = new Request('https://test/api/admin/economy/expenses/add', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: 'Домен pdd-drive.ru', amountRub: 1200, monthly: false }),
  });
  const resAdd = await handleEconomyAdmin(reqAdd, env, new URL(reqAdd.url));
  assert.equal(resAdd.status, 200);
  const dataAdd = await resAdd.json();
  assert.equal(dataAdd.ok, true);
  assert.equal(dataAdd.expense.title, 'Домен pdd-drive.ru');
  const expId = dataAdd.expense.id;

  // 3. Проверяем в stats
  const resGet2 = await handleEconomyAdmin(reqGet, env, new URL(reqGet.url), {
    listUserSummaries: async () => [],
  });
  const dataGet2 = await resGet2.json();
  assert.equal(dataGet2.expenses.extraExpensesRub, 1200);

  // 4. POST delete expense
  const reqDel = new Request('https://test/api/admin/economy/expenses/delete', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: expId }),
  });
  const resDel = await handleEconomyAdmin(reqDel, env, new URL(reqDel.url));
  assert.equal(resDel.status, 200);
  const dataDel = await resDel.json();
  assert.equal(dataDel.ok, true);

  // 5. Проверяем удаление
  const resGet3 = await handleEconomyAdmin(reqGet, env, new URL(reqGet.url), {
    listUserSummaries: async () => [],
  });
  const dataGet3 = await resGet3.json();
  assert.equal(dataGet3.expenses.extraExpensesRub, 0);
});

test('покупки из App Store / Google Play извлекаются из профилей пользователей в выручку и чеки', async () => {
  const env = { INSTALLS: new MemoryKV() };

  // Пользователь с покупкой на 3 месяца через App Store
  const user1 = {
    id: 'apple_u1',
    name: 'Маргарита',
    email: 'margarita@test.com',
    isPremium: true,
    premiumSource: 'appstore',
    premiumExpiresAt: '2027-01-07T19:40:40.000Z',
    storeVerifiedAt: Date.now() - 86400000,
    verifiedPurchase: {
      store: 'appstore',
      productId: 'ru.pdd.pddApp.sub.3months',
      transactionId: 'tx-apple-3m',
    },
  };
  await env.INSTALLS.put('user:apple_u1', JSON.stringify(user1));

  // Пользователь с покупкой на 1 неделю через App Store
  const user2 = {
    id: 'apple_u2',
    name: 'Арина',
    email: 'arina@test.com',
    isPremium: true,
    premiumSource: 'appstore',
    premiumExpiresAt: '2026-10-15T12:00:00.000Z',
    storeVerifiedAt: Date.now() - 3600000,
    verifiedPurchase: {
      store: 'appstore',
      productId: 'u.pdd.pddApp.premium.week',
      transactionId: 'tx-apple-1w',
    },
  };
  await env.INSTALLS.put('user:apple_u2', JSON.stringify(user2));

  const stats = await computeEconomyStats(env, 'month', {
    listUserSummaries: async () => [
      { id: 'apple_u1', isPremium: true, premiumSource: 'appstore', storeVerifiedAt: user1.storeVerifiedAt, premiumExpiresAt: user1.premiumExpiresAt, name: user1.name, email: user1.email },
      { id: 'apple_u2', isPremium: true, premiumSource: 'appstore', storeVerifiedAt: user2.storeVerifiedAt, premiumExpiresAt: user2.premiumExpiresAt, name: user2.name, email: user2.email },
      { id: 'free_u', isPremium: false },
    ],
  });

  // Доход: 290 ₽ + 99 ₽ = 389 ₽
  assert.equal(stats.revenue.appstoreRub, 389);
  assert.equal(stats.revenue.grossRub, 389);
  assert.equal(stats.revenue.activePayingCount, 2);

  // Чеки присутствуют в списке
  assert.equal(stats.receipts.length, 2);
  const txIds = stats.receipts.map(r => r.txId);
  assert.ok(txIds.includes('tx-apple-3m'));
  assert.ok(txIds.includes('tx-apple-1w'));
  const r3m = stats.receipts.find(r => r.txId === 'tx-apple-3m');
  assert.equal(r3m.amountRub, 290);
  assert.equal(r3m.tier, '3 месяца');
  assert.equal(r3m.store, 'App Store');
});

