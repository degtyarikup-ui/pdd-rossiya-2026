import test from 'node:test';
import assert from 'node:assert/strict';
import {
  TASK_STATUSES,
  TASK_PRIORITIES,
  TASK_ASSIGNEES,
  RELEASED_RETENTION_MS,
  ARCHIVED_RETENTION_MS,
  validateTaskInput,
  handleTasksAdmin,
  maintainTaskLifecycle,
} from './tasks_admin.js';
import { TASKS_CLIENT_JS } from './tasks_ui.js';
import worker from './worker.js';

function createMockEnv() {
  const store = new Map();
  const writes = [];
  const deletes = [];
  return {
    INSTALLS: {
      get: async (k) => store.get(k) ?? null,
      put: async (k, v) => { writes.push(k); store.set(k, String(v)); },
      delete: async (k) => { deletes.push(k); store.delete(k); },
      list: async ({ prefix = '' } = {}) => ({
        keys: [...store.keys()].filter(key => key.startsWith(prefix)).map(name => ({ name })),
        list_complete: true,
      }),
    },
    _store: store,
    _writes: writes,
    _deletes: deletes,
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
  assert.equal(Object.hasOwn(valid.data, 'version'), false);
  assert.equal(valid.data.attachments.length, 1);

  // Fallbacks to default status & priority for invalid inputs
  const defaults = validateTaskInput({ text: 'Простая идея', status: 'unknown_status', priority: 'ultra' });
  assert.equal(defaults.data.status, 'idea');
  assert.equal(defaults.data.priority, 'normal');
});

test('assignee validation accepts only the two people or an explicit clear', () => {
  assert.deepEqual(TASK_ASSIGNEES, ['', 'sergey', 'nikita']);
  for (const assignee of TASK_ASSIGNEES) {
    const result = validateTaskInput({ text: 'Задача', assignee });
    assert.equal(result.valid, true);
    assert.equal(result.data.assignee, assignee);
  }
  for (const assignee of ['other', 'Сергей', 'SERGEY', null, 1, {}, undefined]) {
    assert.equal(validateTaskInput({ text: 'Задача', assignee }).error, 'Недопустимый исполнитель');
  }
  assert.equal(Object.hasOwn(validateTaskInput({ text: 'Задача' }).data, 'assignee'), false);
});

