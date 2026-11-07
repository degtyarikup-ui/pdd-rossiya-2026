import { marketingSource, SOURCE_LABELS } from './attribution.js';
import { privatePushTopic } from './notification_identity.js';

// A grant is access, not a purchase. Keep the source of the actual transaction
// separate from the user's effective premiumSource (a longer grant can win).
const PAID_SOURCES = new Set(['appstore', 'googleplay', 'rustore', 'web']);
const MANUAL_SOURCES = new Set(['admin', 'admingrant', 'manual', 'manualgrant', 'gift']);
const normalize = value => String(value || '').toLowerCase().replace(/[\s_-]/g, '');

export function premiumEventSource(event) {
  if (event?.manual === true || event?.isManual === true || MANUAL_SOURCES.has(normalize(event?.kind))) return 'admin_grant';
  const explicit = event?.purchaseSource ?? event?.store;
  const source = normalize(explicit ?? event?.source);
  if (MANUAL_SOURCES.has(source)) return 'admin_grant';
  if (PAID_SOURCES.has(source)) return source;
  if (source === 'legacy') return 'legacy';
  // Existing buffered purchase events predate source tagging. Only verified
  // store/web handlers emitted them; don't lose those genuine purchases.
  if (explicit == null && (!source || source === 'direct' || source === 'legacy')) return 'legacy';
  return 'unknown';
}

export function isPaidPremiumEvent(event) {
  const source = premiumEventSource(event);
  return event?.type === 'purchase' && (PAID_SOURCES.has(source) || source === 'legacy');
}

export async function premiumPurchaseEvent(env, user, purchaseSource, platform, ts, reference) {
  const event = { type: 'purchase', purchaseSource, platform, app: user.app,
    marketingSource: marketingSource(user.marketingSource) };
  if (reference?.isTest || reference?.paid === false || reference?.refunded) {
    return { ...event, premiumReportExcluded: true };
  }
  if (env.SESSION_SECRET && user.id) {
    // Shift the date boundary to 19:00 UTC (22:00 MSK). The same buyer gets
    // the same token across the two slots, and a different token tomorrow.
    const reportDate = new Date(ts + 5 * 3600000).toISOString().slice(0, 10);
    const identity = await privatePushTopic(env, `premium-report:${reportDate}:${user.id}`);
    event.premiumBuyer = identity.slice(-64);
  }
  return event;
}

export function recordPremiumPurchase(slot, event) {
  if (event.premiumReportExcluded === true) {
    slot.premiumReportExcluded = (slot.premiumReportExcluded || 0) + 1;
    return;
  }
  (slot.premiumPurchases ||= []).push([
    premiumEventSource(event), marketingSource(event.marketingSource), event.premiumBuyer || null,
    event.premiumMoney || null, event.premiumPlan || null,
  ]);
}

const METHODS = {
  web: ['Platega', 'СБП'],
  appstore: ['App Store', 'App Store'],
  googleplay: ['Google Play', 'Google Play'],
  rustore: ['RuStore', 'RuStore'],
  legacy: ['Способ оплаты не записан', 'способ не записан'],
};

const premiumSlotCount = slot => (slot?.purchases || 0) - (slot?.premiumReportExcluded || 0);
const premiumPurchases = slots => slots.flatMap(slot => slot?.premiumPurchases || []);
const premiumCount = slots => slots.reduce((sum, slot) => sum + premiumSlotCount(slot), 0);

export const premiumHistoryMissing = slots => premiumPurchases(slots).length < premiumCount(slots);

export function premiumChartSlots(slots, history) {
  if (!premiumHistoryMissing(slots) || !history || typeof history !== 'object') return slots;
  const premiumPurchases = [];
  for (const [method, entries] of Object.entries(history)) {
    if (!PAID_SOURCES.has(method) || !Array.isArray(entries) || !entries.every(validPremiumMoney)) return slots;
    for (const money of entries) premiumPurchases.push([method, 'unknown', null, money]);
  }
  const purchases = premiumCount(slots);
  return premiumPurchases.length === purchases ? [{ purchases, premiumPurchases }] : slots;
}

export function premiumChartPoint(date, slots, fx) {
  const { web, appstore, googleplay } = premiumSalesUsd(slots, fx);
  const available = slots.some(Boolean) && [web, appstore, googleplay].some(value => value !== null);
  return { date, available, web, appstore, googleplay };
}

export function validPremiumMoney(money) {
  return Number.isSafeInteger(money?.milliunits) && money.milliunits > 0 && /^[A-Z]{3}$/.test(money.currency || '');
}

function toUsd(money, fx) {
  if (!validPremiumMoney(money)) return null;
  const { currency, milliunits } = money;
  if (currency === 'USD') return milliunits / 1000;
  const rubPerUnit = currency === 'RUB' ? 1 : fx?.rubPerUnit?.[currency];
  return rubPerUnit > 0 && fx?.rubPerUsd > 0 ? milliunits * rubPerUnit / fx.rubPerUsd / 1000 : null;
}

