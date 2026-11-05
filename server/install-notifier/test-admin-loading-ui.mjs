// Full assembled Worker UI, isolated KV/DO, real admin cookies, and deterministic
// delayed responses. No production requests or publication APIs are used.
// NODE_PATH=<playwright modules> node --test test-admin-loading-ui.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { mkdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import worker from './worker.js';
import { createAdminSession } from './admin_security.js';
import { DEFAULT_ECONOMY_CONFIG } from './economy_admin.js';
import { NotificationsState, DEFAULT_NOTIFICATION_CONFIG } from './notifications.js';

class MemoryKV {
  constructor() { this.store = new Map(); this.metadata = new Map(); }
  async get(key, options) {
    const value = this.store.get(key) ?? null;
    return options === 'json' || options?.type === 'json' ? value === null ? null : JSON.parse(value) : value;
  }
  async getWithMetadata(key, options) { return { value: await this.get(key, options), metadata: this.metadata.get(key) || null }; }
  async put(key, value, options) {
    this.store.set(key, String(value));
    if (options?.metadata) this.metadata.set(key, options.metadata); else this.metadata.delete(key);
  }
  async delete(key) { this.store.delete(key); this.metadata.delete(key); }
  async list({ prefix = '', limit = 1000, cursor = '0' } = {}) {
    const all = [...this.store.keys()].filter(key => key.startsWith(prefix)).sort(), start = Number(cursor) || 0;
    const keys = all.slice(start, start + limit).map(name => ({ name, metadata: this.metadata.get(name) }));
    return { keys, list_complete: start + keys.length >= all.length, cursor: String(start + keys.length) };
  }
}
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
async function bounded(promise, label) {
  let timer;
  try { return await Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Timed out: ' + label)), 15000); })]); }
  finally { clearTimeout(timer); }
}
const day = offset => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Moscow' }).format(new Date(Date.now() + offset * 86400000));
const TASK_TITLE = 'Приватная задача загрузки';
const USER_NAME = 'Приватный пользователь';

async function preview() {
  const env = { INSTALLS: new MemoryKV(), ADMIN_PASSWORD: crypto.randomUUID() };
  await env.INSTALLS.put('economy_fx_usd_v1',JSON.stringify({rubPerUsd:95,effectiveDate:day(0),requestedDay:day(0),checkedAt:new Date().toISOString(),source:'CBR'}));
  const token = await createAdminSession(env), now = Date.now();
  await env.INSTALLS.put('tasks:items', JSON.stringify([{ id: 'loading-task', text: TASK_TITLE, status: 'idea', priority: 'normal', version: '', attachments: [], createdAt: now }]));
  const user = { id: 'google_loading', name: USER_NAME, email: 'private@example.invalid', provider: 'google', createdAt: new Date(now).toISOString(), lastSeen: new Date(now).toISOString() };
  await env.INSTALLS.put('user:google_loading', JSON.stringify(user), { metadata: { ...user, v: 4 } });
  await env.INSTALLS.put('tracked_links', JSON.stringify([{ id: 'loading-link', source: 'tg', campaign: 'loading_probe', page: 'https://pdd-drive.ru/', title: 'Ссылка загрузки', createdAt: new Date(now).toISOString() }]));
  await env.INSTALLS.put('economy_config', JSON.stringify({ ...structuredClone(DEFAULT_ECONOMY_CONFIG), manualRevenues: [{ id: 'loading-income', title: 'Операция загрузки', amount: 1000, amountRub: 1000, currency: 'RUB', store: 'other', date: day(0) }] }));
  await env.INSTALLS.put('blog_articles', JSON.stringify([{ slug: 'loading-preview', title: 'Статья загрузки', datePublished: day(1), published: true, description: 'Локальный пример' }]));
  await env.INSTALLS.put('threads_queue', JSON.stringify([{ id: 'loading-thread', text: 'Пост загрузки', status: 'queued', createdAt: now }]));
  await env.INSTALLS.put('social:accounts', JSON.stringify([{ id: 'loading-social', name: 'Локальный канал', active: false, targets: ['youtube'], postTime: '19:00', driveFolderId: '' }]));
  await env.INSTALLS.put('social:posts', JSON.stringify([{ id: 'loading-video', accountId: 'loading-social', title: 'Видео загрузки', fileName: '001_loading.mp4', status: 'queued', targets: ['youtube'], createdAt: now }]));
  const records = new Map([['config', { ...DEFAULT_NOTIFICATION_CONFIG }]]);
  records.set('message:loading-notice', { id: 'loading-notice', app: 'ru', platform: 'all', store: 'all', kind: 'banner', title: 'Уведомление загрузки', body: 'Локальный пример', enabled: true, status: 'published', layout: 'standard', action: 'premium', createdAt: now, startAt: now, expiresAt: now + 86400000, button: true, inApp: false });
  const storage = {
    get: async key => structuredClone(records.get(key)), put: async (key, value) => records.set(key, structuredClone(value)),
    delete: async key => records.delete(key), setAlarm: async () => {},
    list: async ({ prefix }) => new Map([...records].filter(([key]) => key.startsWith(prefix)).map(([key, value]) => [key, structuredClone(value)])),
  };
  const notifications = new NotificationsState({ storage }, env);
  env.NOTIFICATIONS = { idFromName: () => 'loading-notifications', get: () => ({ fetch: (url, init) => notifications.fetch(new Request(url, init)) }) };
  const requests = [], gates = [], failures = [];
  const matches = (key, url) => key.includes('?') ? key === url.pathname + url.search : key === url.pathname;
  const server = createServer(async (incoming, outgoing) => {
    try {
      const url = new URL(incoming.url, `http://${incoming.headers.host}`), chunks = [];
      const entry = { method: incoming.method, path: url.pathname, query: url.search, prepared: false };
      requests.push(entry);
      const gate = gates.find(item => !item.used && item.method === incoming.method && matches(item.key, url));
      if (gate) gate.used = true;
      const failure = failures.find(item => !item.used && item.method === incoming.method && matches(item.key, url));
      if (failure) failure.used = true;
      for await (const chunk of incoming) chunks.push(chunk);
      const pending = [];
      const response = failure ? Response.json({ error: 'Локальная проверка недоступности' }, { status: failure.status }) : await worker.fetch(new Request(url, {
        method: incoming.method, headers: new Headers(incoming.headers), ...(chunks.length ? { body: Buffer.concat(chunks) } : {}),
      }), env, { waitUntil(promise) { pending.push(promise); } });
      const body = Buffer.from(await response.arrayBuffer());
      entry.prepared = true; entry.status = response.status;
      if (gate) { gate.ready.resolve(entry); await gate.release.promise; }
      if (!outgoing.destroyed) { outgoing.writeHead(response.status, Object.fromEntries(response.headers)); outgoing.end(body); }
      await Promise.allSettled(pending);
    } catch (error) {
      if (!outgoing.destroyed) { outgoing.writeHead(500); outgoing.end(String(error)); }
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return {
    env, token, requests, url: `http://127.0.0.1:${server.address().port}`,
    count(path, method = 'GET') { return requests.filter(item => item.path === path && item.method === method).length; },
    hold(key, method = 'GET') {
      const gate = { key, method, ready: deferred(), release: deferred(), used: false }; gates.push(gate);
      return { get ready() { return (async () => {
        let timer;
        try { return await Promise.race([gate.ready.promise, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('No prepared response for ' + key + ': ' + JSON.stringify(requests.slice(-8)))), 15000); })]); }
        finally { clearTimeout(timer); }
      })(); }, release: () => gate.release.resolve() };
    },
    fail(key, status = 503, method = 'GET') { failures.push({ key, status, method }); },
    async close() { gates.forEach(gate => gate.release.resolve()); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); },
  };
}

