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
  const env = { INSTALLS: new MemoryKV(), ADMIN_PASSWORD: crypto.randomUUID() };
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
      await page.locator(button).click();
      await page.locator('#ec-dialog').waitFor({ state: 'visible' });
      assert.equal(await page.locator('#ec-dialog').evaluate(node => node instanceof HTMLDialogElement && node.open), true);
      assert.equal(await page.locator('#ec-dialog').evaluate(node => node.contains(document.activeElement)), true);
      assert.ok(await page.locator('#ec-dialog').getAttribute('aria-labelledby'));
      const bounds = await page.locator('#ec-dialog').boundingBox();
      assert.ok(Math.abs(bounds.x * 2 + bounds.width - page.viewportSize().width) <= 2, 'dialog is centered horizontally');
      assert.equal(await page.locator('#ec-form input, #ec-form select').evaluateAll(nodes => nodes.every(node => node.labels?.length || node.getAttribute('aria-label'))), true);
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
    try {
      await page.goto(`${preview.url}/admin#economy`);
      await page.locator('#economy-view').waitFor({ state: 'visible' });
      await settled();
      assert.equal((await stats()).revenue.grossRub, 35290);
      await screenshot('desktop');

      await page.locator('#ec-show-tests').check();
      assert.equal(await page.locator('#ec-receipts-body [data-copy="fixture-test"]').count(), 1);
      assert.equal((await stats()).revenue.grossRub, 35290, 'showing test receipts never changes income');
      await page.locator('#ec-show-tests').uncheck();
      await page.locator('#ec-store-filter').selectOption('rustore');
      assert.equal(await page.locator('#ec-receipts-body tr').count(), 1);
      assert.equal(await page.locator('#ec-receipts-body [data-revenue-id="fixture-income"]').count(), 1);
      await page.locator('#ec-search').fill('нет такого поступления');
      assert.match(await page.locator('#ec-receipts-body').innerText(), /Ничего не найдено/);
      await page.locator('#ec-search').clear(); await page.locator('#ec-store-filter').selectOption('all');
      await page.locator('#ec-receipt-mode [data-mode="estimated"]').click();
      assert.equal(await page.locator('#ec-receipts-body [data-copy="fixture-ios"]').count(), 1);
      assert.equal(await page.locator('#ec-receipts-body [data-revenue-id]').count(), 0);
      assert.match(await page.locator('#ec-ledger-note').innerText(), /вне дохода/);
      assert.equal((await stats()).revenue.grossRub, 35290);
      await page.locator('#ec-receipt-mode [data-mode="actual"]').click();

      // Shares are saved together; zero must survive a reload and recalculation.
      await open('#ec-edit-shares');
      await field('nikitaSharePercent', 0);
      assert.equal(await page.locator('#ec-form [name="sergeySharePercent"]').inputValue(), '100');
      await field('reinvestPercent', 0);
      await save();
      assert.equal((await config()).nikitaSharePercent, 0);
      assert.equal((await stats()).partners.sergey.percent, 100);
      await page.reload(); await settled();
      await open('#ec-edit-shares');
      assert.equal(await page.locator('#ec-form [name="nikitaSharePercent"]').inputValue(), '0');
      await field('nikitaSharePercent', 25); await field('reinvestPercent', 10); await save();
      assert.equal((await config()).sergeySharePercent, 75);

      await open('#ec-add-expense');
      await field('title', 'Дизайн и иллюстрации'); await field('amount', 2500);
      await select('frequency', 'once'); await select('currency', 'RUB'); await field('date', day());
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
      assert.ok(expense); assert.equal(expense.frequency, 'once');
      await open(`[data-expense-id="${expense.id}"]`);
      await field('title', 'Облачный сервис'); await field('amount', 12);
      await select('frequency', 'monthly'); await select('currency', 'USD'); await field('date', day());
      await save();
      expense = (await config()).extraExpenses.find(item => item.id === expense.id);
      assert.equal(expense.amount, 12); assert.equal(expense.currency, 'USD'); assert.equal(expense.frequency, 'monthly');
      await page.locator('#ec-expense-filter [data-filter="once"]').click();
      assert.equal(await page.locator(`[data-expense-id="${expense.id}"]`).count(), 0);
      await page.locator('#ec-expense-filter [data-filter="recurring"]').click();
      await open(`[data-expense-id="${expense.id}"]`); await remove();
      assert.equal((await config()).extraExpenses.some(item => item.id === expense.id), false);
      await page.locator('#ec-expense-filter [data-filter="all"]').click();

      await open('#ec-add-expense');
      await field('title', 'Годовая лицензия'); await field('amount', 3000);
      await select('frequency', 'yearly'); await field('date', day()); await field('endDate', day(365));
      await save();
      const yearly = (await config()).extraExpenses.find(item => item.title === 'Годовая лицензия');
      assert.equal(yearly.frequency, 'yearly'); assert.equal(yearly.endDate, day(365));
      const writesBeforeCancel = preview.requests.filter(request => request.method === 'POST').length;
      await open(`[data-delete-expense-id="${yearly.id}"]`);
      assert.equal(await page.locator('#ec-dialog-title').innerText(), 'Удалить расход?');
      assert.equal(await page.locator('#ec-form [name="title"]').count(), 0, 'trash opens confirmation instead of editing');
      assert.equal(await page.locator('#ec-submit').innerText(), 'Удалить');
      await screenshot('delete-expense-dialog');
      await page.locator('#ec-cancel').click();
      await page.locator('#ec-dialog').waitFor({ state: 'hidden' });
      assert.equal(preview.requests.filter(request => request.method === 'POST').length, writesBeforeCancel, 'cancel never writes');
      assert.equal((await config()).extraExpenses.some(item => item.id === yearly.id), true);
      await open(`[data-delete-expense-id="${yearly.id}"]`); await save();
      assert.equal((await config()).extraExpenses.some(item => item.id === yearly.id), false);

      // Built-in budgets use the same direct action and retain their configured amount.
      const beforeBuiltinDeletion = await stats();
      for (const [id, flag, amountField] of [
        ['builtin-cloudflare', 'cloudflareEnabled', 'cloudflareMonthlyUsd'],
        ['builtin-domain', 'domainEnabled', 'domainMonthlyRub'],
      ]) {
        const before = await stats();
        const line = before.expenses.lines.find(item => item.id === id);
        const originalAmount = (await config())[amountField];
        assert.ok(line);
        await open(`[data-delete-expense-id="${id}"]`); await save();
        const deletedConfig = await config(), after = await stats();
        assert.equal(deletedConfig[flag], false);
        assert.equal(deletedConfig[amountField], originalAmount, 'deletion preserves the amount for restoration');
        assert.equal(after.expenses.lines.some(item => item.id === id), false);
        assert.ok(Math.abs(after.expenses.totalRub - (before.expenses.totalRub - line.periodRub)) <= 0.01);
        assert.ok(Math.abs(after.expenses.monthlyRub - (before.expenses.monthlyRub - line.monthlyRub)) <= 0.01);
        await page.reload(); await settled();
        assert.equal(await page.locator(`[data-delete-expense-id="${id}"]`).count(), 0, 'removed budget stays absent after reload');
      }
      await open('#ec-settings');
      assert.equal(await page.locator('#ec-form [name="cloudflareMonthlyUsd"]').inputValue(), '5');
      assert.equal(await page.locator('#ec-form [name="domainMonthlyRub"]').inputValue(), '67');
      await page.locator('#ec-form [name="cloudflareEnabled"]').check();
      await page.locator('#ec-form [name="domainEnabled"]').check();
      await save();
      const restored = await stats();
      assert.equal(restored.expenses.totalRub, beforeBuiltinDeletion.expenses.totalRub);
      assert.equal(restored.expenses.monthlyRub, beforeBuiltinDeletion.expenses.monthlyRub);
      for (const id of ['builtin-cloudflare', 'builtin-domain']) {
        assert.equal(await page.locator(`[data-delete-expense-id="${id}"]`).count(), 1, 'settings restore the expense row');
      }

      await open('#ec-add-revenue');
      await field('title', 'Выплата Google Play'); await field('amountRub', 4500);
      await select('store', 'googleplay'); await field('date', day()); await save();
      let revenue = (await config()).manualRevenues.find(item => item.title === 'Выплата Google Play');
      assert.ok(revenue); assert.equal((await stats()).revenue.grossRub, 39790);
      await open(`[data-revenue-id="${revenue.id}"]`);
      await field('title', 'Уточнённая выплата Google Play'); await field('amountRub', 4800); await save();
      revenue = (await config()).manualRevenues.find(item => item.id === revenue.id);
      assert.equal(revenue.amountRub, 4800); assert.equal((await stats()).revenue.grossRub, 40090);
      await open(`[data-revenue-id="${revenue.id}"]`); await remove();
      assert.equal((await config()).manualRevenues.some(item => item.id === revenue.id), false);

      const allResponse = page.waitForResponse(response => response.url().includes('/economy/stats?period=all'));
      await page.locator('#ec-period-tabs [data-period="all"]').click(); await allResponse; await settled();
      assert.equal((await stats('all')).revenue.grossRub, 40290);
      assert.equal(await page.locator('[data-revenue-id="fixture-old-income"]').count(), 1);
      const recentResponse = page.waitForResponse(response => response.url().includes('/economy/stats?period=30d'));
      await page.locator('#ec-period-tabs [data-period="30d"]').click(); await recentResponse; await settled();
      assert.equal(await page.locator('[data-revenue-id="fixture-old-income"]').count(), 0);

      await open('#ec-settings');
      await field('usdRate', 100); await field('cloudflareMonthlyUsd', 0); await field('domainMonthlyRub', 0);
      let releaseReload, markReloadRequested;
      const reloadGate = new Promise(resolve => { releaseReload = resolve; });
      const reloadRequested = new Promise(resolve => { markReloadRequested = resolve; });
      await page.route('**/api/admin/economy/stats?period=*', async route => {
        markReloadRequested(); await reloadGate; await route.continue();
      }, { times: 1 });
      const savedSettings = page.waitForResponse(response => response.url().endsWith('/economy/settings') && response.request().method() === 'POST');
      await page.locator('#ec-submit').click(); assert.equal((await savedSettings).status(), 200);
      await reloadRequested; await page.locator('#ec-dialog').waitFor({ state: 'hidden' });
      for (const id of ['ec-settings', 'ec-edit-shares', 'ec-add-expense', 'ec-add-revenue']) {
        assert.equal(await page.locator(`#${id}`).isDisabled(), true, `${id} waits for the refreshed snapshot`);
      }
      await page.locator('[data-expense-id="fixture-once"]').evaluate(button => button.click());
      assert.equal(await page.locator('#ec-dialog').isVisible(), false, 'row editing also waits for the new snapshot');
      await page.locator('[data-delete-expense-id="fixture-once"]').evaluate(button => button.click());
      assert.equal(await page.locator('#ec-dialog').isVisible(), false, 'direct deletion also waits for the new snapshot');
      releaseReload(); await settled();
      await page.waitForFunction(() => !document.querySelector('#ec-add-expense').disabled);
      assert.equal((await config()).domainMonthlyRub, 0); assert.equal((await config()).cloudflareMonthlyUsd, 0);

      await page.setViewportSize({ width: 900, height: 1000 });
      const clippedKpis = await page.locator('#economy-view .ec-value').evaluateAll(nodes => nodes.filter(node => node.scrollWidth > node.clientWidth + 1).map(node => node.textContent));
      assert.deepEqual(clippedKpis, [], 'tablet KPI amounts fit their cards');
      const wrappedKpis = await page.locator('#economy-view .ec-value').evaluateAll(nodes => nodes.filter(node => {
        const range = document.createRange(); range.selectNodeContents(node); return range.getClientRects().length > 1;
      }).map(node => node.textContent));
      assert.deepEqual(wrappedKpis, [], 'tablet amounts keep their currency on the same line');
      await screenshot('tablet-900');

      for (const width of [390, 320]) {
        await page.setViewportSize({ width, height: 844 });
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true, `page fits ${width}px`);
        const controls = await page.locator('#economy-view button:visible').evaluateAll(nodes => nodes.filter(node => !node.closest('table')).map(node => {
          const r = node.getBoundingClientRect(); return { text: node.textContent.trim(), left: r.left, right: r.right };
        }));
        assert.deepEqual(controls.filter(r => r.left < -1 || r.right > width + 1), [], `controls fit ${width}px`);
        const rowActions = await page.locator('#ec-expenses-body .ec-money:visible, #ec-expenses-body .ec-edit:visible, #ec-expenses-body [data-delete-expense-id]:visible, #ec-receipts-body .ec-money:visible, #ec-receipts-body .ec-edit:visible').evaluateAll(nodes => nodes.map(node => {
          const r = node.getBoundingClientRect(); return { text: node.textContent.trim() || node.getAttribute('aria-label'), left: r.left, right: r.right };
        }));
        assert.deepEqual(rowActions.filter(r => r.left < -1 || r.right > width + 1), [], `amounts, edit and trash controls fit ${width}px`);
        assert.equal(await page.locator('#ec-expenses-body [data-delete-expense-id]:visible').count(), 4, 'every expense has a visible delete action');
        await open('[data-delete-expense-id="fixture-once"]');
        assert.equal(await page.locator('#ec-dialog-title').innerText(), 'Удалить расход?');
        await screenshot(`mobile-${width}-delete-dialog`);
        await page.keyboard.press('Escape');
        await page.locator('#ec-dialog').waitFor({ state: 'hidden' });
        assert.equal(await page.locator('[data-delete-expense-id="fixture-once"]').evaluate(node => node === document.activeElement), true);
        await open('#ec-add-expense');
        const bounds = await page.locator('#ec-dialog').boundingBox();
        assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= width + 1);
        await screenshot(`mobile-${width}-dialog`);
        await page.keyboard.press('Escape');
        await page.locator('#ec-dialog').waitFor({ state: 'hidden' });
        assert.equal(await page.locator('#ec-add-expense').evaluate(node => node === document.activeElement), true, 'Escape restores focus');
      }
      await page.setViewportSize({ width: 390, height: 844 }); await screenshot('mobile');
      assert.deepEqual(pageErrors, []);
      assert.deepEqual(preview.requests.filter(request => request.status >= 500), []);
    } finally {
      await browser.close();
      await preview.close();
    }
  });
}
