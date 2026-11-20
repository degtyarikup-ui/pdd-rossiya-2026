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
    ...(status === 'ready' ? { assignee: 'sergey' } : status === 'released' ? { assignee: 'nikita' } : {}),
  }));
  tasks.push({ id: 'legacy-task', text: 'Задача без исполнителя', status: 'planned', attachments: [], createdAt: now });
  await env.INSTALLS.put('tasks:items', JSON.stringify(tasks));
  const token = await createAdminSession(env);
  const requests = [];
  const writes = [];
  const holds = [];
  const nextHolds = new Map();
  const nextFailures = new Set();
  const server = createServer(async (incoming, outgoing) => {
    try {
      const url = new URL(incoming.url, `http://${incoming.headers.host}`), chunks = [];
      for await (const chunk of incoming) chunks.push(chunk);
      const assignment = url.pathname === '/api/admin/tasks/assign' && incoming.method === 'POST';
      if (assignment) requests.push(JSON.parse(Buffer.concat(chunks).toString()));
      if (url.pathname.startsWith('/api/admin/tasks/') && incoming.method === 'POST') writes.push({ path: url.pathname, body: JSON.parse(Buffer.concat(chunks).toString()) });
      const hold = incoming.method === 'POST' ? nextHolds.get(url.pathname) : null;
      if (hold) { nextHolds.delete(url.pathname); hold.entered.resolve(); await hold.release.promise; }
      const fail = incoming.method === 'POST' && nextFailures.has(url.pathname);
      if (fail) nextFailures.delete(url.pathname);
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
    url: `http://127.0.0.1:${server.address().port}`, token, requests, writes,
    async task(id) { return JSON.parse(await env.INSTALLS.get('tasks:items')).find(task => task.id === id); },
    hold(path) { const hold = { entered: deferred(), release: deferred() }; holds.push(hold); nextHolds.set('/api/admin/tasks/' + path, hold); return hold; },
    holdAssignment() { return this.hold('assign'); },
    fail(path) { nextFailures.add('/api/admin/tasks/' + path); },
    failAssignment() { this.fail('assign'); },
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
    if (['pdd-drive.ru', 'pdd-drive.app'].includes(url.hostname) && ['/assets/icon-192.png', '/assets/favicon.png'].includes(url.pathname)) {
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

const picker = (page, id) => page.locator('#tasks-board-container .task-assignees[data-task-id="' + id + '"]');
const button = (page, id, assignee) => picker(page, id).locator('[data-assignee="' + assignee + '"]');
const priorityButton = (page, id) => page.locator('.task-priority-btn[data-priority-task="' + id + '"]');
async function assigned(page, id, assignee) {
  await page.waitForFunction(({ id, assignee }) => {
    const control = document.querySelector('#tasks-board-container .task-assignees[data-task-id="' + id + '"]');
    const selected = control?.querySelector('[data-assignee="' + assignee + '"]');
    return selected?.getAttribute('aria-pressed') === 'true' && !selected.disabled;
  }, { id, assignee });
}
async function priorityShown(page, id, label) {
  await page.waitForFunction(({ id, label }) => {
    const control = document.querySelector('.task-priority-btn[data-priority-task="' + id + '"]');
    return control?.textContent.includes(label) && !control.disabled;
  }, { id, label });
}
async function capture(page, name) {
  if (!process.env.TASKS_UI_SCREENSHOTS) return;
  const directory = new URL('../../output/tasks-ui/', import.meta.url);
  await mkdir(directory, { recursive: true });
  await page.screenshot({ path: fileURLToPath(new URL(name + '.png', directory)), fullPage: true });
}

test('the board stays compact and avatars work in every column, after reload, editing and moving', { timeout: 90000 }, async () => {
  const fixture = await browserFixture(), { app, page, errors } = fixture;
  try {
    const removed = '#tasks-view-toggle, #tasks-list-container, #tasks-table-body, #tasks-search-input, #tasks-search-clear, #tasks-version-filter, #tasks-priority-filter, #task-form-version, #tasks-versions-datalist, .tasks-toolbar, .tasks-col-add-btn, .task-badge.version';
    assert.equal(await page.locator(removed).count(), 0, 'versions, list, search, toolbar, filters and header pluses are removed');
    assert.equal(await page.locator('.tasks-col-quick-add').count(), 5, 'each active column retains its bottom add action');
    const header = page.locator('#tasks-header-actions');
    assert.equal(await header.locator('#tasks-archive-btn').count(), 1);
    assert.equal(await header.locator('#tasks-add-task-btn').count(), 1);
    assert.equal(await header.evaluate(actions => {
      const title = document.querySelector('h1');
      const a = actions.getBoundingClientRect(), t = title.getBoundingClientRect();
      return a.left >= t.right && Math.abs((a.top + a.height / 2) - (t.top + t.height / 2)) < 24;
    }), true, 'desktop actions sit beside the task heading');
    assert.equal(await picker(page, 'legacy-task').locator('[aria-pressed="true"]').count(), 0, 'legacy tasks start unassigned');
    await page.locator('#tasks-archive-btn').click();
    assert.equal(await page.locator('#tasks-board-container .task-assignees').count(), 7);
    for (const [index, status] of STATUSES.entries()) {
      const id = 'task-' + status, assignee = status === 'ready' ? 'nikita' : status === 'released' ? 'sergey' : index % 2 ? 'nikita' : 'sergey';
      assert.equal(await picker(page, id).locator('button').count(), 2);
      await button(page, id, assignee).click();
      await assigned(page, id, assignee);
      assert.equal(await picker(page, id).locator('button:visible').count(), 2, 'both avatars remain visible');
      assert.equal((await app.task(id)).assignee, assignee);
      assert.equal(await page.locator('#tasks-edit-modal').isVisible(), false, 'avatar clicks do not open the editor');
    }
    assert.equal(await page.locator('#tasks-board-container .task-assignee-btn img').evaluateAll(images => images.every(image => image.complete && image.naturalWidth > 0 && image.src.startsWith('data:image/'))), true);
    assert.deepEqual(await page.evaluate(() => window.taskTestNotices), [], 'assigning does not show success notices');
    await page.locator('#tasks-board-container').evaluate(board => { board.scrollLeft = 0; });
    await capture(page, 'board-desktop');

    await page.reload();
    await assigned(page, 'task-planned', 'nikita');
    await page.evaluate(() => { window.adminToast = () => {}; });
    await button(page, 'task-planned', 'sergey').focus();
    await page.keyboard.press('Enter');
    await assigned(page, 'task-planned', 'sergey');
    assert.equal((await app.task('task-planned')).assignee, 'sergey');
    await page.locator('#tasks-board-container [data-edit-task="task-planned"]').first().click();
    await page.locator('#task-form-text').fill('Обновлённая задача\nОписание после изменения');
    await page.locator('#task-form-save-btn').click();
    await page.locator('#tasks-edit-modal').waitFor({ state: 'hidden' });
    await assigned(page, 'task-planned', 'sergey');
    assert.equal((await app.task('task-planned')).text, 'Обновлённая задача\nОписание после изменения');
    assert.equal((await app.task('task-planned')).assignee, 'sergey', 'editing preserves assignment');
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
    await page.evaluate(() => scrollTo(0, 0));
    await capture(page, 'board-mobile');
    const mobileHeading = await header.evaluate(actions => {
      const a = actions.getBoundingClientRect(), t = document.querySelector('h1').getBoundingClientRect();
      return { actions: a.toJSON(), title: t.toJSON(), boardTop: document.querySelector('#tasks-view').getBoundingClientRect().top, viewport: innerWidth };
    });
    assert.equal(mobileHeading.actions.left >= 0 && mobileHeading.actions.right <= mobileHeading.viewport && mobileHeading.actions.top >= mobileHeading.title.top - 4 && mobileHeading.actions.bottom < mobileHeading.boardTop, true, 'mobile heading actions remain visible above the board: ' + JSON.stringify(mobileHeading));
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
    assert.equal(await picker(page, 'legacy-task').locator('button:visible').count(), 2, 'both avatars remain visible while saving');
    assert.equal((await app.task('legacy-task')).assignee, undefined, 'optimistic rendering happens before persistence');
    hold.release.resolve();
    await assigned(page, 'legacy-task', 'sergey');
    assert.equal((await app.task('legacy-task')).assignee, 'sergey');

    app.failAssignment();
    const failure = page.waitForResponse(response => response.url().endsWith('/api/admin/tasks/assign') && response.status() === 503);
    await button(page, 'legacy-task', 'sergey').click();
    await failure;
    await assigned(page, 'legacy-task', 'sergey');
    assert.equal(await button(page, 'legacy-task', 'nikita').getAttribute('aria-pressed'), 'false');
    assert.equal(await picker(page, 'legacy-task').locator('button:visible').count(), 2);
    assert.equal((await app.task('legacy-task')).assignee, 'sergey');
    const notices = await page.evaluate(() => window.taskTestNotices);
    assert.equal(notices.length, 1);
    assert.equal(notices[0].isError, true);
    assert.match(notices[0].message, /Проверка ошибки сохранения/);
    await button(page, 'legacy-task', 'nikita').click();
    await assigned(page, 'legacy-task', 'nikita');
    assert.equal(await page.locator('#tasks-edit-modal').isVisible(), false);
    assert.deepEqual(errors, []);
  } finally { await fixture.close(); }
});

test('pressing the selected avatar clears the assignment and restores both muted avatars', { timeout: 45000 }, async () => {
  const fixture = await browserFixture(), { app, page, errors } = fixture;
  try {
    const id = 'task-ready', control = picker(page, id);
    await assigned(page, id, 'sergey');
    assert.equal(await control.locator('button:visible').count(), 2);

    const hold = app.holdAssignment();
    await button(page, id, 'sergey').focus();
    await page.keyboard.press('Enter');
    await hold.entered.promise;
    assert.equal(await control.locator('[aria-pressed="true"]').count(), 0);
    assert.equal(await control.locator('button:disabled').count(), 2);
    assert.equal((await app.task(id)).assignee, 'sergey');
    hold.release.resolve();
    await control.locator('button:disabled').first().waitFor({ state: 'detached' });
    assert.equal((await app.task(id)).assignee, '');
    assert.equal(await button(page, id, 'sergey').evaluate(button => button === document.activeElement), true);

    await page.reload();
    await control.waitFor();
    assert.equal(await control.locator('[aria-pressed="true"]').count(), 0);
    assert.deepEqual(await control.locator('img').evaluateAll(images => images.map(image => {
      const { filter, opacity } = getComputedStyle(image);
      return [filter, opacity];
    })), [['grayscale(1)', '0.45'], ['grayscale(1)', '0.45']]);
    await page.setViewportSize({ width: 390, height: 844 });
    await button(page, id, 'nikita').click();
    await assigned(page, id, 'nikita');
    assert.equal(await control.evaluate(picker => picker.getBoundingClientRect().right <= picker.closest('.task-card-foot').querySelector('.task-foot-actions').getBoundingClientRect().left), true, 'both mobile avatars fit beside actions');
    assert.deepEqual(errors, []);
  } finally { await fixture.close(); }
});

test('priority cycles on the card and the modal saves its three clear choices', { timeout: 60000 }, async () => {
  const fixture = await browserFixture(), { app, page, errors } = fixture;
  try {
    const id = 'task-planned';
    await priorityShown(page, id, 'Обычный');
    for (const [priority, label] of [['high', 'Высокий'], ['low', 'Низкий'], ['normal', 'Обычный']]) {
      const response = page.waitForResponse(response => response.url().endsWith('/api/admin/tasks/priority') && response.status() === 200);
      await priorityButton(page, id).click();
      await response;
      await priorityShown(page, id, label);
      assert.equal((await app.task(id)).priority, priority);
      assert.match(await priorityButton(page, id).getAttribute('title'), new RegExp(label));
      assert.equal(await page.locator('#tasks-edit-modal').isVisible(), false, 'changing priority does not open the editor');
    }
    assert.deepEqual(await page.evaluate(() => window.taskTestNotices), [], 'priority clicks do not show success notices');

    await page.locator('#tasks-board-container [data-edit-task="' + id + '"]').first().click();
    const choices = page.locator('#task-form-priority [data-form-priority]');
    assert.equal(await page.locator('fieldset#task-form-priority').count(), 1);
    assert.equal(await choices.count(), 3);
    assert.equal(await page.locator('select#task-form-priority').count(), 0);
    for (const priority of ['low', 'normal', 'high']) {
      await page.locator('#task-form-priority [data-form-priority="' + priority + '"]').click();
      assert.deepEqual(await choices.evaluateAll(buttons => Object.fromEntries(buttons.map(button => [button.dataset.formPriority, button.getAttribute('aria-pressed')]))), Object.fromEntries(['high', 'normal', 'low'].map(value => [value, String(value === priority)])));
    }
    await capture(page, 'priority-modal-desktop');
    await page.locator('#task-form-save-btn').click();
    await page.locator('#tasks-edit-modal').waitFor({ state: 'hidden' });
    await priorityShown(page, id, 'Высокий');
    assert.equal((await app.task(id)).priority, 'high');
    assert.equal((await app.task(id)).version, 'v1.0.1', 'removing version controls preserves existing stored data');
    assert.equal(app.writes.findLast(write => write.path.endsWith('/save')).body.priority, 'high');
    await page.reload();
    await priorityShown(page, id, 'Высокий');

    await page.locator('#tasks-add-task-btn').click();
    await page.locator('#task-form-text').fill('Новая задача с низким приоритетом');
    await page.locator('#task-form-priority [data-form-priority="low"]').click();
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(await page.locator('#tasks-edit-modal').evaluate(modal => modal.scrollWidth <= modal.clientWidth), true);
    assert.equal(await choices.evaluateAll(buttons => buttons.every(button => {
      const bounds = button.getBoundingClientRect();
      return bounds.width > 0 && bounds.left >= 0 && bounds.right <= innerWidth;
    })), true, 'all three modal priority options fit on mobile');
    await capture(page, 'priority-modal-mobile');
    await page.locator('#task-form-save-btn').click();
    await page.locator('#tasks-edit-modal').waitFor({ state: 'hidden' });
    const createdId = await page.locator('.task-card').filter({ hasText: 'Новая задача с низким приоритетом' }).getAttribute('data-task-id');
    await priorityShown(page, createdId, 'Низкий');
    assert.equal((await app.task(createdId)).priority, 'low');
    assert.equal(await page.locator('.task-badge.version').count(), 0);
    assert.deepEqual(errors, []);
  } finally { await fixture.close(); }
});

test('priority is optimistic, shares the write queue with assignment and restores the prior value on failure', { timeout: 45000 }, async () => {
  const fixture = await browserFixture(), { app, page, errors } = fixture;
  try {
    const id = 'task-planned', hold = app.hold('priority');
    await priorityButton(page, id).click();
    await hold.entered.promise;
    assert.equal(await priorityButton(page, id).isDisabled(), true);
    assert.match(await priorityButton(page, id).textContent(), /Высокий/);
    assert.equal((await app.task(id)).priority, 'normal');
    await button(page, 'legacy-task', 'nikita').click();
    assert.equal(await button(page, 'legacy-task', 'nikita').getAttribute('aria-pressed'), 'true');
    assert.deepEqual(app.writes.map(write => write.path), ['/api/admin/tasks/priority']);
    await page.locator('#tasks-board-container [data-edit-task="' + id + '"]').first().click();
    assert.equal(await page.locator('#task-form-priority [data-form-priority="high"]').getAttribute('aria-pressed'), 'true', 'the editor reflects a pending card change');
    await page.locator('#task-form-priority [data-form-priority="low"]').click();
    await page.locator('#task-form-save-btn').click();
    assert.equal(await page.locator('#task-form-save-btn').isDisabled(), true);
    assert.deepEqual(app.writes.map(write => write.path), ['/api/admin/tasks/priority']);
    hold.release.resolve();
    await page.locator('#tasks-edit-modal').waitFor({ state: 'hidden' });
    await priorityShown(page, id, 'Низкий');
    await assigned(page, 'legacy-task', 'nikita');
    assert.equal((await app.task(id)).priority, 'low', 'a later modal choice wins after the queued card change');
    assert.equal((await app.task('legacy-task')).assignee, 'nikita');
    assert.deepEqual(app.writes.map(write => write.path), ['/api/admin/tasks/priority', '/api/admin/tasks/assign', '/api/admin/tasks/save']);
    await page.evaluate(() => { window.taskTestNotices = []; });

    app.fail('priority');
    const failure = page.waitForResponse(response => response.url().endsWith('/api/admin/tasks/priority') && response.status() === 503);
    await priorityButton(page, id).click();
    await failure;
    await priorityShown(page, id, 'Низкий');
    assert.equal((await app.task(id)).priority, 'low');
    const notices = await page.evaluate(() => window.taskTestNotices);
    assert.equal(notices.length, 1);
    assert.equal(notices[0].isError, true);
    await priorityButton(page, id).click();
    await priorityShown(page, id, 'Обычный');
    assert.equal((await app.task(id)).priority, 'normal', 'a failed write does not block later priority changes');
    assert.equal(await page.locator('#tasks-edit-modal').isVisible(), false);
    assert.deepEqual(errors, []);
  } finally { await fixture.close(); }
});

test('relocated task actions follow navigation, preserve board scroll and stay hidden after logout', { timeout: 45000 }, async () => {
  const fixture = await browserFixture(), { page, errors } = fixture;
  try {
    const header = page.locator('#tasks-header-actions');
    assert.equal(await header.evaluate(actions => Boolean(actions.closest('#app')) && !actions.closest('#tasks-view')), true, 'relocated controls remain inside the authenticated app');
    await page.locator('[data-feature="links"]').click();
    await page.locator('#links-view').waitFor({ state: 'visible' });
    assert.equal(await header.isVisible(), false);
    assert.equal(await page.locator('header.tasks-header').count(), 0);
    await page.goBack();
    await page.locator('#tasks-view').waitFor({ state: 'visible' });
    assert.equal(await header.isVisible(), true);
    await priorityShown(page, 'task-planned', 'Обычный');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.locator('#tasks-board-container').evaluate(async board => {
      board.scrollLeft += board.querySelector('.tasks-col:nth-child(2)').getBoundingClientRect().left - board.getBoundingClientRect().left;
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    });
    const archiveReturnScroll = await page.locator('#tasks-board-container').evaluate(board => board.scrollLeft);
    assert.ok(archiveReturnScroll > 0);
    await page.locator('#tasks-archive-btn').click();
    assert.equal(await page.locator('.tasks-col[data-col-status="archived"]').evaluate(column => {
      const archived = column.getBoundingClientRect(), board = column.closest('.tasks-board').getBoundingClientRect();
      return archived.left >= board.left - 1 && archived.right <= board.right + 1;
    }), true, 'opening archive brings its column into the mobile viewport');
    await page.locator('#tasks-archive-btn').click();
    await page.waitForFunction(scroll => Math.abs(document.querySelector('#tasks-board-container').scrollLeft - scroll) < 1, archiveReturnScroll);
    assert.equal(await page.locator('.tasks-col[data-col-status="archived"]').count(), 0);
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.locator('#tasks-board-container').evaluate(board => { board.scrollLeft = 220; });
    const scrollBefore = await page.locator('#tasks-board-container').evaluate(board => board.scrollLeft);
    await priorityButton(page, 'task-planned').click();
    await priorityShown(page, 'task-planned', 'Высокий');
    assert.equal(await page.locator('#tasks-board-container').evaluate(board => board.scrollLeft), scrollBefore);
    const logout = page.waitForResponse(response => response.url().endsWith('/api/admin/logout'));
    await page.locator('#logout-btn').click();
    await logout;
    await page.locator('#login-overlay').waitFor({ state: 'visible' });
    assert.equal(await header.isVisible(), false);
    assert.equal(await page.locator('#tasks-add-task-btn').isVisible(), false);
    assert.deepEqual(errors, []);
  } finally { await fixture.close(); }
});