async function browserFixture() {
  const app = await preview();
  const { chromium } = createRequire(import.meta.url)('playwright');
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  return {
    app, browser,
    async page(authenticated = true) {
      const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce' });
      await context.route('**/*', async route => {
        const url = new URL(route.request().url());
        if (url.origin === app.url) return route.continue();
        if (url.hostname === 'pdd-drive.ru' && ['/assets/icon-192.png', '/assets/favicon.png'].includes(url.pathname)) {
          return route.fulfill({ contentType: 'image/png', body: await readFile(new URL('../../web_landing/ru' + url.pathname, import.meta.url)) });
        }
        return route.abort();
      });
      if (authenticated) await context.addCookies([{ name: 'pdd_admin_token', value: app.token, url: app.url, httpOnly: true, sameSite: 'Lax' }]);
      const page = await context.newPage(), errors = [];
      page.setDefaultTimeout(10000);
      page.on('pageerror', error => errors.push(error.message));
      return { page, context, errors };
    },
    async close() { await browser.close(); await app.close(); },
  };
}
async function state(page, id, value) {
  await page.waitForFunction(({ id, value }) => document.getElementById(id)?.dataset.loadState === value, { id, value });
}
async function capture(page, name) {
  if (!process.env.ADMIN_LOADING_SCREENSHOTS) return;
  const directory = new URL('../../output/admin-loading/', import.meta.url);
  await mkdir(directory, { recursive: true });
  await page.screenshot({ path: fileURLToPath(new URL(name + '.png', directory)), fullPage: true });
}
const sections = [
  ['analytics', 'analytics-view', ['/api/admin/stats']],
  ['tasks', 'tasks-view', ['/api/admin/tasks']],
  ['links', 'links-view', ['/api/admin/links', '/api/admin/stats']],
  // The other sources can finish first; a partial first response must not hide
  // the skeleton while the main data for this composite workspace is pending.
  ['publications', 'pb-plan-workspace', ['/api/admin/blog']],
  ['users', 'users-view', ['/api/admin/users']],
  ['ai', 'ai-view', ['/api/admin/ai/stats']],
  ['economy', 'economy-view', ['/api/admin/economy/stats']],
  ['notifications', 'notifications-view', ['/api/admin/notifications']],
  ['publications/blog', 'blog-view', ['/api/admin/blog']],
  ['publications/threads', 'threads-view', ['/api/admin/threads/state']],
  ['publications/videos', 'social-view', ['/api/admin/social/state']],
];

