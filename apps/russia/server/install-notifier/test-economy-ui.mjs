// Browser integration against the real assembled admin page and Worker routes.
// NODE_PATH=<directory containing playwright> node --test test-economy-ui.mjs
// ECONOMY_UI_SCREENSHOTS=1 saves review images to output/economy-ui/.
// node test-economy-ui.mjs --serve starts the same isolated local preview.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { mkdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { payoutBinding } from './fixture-economy-payouts.mjs';
import worker from './worker.js';
import { DEFAULT_ECONOMY_CONFIG } from './economy_admin.js';

class MemoryKV {
  constructor() { this.store = new Map(); this.metadata = new Map(); }
  async get(key, options) {
    const value = this.store.get(key) ?? null;
    return options === 'json' || options?.type === 'json' ? value === null ? null : JSON.parse(value) : value;
  }
  async put(key, value, options) {
    this.store.set(key, String(value));
    if (options?.metadata) this.metadata.set(key, options.metadata);
    else this.metadata.delete(key);
  }
  async delete(key) { this.store.delete(key); this.metadata.delete(key); }
  async list({ prefix = '', limit = 1000, cursor = '0' } = {}) {
    const all = [...this.store.keys()].filter(key => key.startsWith(prefix)).sort();
    const start = Number(cursor) || 0;
    const keys = all.slice(start, start + limit).map(name => ({ name, metadata: this.metadata.get(name) }));
    return { keys, list_complete: start + keys.length >= all.length, cursor: String(start + keys.length) };
  }
}

const day = (offset = 0) => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Moscow' }).format(new Date(Date.now() + offset * 86400000));

