import { getUsdRate } from './economy_fx.js';

const cents = (milliunits, currency, fx) => {
  if (currency === 'USD') return Math.round(milliunits / 10);
  const rate = currency === 'RUB' ? 1 : fx?.rubPerUnit?.[currency];
  return rate > 0 && fx?.rubPerUsd > 0 ? Math.round(milliunits * rate / fx.rubPerUsd / 10) : null;
};
const metrics = row => ({ purchases: row.purchases, missingAmounts: row.missingAmounts,
  pricedPurchases: Object.values(row.pricedPurchases || {}).reduce((sum, value) => sum + value, 0), amountCents: 0 });

// Like Economy: preserve native dollars and convert each receipt to cents at
// the shared official rate. All totals are sums of the same rounded receipts.
export function premiumRevenueInUsd(snapshot, fx, sales) {
  const timeline = snapshot.timeline.map(row => ({ date: row.date, ...metrics(row),
    methods: (row.methods || []).map(method => ({ key: method.key, label: method.label, ...metrics(method) })) }));
  const methods = snapshot.methods.map(method => ({ key: method.key, label: method.label, ...metrics(method) }));
  const totals = metrics(snapshot.totals), byDate = new Map(timeline.map(row => [row.date, row]));
  let available = true;
  const observations = sales || snapshot.timeline.flatMap(day => (day.methods || []).map(sale => ({ date: day.date, key: sale.key, sale })));
  for (const { date, key, sale } of observations) for (const [currency, amount] of Object.entries(sale.amounts || {})) {
    const value = cents(amount, currency, fx);
    if (value === null) { available = false; continue; }
    const day = byDate.get(date), method = methods.find(row => row.key === key);
    day.amountCents += value;
    day.methods.find(row => row.key === key).amountCents += value;
    method.amountCents += value;
    totals.amountCents += value;
  }
  if (!available) {
    for (const row of [totals, ...methods, ...timeline, ...timeline.flatMap(day => day.methods)]) row.amountCents = null;
  }
  totals.averageCheckCents = available && totals.pricedPurchases ? Math.round(totals.amountCents / totals.pricedPurchases) : null;
  totals.averageDailyCents = available && timeline.length && (totals.pricedPurchases || !totals.purchases) ? Math.round(totals.amountCents / timeline.length) : null;
  return { available, currency: 'USD', totals, timeline, methods,
    fx: fx ? { source: fx.source, rubPerUsd: fx.rubPerUsd, effectiveDate: fx.effectiveDate, stale: fx.stale === true } : null };
}

export async function premiumUsdSnapshot(env, snapshot, sales, now) {
  const needsFx = Object.keys(snapshot.totals.amounts).some(currency => currency !== 'USD');
  const fx = needsFx ? await getUsdRate(env, { now, allCurrencies: true }).catch(() => null) : null;
  return premiumRevenueInUsd(snapshot, fx, sales);
}