async function taskRequest(env, path, body) {
  const request = new Request(`https://test/api/admin/tasks${path}`, body === undefined ? {} : {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const response = await handleTasksAdmin(request, env, new URL(request.url));
  return { status: response.status, data: await response.json() };
}

const DAY = 24 * 60 * 60 * 1000;
const EPOCH = 1_700_000_000_000;

function storedTask(overrides = {}) {
  return {
    id: 'task-1', text: 'Задача', status: 'idea', priority: 'normal', assignee: '',
    attachments: [], createdAt: EPOCH, updatedAt: EPOCH, statusChangedAt: EPOCH,
    ...overrides,
  };
}

function seedTasks(env, tasks) {
  env._store.set('tasks:items', JSON.stringify(tasks));
}

function readTasks(env) {
  return JSON.parse(env._store.get('tasks:items'));
}

test('task API ignores incoming app versions and emits no version catalog', async () => {
  const env = createMockEnv();
  seedTasks(env, [storedTask({ version: 'legacy-v1' })]);
  const list = await taskRequest(env, '');
  assert.equal(Object.hasOwn(list.data, 'versions'), false);
  const edited = await taskRequest(env, '/save', { id: 'task-1', text: 'Правка', version: 'new-v2' });
  assert.equal(Object.hasOwn(edited.data, 'versions'), false);
  assert.equal(edited.data.task.version, 'legacy-v1');
  const created = await taskRequest(env, '/save', { text: 'Новая', version: 'new-v3' });
  assert.equal(Object.hasOwn(created.data.task, 'version'), false);
  const removed = await taskRequest(env, '/delete', { id: created.data.task.id });
  assert.equal(Object.hasOwn(removed.data, 'versions'), false);
});

test('quick priority changes preserve task content and the lifecycle clock', async t => {
  const env = createMockEnv();
  let now = EPOCH + DAY;
  t.mock.method(Date, 'now', () => now);
  const original = storedTask({ status: 'released', statusChangedAt: EPOCH, customField: 'keep' });
  const other = storedTask({ id: 'other-task' });
  seedTasks(env, [original, other]);
  for (const priority of TASK_PRIORITIES) {
    const result = await taskRequest(env, '/priority', { id: original.id, priority });
    assert.equal(result.status, 200);
    assert.deepEqual(result.data.task, { ...original, priority, updatedAt: now });
    assert.deepEqual(readTasks(env)[1], other);
    now++;
  }
  const before = env._store.get('tasks:items');
  for (const body of [
    { priority: 'high' }, { id: '', priority: 'high' }, { id: '  ', priority: 'normal' },
    { id: original.id }, { id: original.id, priority: 'urgent' }, { id: original.id, priority: null },
  ]) {
    assert.equal((await taskRequest(env, '/priority', body)).status, 400);
  }
  assert.equal((await taskRequest(env, '/priority', { id: 'missing', priority: 'high' })).status, 404);
  const badJson = new Request('https://test/api/admin/tasks/priority', { method: 'POST', body: '{' });
  assert.equal((await handleTasksAdmin(badJson, env, new URL(badJson.url))).status, 400);
  assert.equal(env._store.get('tasks:items'), before);
});

test('lifecycle archives at seven days and deletes at thirty archived days, exactly once', async () => {
  assert.equal(RELEASED_RETENTION_MS, 7 * DAY);
  assert.equal(ARCHIVED_RETENTION_MS, 30 * DAY);
  const env = createMockEnv();
  const unrelated = storedTask({ id: 'other-task', status: 'in_progress' });
  seedTasks(env, [storedTask({ status: 'released' }), unrelated]);
  assert.deepEqual(await maintainTaskLifecycle(env, EPOCH + 7 * DAY - 1), {
    ok: true, changed: false, archived: 0, deleted: 0,
  });
  assert.deepEqual(env._writes, []);
  const archived = await maintainTaskLifecycle(env, EPOCH + 7 * DAY);
  assert.equal(archived.archived, 1);
  assert.deepEqual(readTasks(env), [storedTask({
    status: 'archived', statusChangedAt: EPOCH + 7 * DAY, updatedAt: EPOCH + 7 * DAY,
  }), unrelated]);
  env._writes.length = 0;
  assert.equal((await maintainTaskLifecycle(env, EPOCH + 37 * DAY - 1)).changed, false);
  assert.deepEqual(env._writes, []);
  assert.equal((await maintainTaskLifecycle(env, EPOCH + 37 * DAY)).deleted, 1);
  assert.deepEqual(readTasks(env), [unrelated]);
  env._writes.length = 0;
  assert.equal((await maintainTaskLifecycle(env, EPOCH + 38 * DAY)).changed, false);
  assert.deepEqual(env._writes, []);
});

test('lifecycle catches up through release and archive retention after long downtime', async () => {
  const env = createMockEnv();
  seedTasks(env, [storedTask({ status: 'released' })]);
  const result = await maintainTaskLifecycle(env, EPOCH + 37 * DAY);
  assert.deepEqual(result, { ok: true, changed: true, archived: 1, deleted: 1 });
  assert.deepEqual(readTasks(env), []);
});

test('unrelated edits preserve released age and manual archive starts a fresh thirty days', async t => {
  const env = createMockEnv();
  let now = EPOCH;
  t.mock.method(Date, 'now', () => now);
  const created = await taskRequest(env, '/save', { text: 'Выпуск', status: 'released' });
  const id = created.data.task.id;
  assert.equal(created.data.task.statusChangedAt, EPOCH);
  now += 6 * DAY;
  assert.equal((await taskRequest(env, '/assign', { id, assignee: 'nikita' })).data.task.statusChangedAt, EPOCH);
  assert.equal((await taskRequest(env, '/priority', { id, priority: 'high' })).data.task.statusChangedAt, EPOCH);
  assert.equal((await taskRequest(env, '/save', { id, text: 'Новый текст', status: 'released' })).data.task.statusChangedAt, EPOCH);
  assert.equal((await taskRequest(env, '/move', { id, status: 'released' })).data.task.statusChangedAt, EPOCH);
  now += DAY;
  const manual = await taskRequest(env, '/move', { id, status: 'archived' });
  assert.equal(manual.data.task.statusChangedAt, now);
  assert.equal((await maintainTaskLifecycle(env, now + 30 * DAY - 1)).deleted, 0);
  assert.equal((await maintainTaskLifecycle(env, now + 30 * DAY)).deleted, 1);
});

test('reopening and re-releasing restart the clock through both move and full save', async t => {
  const env = createMockEnv();
  let now = EPOCH + DAY;
  t.mock.method(Date, 'now', () => now);
  seedTasks(env, [storedTask({ status: 'released' })]);
  const reopened = await taskRequest(env, '/move', { id: 'task-1', status: 'ready' });
  assert.equal(reopened.data.task.statusChangedAt, now);
  now += DAY;
  const released = await taskRequest(env, '/save', { id: 'task-1', text: 'Выпущено повторно', status: 'released' });
  assert.equal(released.data.task.statusChangedAt, now);
  assert.equal((await maintainTaskLifecycle(env, now + 7 * DAY - 1)).archived, 0);
  assert.equal((await maintainTaskLifecycle(env, now + 7 * DAY)).archived, 1);
  now += 8 * DAY;
  const reopenedArchive = await taskRequest(env, '/save', { id: 'task-1', text: 'Снова в работе', status: 'in_progress' });
  assert.equal(reopenedArchive.data.task.statusChangedAt, now);
  assert.equal((await maintainTaskLifecycle(env, now + 40 * DAY)).deleted, 0);
});

test('legacy clocks use updatedAt, createdAt or maintenance time and then stop following edits', async t => {
  const env = createMockEnv();
  let now = EPOCH + DAY;
  t.mock.method(Date, 'now', () => now);
  const legacy = [
    storedTask({ id: 'explicit', statusChangedAt: EPOCH - DAY, updatedAt: EPOCH }),
    storedTask({ id: 'updated', statusChangedAt: undefined, updatedAt: EPOCH - 2 * DAY }),
    storedTask({ id: 'created', statusChangedAt: 'bad', updatedAt: null, createdAt: EPOCH - 3 * DAY }),
    storedTask({ id: 'fallback', statusChangedAt: -1, updatedAt: 'bad', createdAt: null }),
    storedTask({ id: 'zero', statusChangedAt: 0 }),
  ];
  seedTasks(env, legacy);
  assert.equal((await maintainTaskLifecycle(env, now)).changed, true);
  assert.deepEqual(readTasks(env).map(task => task.statusChangedAt), [EPOCH - DAY, EPOCH - 2 * DAY, EPOCH - 3 * DAY, now, EPOCH]);
  env._writes.length = 0;
  assert.equal((await maintainTaskLifecycle(env, now + DAY)).changed, false);
  assert.deepEqual(env._writes, []);
  now += 2 * DAY;
  assert.equal((await taskRequest(env, '/assign', { id: 'updated', assignee: 'sergey' })).data.task.statusChangedAt, EPOCH - 2 * DAY);
  assert.equal((await taskRequest(env, '/priority', { id: 'created', priority: 'high' })).data.task.statusChangedAt, EPOCH - 3 * DAY);
  assert.equal((await taskRequest(env, '/save', { id: 'fallback', text: 'Правка', status: 'idea' })).data.task.statusChangedAt, EPOCH + DAY);

  // Seed on each mutation before updatedAt is overwritten, even without a prior cron.
  for (const path of ['/assign', '/priority', '/save']) {
    const fresh = createMockEnv();
    seedTasks(fresh, [storedTask({ statusChangedAt: undefined, updatedAt: EPOCH - DAY })]);
    const result = await taskRequest(fresh, path, { id: 'task-1', assignee: 'nikita', priority: 'low', text: 'Правка', status: 'idea' });
    assert.equal(result.data.task.statusChangedAt, EPOCH - DAY);
    assert.equal(result.data.task.updatedAt, now);
  }
});

test('legacy zero, negative and non-finite clocks start from maintenance instead of purging immediately', async () => {
  const env = createMockEnv();
  seedTasks(env, [0, -1, Infinity, NaN].map((clock, index) => storedTask({
    id: 'unknown-clock-' + index, status: 'archived', statusChangedAt: clock, updatedAt: clock, createdAt: clock,
  })));
  const now = EPOCH + 100 * DAY;
  const result = await maintainTaskLifecycle(env, now);
  assert.equal(result.deleted, 0);
  assert.equal(readTasks(env).length, 4);
  assert.ok(readTasks(env).every(task => task.statusChangedAt === now));
  assert.equal((await maintainTaskLifecycle(env, now + 30 * DAY - 1)).deleted, 0);
  assert.equal((await maintainTaskLifecycle(env, now + 30 * DAY)).deleted, 4);
});

test('maintenance and mutations fail closed on malformed snapshots and attachment metadata', async t => {
  t.mock.method(console, 'error', () => {});
  for (const raw of [
    '{', '{}', 'null', '[null]', JSON.stringify([storedTask(), storedTask()]),
    JSON.stringify([storedTask({ text: null })]), JSON.stringify([storedTask({ status: 'unknown' })]),
    JSON.stringify([storedTask({ status: 'archived', attachments: {} })]),
    JSON.stringify([storedTask({ status: 'archived', attachments: [null] })]),
    JSON.stringify([storedTask({ status: 'archived', attachments: [{ id: '' }] })]),
  ]) {
    const env = createMockEnv();
    env._store.set('tasks:items', raw);
    await assert.rejects(maintainTaskLifecycle(env, EPOCH + 100 * DAY));
    assert.equal((await taskRequest(env, '/save', { text: 'Новая' })).status, 503);
    assert.equal(env._store.get('tasks:items'), raw);
    assert.deepEqual(env._writes, []);
    assert.deepEqual(env._deletes, []);
  }
  const env = createMockEnv();
  env.INSTALLS.get = async () => { throw new Error('KV unavailable'); };
  await assert.rejects(maintainTaskLifecycle(env, EPOCH + 100 * DAY), /KV unavailable/);
  assert.equal((await taskRequest(env, '/save', { text: 'Новая' })).status, 503);
  assert.deepEqual(env._writes, []);
  assert.deepEqual(env._deletes, []);
  const empty = createMockEnv();
  assert.equal((await maintainTaskLifecycle(empty, EPOCH)).changed, false);
  assert.deepEqual(empty._writes, []);
});

test('expired tasks remove their blobs while attachments shared with retained tasks survive', async () => {
  const env = createMockEnv();
  const attachment = id => ({ id, name: id + '.png', type: 'image/png' });
  const retained = storedTask({ id: 'retained', attachments: [attachment('shared')] });
  seedTasks(env, [storedTask({ status: 'archived', attachments: [attachment('orphan'), attachment('shared'), attachment('orphan')] }), retained]);
  env._store.set('task_att:orphan', 'orphan-data');
  env._store.set('task_att:shared', 'shared-data');
  assert.equal((await maintainTaskLifecycle(env, EPOCH + 30 * DAY)).deleted, 1);
  assert.deepEqual(readTasks(env), [retained]);
  assert.equal(env._store.has('task_att:orphan'), false);
  assert.equal(env._store.get('task_att:shared'), 'shared-data');
  assert.deepEqual(env._deletes, ['task_att:orphan']);
  assert.deepEqual(JSON.parse(env._store.get('tasks:attachment_cleanup')), []);
  env._writes.length = 0;
  assert.equal((await maintainTaskLifecycle(env, EPOCH + 31 * DAY)).changed, false);
  assert.deepEqual(env._writes, []);
  const sharedDelete = await taskRequest(env, '/delete', { id: retained.id });
  assert.equal(sharedDelete.status, 200);
  assert.equal(env._store.has('task_att:shared'), false);
});

test('failed attachment cleanup keeps retry metadata and the next pass completes it', async t => {
  t.mock.method(console, 'error', () => {});
  const env = createMockEnv();
  seedTasks(env, [storedTask({ status: 'archived', attachments: [{ id: 'retry' }] })]);
  env._store.set('task_att:retry', 'data');
  const originalDelete = env.INSTALLS.delete;
  env.INSTALLS.delete = async () => { throw new Error('delete unavailable'); };
  await assert.rejects(maintainTaskLifecycle(env, EPOCH + 30 * DAY), /Не удалось удалить вложения/);
  assert.deepEqual(readTasks(env), []);
  assert.deepEqual(JSON.parse(env._store.get('tasks:attachment_cleanup')), ['retry']);
  assert.equal(env._store.has('task_att:retry'), true);
  env.INSTALLS.delete = originalDelete;
  const result = await maintainTaskLifecycle(env, EPOCH + 31 * DAY);
  assert.equal(result.changed, false);
  assert.equal(env._store.has('task_att:retry'), false);
  assert.deepEqual(JSON.parse(env._store.get('tasks:attachment_cleanup')), []);
});

test('cleanup intent is safe when task write fails or queued attachment becomes shared', async t => {
  t.mock.method(console, 'error', () => {});
  const env = createMockEnv();
  const original = storedTask({ status: 'archived', attachments: [{ id: 'retry' }] });
  seedTasks(env, [original]);
  env._store.set('task_att:retry', 'data');
  const put = env.INSTALLS.put;
  env.INSTALLS.put = async (key, value) => {
    if (key === 'tasks:items') throw new Error('write unavailable');
    return put(key, value);
  };
  await assert.rejects(maintainTaskLifecycle(env, EPOCH + 30 * DAY), /write unavailable/);
  assert.deepEqual(readTasks(env), [original]);
  assert.equal(env._store.get('task_att:retry'), 'data');
  assert.deepEqual(JSON.parse(env._store.get('tasks:attachment_cleanup')), ['retry']);
  assert.deepEqual(env._deletes, []);
  env.INSTALLS.put = put;
  seedTasks(env, [storedTask({ id: 'kept', attachments: [{ id: 'retry' }] })]);
  await maintainTaskLifecycle(env, EPOCH + 31 * DAY);
  assert.equal(env._store.get('task_att:retry'), 'data');
  assert.deepEqual(env._deletes, []);
  assert.deepEqual(JSON.parse(env._store.get('tasks:attachment_cleanup')), []);

  env._store.set('tasks:attachment_cleanup', '[null]');
  env._writes.length = 0;
  await assert.rejects(maintainTaskLifecycle(env, EPOCH + 100 * DAY), /очередь/);
  assert.equal((await taskRequest(env, '/delete', { id: 'kept' })).status, 503);
  assert.deepEqual(env._writes, []);
  assert.deepEqual(env._deletes, []);
});

test('hourly worker cron maintains tasks without a page visit, admin password or bot credentials', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ error: 'offline fixture' }, { status: 503 }));
  t.mock.method(console, 'log', () => {});
  t.mock.method(console, 'error', () => {});
  const scheduledTime = Date.parse('2026-11-16T10:00:00Z');
  const env = createMockEnv();
  const released = storedTask({ id: 'release', status: 'released', statusChangedAt: scheduledTime - 7 * DAY });
  const archived = storedTask({ id: 'archive', status: 'archived', statusChangedAt: scheduledTime - 30 * DAY });
  seedTasks(env, [released, archived]);
  const run = async time => {
    const pending = [];
    await worker.scheduled({ cron: '*/5 * * * *', scheduledTime: time }, env, {
      waitUntil(promise) { pending.push(promise); },
    });
    while (pending.length) await Promise.all(pending.splice(0));
  };
  await run(scheduledTime - 5 * 60 * 1000);
  assert.deepEqual(readTasks(env), [released, archived]);
  assert.equal(env._writes.includes('tasks:items'), false);
  await run(scheduledTime);
  assert.deepEqual(readTasks(env), [{
    ...released, status: 'archived', statusChangedAt: scheduledTime, updatedAt: scheduledTime,
  }]);
  assert.equal(env._writes.filter(key => key === 'tasks:items').length, 1);
});

