// Админский учёт экономики. Платежи и сроки Premium здесь не изменяются.
// Денежные поступления, оценки продаж и бюджет расходов считаются отдельно.
export const DEFAULT_ECONOMY_CONFIG = {
  usdRate: 95,
  cloudflareMonthlyUsd: 5,
  cloudflareEnabled: true,
  domainMonthlyRub: 67,
  domainEnabled: true,
  reinvestPercent: 15,
  nikitaSharePercent: 6.7,
  sergeySharePercent: 93.3,
  targetMonthlyProfit: 50000,
  excludeTestOrders: true,
  extraExpenses: [],
  manualRevenues: [],
};
const CONFIG_KEY = 'economy_config';
const DAY = 86400000;
// Вся админка ведёт календарные даты по МСК (UTC+3). Суррогат UTC
// используется только для арифметики календаря, а не для времени платежа.
const MOSCOW_OFFSET = 3 * 3600000;
const stores = { web: 'СБП (Platega)', appstore: 'App Store', googleplay: 'Google Play', rustore: 'RuStore', other: 'Другое' };
const numericRules = {
  usdRate: [0.0001, 100000], cloudflareMonthlyUsd: [0, 100000000],
  domainMonthlyRub: [0, 100000000], reinvestPercent: [0, 100],
  nikitaSharePercent: [0, 100], sergeySharePercent: [0, 100],
  targetMonthlyProfit: [0, 1000000000],
};
const booleanSettings = ['excludeTestOrders', 'cloudflareEnabled', 'domainEnabled'];
const round = value => Math.round((value + Number.EPSILON) * 100) / 100;
const dayString = value => new Date(value).toISOString().slice(0, 10);
const dayStart = value => Date.parse(dayString(value));
const reportDay = value => dayString(value + MOSCOW_OFFSET);
function reply(data, status = 200) {
  return Response.json(data, { status, headers: { 'Cache-Control': 'no-store' } });
}
function object(value) {
  return value && typeof value === 'object' && !Array.isArray(value);
}
function number(value, label, min = 0, max = 1000000000) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
    throw new Error('Некорректное значение: ' + label);
  }
  return value;
}
function date(value, label, fallback) {
  if (value === undefined || value === null || value === '') {
    if (fallback) return fallback;
    throw new Error('Укажите дату: ' + label);
  }
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2}))?$/.test(value)) {
    throw new Error('Некорректная дата: ' + label);
  }
  const day = value.slice(0, 10);
  const stamp = Date.parse(value);
  const midnight = Date.parse(day);
  if (!Number.isFinite(stamp) || !Number.isFinite(midnight) || dayString(midnight) !== day || day < '2000-01-01' || day > '2100-12-31') {
    throw new Error('Некорректная дата: ' + label);
  }
  return value.length > 10 ? reportDay(stamp) : day;
}
function title(value) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > 160) throw new Error('Название: от 1 до 160 символов');
  return value.trim();
}
function normalizeExpense(input, now = Date.now()) {
  if (!object(input)) throw new Error('Некорректный расход');
  const frequency = input.frequency ?? (input.monthly ? 'monthly' : 'once');
  if (!['once', 'monthly', 'yearly'].includes(frequency)) throw new Error('Укажите периодичность расхода');
  const currency = input.currency ?? 'RUB';
  if (!['RUB', 'USD'].includes(currency)) throw new Error('Укажите валюту RUB или USD');
  const amount = number(input.amount ?? input.amountRub, 'сумма расхода', 0.01);
  const starts = date(input.date ?? input.createdAt, 'расход', reportDay(now));
  const endDate = input.endDate ? date(input.endDate, 'окончание') : null;
  if (endDate && endDate < starts) throw new Error('Дата окончания раньше даты начала');
  return {
    id: typeof input.id === 'string' ? input.id : crypto.randomUUID(),
    title: title(input.title), amount, currency, frequency, date: starts, endDate,
    // Совместимость с сохранёнными расходами и предыдущей версией панели.
    amountRub: currency === 'RUB' ? amount : undefined, monthly: frequency === 'monthly',
    createdAt: input.createdAt || new Date(now).toISOString(),
  };
}
function normalizeRevenue(input, now = Date.now(), allowFuture = false) {
  if (!object(input)) throw new Error('Некорректное поступление');
  const store = input.store ?? 'other';
  if (!Object.hasOwn(stores, store)) throw new Error('Укажите источник поступления');
  const received = date(input.date ?? input.createdAt, 'поступление', reportDay(now));
  if (!allowFuture && received > reportDay(now)) throw new Error('Поступление не может быть в будущем');
  return { id: typeof input.id === 'string' ? input.id : crypto.randomUUID(),
    title: title(input.title), amountRub: number(input.amountRub, 'сумма поступления', 0.01), store,
    date: received, createdAt: input.createdAt || new Date(now).toISOString() };
}
function normalizeList(items, normalize) {
  if (!Array.isArray(items)) return [];
  return items.flatMap(item => { try { return [normalize(item)]; } catch (_) { return []; } });
}
function safeConfig(parsed = {}) {
  const result = { ...DEFAULT_ECONOMY_CONFIG, extraExpenses: [], manualRevenues: [] };
  for (const [key, [min, max]] of Object.entries(numericRules)) {
    const value = parsed[key];
    if (typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max) result[key] = value;
  }
  if (!Object.hasOwn(parsed, 'nikitaSharePercent') && typeof parsed.sergeySharePercent === 'number') result.nikitaSharePercent = round(100 - result.sergeySharePercent);
  result.sergeySharePercent = round(100 - result.nikitaSharePercent);
  for (const key of booleanSettings) {
    if (typeof parsed[key] === 'boolean') result[key] = parsed[key];
  }
  result.extraExpenses = normalizeList(parsed.extraExpenses, normalizeExpense);
  result.manualRevenues = normalizeList(parsed.manualRevenues, item => normalizeRevenue(item, Date.now(), true));
  return result;
}
export function isTestOrder(order) {
  if (!order) return false;
  if (order.isTest === true || order.test === true || String(order.environment || '').toLowerCase() === 'sandbox') return true;
  // Старые собственные проверки не имели isTest. Цена 99 ₽, имя и способ
  // оплаты не являются признаками теста: это также обычные покупки клиентов.
  const email = String(order.email || order.accountEmail || '').trim().toLowerCase();
  return email === 'mojomaker.play@gmail.com';
}
export async function getEconomyConfig(env) {
  if (!env?.INSTALLS) return safeConfig();
  try { return safeConfig(JSON.parse(await env.INSTALLS.get(CONFIG_KEY) || '{}')); }
  catch (_) { return safeConfig(); }
}
export async function saveEconomyConfig(env, updates) {
  if (!env?.INSTALLS) throw new Error('Хранилище недоступно');
  if (!object(updates)) throw new Error('Некорректные настройки');
  const next = await getEconomyConfig(env);
  for (const [key, value] of Object.entries(updates)) {
    if (numericRules[key]) next[key] = number(value, key, ...numericRules[key]);
    else if (booleanSettings.includes(key)) {
      if (typeof value !== 'boolean') throw new Error('Некорректное значение: ' + key);
      next[key] = value;
    } else if (key === 'extraExpenses' || key === 'manualRevenues') {
      if (!Array.isArray(value) || value.length > 1000) throw new Error('Слишком много записей');
      next[key] = value.map(item => key === 'extraExpenses' ? normalizeExpense(item) : normalizeRevenue(item, Date.now(), true));
    } else throw new Error('Неизвестная настройка: ' + key);
  }
  const hasNikita = Object.hasOwn(updates, 'nikitaSharePercent');
  const hasSergey = Object.hasOwn(updates, 'sergeySharePercent');
  if (hasNikita && hasSergey && Math.abs(updates.nikitaSharePercent + updates.sergeySharePercent - 100) > 0.001) throw new Error('Сумма долей должна быть 100%');
  if (hasSergey && !hasNikita) next.nikitaSharePercent = round(100 - next.sergeySharePercent);
  next.sergeySharePercent = round(100 - next.nikitaSharePercent);
  await env.INSTALLS.put(CONFIG_KEY, JSON.stringify(next));
  return next;
}
async function listAll(env, prefix) {
  if (!env?.INSTALLS) return [];
  const keys = [];
  let cursor;
  do {
    const page = await env.INSTALLS.list({ prefix, limit: 1000, ...(cursor ? { cursor } : {}) });
    keys.push(...(page.keys || []));
    cursor = !page.list_complete && page.cursor ? page.cursor : null;
  } while (cursor);
  return keys;
}
function timestamp(value) {
  const parsed = typeof value === 'number' ? value
    : typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) ? Date.parse(value) - MOSCOW_OFFSET
    : Date.parse(value || '');
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}
function inPeriod(time, start, now) { return time !== null && time >= start && time <= now; }
function dueDate(expense, index) {
  const start = new Date(expense.date + 'T00:00:00Z');
  const month = start.getUTCMonth() + index * (expense.frequency === 'yearly' ? 12 : 1);
  const first = new Date(Date.UTC(start.getUTCFullYear(), month, 1));
  const lastDay = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
  return Date.UTC(first.getUTCFullYear(), first.getUTCMonth(), Math.min(start.getUTCDate(), lastDay));
}
function occurrences(expense, periodStart, now) {
  const start = Date.parse(expense.date);
  const end = Math.min(now, expense.endDate ? Date.parse(expense.endDate) + DAY - 1 : now);
  if (end < start) return 0;
  if (expense.frequency === 'once') return inPeriod(start, periodStart, end) ? 1 : 0;
  const from = new Date(Math.max(periodStart, start));
  const anchor = new Date(start);
  const monthDelta = (from.getUTCFullYear() - anchor.getUTCFullYear()) * 12 + from.getUTCMonth() - anchor.getUTCMonth();
  const step = expense.frequency === 'yearly' ? 12 : 1;
  let i = Math.max(0, Math.floor(monthDelta / step));
  let count = 0;
  for (let due = dueDate(expense, i); due <= end; due = dueDate(expense, ++i)) {
    if (due >= periodStart) count++;
  }
  return count;
}
// Инфраструктура без дат списания — именно бюджет, пропорционально дням
// каждого календарного месяца. Текущий день включён; будущие дни исключены.
function budgetMonths(start, now) {
  let cursor = dayStart(start);
  const end = dayStart(now) + DAY;
  let months = 0;
  while (cursor < end) {
    const date = new Date(cursor);
    const nextMonth = Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1);
    const daysInMonth = new Date(nextMonth - DAY).getUTCDate();
    const until = Math.min(end, nextMonth);
    months += (until - cursor) / DAY / daysInMonth;
    cursor = until;
  }
  return months;
}
export async function computeEconomyStats(env, period = 'month', deps = {}) {
  if (!['month', '30d', 'all'].includes(period)) throw new Error('Неизвестный период');
  const now = deps.now ?? Date.now();
  const calendarNow = Date.parse(reportDay(now));
  const nowDate = new Date(calendarNow);
  const monthStart = Date.UTC(nowDate.getUTCFullYear(), nowDate.getUTCMonth(), 1);
  const calendarPeriodStart = period === 'month' ? monthStart : period === '30d' ? calendarNow - 29 * DAY : 0;
  const periodStart = period === 'all' ? 0 : calendarPeriodStart - MOSCOW_OFFSET;
  const config = await getEconomyConfig(env);
  const receipts = [], estimatedReceipts = [];
  const knownDates = [];
  const revenueByStore = { web: 0, appstore: 0, googleplay: 0, rustore: 0, other: 0 };
  const remember = value => { const time = timestamp(value); if (time !== null && time <= now) knownDates.push(time); return time; };
  let webConfirmedOrdersCount = 0;
  for (const key of await listAll(env, 'pay_order:')) {
    try {
      const order = JSON.parse(await env.INSTALLS.get(key.name));
      // Возврат сохраняет confirmedAt. Историческая дата подтверждения
      // не делает chargebacked/canceled/mismatch оплату доходом.
      if (!order || (order.status ? order.status !== 'confirmed' : !order.confirmedAt)) continue;
      const time = remember(order.confirmedAt || order.createdAt);
      if (!inPeriod(time, periodStart, now)) continue;
      const amount = Number(order.amount);
      if (!Number.isFinite(amount) || amount <= 0) continue;
      const isTest = isTestOrder(order);
      receipts.push({ id: order.orderId || order.txId || key.name, date: new Date(time).toISOString(),
        customer: order.name || order.accountEmail || order.email || order.userId || 'Пользователь',
        email: order.email || order.accountEmail || '', store: stores.web, storeKey: 'web',
        tier: order.tier === 'threeMonths' ? '3 месяца' : '1 неделя', amountRub: amount,
        txId: order.txId || order.orderId || key.name, isTest, status: 'confirmed', type: 'payment',
        includedInRevenue: !isTest || !config.excludeTestOrders });
      if (!isTest || !config.excludeTestOrders) { revenueByStore.web += amount; webConfirmedOrdersCount++; }
    } catch (_) { /* Повреждённая отдельная запись не скрывает всю страницу. */ }
  }
  let users = [];
  if (typeof deps.listUserSummaries === 'function') users = await deps.listUserSummaries(env);
  const storeCounts = { web: 0, appstore: 0, googleplay: 0, rustore: 0, admin_grant: 0 };
  let activePayingCount = 0;
  const seenTransactions = new Set();
  for (const user of users) {
    remember(user.createdAt);
    const source = String(user.premiumSource || '').toLowerCase();
    const expiry = timestamp(user.premiumExpiresAt);
    if (user.isPremium && (!expiry || expiry > now)) {
      if (Object.hasOwn(storeCounts, source)) storeCounts[source]++;
      if (['web', 'appstore', 'googleplay', 'rustore'].includes(source)) activePayingCount++;
    }
    if (!['appstore', 'googleplay', 'rustore'].includes(source)) continue;
    let full = user;
    try { full = JSON.parse(await env.INSTALLS.get('user:' + user.id) || 'null') || user; } catch (_) {}
    const purchase = full.verifiedPurchase || {};
    // Проверка подписки может повторяться: storeVerifiedAt не дата продажи.
    const time = remember(full.purchasedAt || user.purchasedAt || full.storeVerifiedAt || user.storeVerifiedAt);
    if (!inPeriod(time, periodStart, now)) continue;
    const txId = purchase.transactionId || purchase.orderId || user.id;
    const unique = source + ':' + txId;
    if (seenTransactions.has(unique)) continue;
    seenTransactions.add(unique);
    const product = String(purchase.productId || '').toLowerCase();
    const duration = expiry && time ? (expiry - time) / DAY : 0;
    const is3m = product.includes('3month') || duration >= 60;
    const isTest = isTestOrder({ ...full, environment: purchase.environment });
    estimatedReceipts.push({ id: txId, date: new Date(time).toISOString(), customer: user.name || user.email || 'Пользователь',
      email: user.email || '', store: stores[source], storeKey: source, tier: is3m ? '3 месяца' : '1 неделя',
      amountRub: is3m ? 290 : 99, txId, isTest, status: 'estimated', type: 'estimate', includedInRevenue: false,
      dateBasis: full.purchasedAt || user.purchasedAt ? 'purchase' : 'verification' });
  }
  let manualRevenuesRub = 0;
  for (const revenue of config.manualRevenues) {
    const time = remember(revenue.date);
    if (!inPeriod(time, periodStart, now)) continue;
    revenueByStore[revenue.store] += revenue.amountRub;
    manualRevenuesRub += revenue.amountRub;
    receipts.push({ id: revenue.id, date: revenue.date, customer: revenue.title, email: '', store: stores[revenue.store],
      storeKey: revenue.store, tier: 'Поступление', amountRub: revenue.amountRub, txId: revenue.id,
      isTest: false, status: 'confirmed', type: 'manual', includedInRevenue: true, editable: true });
  }
  config.extraExpenses.forEach(expense => remember(expense.date));
  const budgetStart = period === 'all'
    ? (knownDates.length ? Date.parse(reportDay(Math.min(...knownDates))) : monthStart)
    : calendarPeriodStart;
  const multiplier = budgetMonths(budgetStart, calendarNow);
  const cloudflareMonthlyRub = config.cloudflareEnabled ? round(config.cloudflareMonthlyUsd * config.usdRate) : 0;
  const domainMonthlyRub = config.domainEnabled ? config.domainMonthlyRub : 0;
  const cloudflarePeriodRub = round(cloudflareMonthlyRub * multiplier);
  const domainPeriodRub = round(domainMonthlyRub * multiplier);
  const lines = [
    { id: 'builtin-cloudflare', title: 'Cloudflare', amount: config.cloudflareMonthlyUsd, currency: 'USD', frequency: 'monthly',
      date: dayString(budgetStart), endDate: null, builtin: true, source: 'cloudflare', basis: 'budget',
      periodRub: cloudflarePeriodRub, monthlyRub: cloudflareMonthlyRub, occurrences: null },
    { id: 'builtin-domain', title: 'Домен pdd-drive.ru', amount: config.domainMonthlyRub, currency: 'RUB', frequency: 'monthly',
      date: dayString(budgetStart), endDate: null, builtin: true, source: 'domain', basis: 'budget',
      periodRub: domainPeriodRub, monthlyRub: domainMonthlyRub, occurrences: null },
  ].filter(line => line.source === 'cloudflare' ? config.cloudflareEnabled : config.domainEnabled);
  let extraExpensesRub = 0, oneOffRub = 0, recurringRub = lines.reduce((sum, line) => sum + line.periodRub, 0);
  let monthlyRub = cloudflareMonthlyRub + domainMonthlyRub;
  for (const expense of config.extraExpenses) {
    const amountRub = expense.amount * (expense.currency === 'USD' ? config.usdRate : 1);
    const count = occurrences(expense, calendarPeriodStart, calendarNow);
    const periodRub = round(amountRub * count);
    const activeRecurring = expense.frequency !== 'once' && expense.date <= reportDay(now) && (!expense.endDate || expense.endDate >= reportDay(now));
    const monthly = activeRecurring ? round(amountRub / (expense.frequency === 'yearly' ? 12 : 1)) : 0;
    extraExpensesRub += periodRub;
    monthlyRub += monthly;
    if (expense.frequency === 'once') oneOffRub += periodRub; else recurringRub += periodRub;
    lines.push({ ...expense, builtin: false, source: 'custom', basis: 'scheduled', amountRub: round(amountRub),
      periodRub, monthlyRub: monthly, occurrences: count });
  }
  const aiKeys = ['ai_stats_cost_usd', 'ai_stats_total_req', 'ai_stats_prompt_tokens', 'ai_stats_candidate_tokens'];
  const aiValues = env?.INSTALLS ? await Promise.all(aiKeys.map(key => env.INSTALLS.get(key))) : [];
  const aiNumbers = aiValues.map(value => Math.max(0, Number(value) || 0));
  const aiCostUsd = aiNumbers[0] || 0;
  const aiCostRub = round(aiCostUsd * config.usdRate);
  const aiIncluded = period === 'all' && aiValues[0] !== null && aiValues[0] !== undefined;
  // В KV есть только накопительная стоимость ИИ. Не приписываем её месяцу.
  const aiPeriodRub = aiIncluded ? aiCostRub : 0;
  const totalExpensesRub = round(recurringRub + oneOffRub + aiPeriodRub);
  const grossRevenueRub = round(Object.values(revenueByStore).reduce((sum, value) => sum + value, 0));
  const operatingProfitRub = round(grossRevenueRub - totalExpensesRub);
  const reinvestRub = round(Math.max(0, operatingProfitRub) * config.reinvestPercent / 100);
  const distributableNetProfitRub = round(operatingProfitRub - reinvestRub);
  const payout = Math.max(0, distributableNetProfitRub);
  const nikitaPayoutRub = round(payout * config.nikitaSharePercent / 100);
  const sergeyPayoutRub = round(payout - nikitaPayoutRub);
  receipts.sort((a, b) => timestamp(b.date) - timestamp(a.date));
  estimatedReceipts.sort((a, b) => timestamp(b.date) - timestamp(a.date));
  const estimatedStoresRub = round(estimatedReceipts.reduce((sum, receipt) => sum + ((!receipt.isTest || !config.excludeTestOrders) ? receipt.amountRub : 0), 0));
  return {
    period, updatedAt: new Date(now).toISOString(),
    periodInfo: { from: dayString(budgetStart), to: reportDay(now), timeZone: 'Europe/Moscow',
      budgetMonths: Math.round(multiplier * 10000) / 10000, infrastructureBasis: 'prorated_monthly_budget',
      allTimeStartBasis: period === 'all' ? 'earliest_known_record' : undefined },
    config,
    revenue: { grossRub: grossRevenueRub, webRub: round(revenueByStore.web), appstoreRub: round(revenueByStore.appstore),
      gplayRub: round(revenueByStore.googleplay), rustoreRub: round(revenueByStore.rustore), otherRub: round(revenueByStore.other),
      manualRub: round(manualRevenuesRub), ordersCount: webConfirmedOrdersCount, activePayingCount, storeCounts,
      estimatedStoresRub, estimatesIncludedInGross: false },
    receipts, estimatedReceipts,
    expenses: { totalRub: totalExpensesRub, monthlyRub: round(monthlyRub), recurringRub: round(recurringRub), oneOffRub: round(oneOffRub),
      lines, cloudflare: { usd: config.cloudflareMonthlyUsd, rub: cloudflarePeriodRub, monthlyRub: cloudflareMonthlyRub, enabled: config.cloudflareEnabled, basis: 'budget' },
      domain: { rub: domainPeriodRub, monthlyRub: domainMonthlyRub, enabled: config.domainEnabled, basis: 'budget' },
      ai: { usd: Number(aiCostUsd.toFixed(6)), rub: aiCostRub, periodRub: aiPeriodRub, scope: 'all',
        includedInTotal: aiIncluded, available: aiValues[0] !== null && aiValues[0] !== undefined,
        totalRequests: aiNumbers[1] || 0, promptTokens: aiNumbers[2] || 0, candidateTokens: aiNumbers[3] || 0 },
      extraExpensesRub: round(extraExpensesRub), extraList: lines.filter(line => !line.builtin) },
    profit: { operatingRub: operatingProfitRub, reinvestPercent: config.reinvestPercent, reinvestRub,
      distributableNetRub: distributableNetProfitRub, marginPercent: grossRevenueRub > 0 ? round(distributableNetProfitRub / grossRevenueRub * 100) : 0 },
    partners: {
      sergey: { name: 'Сергей', role: 'Основатель / Разработка', percent: config.sergeySharePercent, payoutRub: sergeyPayoutRub },
      nikita: { name: 'Никита', role: 'Партнёр / Развитие', percent: config.nikitaSharePercent, payoutRub: nikitaPayoutRub },
    },
    breakEven: { targetRub: totalExpensesRub, monthlyRub: round(monthlyRub), weeklySubsNeeded: Math.ceil(totalExpensesRub / 99),
      threeMonthSubsNeeded: Math.ceil(totalExpensesRub / 290), coveragePercent: totalExpensesRub > 0 ? Math.round(grossRevenueRub / totalExpensesRub * 100) : 100,
      isProfitable: grossRevenueRub >= totalExpensesRub },
    unitEconomics: { totalUsersCount: users.length, activePayingCount,
      payingConversionRate: users.length ? round(activePayingCount / users.length * 100) : 0,
      arppu: activePayingCount ? round(grossRevenueRub / activePayingCount) : 0, arpu: users.length ? round(grossRevenueRub / users.length) : 0 },
  };
}
export async function handleEconomyAdmin(request, env, url, deps = {}) {
  const path = url.pathname;
  if (path === '/api/admin/economy/stats' && request.method === 'GET') {
    const period = url.searchParams.get('period') || 'month';
    if (!['month', '30d', 'all'].includes(period)) return reply({ error: 'Неизвестный период' }, 400);
    return reply({ ok: true, ...await computeEconomyStats(env, period, deps) });
  }
  const match = path.match(/^\/api\/admin\/economy\/(expenses|revenues)\/(add|update|delete)$/);
  if (request.method !== 'POST' || (!match && path !== '/api/admin/economy/settings')) return reply({ error: 'not found' }, 404);
  let body;
  try { body = await request.json(); } catch (_) { return reply({ error: 'Некорректный JSON' }, 400); }
  if (!object(body)) return reply({ error: 'Некорректные данные' }, 400);
  if (!env?.INSTALLS) return reply({ error: 'Хранилище недоступно' }, 503);
  if (path.endsWith('/settings')) {
    if (Object.hasOwn(body, 'extraExpenses') || Object.hasOwn(body, 'manualRevenues')) return reply({ error: 'Изменяйте записи через список расходов и поступлений' }, 400);
    try { return reply({ ok: true, config: await saveEconomyConfig(env, body) }); }
    catch (error) { return reply({ error: error.message }, 400); }
  }
  const [, kind, action] = match;
  const key = kind === 'expenses' ? 'extraExpenses' : 'manualRevenues';
  const config = await getEconomyConfig(env);
  const list = config[key];
  const id = typeof body.id === 'string' ? body.id : '';
  const builtinConfigKey = id === 'builtin-cloudflare' ? 'cloudflareEnabled' : id === 'builtin-domain' ? 'domainEnabled' : null;
  if (kind === 'expenses' && action === 'delete' && builtinConfigKey) {
    await saveEconomyConfig(env, { [builtinConfigKey]: false });
    return reply({ ok: true, id });
  }
  const index = list.findIndex(item => item.id === id);
  if (action !== 'add' && !id) return reply({ error: 'Не указан ID' }, 400);
  if (action !== 'add' && index < 0) return reply({ error: 'Запись не найдена' }, 404);
  if (action === 'delete') {
    await saveEconomyConfig(env, { [key]: list.filter(item => item.id !== id) });
    return reply({ ok: true, id });
  }
  let item;
  try {
    const input = action === 'update' ? { ...list[index], ...body, id, createdAt: list[index].createdAt } : { ...body, id: crypto.randomUUID(), createdAt: new Date(deps.now ?? Date.now()).toISOString() };
    // Обновление старым клиентом не оставляет новое amount/frequency поверх legacy.
    if (Object.hasOwn(body, 'amountRub') && !Object.hasOwn(body, 'amount')) input.amount = body.amountRub;
    if (Object.hasOwn(body, 'monthly') && !Object.hasOwn(body, 'frequency')) input.frequency = body.monthly ? 'monthly' : 'once';
    item = kind === 'expenses' ? normalizeExpense(input, deps.now ?? Date.now()) : normalizeRevenue(input, deps.now ?? Date.now());
  } catch (error) { return reply({ error: error.message }, 400); }
  if (action === 'add') list.unshift(item); else list[index] = item;
  await saveEconomyConfig(env, { [key]: list });
  return reply({ ok: true, [kind === 'expenses' ? 'expense' : 'revenue']: item });
}