test('all admin sections show accessible loading skeletons until their first response', { timeout: 180000 }, async t => {
  const fixture = await browserFixture();
  try {
    for (const [route, view, paths] of sections.filter(section => !process.env.ADMIN_LOADING_ONLY || section[0] === process.env.ADMIN_LOADING_ONLY)) await t.test(route, async () => {
      const { page, context, errors } = await fixture.page();
      const gates = paths.map(path => fixture.app.hold(path));
      try {
        await page.goto(`${fixture.app.url}/admin#${route}`);
        await Promise.all(gates.map(gate => gate.ready));
        await state(page, view, 'loading');
        const skeleton = page.locator(`#${view} > .admin-view-skeleton`);
        assert.equal(await skeleton.isVisible(), true, route + ': first load has visible skeleton');
        assert.equal(await skeleton.getAttribute('role'), 'status');
        assert.equal(await skeleton.getAttribute('aria-label'), 'Загрузка данных');
        assert.equal(await page.locator(`#${view}`).getAttribute('aria-busy'), 'true');
        await capture(page, route.replaceAll('/', '-') + '-loading');
        if (route === 'tasks') {
          await page.setViewportSize({ width: 375, height: 812 });
          assert.equal(await skeleton.isVisible(), true);
          assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'loading layout fits a narrow screen');
          await capture(page, 'tasks-mobile-loading');
          await page.setViewportSize({ width: 1440, height: 1000 });
        }
        gates.forEach(gate => gate.release());
        await state(page, view, 'ready');
        assert.equal(await skeleton.isVisible(), false);
        assert.equal(await page.locator(`#${view}`).getAttribute('aria-busy'), 'false');
        const away = route === 'tasks' ? 'users' : 'tasks';
        await page.locator(`.sidebar-menu [data-feature="${away}"]`).click(); await state(page, away + '-view', 'ready');
        const before = fixture.app.count(paths[0]);
        await page.locator(`.sidebar-menu [data-feature="${route.split('/')[0]}"]`).click();
        if (route.startsWith('publications/')) await page.locator(`[data-pb-workspace="${route.split('/')[1]}"]`).click();
        await state(page, view, 'ready');
        assert.equal(await skeleton.isVisible(), false, route + ': revisit renders the cached workspace');
        assert.equal(fixture.app.count(paths[0]), before, route + ': fresh revisit avoids another GET');
        assert.deepEqual(errors, []);
      } catch (error) {
        console.error(route + ': ' + error.message + '; view state: ' + await page.locator(`#${view}`).getAttribute('data-load-state') + '; browser errors: ' + JSON.stringify(errors));
        await capture(page, route.replaceAll('/', '-') + '-failure'); throw error;
      } finally { gates.forEach(gate => gate.release()); await context.close(); }
    });
  } finally { await fixture.close(); }
});