export function premiumSalesUsd(slots, fx) {
  const totals = Object.fromEntries([...PAID_SOURCES].map(method => [method, 0]));
  const purchases = premiumPurchases(slots);
  const complete = purchases.length === premiumCount(slots) && purchases.every(([method]) => PAID_SOURCES.has(method));
  if (!complete) return Object.fromEntries(Object.keys(totals).map(method => [method, null]));
  for (const [method, , , money] of purchases) {
    const usd = toUsd(money, fx);
    totals[method] = totals[method] === null || usd === null ? null : totals[method] + usd;
  }
  return totals;
}

export const premiumNeedsFx = slots => premiumPurchases(slots).some(([, , , money]) => validPremiumMoney(money) && money.currency !== 'USD');

export function buildPremiumDailyMessage(slots, period, fx) {
  const total = premiumCount(slots);
  const purchases = premiumPurchases(slots);
  const buyers = new Set();
  const plans = { weekly: new Set(), threeMonths: new Set() };
  const methods = new Map();
  const channels = new Map();
  const increment = (counts, key, count = 1) => counts.set(key, (counts.get(key) || 0) + count);
  const add = (method, source, count) => {
    increment(methods, method, count);
    if (!channels.has(source)) channels.set(source, new Map());
    increment(channels.get(source), method, count);
  };
  for (const [method, source, buyer, , plan] of purchases) {
    add(method, source, 1);
    if (buyer) buyers.add(buyer);
    if (buyer && Object.hasOwn(plans, plan)) plans[plan].add(buyer);
  }
  if (total > purchases.length) add('legacy', 'unknown', total - purchases.length);

  const buyersKnown = total === purchases.length && purchases.every(([, , buyer]) => buyer);
  const bold = value => `<b>${value}</b>`;
  const lines = [
    '<b>Premium за сутки</b>', `<i>${period}</i>`, '',
    `⭐ Покупатели: ${bold(buyersKnown ? buyers.size : '—')}`,
  ];
  if (!buyersKnown) lines.push(`Подтверждённые покупки: ${bold(total)}`);
  const plansKnown = buyersKnown && purchases.every(([, , , , plan]) => Object.hasOwn(plans, plan));
  lines.push('', '📅 <b>Какие тарифы купили</b>',
    `На неделю: ${bold(plansKnown ? plans.weekly.size : '—')}`,
    `На 3 месяца: ${bold(plansKnown ? plans.threeMonths.size : '—')}`);

  const byCount = ([, a], [, b]) => b - a;
  const channelCount = ([, entries]) => [...entries.values()].reduce((sum, count) => sum + count, 0);
  lines.push('', '💳 <b>Как оплатили</b>');
  for (const [method, [label]] of Object.entries(METHODS)) {
    const count = methods.get(method) || 0;
    if (count || ['web', 'appstore', 'googleplay'].includes(method)) lines.push(`${label}: ${bold(count)}`);
  }
  if (total) lines.push('', '📍 <b>Откуда пришли и как оплатили</b>');
  const knownChannels = [...channels].filter(([source]) => source !== 'unknown').sort((a, b) => channelCount(b) - channelCount(a));
  if (channels.has('unknown')) knownChannels.push(['unknown', channels.get('unknown')]);
  const sourceLines = grouped => knownChannels.flatMap(([source, entries]) => {
    const label = source === 'unknown' ? 'Источник не записан' : SOURCE_LABELS[source];
    const rows = [...entries].sort(byCount).map(([method, count]) => `${METHODS[method][1]}: ${bold(count)}`);
    return grouped ? [`${label} → ${rows.join(', ')}`] : rows.map(row => `${label} → ${row}`);
  });
  const sourceIndex = lines.length;
  const sales = premiumSalesUsd(slots, fx);
  const usd = value => value === null ? '—' : `$${value.toFixed(2)}`;
  const amounts = Object.values(sales);
  const salesTotal = amounts.includes(null) ? null : amounts.reduce((sum, value) => sum + value, 0);
  lines.push('', `💰 ${bold(`Сумма покупок: ${usd(salesTotal)}`)}`);
  for (const [method, [label]] of Object.entries(METHODS)) {
    if (method !== 'legacy' && methods.has(method)) lines.push(`${label}: ${usd(sales[method])}`);
  }
  if (!plansKnown || salesTotal === null) lines.push('<i>— нет данных</i>');
  const detailedSources = sourceLines(false);
  const grouped = lines.join('\n').length + detailedSources.join('\n').length >= 4096;
  lines.splice(sourceIndex, 0, ...(grouped ? sourceLines(true) : detailedSources));
  return lines.join('\n');
}
