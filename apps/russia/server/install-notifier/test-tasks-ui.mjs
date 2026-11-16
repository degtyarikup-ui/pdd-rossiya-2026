// Full assembled admin UI, real session/CSRF and isolated in-memory task data.
// NODE_PATH=<playwright modules> node --test test-tasks-ui.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { mkdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import worker from './worker.js';
import { createAdminSession } from './admin_security.js';

const STATUSES = ['idea', 'planned', 'in_progress', 'ready', 'released', 'archived'];
class MemoryKV {
  constructor() { this.store = new Map(); }
  async get(key, options) {
    const value = this.store.get(key) ?? null;
    return options === 'json' || options?.type === 'json' ? value === null ? null : JSON.parse(value) : value;
  }
  async put(key, value) { this.store.set(key, String(value)); }
  async delete(key) { this.store.delete(key); }
  async list({ prefix = '' } = {}) {
    return { keys: [...this.store.keys()].filter(name => name.startsWith(prefix)).map(name => ({ name })), list_complete: true };
  }
}
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};

async function preview() {
  const env = { INSTALLS: new MemoryKV(), ADMIN_PASSWORD: crypto.randomUUID() };
  const now = Date.now();
  const tasks = STATUSES.map(status => ({
    id: 'task-' + status, text: 'Задача ' + status + '\nОписание задачи', status,
    priority: 'normal', version: 'v1.0.1', attachments: [], createdAt: now, updatedAt: now,
  }));
  tasks.push({ id: 'legacy-task', text: 'Задача без исполнителя', status: 'planned', attachments: [], createdAt: now });
  await env.INSTALLS.put('tasks:items', JSON.stringify(tasks));
  const token = await createAdminSession(env);
  const requests = [];
  const holds = [];
  let nextHold = null;
  let nextFailure = false;
  const server = createServer(async (incoming, outgoing) => {
    try {
      const url = new URL(incoming.url, `http://${incoming.headers.host}`), chunks = [];
      for await (const chunk of incoming) chunks.push(chunk);
      const assignment = url.pathname === '/api/admin/tasks/assign' && incoming.method === 'POST';
      if (assignment) requests.push(JSON.parse(Buffer.concat(chunks).toString()));
      const hold = assignment ? nextHold : null;
      if (hold) { nextHold = null; hold.entered.resolve(); await hold.release.promise; }
      const fail = assignment && nextFailure;
      if (fail) nextFailure = false;
      const response = fail ? Response.json({ error: 'Проверка ошибки сохранения' }, { status: 503 }) : await worker.fetch(new Request(url, {
        method: incoming.method, headers: new Headers(incoming.headers), ...(chunks.length ? { body: Buffer.concat(chunks) } : {}),
      }), env, { waitUntil(promise) { promise.catch(() => {}); } });
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      outgoing.end(Buffer.from(await response.arrayBuffer()));
    } catch (error) {
      outgoing.writeHead(500); outgoing.end(String(error));
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return {
    url: `http://127.0.0.1:${server.address().port}`, token, requests,
    async task(id) { return JSON.parse(await env.INSTALLS.get('tasks:items')).find(task => task.id === id); },
    holdAssignment() { nextHold = { entered: deferred(), release: deferred() }; holds.push(nextHold); return nextHold; },
    failAssignment() { nextFailure = true; },
    async close() {
      holds.forEach(hold => hold.release.resolve());
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    },
  };
}

async function browserFixture() {
  const app = await preview();
  const { chromium } = createRequire(import.meta.url)('playwright');
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce' });
  await context.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.origin === app.url) return route.continue();
    if (url.hostname === 'pdd-drive.ru' && ['/assets/icon-192.png', '/assets/favicon.png'].includes(url.pathname)) {
      return route.fulfill({ contentType: 'image/png', body: await readFile(new URL('../../web_landing/ru' + url.pathname, import.meta.url)) });
    }
    return route.abort();
  });
  await context.addCookies([{ name: 'pdd_admin_token', value: app.token, url: app.url, httpOnly: true, sameSite: 'Lax' }]);
  const page = await context.newPage(), errors = [];
  page.setDefaultTimeout(10000);
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(app.url + '/admin#tasks');
  await page.locator('#tasks-board-container .task-card[data-task-id="legacy-task"]').waitFor();
  await page.evaluate(() => {
    window.taskTestNotices = [];
    window.adminToast = (message, isError) => window.taskTestNotices.push({ message, isError: Boolean(isError) });
  });
  return { app, page, errors, async close() { await browser.close(); await app.close(); } };
}