test('maintenance skips an intervening task edit before writing or deleting its attachments', async () => {
  for (const changeAfterCleanupIntent of [false, true]) {
    const env = createMockEnv();
    const expired = storedTask({ status: 'archived', attachments: [{ id: 'keep' }] });
    const reopened = { ...expired, status: 'in_progress', statusChangedAt: EPOCH + 30 * DAY };
    seedTasks(env, [expired]);
    env._store.set('task_att:keep', 'data');
    const get = env.INSTALLS.get;
    let taskReads = 0;
    env.INSTALLS.get = async key => {
      if (key === 'tasks:items' && ++taskReads === (changeAfterCleanupIntent ? 3 : 2)) seedTasks(env, [reopened]);
      return get(key);
    };
    const result = await maintainTaskLifecycle(env, EPOCH + 30 * DAY);
    assert.deepEqual(result, { ok: true, changed: false, archived: 0, deleted: 0, skipped: 'snapshot_changed' });
    assert.deepEqual(readTasks(env), [reopened]);
    assert.equal(env._writes.includes('tasks:items'), false);
    assert.deepEqual(env._deletes, []);
    assert.equal(env._store.get('task_att:keep'), 'data');
    env.INSTALLS.get = get;
    await maintainTaskLifecycle(env, EPOCH + 31 * DAY);
    assert.deepEqual(readTasks(env), [reopened]);
    assert.equal(env._store.get('task_att:keep'), 'data');
  }
});