async function startPreview() {
  const env = { INSTALLS: new MemoryKV(), ECONOMY_PAYOUTS: payoutBinding(), ADMIN_PASSWORD: crypto.randomUUID() };
  const lastDay = new Date(day(-40).slice(0,7)+'-01T00:00:00Z');
  lastDay.setUTCMonth(lastDay.getUTCMonth()+1,0);
  const priorDay = lastDay.toISOString().slice(0,10);
  for (const [key,date] of [['economy_fx_usd_v1',day()],['economy_fx_usd_v1:'+priorDay,priorDay]]) {
    await env.INSTALLS.put(key,JSON.stringify({rubPerUsd:95,rubPerUnit:{USD:95,RUB:1},effectiveDate:date,requestedDay:date,checkedAt:new Date().toISOString(),source:'CBR'}));
  }
  const config = {
    ...structuredClone(DEFAULT_ECONOMY_CONFIG),
    extraExpenses: [
      { id: 'fixture-monthly', title: 'Монтаж видео', amount: 1200, amountRub: 1200, currency: 'RUB', frequency: 'monthly', monthly: true, date: day(-60), createdAt: day(-60) },
      { id: 'fixture-once', title: 'Иллюстрации', amount: 800, amountRub: 800, currency: 'RUB', frequency: 'once', monthly: false, date: day(), createdAt: day() },
    ],
    manualRevenues: [
      { id: 'fixture-income', title: 'Выплата RuStore', amountRub: 35000, store: 'rustore', date: day(), createdAt: day() },
      { id: 'fixture-old-income', title: 'Прошлая выплата', amountRub: 5000, store: 'appstore', date: day(-60), createdAt: day(-60) },
    ],
  };
  await env.INSTALLS.put('economy_config', JSON.stringify(config));
  await env.INSTALLS.put('ai_stats_cost_usd', '0');
  const purchaseAt = new Date(Date.now() - 60000).toISOString();
  const premiumUser = {
    id: 'fixture-premium', name: 'Анна', email: 'anna@example.invalid', provider: 'apple', isPremium: true,
    premiumSource: 'appstore', premiumExpiresAt: `${day(90)}T12:00:00.000Z`, purchasedAt: purchaseAt,
    verifiedPurchase: { transactionId: 'fixture-ios', productId: 'premium_3months', environment: 'Production' },
  };
  await env.INSTALLS.put('user:fixture-premium', JSON.stringify(premiumUser), { metadata: { ...premiumUser, v: 4 } });
  await env.INSTALLS.put('pay_order:fixture-sbp', JSON.stringify({
    orderId: 'fixture-sbp', status: 'confirmed', amount: 290, tier: 'threeMonths', method: 'sbp',
    confirmedAt: purchaseAt, createdAt: purchaseAt,
  }));
  await env.INSTALLS.put('pay_order:fixture-test', JSON.stringify({
    orderId: 'fixture-test', status: 'confirmed', amount: 290, tier: 'threeMonths', isTest: true,
    confirmedAt: purchaseAt, createdAt: purchaseAt,
  }));
  const requests = [];
  const server = createServer(async (incoming, outgoing) => {
    try {
      const body = [];
      for await (const chunk of incoming) body.push(chunk);
      const url = new URL(incoming.url, `http://${incoming.headers.host}`);
      const headers = new Headers(incoming.headers);
      // The preview is bound to loopback and never uses production credentials.
      if (url.pathname.startsWith('/api/admin/')) headers.set('authorization', `Bearer ${env.ADMIN_PASSWORD}`);
      const request = new Request(url, { method: incoming.method, headers,
        ...(body.length ? { body: Buffer.concat(body) } : {}) });
      const pending = [];
      const response = await worker.fetch(request, env, { waitUntil(promise) { pending.push(promise); } });
      requests.push({ method: incoming.method, path: url.pathname, query: url.search, status: response.status });
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      outgoing.end(Buffer.from(await response.arrayBuffer()));
      await Promise.allSettled(pending);
    } catch (error) {
      outgoing.writeHead(500, { 'content-type': 'text/plain' });
      outgoing.end(String(error));
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return {
    env, requests, url: `http://127.0.0.1:${server.address().port}`,
    async close() { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); },
  };
}

if (process.argv.includes('--serve')) {
  const preview = await startPreview();
  console.log(`Isolated economy preview: ${preview.url}/admin#economy`);
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => { await preview.close(); process.exit(0); });
} else {
  test('economy workspace persists edits and remains usable on desktop and mobile', { timeout: 120000 }, async () => {
    const require = createRequire(import.meta.url);
    const { chromium } = require('playwright');
    const preview = await startPreview();
    const browser = await chromium.launch({ headless: true,
      executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      args: ['--disable-dev-shm-usage'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, reducedMotion: 'reduce' });
    await context.route('**/*', async route => {
      const url = new URL(route.request().url());
      if (url.origin === preview.url) return route.continue();
      if (url.hostname === 'pdd-drive.ru' && ['/assets/icon-192.png', '/assets/favicon.png'].includes(url.pathname)) {
        return route.fulfill({ contentType: 'image/png', body: await readFile(new URL(`../../web_landing/ru${url.pathname}`, import.meta.url)) });
      }
      return route.abort();
    });
    const page = await context.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    const screenshotDir = fileURLToPath(new URL('../../output/economy-ui/', import.meta.url));
    async function screenshot(name) {
      if (!process.env.ECONOMY_UI_SCREENSHOTS) return;
      await mkdir(screenshotDir, { recursive: true });
      await page.screenshot({ path: `${screenshotDir}/${name}.png`, fullPage: !name.includes('dialog') });
    }
    const config = async () => JSON.parse(await preview.env.INSTALLS.get('economy_config'));
    const stats = async (period = 'month') => (await context.request.get(`${preview.url}/api/admin/economy/stats?period=${period}`)).json();
    async function settled() {
      await page.waitForFunction(() => document.querySelector('#ec-data-state')?.classList.contains('ready'), null, { timeout: 10000 });
    }
    async function save() {
      const response = page.waitForResponse(response => response.url().includes('/api/admin/economy/') && response.request().method() === 'POST');
      await page.locator('#ec-submit').click();
      assert.equal((await response).status(), 200);
      await page.locator('#ec-dialog').waitFor({ state: 'hidden' });
      await settled();
    }
    async function field(name, value) { await page.locator(`#ec-form [name="${name}"]`).fill(String(value)); }
    async function select(name, value) { await page.locator(`#ec-form [name="${name}"]`).selectOption(value); }
    async function open(button) {
      await page.locator(button).first().click();
      await page.locator('#ec-dialog').waitFor({ state: 'visible' });
      assert.equal(await page.locator('#ec-dialog').evaluate(node => node instanceof HTMLDialogElement && node.open), true);
      assert.equal(await page.locator('#ec-dialog').evaluate(node => node.contains(document.activeElement)), true);
      assert.ok(await page.locator('#ec-dialog').getAttribute('aria-labelledby'));
      const bounds = await page.locator('#ec-dialog').boundingBox();
      assert.ok(Math.abs(bounds.x * 2 + bounds.width - page.viewportSize().width) <= 2, 'dialog is centered horizontally');
      assert.equal(await page.locator('#ec-form input, #ec-form select').evaluateAll(nodes => nodes.every(node => node.type==='hidden' || node.labels?.length || node.getAttribute('aria-label'))), true);
    }
    async function remove() {
      await page.locator('#ec-delete').click();
      assert.equal(await page.locator('#ec-dialog').isVisible(), true, 'first delete click asks for confirmation');
      const response = page.waitForResponse(response => response.url().endsWith('/delete') && response.request().method() === 'POST');
      await page.locator('#ec-delete').click();
      assert.equal((await response).status(), 200);
      await page.locator('#ec-dialog').waitFor({ state: 'hidden' });
      await settled();
    }
    async function add(kind) {
      await open('#ec-add-operation');
      await select('operationType', kind);
    }
    const view = name => page.locator('[data-ec-view="'+name+'"]').click();
    const openPeriod = () => page.locator('#ec-period-menu > summary').click();
    async function mode(value) {
      await page.locator('#ec-receipt-mode').selectOption(value);
    }
    const edit = (kind, id) => `#ec-receipts-body .ec-edit[data-edit-kind="${kind}"][data-id="${id}"]`;
    try {
      await page.goto(`${preview.url}/admin#economy`);
      await page.locator('#economy-view').waitFor({ state: 'visible' });
      await settled();
      let initial = await stats();
      assert.equal(initial.revenue.grossRub, 580);
      assert.equal(initial.expenses.paymentFeesRub, 23.2);
      assert.equal(initial.currency,'USD');
      assert.match(await page.locator('#ec-gross-val').innerText(),/^\$6,10$/);
      const currentDate = new Date(day().slice(0,7)+'-01T00:00:00Z');
      const previousMonth = new Date(Date.UTC(currentDate.getUTCFullYear(),currentDate.getUTCMonth()-1,1)).toISOString().slice(0,7);
      assert.equal(await page.locator('#ec-month-next').isDisabled(),true);
      // A slow previous-month response must never relabel the current report.
      let releaseMonth, requestedMonth;
      const blocked = new Promise(resolve => { releaseMonth=resolve; });
      const requested = new Promise(resolve => { requestedMonth=resolve; });
      await page.route('**/api/admin/economy/stats?period='+previousMonth,async route=>{
        requestedMonth(); await blocked;
        await route.fulfill({json:{...initial,period:previousMonth,selectedMonth:previousMonth}});
      },{times:1});
      await page.locator('#ec-month-prev').click(); await requested;
      assert.equal(await page.locator('#ec-report-month').inputValue(),previousMonth);
      assert.equal(await page.locator('#ec-overview').isVisible(),false,'previous totals are hidden while the new month loads');
      assert.equal(await page.locator('#economy-view > .admin-view-skeleton').isVisible(),true);
      assert.match(await page.locator('#ec-data-state').innerText(),/Загружаем отчёт/);
      assert.equal(await page.locator('#ec-month-next').isEnabled(),true);
      await page.locator('#ec-month-next').click(); await settled();
      const late=page.waitForResponse(response=>response.url().endsWith('period='+previousMonth));
      releaseMonth(); await late;
      assert.equal(await page.locator('#ec-report-month').inputValue(),day().slice(0,7));
      assert.equal(await page.locator('#ec-month-next').isDisabled(),true);
      assert.equal(await page.locator('#ec-refresh').getAttribute('aria-busy'),'false');
      const september = (currentDate.getUTCFullYear()-1)+'-09';
      await page.route('**/api/admin/economy/stats?period='+september,route=>route.fulfill({json:{...initial,period:september,selectedMonth:september}}),{times:1});
      await page.setViewportSize({width:320,height:800});
      await openPeriod(); await page.locator('#ec-report-month').fill(september); await settled();
      const controlRects=await page.locator('#ec-month-prev,#ec-period-menu summary,#ec-month-next,#ec-refresh,#ec-add-operation').evaluateAll(nodes=>nodes.map(node=>{
        const {top,bottom,left,right,width}=node.getBoundingClientRect();return {top,bottom,left,right,width};
      }));
      assert.equal(controlRects.length,5);
      assert.ok(controlRects.every(rect=>rect.left>=0&&rect.right<=320&&rect.width>=24));
      assert.ok(Math.max(...controlRects.map(rect=>rect.top))<Math.min(...controlRects.map(rect=>rect.bottom)),'all four actions and month picker fit one line at 320px');
      assert.match(await page.locator('#ec-period-compact').innerText(),/сент/i);
      await screenshot('month-toolbar-320');
      await openPeriod(); await page.locator('#ec-period-tabs [data-period="month"]').click(); await settled();
      await page.setViewportSize({width:1440,height:900});
      assert.equal(await page.locator('#ec-ledger').isVisible(),false);
      assert.equal(await page.locator('#ec-shares').isVisible(),false);
      assert.equal(await page.locator('#ec-breakdown').getAttribute('open'),null);
      assert.ok(await page.locator('#ec-recent-list button').count()<=4);
      await screenshot('overview-desktop');
      await page.locator('[data-open-view="shares"]').click();
      assert.equal(await page.locator('#ec-shares').isVisible(),true);
      await page.goBack(); await page.locator('#ec-overview').waitFor({state:'visible'});
      await page.locator('#ec-recent-list button').first().click();
      await page.locator('#ec-dialog').waitFor({state:'visible'}); await page.keyboard.press('Escape');
      await page.locator('#ec-breakdown summary').click();
      const incomeSources = page.locator('#ec-gross-sub > span');
      assert.deepEqual(await incomeSources.allTextContents(), ['App Store $3,05', 'Platega $3,05', 'Google Play $0,00']);
      assert.equal(await incomeSources.evaluateAll(nodes => new Set(nodes.map(node => node.offsetTop)).size), 1);
      assert.match(await page.locator('#ec-fx-status').innerText(),/ЦБ.*95/);
      assert.equal(initial.receipts.some(row=>row.isTest),false);
      await page.locator('[data-open-view="ledger"]').click();
      assert.match(await page.locator('#ec-receipts-body').innerText(), /Анна/);
      const sbpRow = page.locator('#ec-receipts-body tr').filter({ has: page.locator('[data-detail-key="receipt:fixture-sbp"]') });
      assert.match(await sbpRow.innerText(), /Комиссия −\$0,24/);
      await open('#ec-receipts-body .ec-edit[data-detail-key="receipt:fixture-sbp"]');
      assert.match(await page.locator('#ec-form').innerText(), /МСК/);
      await page.locator('#ec-cancel').click();
      assert.equal(await page.locator('[data-detail-key="payment-fees"]').count(), 0);
      await mode('commission');
      const feeRow = page.locator('#ec-receipts-body tr').filter({ hasText: 'Комиссия Platega' });
      assert.equal(await feeRow.count(), 1);
      assert.doesNotMatch(await feeRow.innerText(), /За период/);
      assert.match(await feeRow.innerText(), /−\$0,24/);
      await mode('all');
      assert.equal(await page.locator('#ec-expense-register').getAttribute('open'), null);
      await screenshot('desktop');
      // Provider balances are current reference values and never become revenue.
      assert.equal(preview.requests.some(request => request.path.endsWith('/economy/platega')), false, 'provider reads are lazy');
      await page.route('**/api/admin/economy/platega', route => route.fulfill({
        contentType: 'application/json', body: JSON.stringify({ ok: true, configured: true, updatedAt: new Date().toISOString(),
          balances: [{ currency: 'RUB', amount: 1250.5 }, { currency: 'USDT', amount: 12.35, frozenBalance: 1.5 }] }),
      }), { times: 1 });
      await page.locator('#ec-platega-panel > summary').click();
      await page.waitForFunction(() => document.querySelector('#ec-platega-body')?.textContent.includes('USDT'));
      assert.match(await page.locator('#ec-platega-body').innerText(), /12,35/);
      assert.match(await page.locator('#ec-platega-body').innerText(), /1,5/);
      assert.equal((await stats()).revenue.grossRub, initial.revenue.grossRub);
      await screenshot('platega-balances');
      await page.route('**/api/admin/economy/platega', route => route.fulfill({
        status: 503, contentType: 'application/json', body: JSON.stringify({ error: 'Platega временно недоступна' }),
      }), { times: 1 });
      await page.locator('#ec-platega-refresh').click();
      await page.waitForFunction(() => document.querySelector('#ec-platega-status')?.textContent.includes('недоступна'));
      assert.match(await page.locator('#ec-platega-body').innerText(), /12,35/, 'provider failure retains last known balance');
      await page.locator('#ec-platega-panel > summary').click();

      // Filters change the journal only, including test visibility and source search.
      assert.equal(await page.locator('#ec-show-tests').count(),0);
      assert.equal((await stats()).revenue.grossRub, 580);

      await mode('withdrawal');
      await page.locator('#ec-store-filter').selectOption('rustore');
      assert.equal(await page.locator(edit('revenue', 'fixture-income')).count(), 1);
      await open(edit('revenue', 'fixture-income'));
      await select('currency', 'USD');
      assert.equal(await page.locator('#ec-form [name="usdRate"]').count(),0);
      await page.locator('#ec-cancel').click();
      await page.locator('#ec-search').fill('нет такой операции');
      assert.match(await page.locator('#ec-receipts-body').innerText(), /Ничего не найдено/);
      await page.locator('#ec-search').clear();
      await page.locator('#ec-store-filter').selectOption('all');
      await mode('all');

      const shareRows = page.locator('.ec-share-row');
      const shareInput = (index, name) => shareRows.nth(index).locator('[name="share' + name + '"]');
      await view('shares');
      await open('#ec-edit-shares');
      assert.deepEqual(await shareRows.locator('[name="sharePercent"]').evaluateAll(nodes => nodes.map(node => Number(node.value))), [15, 79.3, 5.7]);
      await shareInput(0, 'Name').fill('Развитие');
      await shareInput(0, 'Percent').fill('50');
      await shareInput(1, 'Percent').fill('40');
      await shareInput(2, 'Percent').fill('5');
      assert.match(await page.locator('#ec-form-preview').innerText(), /95%/);
      await page.locator('#ec-submit').click();
      assert.match(await page.locator('#ec-form-error').innerText(), /100%/);
      await shareInput(2, 'Percent').fill('10');
      await screenshot('shares-dialog');
      await save();
      assert.deepEqual((await config()).profitShares.map(({ name, percent }) => ({ name, percent })), [
        { name: 'Развитие', percent: 50 }, { name: 'Сергей', percent: 40 }, { name: 'Никита', percent: 10 },
      ]);
      await page.reload(); await settled();
      assert.equal(await page.locator('#ec-shares').isVisible(),true);
      assert.match(await page.locator('#ec-allocation-list').innerText(), /Развитие\s+50%/);
      for (const width of [320, 390, 900, 1440]) {
        await page.setViewportSize({ width, height:900 });
        assert.ok(await page.locator('#ec-allocation-list').evaluate(el => el.scrollWidth <= el.clientWidth+1));
        assert.ok(await page.locator('.ec-balance-values dd').evaluateAll(items => items.every(el => el.scrollWidth<=el.clientWidth+1)));
      }
      const currentMonth = day().slice(0,7), priorMonth = day(-40).slice(0,7);
      await open('#ec-allocation-list .ec-allocation-item:last-child .ec-pay-partner');
      await select('partnerId', (await config()).profitShares[2].id);
      await field('amount', 17); await field('month', priorMonth); await save();
      await page.locator('[data-payout-history]').click();
      assert.equal(await page.locator('#ec-receipt-mode').inputValue(),'payout');
      await page.getByRole('button', {name:'Никита',exact:true}).waitFor();
      const payout = (await stats()).payouts[0];
      assert.equal(payout.month, priorMonth);
      await view('shares'); await openPeriod();
      await page.locator('#ec-report-month').fill(priorMonth);
      await page.waitForFunction(month => document.querySelector('#ec-report-month').value===month && document.querySelector('#ec-edit-shares').disabled && document.querySelector('#ec-data-state').classList.contains('ready'), priorMonth);
      assert.match(await page.locator('#ec-allocation-list').innerText(), /17,00/);
      await openPeriod(); await page.locator('#ec-report-month').fill(currentMonth);
      await page.waitForFunction(() => !document.querySelector('#ec-edit-shares').disabled);
      await view('ledger'); await open(edit('payout',payout.id)); await field('amount', 15); await save();
      assert.equal((await stats()).payouts[0].amount,15);
      await open(edit('payout',payout.id)); await remove(); await mode('all');
      await view('shares');
      await open('#ec-edit-shares');
      await shareRows.nth(2).locator('[data-remove-share]').click();
      await page.locator('#ec-add-share').click();
      await shareInput(2, 'Name').fill('Резерв');
      await shareInput(2, 'Percent').fill('10');
      await save();
      assert.equal((await config()).profitShares[2].name, 'Резерв');
      assert.equal((await config()).profitShares[2].percent, 10);
      assert.match(await page.locator('#ec-allocation-list').innerText(), /Резерв\s+10%/);

      await add('expense');
      await field('title', 'Дизайн и иллюстрации'); await field('amount', 2500);
      await field('date', day());
      await screenshot('expense-dialog');
      await page.route('**/api/admin/economy/expenses/add', route => route.fulfill({
        status: 503, contentType: 'application/json', body: JSON.stringify({ error: 'Не удалось сохранить расход' }),
      }), { times: 1 });
      const failedSave = page.waitForResponse(response => response.url().endsWith('/expenses/add'));
      await page.locator('#ec-submit').click(); await failedSave;
      await page.locator('#ec-form-error').waitFor({ state: 'visible' });
      assert.equal(await page.locator('#ec-dialog').isVisible(), true);
      assert.equal(await page.locator('#ec-form [name="title"]').inputValue(), 'Дизайн и иллюстрации');
      assert.equal((await config()).extraExpenses.some(item => item.title === 'Дизайн и иллюстрации'), false);
      await save();
      let expense = (await config()).extraExpenses.find(item => item.title === 'Дизайн и иллюстрации');
      assert.equal(expense.frequency, 'once');
      await view('ledger'); await open(edit('expense', expense.id));
      await field('title', 'Облачный сервис'); await field('amount', 12);
      await select('frequency', 'monthly'); await select('currency', 'USD');
      await save();
      expense = (await config()).extraExpenses.find(item => item.id === expense.id);
      assert.equal(expense.amount, 12); assert.equal(expense.currency, 'USD'); assert.equal(expense.frequency, 'monthly');
      await open(edit('expense', expense.id)); await remove();
      assert.equal((await config()).extraExpenses.some(item => item.id === expense.id), false);

      // The withdrawal principal is a transfer. Only its fee changes profit.
      const beforeWithdrawal = await stats();
      await add('withdrawal');
      await field('title', ''); await field('amount', 25);
      await select('currency', 'USD');
      await field('fee', 1.5); await select('feeMode', 'additional');
      await field('date', day()); await screenshot('withdrawal-dialog'); await save();
      let withdrawal = (await config()).withdrawals.find(item => item.title === 'Вывод средств');
      assert.ok(withdrawal);
      let afterWithdrawal = await stats();
      assert.equal(afterWithdrawal.revenue.grossRub, beforeWithdrawal.revenue.grossRub);
      assert.equal(afterWithdrawal.withdrawalSummary.receivedRub, 2375);
      assert.equal(afterWithdrawal.usd.withdrawalSummary.receivedUsd,25);
      assert.equal(afterWithdrawal.usd.withdrawalSummary.debitedUsd,26.5);
      assert.equal(afterWithdrawal.usd.expenses.withdrawalFeesUsd,1.5);
      assert.match(await page.locator('#ec-withdrawn-total').innerText(),/\$25,00/);
      assert.equal(afterWithdrawal.withdrawalSummary.debitedRub, 2517.5);
      assert.equal(afterWithdrawal.expenses.withdrawalFeesRub, 142.5);
      assert.ok(Math.abs(afterWithdrawal.profit.operatingRub - beforeWithdrawal.profit.operatingRub + 142.5) < .01);
      await mode('withdrawal');
      assert.equal(await page.locator(edit('withdrawal', withdrawal.id)).count(), 1);
      await open(edit('withdrawal', withdrawal.id)); await select('feeMode', 'included'); await save();
      assert.equal((await stats()).withdrawalSummary.receivedRub, 2232.5);
      await page.reload(); await settled();
      assert.equal(await page.locator('#ec-ledger').isVisible(),true);
      assert.equal((await config()).withdrawals[0].feeMode, 'included');
      await mode('all');

      // A standalone fee and a manual payment are independently editable.
      await add('commission');
      await field('title', 'Банковская комиссия'); await field('amount', 100); await save();
      const commission = (await config()).extraExpenses.find(item => item.title === 'Банковская комиссия');
      assert.equal(commission.category, 'commission');
      await mode('commission');
      assert.match(await page.locator('#ec-receipts-body').innerText(), /Банковская комиссия/);
      assert.match(await page.locator('#ec-receipts-body').innerText(), /Platega/);
      await mode('all');
      await add('revenue');
      await field('title', 'Партнёрское поступление'); await field('amount', 10);
      await select('currency', 'USD'); await select('store', 'other'); await save();
      const revenue = (await config()).manualRevenues.find(item => item.title === 'Партнёрское поступление');
      assert.equal(revenue.amountRub, 950);
      assert.equal((await stats()).revenue.grossRub, 1530);
      await view('overview'); await page.locator('#ec-breakdown summary').click();
      assert.match(await page.locator('#ec-gross-sub').innerText(), /Другое \$10,00/);

      // Later settings edits do not revalue already recorded FX transactions.
      await open('#ec-settings'); await field('paymentFeePercent', 8); await save();
      assert.equal((await stats()).withdrawalSummary.feeRub, 142.5);
      assert.equal((await stats()).revenue.grossRub, 1530);
      await view('ledger'); await open(edit('revenue', revenue.id)); await remove();
      assert.equal((await stats()).revenue.grossRub, 580);
      await open(edit('withdrawal', withdrawal.id)); await remove();
      assert.equal((await config()).withdrawals.length, 0);
      assert.equal((await stats()).expenses.withdrawalFeesRub, 0);

      // Date filters include old transactions only for the all-time view.
      const allResponse = page.waitForResponse(response => response.url().includes('/economy/stats?period=all'));
      await openPeriod(); await page.locator('#ec-period-tabs [data-period="all"]').click(); await allResponse; await settled();
      await page.locator('#ec-search').fill('Прошлая выплата');
      assert.equal(await page.locator(edit('revenue', 'fixture-old-income')).count(), 1);
      const recentResponse = page.waitForResponse(response => response.url().includes('/economy/stats?period=30d'));
      await openPeriod(); await page.locator('#ec-period-tabs [data-period="30d"]').click(); await recentResponse; await settled();
      assert.equal(await page.locator(edit('revenue', 'fixture-old-income')).count(), 0);
      await page.locator('#ec-search').clear();

      // Future/old expenses remain accessible for edits in the collapsed register.
      await add('expense'); await field('title', 'Годовая лицензия'); await field('amount', 3000);
      await select('frequency', 'yearly'); await field('date', day(2)); await field('endDate', day(365)); await save();
      const yearly = (await config()).extraExpenses.find(item => item.title === 'Годовая лицензия');
      assert.equal(await page.locator(edit('expense', yearly.id)).count(), 0);
      await page.locator('#ec-expense-register > summary').click();
      await open(`#ec-expenses-body [data-edit-kind="expense"][data-id="${yearly.id}"]`); await remove();
      assert.equal((await config()).extraExpenses.some(item => item.id === yearly.id), false);
      await page.locator('#ec-expense-register > summary').click();

      await page.setViewportSize({ width: 900, height: 1000 }); await screenshot('tablet-900');
      for (const width of [390, 320]) {
        await page.setViewportSize({ width, height: 844 });
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true, `page fits ${width}px`);
        await view('overview');
        const clipped = await page.locator('#economy-view .ec-value').evaluateAll(nodes => nodes.filter(node => node.scrollWidth > node.clientWidth + 1).map(node => node.textContent));
        assert.deepEqual(clipped, [], `KPI values fit ${width}px`);
        assert.ok(await incomeSources.evaluateAll(nodes => nodes.every(node => node.getBoundingClientRect().right <= innerWidth)), 'income sources fit on mobile');
        assert.equal(await page.locator('#ec-gross-sub').evaluate(node => node.scrollWidth <= node.clientWidth + 1), true);
        await view('ledger');
        const rowActions = await page.locator('#ec-receipts-body .ec-money:visible, #ec-receipts-body .ec-edit:visible').evaluateAll(nodes => nodes.map(node => {
          const r = node.getBoundingClientRect(); return { text: node.textContent.trim() || node.getAttribute('aria-label'), left: r.left, right: r.right };
        }));
        assert.deepEqual(rowActions.filter(r => r.left < -1 || r.right > width + 1), [], `amounts and edit controls fit ${width}px`);
        await view('shares');
        await open('#ec-edit-shares');
        assert.equal(await page.locator('#ec-dialog').evaluate(node => node.scrollWidth <= node.clientWidth + 1), true);
        await screenshot(`mobile-${width}-shares-dialog`);
        await page.keyboard.press('Escape');
        await page.locator('#ec-dialog').waitFor({ state: 'hidden' });
        await add('withdrawal'); await select('currency', 'USD');
        const bounds = await page.locator('#ec-dialog').boundingBox();
        assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= width + 1);
        await screenshot(`mobile-${width}-dialog`);
        await page.keyboard.press('Escape');
        await page.locator('#ec-dialog').waitFor({ state: 'hidden' });
        assert.equal(await page.locator('#ec-add-operation').evaluate(node => node === document.activeElement), true, 'Escape restores focus');
      }
      await page.setViewportSize({ width: 390, height: 844 }); await view('overview');
      await page.locator('#ec-breakdown summary').click(); await screenshot('mobile');
      assert.deepEqual(pageErrors, []);
      assert.deepEqual(preview.requests.filter(request => request.status >= 500), []);
    } finally {
      await browser.close();
      await preview.close();
    }
  });
}