test('revisits reuse data, stale data stays visible, refresh and concurrent callers share one request', { timeout: 60000 }, async () => {
  const fixture = await browserFixture(), { page, context, errors } = await fixture.page();
  const app = fixture.app;
  try {
    await page.goto(`${app.url}/admin#tasks`); await state(page, 'tasks-view', 'ready');
    assert.match(await page.locator('#tasks-view').innerText(), new RegExp(TASK_TITLE));
    const count = app.count('/api/admin/tasks');
    await page.locator('.sidebar-menu [data-feature="users"]').click(); await state(page, 'users-view', 'ready');
    await page.locator('.sidebar-menu [data-feature="tasks"]').click(); await state(page, 'tasks-view', 'ready');
    assert.equal(app.count('/api/admin/tasks'), count, 'fresh cache avoids another request');
    // Advance Date.now only: timers and browser/Worker clocks remain untouched.
    await page.evaluate(() => { const now = Date.now; Date.now = () => now() + 60000; });
    await page.locator('.sidebar-menu [data-feature="users"]').click(); await state(page, 'users-view', 'ready');
    const gate = app.hold('/api/admin/tasks');
    await page.locator('.sidebar-menu [data-feature="tasks"]').click(); await gate.ready;
    await state(page, 'tasks-view', 'refreshing');
    assert.match(await page.locator('#tasks-view').innerText(), new RegExp(TASK_TITLE));
    assert.equal(await page.locator('#tasks-view > .admin-view-skeleton').isVisible(), false);
    gate.release(); await state(page, 'tasks-view', 'ready');

    const concurrent = app.hold('/api/admin/tasks');
    const before = app.count('/api/admin/tasks');
    await page.evaluate(() => { window.loadingResults = []; window.loadingPromises = Promise.all([1, 2].map(id => AdminData.load('/api/admin/tasks', { view: 'tasks-view', force: true, onData: (data, meta) => { if (!meta?.cached) window.loadingResults.push({ id, title: data.tasks[0].text }); } }))); });
    await concurrent.ready;
    assert.equal(app.count('/api/admin/tasks'), before + 1, 'simultaneous loads deduplicate the network request');
    concurrent.release(); await page.evaluate(() => window.loadingPromises);
    assert.deepEqual((await page.evaluate(() => window.loadingResults)).map(item => item.id).sort(), [1, 2]);

    await page.locator('.sidebar-menu [data-feature="economy"]').click(); await state(page, 'economy-view', 'ready');
    const refresh = app.hold('/api/admin/economy/stats'), refreshBefore = app.count('/api/admin/economy/stats');
    await page.locator('#ec-refresh').click(); await refresh.ready;
    assert.equal(app.count('/api/admin/economy/stats'), refreshBefore + 1, 'explicit refresh bypasses fresh cache');
    refresh.release(); await state(page, 'economy-view', 'ready');

    app.fail('/api/admin/economy/stats');
    await page.locator('#ec-refresh').click(); await state(page, 'economy-view', 'stale');
    assert.match(await page.locator('#economy-view').innerText(), /Операция загрузки/);
    assert.match(await page.locator('#economy-view').innerText(), /Не удалось|не обнов|сохранён/i);
    assert.equal(await page.locator('#economy-view > .admin-view-skeleton').isVisible(), false);
    await capture(page, 'economy-stale');
    await page.locator('.sidebar-menu [data-feature="tasks"]').click(); await state(page, 'tasks-view', 'ready');
    const reload = app.hold('/api/admin/tasks');
    await page.reload(); await reload.ready; await state(page, 'tasks-view', 'loading');
    assert.equal(await page.getByText(TASK_TITLE, { exact: true }).isVisible(), false, 'a new document does not restore private records from disk');
    reload.release(); await state(page, 'tasks-view', 'ready');
    assert.deepEqual(errors, []);
  } finally { await context.close(); await fixture.close(); }
});

test('first-load failures expose a working retry without leaving the skeleton stuck', { timeout: 30000 }, async () => {
  const fixture = await browserFixture(), { page, context, errors } = await fixture.page(), app = fixture.app;
  try {
    app.fail('/api/admin/tasks');
    await page.goto(`${app.url}/admin#tasks`); await state(page, 'tasks-view', 'error');
    assert.equal(await page.locator('#tasks-view > .admin-view-skeleton').isVisible(), false);
    assert.match(await page.locator('#tasks-view > .admin-load-notice').innerText(), /Не удалось загрузить/);
    const before = app.count('/api/admin/tasks');
    await page.locator('#tasks-view > .admin-load-notice button').click(); await state(page, 'tasks-view', 'ready');
    assert.equal(app.count('/api/admin/tasks'), before + 1);
    assert.match(await page.locator('#tasks-view').innerText(), new RegExp(TASK_TITLE));
    assert.deepEqual(errors, []);
  } finally { await context.close(); await fixture.close(); }
});

test('retry in a composite view reloads its failed endpoint, preserving the successful source', { timeout: 30000 }, async () => {
  const fixture = await browserFixture(), { page, context, errors } = await fixture.page(), app = fixture.app;
  try {
    app.fail('/api/admin/links');
    await page.goto(`${app.url}/admin#links`); await state(page, 'links-view', 'stale');
    const linksBefore = app.count('/api/admin/links'), statsBefore = app.count('/api/admin/stats');
    await page.locator('#links-view > .admin-load-notice button').click(); await state(page, 'links-view', 'ready');
    assert.equal(app.count('/api/admin/links'), linksBefore + 1, 'retry repeats the failed links request');
    assert.equal(app.count('/api/admin/stats'), statsBefore, 'successful statistics are retained');
    assert.match(await page.locator('#links-view').innerText(), /Ссылка загрузки|loading_probe/);
    assert.deepEqual(errors, []);
  } finally { await context.close(); await fixture.close(); }
});