const picker = (page, id, view = 'board') => page.locator((view === 'board' ? '#tasks-board-container' : '#tasks-table-body') + ' .task-assignees[data-task-id="' + id + '"]');
const button = (page, id, assignee, view = 'board') => picker(page, id, view).locator('[data-assignee="' + assignee + '"]');
async function assigned(page, id, assignee, view = 'board') {
  await page.waitForFunction(({ id, assignee, view }) => {
    const scope = document.querySelector(view === 'board' ? '#tasks-board-container' : '#tasks-table-body');
    const control = scope?.querySelector('.task-assignees[data-task-id="' + id + '"]');
    const selected = control?.querySelector('[data-assignee="' + assignee + '"]');
    return selected?.getAttribute('aria-pressed') === 'true' && !selected.disabled;
  }, { id, assignee, view });
}
async function capture(page, name) {
  if (!process.env.TASKS_UI_SCREENSHOTS) return;
  const directory = new URL('../../output/tasks-ui/', import.meta.url);
  await mkdir(directory, { recursive: true });
  await page.screenshot({ path: fileURLToPath(new URL(name + '.png', directory)), fullPage: true });
}

test('avatar assignment works in all task columns, survives reload, editing, moving and list view', { timeout: 90000 }, async () => {
  const fixture = await browserFixture(), { app, page, errors } = fixture;
  try {
    assert.equal(await picker(page, 'legacy-task').locator('[aria-pressed="true"]').count(), 0, 'legacy tasks start unassigned');
    await page.locator('#tasks-archive-btn').click();
    assert.equal(await page.locator('#tasks-board-container .task-assignees').count(), 7);
    for (const [index, status] of STATUSES.entries()) {
      const id = 'task-' + status, assignee = index % 2 ? 'nikita' : 'sergey';
      assert.equal(await picker(page, id).locator('button').count(), 2);
      await button(page, id, assignee).click();
      await assigned(page, id, assignee);
      assert.equal((await app.task(id)).assignee, assignee);
      assert.equal(await page.locator('#tasks-edit-modal').isVisible(), false, 'avatar clicks do not open the editor');
    }
    assert.equal(await page.locator('#tasks-board-container .task-assignee-btn img').evaluateAll(images => images.every(image => image.complete && image.naturalWidth > 0 && image.src.startsWith('data:image/'))), true);
    assert.deepEqual(await page.evaluate(() => window.taskTestNotices), [], 'assigning does not show success notices');
    const count = app.requests.length;
    await button(page, 'task-planned', 'nikita').click();
    assert.equal(app.requests.length, count, 'clicking the selected avatar does not save again');
    await page.locator('#tasks-board-container').evaluate(board => { board.scrollLeft = 0; });
    await capture(page, 'board-desktop');

    await page.reload();
    await assigned(page, 'task-planned', 'nikita');
    await page.evaluate(() => { window.adminToast = () => {}; });
    await page.locator('#tasks-view-toggle [data-view="list"]').click();
    await assigned(page, 'task-planned', 'nikita', 'list');
    await button(page, 'task-planned', 'sergey', 'list').focus();
    await page.keyboard.press('Enter');
    await assigned(page, 'task-planned', 'sergey', 'list');
    assert.equal((await app.task('task-planned')).assignee, 'sergey');
    await page.locator('#tasks-table-body [data-edit-task="task-planned"]').first().click();
    await page.locator('#task-form-text').fill('Обновлённая задача\nОписание после изменения');
    await page.locator('#task-form-save-btn').click();
    await page.locator('#tasks-edit-modal').waitFor({ state: 'hidden' });
    await assigned(page, 'task-planned', 'sergey', 'list');
    assert.equal((await app.task('task-planned')).text, 'Обновлённая задача\nОписание после изменения');
    assert.equal((await app.task('task-planned')).assignee, 'sergey', 'editing preserves assignment');
    await capture(page, 'list-desktop');

    await page.locator('#tasks-view-toggle [data-view="board"]').click();
    const transfer = await page.evaluateHandle(() => new DataTransfer());
    await page.locator('#tasks-board-container .task-card[data-task-id="task-planned"]').dispatchEvent('dragstart', { dataTransfer: transfer });
    const move = page.waitForResponse(response => response.url().endsWith('/api/admin/tasks/move') && response.status() === 200);
    await page.locator('.tasks-col[data-col-status="in_progress"]').dispatchEvent('drop', { dataTransfer: transfer });
    await move;
    await assigned(page, 'task-planned', 'sergey');
    assert.equal((await app.task('task-planned')).status, 'in_progress');
    assert.equal((await app.task('task-planned')).assignee, 'sergey', 'moving preserves assignment');
    await transfer.dispose();
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(await page.locator('#tasks-board-container .task-card').evaluateAll(cards => cards.every(card => card.scrollWidth <= card.clientWidth)), true);
    assert.equal(await page.locator('#tasks-board-container .task-card-foot').evaluateAll(feet => feet.every(foot => {
      const control = foot.querySelector('.task-assignees').getBoundingClientRect(), actions = foot.querySelector('.task-foot-actions').getBoundingClientRect();
      return control.right <= actions.left && control.left >= foot.getBoundingClientRect().left;
    })), true, 'avatars fit on the lower left without overlapping actions');
    await page.locator('#tasks-board-container .task-card[data-task-id="task-planned"]').scrollIntoViewIfNeeded();
    await capture(page, 'board-mobile');
    assert.deepEqual(errors, []);
  } finally { await fixture.close(); }
});

