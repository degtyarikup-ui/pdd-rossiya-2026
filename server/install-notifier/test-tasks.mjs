import test from 'node:test';
import assert from 'node:assert/strict';
import {
  TASK_STATUSES,
  TASK_PRIORITIES,
  validateTaskInput,
  extractVersions,
  handleTasksAdmin,
} from './tasks_admin.js';
import { TASKS_CLIENT_JS } from './tasks_ui.js';
import worker from './worker.js';

function createMockEnv() {
  const store = new Map();
  return {
    INSTALLS: {
      get: async (k) => store.get(k) ?? null,
      put: async (k, v) => store.set(k, String(v)),
      delete: async (k) => store.delete(k),
    },
    _store: store,
  };
}

test('validation rejects empty or oversized task text and sanitizes fields', () => {
  assert.equal(validateTaskInput({ text: '' }).error, 'Текст задачи не может быть пустым');
  assert.equal(validateTaskInput({ text: '   ' }).error, 'Текст задачи не может быть пустым');
  assert.equal(validateTaskInput({ text: 'a'.repeat(10001) }).error, 'Текст задачи слишком длинный (максимум 10000 символов)');

  const valid = validateTaskInput({
    text: 'Сделать новый режим экзамена',
    status: 'in_progress',
    priority: 'high',
    version: 'v1.0.8',
    attachments: [{ id: 'att-1', name: 'screen.png', type: 'image/png', size: 1024 }],
  });

  assert.equal(valid.valid, true);
  assert.equal(valid.data.text, 'Сделать новый режим экзамена');
  assert.equal(valid.data.status, 'in_progress');
  assert.equal(valid.data.priority, 'high');
  assert.equal(valid.data.version, 'v1.0.8');
  assert.equal(valid.data.attachments.length, 1);

  // Fallbacks to default status & priority for invalid inputs
  const defaults = validateTaskInput({ text: 'Простая идея', status: 'unknown_status', priority: 'ultra' });
  assert.equal(defaults.data.status, 'idea');
  assert.equal(defaults.data.priority, 'normal');
});

test('extractVersions extracts unique non-empty sorted versions', () => {
  const tasks = [
    { text: '1', version: 'v1.0.7' },
    { text: '2', version: 'v1.1.0' },
    { text: '3', version: 'v1.0.7' },
    { text: '4', version: '' },
    { text: '5', version: null },
  ];
  const versions = extractVersions(tasks);
  assert.deepEqual(versions, ['v1.1.0', 'v1.0.7']);
});

test('CRUD operations and status moves in handleTasksAdmin', async () => {
  const env = createMockEnv();

  // 1. GET empty tasks
  const getReq = new Request('https://test/api/admin/tasks', { method: 'GET' });
  const getRes = await handleTasksAdmin(getReq, env, new URL(getReq.url));
  assert.equal(getRes.status, 200);
  const getData = await getRes.json();
  assert.equal(getData.ok, true);
  assert.deepEqual(getData.tasks, []);

  // 2. CREATE task
  const createReq = new Request('https://test/api/admin/tasks/save', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      text: 'Добавить тёмную тему для билетов',
      status: 'idea',
      version: 'v1.0.7',
      priority: 'high',
    }),
  });
  const createRes = await handleTasksAdmin(createReq, env, new URL(createReq.url));
  assert.equal(createRes.status, 200);
  const createData = await createRes.json();
  assert.equal(createData.ok, true);
  assert.equal(createData.task.text, 'Добавить тёмную тему для билетов');
  assert.equal(createData.task.status, 'idea');
  assert.equal(createData.task.priority, 'high');
  assert.ok(createData.task.id);
  const taskId = createData.task.id;

  // 3. MOVE task
  const moveReq = new Request('https://test/api/admin/tasks/move', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ id: taskId, status: 'in_progress' }),
  });
  const moveRes = await handleTasksAdmin(moveReq, env, new URL(moveReq.url));
  assert.equal(moveRes.status, 200);
  const moveData = await moveRes.json();
  assert.equal(moveData.ok, true);
  assert.equal(moveData.task.status, 'in_progress');

  // 4. UPDATE task text and version
  const updateReq = new Request('https://test/api/admin/tasks/save', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      id: taskId,
      text: 'Добавить тёмную тему (обновлено)',
      status: 'ready',
      version: 'v1.0.8',
      priority: 'normal',
    }),
  });
  const updateRes = await handleTasksAdmin(updateReq, env, new URL(updateReq.url));
  assert.equal(updateRes.status, 200);
  const updateData = await updateRes.json();
  assert.equal(updateData.task.text, 'Добавить тёмную тему (обновлено)');
  assert.equal(updateData.task.status, 'ready');
  assert.equal(updateData.task.version, 'v1.0.8');

  // 5. DELETE task
  const delReq = new Request('https://test/api/admin/tasks/delete', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ id: taskId }),
  });
  const delRes = await handleTasksAdmin(delReq, env, new URL(delReq.url));
  assert.equal(delRes.status, 200);
  const delData = await delRes.json();
  assert.equal(delData.ok, true);
  assert.equal(delData.id, taskId);

  // Confirm deleted from storage
  const getAfterReq = new Request('https://test/api/admin/tasks', { method: 'GET' });
  const getAfterRes = await handleTasksAdmin(getAfterReq, env, new URL(getAfterReq.url));
  const getAfterData = await getAfterRes.json();
  assert.equal(getAfterData.tasks.length, 0);
});