if (!process.argv.includes('--serve')) test('Cloudflare invoices are read-only in current ledger and archive; settings save and mobile layout work', { timeout: 60000 }, async () => {
 const {chromium}=createRequire(import.meta.url)('playwright');const preview=await startPreview();
 preview.env.CLOUDFLARE_BILLING_TOKEN=crypto.randomUUID();preview.env.CLOUDFLARE_BILLING_ACCOUNT_ID='fixture';
 await preview.env.INSTALLS.put('economy_cloudflare_v1',JSON.stringify({accountId:'fixture',updatedAt:new Date().toISOString(),pending:0,invoices:[{id:'today',amount:10.15,currency:'USD',date:day(),receipt:'IN-TODAY'},{id:'old',amount:5,currency:'USD',date:day(-60),receipt:'IN-OLD'}],usage:{usd:0.15,from:day(-10),to:day(),services:[{name:'Durable Objects',usd:0.15}]},subscriptions:[{name:'Workers Paid',usd:5}]}));
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 try {
 const page=await browser.newPage({viewport:{width:1440,height:1100}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(preview.url+'/admin#economy');await page.locator('[data-ec-view="ledger"]').click();await page.locator('#ec-cloudflare-panel').waitFor({state:'visible'});
 await page.locator('#ec-cloudflare-panel summary').click();assert.match(await page.locator('#ec-cloudflare-body').innerText(),/весь|всего аккаунта/);
 await page.locator('#ec-receipts-body [data-detail-key="expense:cloudflare:today"]').first().click();assert.match(await page.locator('#ec-fields').innerText(),/IN-TODAY/);assert.equal(await page.locator('#ec-submit').isVisible(),false);await page.locator('#ec-cancel').click();
 await page.locator('#ec-expense-register summary').click();await page.locator('#ec-expenses-body [data-detail-key="expense:cloudflare:old"]').first().click();assert.match(await page.locator('#ec-fields').innerText(),/IN-OLD/);await page.locator('#ec-cancel').click();
 await page.locator('[data-ec-view="overview"]').click();await page.locator('#ec-breakdown summary').click();await page.locator('#ec-settings').click();await page.locator('#ec-submit').click();await page.locator('#ec-dialog').waitFor({state:'hidden'});
 await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true);
 await page.locator('[data-ec-view="ledger"]').click();
 if(process.env.ECONOMY_UI_SCREENSHOTS){await mkdir(new URL('../../output/cloudflare-billing/',import.meta.url),{recursive:true});await page.locator('#ec-cloudflare-panel').screenshot({path:fileURLToPath(new URL('../../output/cloudflare-billing/mobile-panel.png',import.meta.url))});}
 assert.deepEqual(errors,[]);
 }finally{await browser.close();await preview.close();}
});

if (!process.argv.includes('--serve')) test('share cards distinguish fund allocation, unpaid, partial, settled and overpaid balances', async () => {
  const preview = await startPreview();
  const { chromium } = createRequire(import.meta.url)('playwright');
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  try {
    const context = await browser.newContext({ viewport: { width:1440, height:900 } });
    const api = preview.url+'/api/admin/economy/';
    async function post(path,data) {
      const response = await context.request.post(api+path,{ data }); assert.equal(response.status(),200);
    }
    await post('settings',{ profitShares:[
      {name:'В развитие',percent:40}, {name:'Анна',percent:20}, {name:'Борис',percent:20},
      {name:'Вера',percent:15}, {name:'Дарья',percent:5}, {name:'Игорь',percent:0},
    ] });
    await post('revenues/add',{ title:'Продажи', date:day(), amount:1000, currency:'USD', store:'other' });
    const report = await (await context.request.get(api+'stats?period=month')).json();
    const partner = name => report.settlements.find(share => share.name===name);
    for (const [name,amount] of [['Борис',17],['Вера',partner('Вера').payoutUsd],['Дарья',partner('Дарья').payoutUsd+1]]) {
      await post('payouts/add',{ id:crypto.randomUUID(),month:report.selectedMonth,date:day(),partnerId:partner(name).id,amount });
    }
    const page = await context.newPage();
    await page.goto(preview.url+'/admin#economy/shares');
    const card = name => page.locator('.ec-allocation-item').filter({ has:page.getByRole('heading',{ name,exact:true }) });
    await card('В развитие').waitFor();
    assert.equal(await card('В развитие').getByRole('button').count(),0);
    assert.match(await card('В развитие').innerText(),/бюджете проекта/);
    assert.equal(await card('Анна').locator('progress').getAttribute('value'),'0');
    assert.equal(await card('Борис').locator('progress').getAttribute('value'),'17');
    assert.equal(await card('Борис').locator('.ec-allocation-primary dt').innerText(),'Осталось выплатить');
    assert.match(await card('Вера').innerText(),/выплачена полностью/);
    assert.match(await card('Дарья').locator('.ec-allocation-primary').innerText(),/Переплата\s+\$1,00/);
    assert.match(await card('Игорь').innerText(),/начислений нет/);
    await page.setViewportSize({width:320,height:800});
    assert.ok(await page.locator('.ec-allocation-item').evaluateAll(nodes=>nodes.every(el=>el.scrollWidth<=el.clientWidth+1)));
  } finally {
    await browser.close();
    await preview.close();
  }
});