test('rapid assignments and editing wait in order without overwriting one another', { timeout: 45000 }, async () => {
  const fixture = await browserFixture(), { app, page, errors } = fixture;
  try {
    const hold = app.holdAssignment();
    await button(page, 'legacy-task', 'sergey').click();
    await hold.entered.promise;
    await button(page, 'task-planned', 'nikita').click();
    assert.equal(await button(page, 'task-planned', 'nikita').getAttribute('aria-pressed'), 'true');
    assert.equal(await picker(page, 'task-planned').locator('button:disabled').count(), 2);
    assert.equal(app.requests.length, 1, 'the next task write stays queued while the first request is in flight');

    await page.locator('#tasks-board-container [data-edit-task="legacy-task"]').first().click();
    await page.locator('#task-form-text').fill('Правка во время назначения');
    await page.locator('#task-form-save-btn').click();
    assert.equal(await page.locator('#task-form-save-btn').isDisabled(), true);
    assert.equal((await app.task('legacy-task')).text, 'Задача без исполнителя', 'queued editing has not reached storage yet');
    assert.equal(app.requests.length, 1);
    hold.release.resolve();
    await page.locator('#tasks-edit-modal').waitFor({ state: 'hidden' });
    await assigned(page, 'legacy-task', 'sergey');
    await assigned(page, 'task-planned', 'nikita');
    assert.deepEqual(app.requests.map(request => [request.id, request.assignee]), [['legacy-task', 'sergey'], ['task-planned', 'nikita']]);
    assert.equal((await app.task('legacy-task')).text, 'Правка во время назначения');
    assert.equal((await app.task('legacy-task')).assignee, 'sergey');
    assert.equal((await app.task('task-planned')).assignee, 'nikita');
    assert.deepEqual(errors, []);
  } finally { await fixture.close(); }
});

test('assignment updates immediately, blocks duplicate clicks and rolls back after a failed save', { timeout: 45000 }, async () => {
  const fixture = await browserFixture(), { app, page, errors } = fixture;
  try {
    const hold = app.holdAssignment();
    await button(page, 'legacy-task', 'sergey').click();
    await hold.entered.promise;
    assert.equal(await button(page, 'legacy-task', 'sergey').getAttribute('aria-pressed'), 'true');
    assert.equal(await picker(page, 'legacy-task').locator('button:disabled').count(), 2);
    assert.equal((await app.task('legacy-task')).assignee, undefined, 'optimistic rendering happens before persistence');
    hold.release.resolve();
    await assigned(page, 'legacy-task', 'sergey');
    assert.equal((await app.task('legacy-task')).assignee, 'sergey');

    app.failAssignment();
    const failure = page.waitForResponse(response => response.url().endsWith('/api/admin/tasks/assign') && response.status() === 503);
    await button(page, 'legacy-task', 'nikita').click();
    await failure;
    await assigned(page, 'legacy-task', 'sergey');
    assert.equal(await button(page, 'legacy-task', 'nikita').getAttribute('aria-pressed'), 'false');
    assert.equal((await app.task('legacy-task')).assignee, 'sergey');
    const notices = await page.evaluate(() => window.taskTestNotices);
    assert.equal(notices.length, 1);
    assert.equal(notices[0].isError, true);
    assert.match(notices[0].message, /Проверка ошибки сохранения/);
    assert.equal(await page.locator('#tasks-edit-modal').isVisible(), false);
    assert.deepEqual(errors, []);
  } finally { await fixture.close(); }
});