test('cleanup rereads current task references before deleting newly shared blobs', async () => {
  const env = createMockEnv();
  const expired = storedTask({ status: 'archived', attachments: [{ id: 'shared-late' }] });
  const retained = storedTask({ id: 'retained', attachments: [{ id: 'shared-late' }] });
  seedTasks(env, [expired]);
  env._store.set('task_att:shared-late', 'data');
  const get = env.INSTALLS.get;
  let taskReads = 0;
  env.INSTALLS.get = async key => {
    if (key === 'tasks:items' && ++taskReads === 4) seedTasks(env, [retained]);
    return get(key);
  };
  await maintainTaskLifecycle(env, EPOCH + 30 * DAY);
  assert.deepEqual(readTasks(env), [retained]);
  assert.equal(env._store.get('task_att:shared-late'), 'data');
  assert.deepEqual(env._deletes, []);
  assert.deepEqual(JSON.parse(env._store.get('tasks:attachment_cleanup')), []);
});

test('assigning legacy tasks persists both people and clear without changing task content', async () => {
  const env = createMockEnv();
  const original = {
    id: 'existing-task', text: 'Текст задачи', status: 'planned', priority: 'high',
    version: 'v2.2.15', attachments: [{ id: 'screen', name: 'screen.png' }],
    createdAt: 123, updatedAt: 456, customField: 'preserved',
  };
  const otherTask = { ...original, id: 'other-task' };
  env._store.set('tasks:items', JSON.stringify([original, otherTask]));
  const before = await taskRequest(env, '');
  assert.equal(before.data.tasks[0].assignee, '');

  for (const assignee of ['sergey', 'nikita', '']) {
    const assigned = await taskRequest(env, '/assign', { id: original.id, assignee });
    assert.equal(assigned.status, 200);
    assert.equal(assigned.data.ok, true);
    assert.ok(assigned.data.task.updatedAt > original.updatedAt);
    assert.deepEqual(assigned.data.task, { ...original, assignee, statusChangedAt: original.updatedAt, updatedAt: assigned.data.task.updatedAt });

    const stored = JSON.parse(env._store.get('tasks:items'));
    assert.equal(stored[0].assignee, assignee);
    assert.deepEqual(stored[1], otherTask);
    const refreshed = await taskRequest(env, '');
    assert.equal(refreshed.data.tasks[0].assignee, assignee);
  }
});