test('attachment upload and download lifecycle', async () => {
  const env = createMockEnv();

  const fakePngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
  const uploadReq = new Request('https://test/api/admin/tasks/upload', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      name: 'pixel.png',
      type: 'image/png',
      base64: fakePngBase64,
    }),
  });
  const uploadRes = await handleTasksAdmin(uploadReq, env, new URL(uploadReq.url));
  assert.equal(uploadRes.status, 200);
  const uploadData = await uploadRes.json();
  assert.equal(uploadData.ok, true);
  assert.ok(uploadData.attachment.id);
  assert.equal(uploadData.attachment.name, 'pixel.png');

  // Fetch uploaded attachment
  const attUrl = 'https://test' + uploadData.attachment.url;
  const attReq = new Request(attUrl, { method: 'GET' });
  const attRes = await handleTasksAdmin(attReq, env, new URL(attUrl));
  assert.equal(attRes.status, 200);
  assert.equal(attRes.headers.get('Content-Type'), 'image/png');
  const buffer = await attRes.arrayBuffer();
  assert.ok(buffer.byteLength > 0);
});

test('worker rejects unauthorized /api/admin/tasks requests', async () => {
  const r = await worker.fetch(new Request('https://test/api/admin/tasks', { method: 'GET' }), {
    INSTALLS: { get: async () => null },
  });
  assert.equal(r.status, 401);
});

test('admin page embeds tasks view, nav item under analytics, and complete client compiles', async () => {
  // Check TASKS_CLIENT_JS compiles without syntax errors
  new Function(TASKS_CLIENT_JS);

  const html = await (await worker.fetch(new Request('https://test/admin'), {})).text();
  assert.equal((html.match(/id="tasks-view"/g) || []).length, 1);
  assert.match(html, /data-feature="tasks"/);
  assert.match(html, /<span>Задачи<\/span>/);

  // Verify that Tasks appears right after Analytics and before Links in sidebar
  const analyticsIdx = html.indexOf('data-feature="analytics"');
  const tasksIdx = html.indexOf('data-feature="tasks"');
  const linksIdx = html.indexOf('data-feature="links"');
  assert.ok(analyticsIdx !== -1, 'analytics should exist');
  assert.ok(tasksIdx !== -1, 'tasks should exist');
  assert.ok(linksIdx !== -1, 'links should exist');
  assert.ok(tasksIdx > analyticsIdx, 'tasks must be after analytics');
  assert.ok(tasksIdx < linksIdx, 'tasks must be before links');

  // Verify full script compiles
  const scriptContent = html.match(/<script>([\s\S]*)<\/script>/)[1];
  new Function(scriptContent);
});
