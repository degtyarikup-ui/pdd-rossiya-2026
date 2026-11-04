// Account-level billing, never sampled Workers analytics. No payment mutations.
const KEY = 'economy_cloudflare_v1';
const TTL = 3600000;
const flights = new WeakMap();
const round = n => Math.round((n + Number.EPSILON) * 100) / 100;
const day = value => new Date(Date.parse(value) + 10800000).toISOString().slice(0, 10);
const validAmount = value => typeof value === 'number' && Number.isFinite(value) && value >= 0;
export function normalizeInvoices(rows) {
  const seen = new Map();
  let pending = 0;
  for (const row of rows) {
    if (row.type !== 'invoice' || row.status !== 'CLOSED') { pending++; continue; }
    const id = row.invoice_id || row.id;
    if (typeof id !== 'string' || !id || !validAmount(row.amount) || !['usd', 'rub'].includes(String(row.currency).toLowerCase()) || !Number.isFinite(Date.parse(row.occurred_at))) throw new Error('Invalid invoice');
    const invoice = { id, amount: round(row.amount), currency: row.currency.toUpperCase(), date: day(row.occurred_at), receipt: String(row.receipt_id || ''), status: 'CLOSED' };
    if (seen.has(id) && JSON.stringify(seen.get(id)) !== JSON.stringify(invoice)) throw new Error('Conflicting invoice');
    seen.set(id, invoice);
  }
  return { invoices: [...seen.values()].sort((a,b) => b.date.localeCompare(a.date)), pending };
}
export function normalizeUsage(rows) {
  if (!Array.isArray(rows)) throw new Error('Invalid usage');
  const groups = new Map(); let from = null, to = null;
  for (const row of rows) {
    if (row.ChargeCategory !== 'Usage' || row.BillingCurrency !== 'USD' || !validAmount(row.BilledCost) || !Number.isFinite(Date.parse(row.ChargePeriodEnd)) || !Number.isFinite(Date.parse(row.BillingPeriodStart))) throw new Error('Invalid usage row');
    const name = String(row.ServiceFamilyName || row.ServiceName || 'Cloudflare');
    groups.set(name, (groups.get(name) || 0) + row.BilledCost);
    from = !from || row.BillingPeriodStart < from ? row.BillingPeriodStart : from;
    to = !to || row.ChargePeriodEnd > to ? row.ChargePeriodEnd : to;
  }
  return { from, to, usd: round([...groups.values()].reduce((a,b) => a+b,0)), services: [...groups].map(([name,usd]) => ({ name, usd: round(usd) })) };
}
async function fetchBilling(env, deps) {
  const request = async path => {
    const response = await (deps.fetch || fetch)('https://api.cloudflare.com/client/v4/accounts/' + env.CLOUDFLARE_BILLING_ACCOUNT_ID + '/' + path, {
      method: 'GET', redirect: 'error', headers: { Authorization: 'Bearer ' + env.CLOUDFLARE_BILLING_TOKEN, Accept: 'application/json' }, signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new Error('Billing unavailable');
    const data = await response.json();
    if (!data.success) throw new Error('Billing unavailable');
    return data;
  };
  const history = async () => {
    const rows = [];
    for (let page = 1; page <= 100; page++) {
      const data = await request('billing/history?per_page=50&page=' + page);
      if (!Array.isArray(data.result)) throw new Error('Invalid billing history');
      rows.push(...data.result);
      const info = data.result_info || {};
      const more = typeof info.next_page === 'boolean' ? info.next_page : info.total_pages ? page < info.total_pages : info.total_count != null ? rows.length < info.total_count : data.result.length === 50;
      if (!more) return normalizeInvoices(rows);
    }
    throw new Error('Incomplete billing history');
  };
  const [invoices, usage, subscriptions] = await Promise.allSettled([
    history(), request('billable-usage').then(data => normalizeUsage(data.result)),
    request('subscriptions').then(data => {
      if (!Array.isArray(data.result) || data.result_info?.next_page || data.result_info?.total_pages > 1) throw new Error('Incomplete subscriptions');
      return data.result.filter(row => row.state === 'Paid' && row.frequency === 'monthly' && row.currency === 'USD').map(row => {
        if (!validAmount(row.price)) throw new Error('Invalid subscription');
        return { name: String(row.rate_plan?.public_name || 'Cloudflare'), usd: row.price, from: row.current_period_start, to: row.current_period_end };
      });
    }),
  ]);
  if (invoices.status !== 'fulfilled') throw new Error('Billing history unavailable');
  return { ...invoices.value, usage: usage.status === 'fulfilled' ? usage.value : null, subscriptions: subscriptions.status === 'fulfilled' ? subscriptions.value : null, updatedAt: new Date(deps.now ?? Date.now()).toISOString(), accountId: env.CLOUDFLARE_BILLING_ACCOUNT_ID };
}
export async function getCloudflareBilling(env, deps = {}) {
  if (!env.CLOUDFLARE_BILLING_TOKEN || !env.CLOUDFLARE_BILLING_ACCOUNT_ID) return { configured: false };
  let cached;
  try { cached = JSON.parse(await env.INSTALLS.get(KEY)); } catch (_) {}
  if (cached?.accountId !== env.CLOUDFLARE_BILLING_ACCOUNT_ID) cached = null;
  if (cached && !deps.force && (deps.now ?? Date.now()) - Date.parse(cached.updatedAt) < TTL) return { ...cached, configured: true, stale: false };
  let task = flights.get(env.INSTALLS);
  if (!task) {
    task = fetchBilling(env, deps).then(async data => { await env.INSTALLS.put(KEY, JSON.stringify(data)); return data; });
    flights.set(env.INSTALLS, task);
  }
  try { return { ...await task, configured: true, stale: false }; }
  catch (_) {
    if (cached) return { ...cached, configured: true, stale: true, error: 'Cloudflare недоступен. Показаны последние счета.' };
    throw new Error('Счета Cloudflare пока недоступны. Повторите обновление.');
  } finally { if (flights.get(env.INSTALLS) === task) flights.delete(env.INSTALLS); }
}
// Only unambiguous, exact date/currency/amount matches. Original manual entries
// remain intact; matching invoices replace them only while the match holds.
export function cloudflareExpenseLines(billing, expenses, rate, from, to) {
  const replaced = new Set();
  const lines = (billing.invoices || []).map(invoice => {
    const matches = expenses.filter(e => /cloudflare|claudlfare/i.test(e.title) && e.frequency === 'once' && e.currency === invoice.currency && e.date === invoice.date && round(e.amount) === invoice.amount);
    const same = billing.invoices.filter(i => i.date === invoice.date && i.currency === invoice.currency && i.amount === invoice.amount);
    const legacy = matches.length === 1 && same.length === 1 ? matches[0] : null;
    if (legacy) replaced.add(legacy.id);
    const amountRub = round(invoice.amount * (invoice.currency === 'USD' ? rate : 1));
    return { ...invoice, id: 'cloudflare:' + invoice.id, title: legacy?.title || 'Cloudflare · счёт ' + (invoice.receipt || invoice.date), frequency: 'once', source: 'cloudflare', basis: 'invoice', imported: true, category: 'expense', amountRub, periodRub: invoice.date >= from && invoice.date <= to ? amountRub : 0, monthlyRub: 0, occurrences: invoice.date >= from && invoice.date <= to ? 1 : 0, matchedManualId: legacy?.id || null };
  });
  return { lines, replaced };
}
