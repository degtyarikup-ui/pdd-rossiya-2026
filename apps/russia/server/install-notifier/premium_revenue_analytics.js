import { mapAdminReads } from './admin_reads.js';
import { isTestOrder } from './economy_admin.js';
import { isPaidPremiumEvent, premiumEventSource, validPremiumMoney } from './premium_analytics.js';

const METHOD_LABELS = { web: 'СБП', appstore: 'App Store', googleplay: 'Google Play', rustore: 'RuStore', unknown: 'Способ не записан' };
const moscowDay = timestamp => new Date(timestamp + 3 * 3600000).toISOString().slice(0, 10);
const count = value => Number.isSafeInteger(value) && value >= 0 ? value : 0;
const metrics = () => ({ purchases: 0, missingAmounts: 0, amounts: {}, pricedPurchases: {} });
const methodKey = value => Object.hasOwn(METHOD_LABELS, value) ? value : 'unknown';
const appKey = value => ['ru', 'by', 'rs'].includes(value) ? value : 'ru';

function add(target, source) {
  target.purchases += count(source.purchases);
  target.missingAmounts += count(source.missingAmounts);
  for (const [currency, amount] of Object.entries(source.amounts || {})) {
    if (/^[A-Z]{3}$/.test(currency) && count(amount)) target.amounts[currency] = (target.amounts[currency] || 0) + amount;
  }
  for (const [currency, purchases] of Object.entries(source.pricedPurchases || {})) {
    if (/^[A-Z]{3}$/.test(currency) && count(purchases)) target.pricedPurchases[currency] = (target.pricedPurchases[currency] || 0) + purchases;
  }
}

function record(target, money) {
  target.purchases++;
  if (!validPremiumMoney(money)) { target.missingAmounts++; return; }
  const { currency, milliunits } = money;
  target.amounts[currency] = (target.amounts[currency] || 0) + milliunits;
  target.pricedPurchases[currency] = (target.pricedPurchases[currency] || 0) + 1;
}

// Persist only money/count aggregates inside the existing batched day write.
// No identities, receipts, new per-purchase KV writes or tariff estimates.
export function recordPremiumDailyPurchase(day, event) {
  if (!isPaidPremiumEvent(event)) return;
  const revenue = day.premiumRevenue ||= { version: 1, apps: {} };
  const app = revenue.apps[appKey(event.app)] ||= { excluded: 0, methods: {} };
  if (event.premiumReportExcluded === true) { app.excluded++; return; }
  if (event.premiumPaid !== true && !validPremiumMoney(event.premiumMoney)) {
    app.unverified = (app.unverified || 0) + 1;
    return;
  }
  const method = app.methods[methodKey(premiumEventSource(event))] ||= metrics();
  record(method, event.premiumMoney);
}

async function paymentOrders(env) {
  if (!env?.INSTALLS) throw new Error('premium purchase storage unavailable');
  const keys = [];
  let cursor;
  do {
    const page = await env.INSTALLS.list({ prefix: 'pay_order:', limit: 1000, ...(cursor ? { cursor } : {}) });
    if (!Array.isArray(page.keys)) throw new Error('premium purchase directory unavailable');
    keys.push(...page.keys);
    if (!page.list_complete && (!page.cursor || page.cursor === cursor)) throw new Error('premium purchase directory incomplete');
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  return mapAdminReads(keys, async key => {
    const raw = await env.INSTALLS.get(key.name);
    if (!raw) throw new Error('premium purchase record unavailable');
    const order = JSON.parse(raw);
    if (!order || typeof order !== 'object' || Array.isArray(order)) throw new Error('premium purchase record invalid');
    return { ...order, _key: key.name };
  });
}

export async function premiumRevenueSnapshot(env, days, app = 'all', now = Date.now()) {
  const orders = await paymentOrders(env);
  const rows = new Map(days.map(({ date }) => [date, { date, ...metrics(), methods: new Map() }]));
  const totals = metrics();
  const methods = new Map();
  const seen = new Set();
  const webHistory = new Map();
  const coverage = { unverifiedPurchases: 0, missingDates: 0 };
  const addSale = (row, key, sale) => {
    const method = row.methods.get(key) || { key, label: METHOD_LABELS[key], ...metrics() };
    add(method, sale); row.methods.set(key, method); add(row, sale);
  };

  for (const order of orders) {
    if (app !== 'all' && appKey(order.app) !== app) continue;
    const timestamp = Date.parse(order.confirmedAt || '');
    // All originally confirmed orders help identify old unpriced counters,
    // including orders which were subsequently returned or marked as tests.
    if (!Number.isFinite(timestamp) || timestamp > now) {
      if (order.status === 'confirmed' && !isTestOrder(order)) coverage.missingDates++;
      continue;
    }
    const date = moscowDay(timestamp);
    const row = rows.get(date);
    if (!row) continue;
    const identity = String(order.txId || order.orderId || order._key);
    if (seen.has(identity)) continue;
    seen.add(identity);
    webHistory.set(date, (webHistory.get(date) || 0) + 1);
    if ((order.status && order.status !== 'confirmed') || isTestOrder(order) || order.refunded === true || order.reversed === true) continue;
    const amount = Number(order.amount);
    const milliunits = Math.round(amount * 1000);
    const currency = String(order.currency || 'RUB').toUpperCase();
    const sale = metrics();
    record(sale, Number.isFinite(amount) && amount > 0 ? { milliunits, currency } : null);
    addSale(row, 'web', sale);
  }

  for (const { date, data } of days) {
    const row = rows.get(date);
    const apps = data?.premiumRevenue?.version === 1 ? data.premiumRevenue.apps || {} : {};
    let recorded = 0, excluded = 0, web = 0;
    for (const [code, aggregate] of Object.entries(apps)) {
      if (app !== 'all' && code !== app) continue;
      excluded += count(aggregate.excluded);
      recorded += count(aggregate.unverified);
      coverage.unverifiedPurchases += count(aggregate.unverified);
      for (const [source, sale] of Object.entries(aggregate.methods || {})) {
        recorded += count(sale.purchases);
        if (source === 'web') { web += count(sale.purchases); continue; }
        addSale(row, methodKey(source), sale);
      }
    }
    // Old counters cannot prove a paid, non-sandbox store transaction or its
    // price. Keep that gap separate from confirmed totals instead of estimating.
    if (app === 'all' || app === 'ru') {
      coverage.unverifiedPurchases += Math.max(0, count(data?.purchases) - excluded - recorded - Math.max(0, (webHistory.get(date) || 0) - web));
    }
    add(totals, row);
    for (const [source, sale] of row.methods) {
      const method = methods.get(source) || { key: source, label: METHOD_LABELS[source], ...metrics() };
      add(method, sale); methods.set(source, method);
    }
  }
  const currencies = [...new Set([...Object.keys(totals.amounts), ...Object.keys(totals.pricedPurchases)])]
    .sort((a, b) => a === 'RUB' ? -1 : b === 'RUB' ? 1 : a.localeCompare(b));
  return { available: true, timeZone: 'Europe/Moscow', totals, currencies: currencies.length ? currencies : ['RUB'],
    timeline: [...rows.values()].map(row => ({ ...row, methods: [...row.methods.values()] })),
    methods: [...methods.values()], coverage };
}