test('task save keeps an omitted assignee and supports explicit reassignment and clear', async () => {
  const env = createMockEnv();
  const blank = await taskRequest(env, '/save', { text: 'Без исполнителя' });
  assert.equal(blank.data.task.assignee, '');
  const created = await taskRequest(env, '/save', { text: 'Новая задача', assignee: 'sergey' });
  assert.equal(created.data.task.assignee, 'sergey');
  const id = created.data.task.id;

  const edited = await taskRequest(env, '/save', { id, text: 'Исправленный текст' });
  assert.equal(edited.data.task.assignee, 'sergey');
  const reassigned = await taskRequest(env, '/save', { id, text: 'Исправленный текст', assignee: 'nikita' });
  assert.equal(reassigned.data.task.assignee, 'nikita');
  const moved = await taskRequest(env, '/move', { id, status: 'ready' });
  assert.equal(moved.data.task.assignee, 'nikita');
  const cleared = await taskRequest(env, '/save', { id, text: 'Исправленный текст', assignee: '' });
  assert.equal(cleared.data.task.assignee, '');
});

test('invalid assignments do not change stored tasks', async () => {
  const env = createMockEnv();
  await taskRequest(env, '/save', { text: 'Задача', assignee: 'sergey' });
  const original = env._store.get('tasks:items');
  const id = JSON.parse(original)[0].id;
  for (const body of [
    { assignee: 'nikita' }, { id: '', assignee: 'nikita' }, { id: '  ', assignee: 'nikita' },
    { id }, { id, assignee: null }, { id, assignee: 'other' },
  ]) {
    assert.equal((await taskRequest(env, '/assign', body)).status, 400);
    assert.equal(env._store.get('tasks:items'), original);
  }
  assert.equal((await taskRequest(env, '/assign', { id: 'missing', assignee: 'nikita' })).status, 404);
  assert.equal((await taskRequest(env, '/save', { id, text: 'Изменение', assignee: 'other' })).status, 400);
  const request = new Request('https://test/api/admin/tasks/assign', { method: 'POST', body: '{' });
  assert.equal((await handleTasksAdmin(request, env, new URL(request.url))).status, 400);
  assert.equal(env._store.get('tasks:items'), original);
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

  // 4. UPDATE task text; app versions are ignored.
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
  assert.equal(Object.hasOwn(updateData.task, 'version'), false);
  assert.equal(Object.hasOwn(updateData, 'versions'), false);

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
  const assignment = await worker.fetch(new Request('https://test/api/admin/tasks/assign', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ id: 'existing-task', assignee: 'nikita' }),
  }), { INSTALLS: { get: async () => null } });
  assert.equal(assignment.status, 401);
  const priority = await worker.fetch(new Request('https://test/api/admin/tasks/priority', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ id: 'existing-task', priority: 'high' }),
  }), { INSTALLS: { get: async () => null } });
  assert.equal(priority.status, 401);
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
  const scriptContent = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(match => match[1]).join('\n');
  new Function(scriptContent);
});