test('a successful mutation prevents an older response from rendering or repopulating cache', { timeout: 60000 }, async () => {
  const fixture = await browserFixture(), { page, context, errors } = await fixture.page(), app = fixture.app;
  try {
    await page.goto(`${app.url}/admin#tasks`); await state(page, 'tasks-view', 'ready');
    const url = '/api/admin/tasks?loading-race=1', old = app.hold(url);
    await page.evaluate(url => { window.raceValues = []; window.oldLoad = AdminData.load(url, { view: 'tasks-view', onData: data => window.raceValues.push(data.tasks.map(task => task.text)) }).catch(error => ({ error: error.message })); }, url);
    await old.ready;
    const result = await page.evaluate(async () => {
      const response = await fetch('/api/admin/tasks/save', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ text: 'Добавлено после задержанного чтения', status: 'idea' }) });
      return { status: response.status, data: await response.json() };
    });
    assert.equal(result.status, 200);
    await page.evaluate(async url => { await AdminData.load(url, { view: 'tasks-view', force: true, onData: data => window.raceValues.push(data.tasks.map(task => task.text)) }); }, url);
    old.release(); await page.evaluate(() => window.oldLoad);
    await page.evaluate(async url => { await AdminData.load(url, { view: 'tasks-view', onData: data => window.raceValues.push(data.tasks.map(task => task.text)) }); }, url);
    const values = await page.evaluate(() => window.raceValues);
    assert.ok(values.length >= 2);
    assert.ok(values.every(value => value.includes('Добавлено после задержанного чтения')), 'no obsolete callback or cached response survives the mutation');
    assert.deepEqual(errors, []);
  } finally { await context.close(); await fixture.close(); }
});

test('session gates every read, logout hides private content and clears the page cache', { timeout: 60000 }, async () => {
  const fixture = await browserFixture(), { page, context, errors } = await fixture.page(false), app = fixture.app;
  try {
    const session = app.hold('/api/admin/session');
    await page.goto(`${app.url}/admin#users`); await session.ready;
    assert.equal(await page.locator('#app').isVisible(), false, 'app is hidden until authorization completes');
    assert.equal(app.requests.filter(item => item.path.startsWith('/api/admin/') && item.path !== '/api/admin/session').length, 0, 'no private endpoint requested before session confirmation');
    await page.evaluate(() => { window.authAttempts = Promise.allSettled([AdminData.ensureSession(), AdminData.ensureSession()]); });
    assert.equal(app.count('/api/admin/session'), 1, 'concurrent consumers share session request');
    session.release(); await page.locator('#login-overlay').waitFor({ state: 'visible' });
    await bounded(page.evaluate(() => window.authAttempts), 'unauthorized session consumers settle');
    await context.addCookies([{ name: 'pdd_admin_token', value: app.token, url: app.url, httpOnly: true, sameSite: 'Lax' }]);
    await page.reload(); await state(page, 'users-view', 'ready');
    assert.match(await page.locator('#users-view').innerText(), new RegExp(USER_NAME));
    assert.equal(await page.evaluate(() => [localStorage, sessionStorage].some(storage => Object.values(storage).some(value => value.includes('private@example.invalid')))), false, 'private response data stays out of persistent browser storage');
    await Promise.all([page.waitForNavigation({ waitUntil: 'load' }), page.locator('#logout-btn').click()]);
    await page.locator('#app').waitFor({ state: 'hidden' });
    await page.locator('#login-overlay').waitFor({ state: 'visible' });
    assert.equal(await app.env.INSTALLS.get(`admin_session:${app.token}`), null, 'logout revokes the actual server session');
    assert.equal(await page.getByText(USER_NAME, { exact: true }).isVisible(), false);
    const callbacks = await bounded(page.evaluate(async () => { let count = 0; try { await AdminData.load('/api/admin/users', { view: 'users-view', onData: () => { count++; } }); } catch {} return count; }), 'cache read after logout rejects');
    assert.equal(callbacks, 0, 'cached users cannot be delivered after logout');
    assert.equal(await page.locator('#app').isVisible(), false);
    assert.deepEqual(errors, []);
  } finally { await context.close(); await fixture.close(); }
});
