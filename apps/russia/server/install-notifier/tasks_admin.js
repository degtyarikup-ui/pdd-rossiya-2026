// API раздела «Задачи» админки: Канбан-доска, статусы жизненного цикла,
// исполнители, приоритеты и вложения (скриншоты/файлы).
// Хранилище: KV env.INSTALLS.

export const TASK_STATUSES = ['idea', 'planned', 'in_progress', 'ready', 'released', 'archived'];
export const TASK_PRIORITIES = ['high', 'normal', 'low'];
export const TASK_ASSIGNEES = ['', 'sergey', 'nikita'];
export const MAX_TASK_TEXT_LENGTH = 10000;
export const MAX_ATTACHMENT_SIZE = 10 * 1024 * 1024; // 10 МБ
export const RELEASED_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;
export const ARCHIVED_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

const KV_TASKS_KEY = 'tasks:items';
const KV_ATTACHMENT_PREFIX = 'task_att:';
const KV_ATTACHMENT_CLEANUP_KEY = 'tasks:attachment_cleanup';

function reply(data, status = 200, extraHeaders = {}) {
  return Response.json(data, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
      ...extraHeaders,
    },
  });
}

async function readTasksSnapshot(env) {
  if (!env?.INSTALLS) throw new Error('Хранилище задач недоступно');
  const raw = await env.INSTALLS.get(KV_TASKS_KEY);
  if (raw === null || raw === undefined) return { raw, tasks: [] };
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed)) throw new Error('Некорректный список задач');
  const ids = new Set();
  for (const task of parsed) {
    if (!task || typeof task !== 'object' || Array.isArray(task)
      || typeof task.id !== 'string' || !task.id.trim() || ids.has(task.id)
      || typeof task.text !== 'string' || !task.text.trim()
      || !TASK_STATUSES.includes(task.status)
      || (task.attachments !== undefined && (!Array.isArray(task.attachments)
        || task.attachments.some(att => !att || typeof att !== 'object' || Array.isArray(att)
          || typeof att.id !== 'string' || !att.id.trim())))) {
      throw new Error('Некорректная запись задачи');
    }
    ids.add(task.id);
  }
  return { raw, tasks: parsed };
}

export async function getStoredTasks(env) {
  return (await readTasksSnapshot(env)).tasks;
}

export async function putStoredTasks(env, tasks) {
  if (!env?.INSTALLS) throw new Error('Хранилище задач недоступно');
  await env.INSTALLS.put(KV_TASKS_KEY, JSON.stringify(tasks));
  return true;
}

function validTimestamp(value) {
  return Number.isFinite(value) && value > 0;
}

function taskStatusChangedAt(task, now) {
  return [task.statusChangedAt, task.updatedAt, task.createdAt, now].find(validTimestamp);
}

function attachmentIds(tasks) {
  return new Set(tasks.flatMap(task => (task.attachments || []).map(att => att.id)));
}

async function attachmentCleanupQueue(env) {
  const raw = await env.INSTALLS.get(KV_ATTACHMENT_CLEANUP_KEY);
  if (raw === null || raw === undefined) return [];
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed) || parsed.some(id => typeof id !== 'string' || !id.trim())) {
    throw new Error('Некорректная очередь удаления вложений');
  }
  return [...new Set(parsed)];
}

// Persist cleanup intent before removing task rows; failed blob deletion is retried.
async function storeTasksAndCleanAttachments(env, tasks, removedTasks, writeTasks, pendingCleanup, expectedSnapshot) {
  const pending = pendingCleanup ?? await attachmentCleanupQueue(env);
  const retainedIds = attachmentIds(tasks);
  const candidates = [...new Set([...pending, ...attachmentIds(removedTasks)])]
    .filter(id => !retainedIds.has(id));
  const addedCandidates = candidates.some(id => !pending.includes(id));
  if (writeTasks && expectedSnapshot && (await readTasksSnapshot(env)).raw !== expectedSnapshot.raw) return false;
  if (addedCandidates) await env.INSTALLS.put(KV_ATTACHMENT_CLEANUP_KEY, JSON.stringify(candidates));
  if (writeTasks) {
    // KV has no compare-and-swap: skip an observed intervening edit and retry
    // next hour. This narrows the pre-existing whole-array race best effort.
    if (addedCandidates && expectedSnapshot && (await readTasksSnapshot(env)).raw !== expectedSnapshot.raw) return false;
    await putStoredTasks(env, tasks);
  }

  const failed = [];
  const latestAttachmentIds = candidates.length ? attachmentIds(await getStoredTasks(env)) : retainedIds;
  for (const id of candidates) {
    if (latestAttachmentIds.has(id)) continue;
    try {
      await env.INSTALLS.delete(KV_ATTACHMENT_PREFIX + id);
    } catch (error) {
      failed.push(id);
      console.error('Failed to delete task attachment', id, error);
    }
  }
  const storedCleanup = addedCandidates ? candidates : pending;
  if (storedCleanup.length && JSON.stringify(failed) !== JSON.stringify(storedCleanup)) {
    await env.INSTALLS.put(KV_ATTACHMENT_CLEANUP_KEY, JSON.stringify(failed));
  }
  if (failed.length) throw new Error('Не удалось удалить вложения задач');
  return true;
}

export async function maintainTaskLifecycle(env, now = Date.now()) {
  if (!validTimestamp(now)) throw new Error('Некорректное время обслуживания задач');
  const snapshot = await readTasksSnapshot(env);
  const tasks = snapshot.tasks;
  const pendingCleanup = await attachmentCleanupQueue(env);
  const retained = [];
  const removed = [];
  let changed = false;
  let archived = 0;
  for (const task of tasks) {
    const statusChangedAt = taskStatusChangedAt(task, now);
    let next = task;
    if (task.statusChangedAt !== statusChangedAt) {
      next = { ...next, statusChangedAt };
      changed = true;
    }
    if (next.status === 'released' && now - next.statusChangedAt >= RELEASED_RETENTION_MS) {
      next = { ...next, status: 'archived', statusChangedAt: next.statusChangedAt + RELEASED_RETENTION_MS, updatedAt: now };
      changed = true;
      archived++;
    }
    if (next.status === 'archived' && now - next.statusChangedAt >= ARCHIVED_RETENTION_MS) {
      removed.push(next);
      changed = true;
    } else {
      retained.push(next);
    }
  }
  const stored = await storeTasksAndCleanAttachments(env, retained, removed, changed, pendingCleanup, snapshot);
  if (!stored) return { ok: true, changed: false, archived: 0, deleted: 0, skipped: 'snapshot_changed' };
  return { ok: true, changed, archived, deleted: removed.length };
}

export function validateTaskInput(input) {
  const text = typeof input?.text === 'string' ? input.text.trim() : '';
  if (!text) {
    return { error: 'Текст задачи не может быть пустым' };
  }
  if (text.length > MAX_TASK_TEXT_LENGTH) {
    return { error: `Текст задачи слишком длинный (максимум ${MAX_TASK_TEXT_LENGTH} символов)` };
  }

  const hasAssignee = Object.prototype.hasOwnProperty.call(input, 'assignee');
  if (hasAssignee && !TASK_ASSIGNEES.includes(input.assignee)) {
    return { error: 'Недопустимый исполнитель' };
  }

  const status = TASK_STATUSES.includes(input?.status) ? input.status : 'idea';
  const priority = TASK_PRIORITIES.includes(input?.priority) ? input.priority : 'normal';

  const attachments = Array.isArray(input?.attachments)
    ? input.attachments.filter(a => a && typeof a.id === 'string' && a.id.trim()).map(a => ({
        id: a.id.trim(),
        name: typeof a.name === 'string' ? a.name.slice(0, 255) : 'файл',
        type: typeof a.type === 'string' ? a.type.slice(0, 100) : 'application/octet-stream',
        size: Number.isFinite(a.size) ? a.size : 0,
        createdAt: Number.isFinite(a.createdAt) ? a.createdAt : Date.now(),
      }))
    : [];

  return {
    valid: true,
    data: {
      text,
      status,
      priority,
      attachments,
      ...(hasAssignee ? { assignee: input.assignee } : {}),
    },
  };
}

export async function handleTasksAdmin(request, env, url) {
  try {
    return await dispatchTasksAdmin(request, env, url);
  } catch (error) {
    console.error('Tasks storage error:', error);
    return reply({ error: 'Хранилище задач недоступно' }, 503);
  }
}

async function dispatchTasksAdmin(request, env, url) {
  const path = url.pathname;
  const method = request.method;

  // 1. Получение списка всех задач
  if (path === '/api/admin/tasks' && method === 'GET') {
    const tasks = (await getStoredTasks(env)).map(task => ({ ...task, assignee: task.assignee ?? '' }));
    return reply({ ok: true, tasks });
  }

  // 2. Создание или обновление задачи
  if (path === '/api/admin/tasks/save' && method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return reply({ error: 'Некорректный JSON' }, 400);
    }

    const check = validateTaskInput(body);
    if (check.error) return reply({ error: check.error }, 400);

    const tasks = await getStoredTasks(env);
    const now = Date.now();
    const id = typeof body.id === 'string' && body.id.trim() ? body.id.trim() : null;

    let targetTask = null;
    if (id) {
      const idx = tasks.findIndex(t => t.id === id);
      if (idx !== -1) {
        tasks[idx] = {
          ...tasks[idx],
          assignee: tasks[idx].assignee ?? '',
          statusChangedAt: tasks[idx].status === check.data.status ? taskStatusChangedAt(tasks[idx], now) : now,
          ...check.data,
          updatedAt: now,
        };
        targetTask = tasks[idx];
      }
    }

    if (!targetTask) {
      targetTask = {
        id: crypto.randomUUID(),
        assignee: '',
        ...check.data,
        createdAt: now,
        updatedAt: now,
        statusChangedAt: now,
      };
      // Новые задачи добавляем в начало списка
      tasks.unshift(targetTask);
    }

    await putStoredTasks(env, tasks);
    return reply({ ok: true, task: targetTask });
  }

  // 3. Быстрое изменение статуса (move)
  if (path === '/api/admin/tasks/move' && method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return reply({ error: 'Некорректный JSON' }, 400);
    }

    const { id, status } = body || {};
    if (!id || typeof id !== 'string') return reply({ error: 'Не указан ID задачи' }, 400);
    if (!TASK_STATUSES.includes(status)) return reply({ error: 'Недопустимый статус' }, 400);

    const tasks = await getStoredTasks(env);
    const task = tasks.find(t => t.id === id);
    if (!task) return reply({ error: 'Задача не найдена' }, 404);

    const now = Date.now();
    task.statusChangedAt = task.status === status ? taskStatusChangedAt(task, now) : now;
    task.status = status;
    task.updatedAt = now;
    await putStoredTasks(env, tasks);

    return reply({ ok: true, task });
  }

  // Быстрое назначение исполнителя без перезаписи содержимого карточки.
  if (path === '/api/admin/tasks/assign' && method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return reply({ error: 'Некорректный JSON' }, 400);
    }

    const { id, assignee } = body || {};
    if (typeof id !== 'string' || !id.trim()) return reply({ error: 'Не указан ID задачи' }, 400);
    if (!TASK_ASSIGNEES.includes(assignee)) return reply({ error: 'Недопустимый исполнитель' }, 400);

    const tasks = await getStoredTasks(env);
    const task = tasks.find(t => t.id === id.trim());
    if (!task) return reply({ error: 'Задача не найдена' }, 404);

    const now = Date.now();
    task.statusChangedAt = taskStatusChangedAt(task, now);
    task.assignee = assignee;
    task.updatedAt = now;
    await putStoredTasks(env, tasks);

    return reply({ ok: true, task });
  }

  if (path === '/api/admin/tasks/priority' && method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return reply({ error: 'Некорректный JSON' }, 400);
    }
    const { id, priority } = body || {};
    if (typeof id !== 'string' || !id.trim()) return reply({ error: 'Не указан ID задачи' }, 400);
    if (!TASK_PRIORITIES.includes(priority)) return reply({ error: 'Недопустимый приоритет' }, 400);

    const tasks = await getStoredTasks(env);
    const task = tasks.find(t => t.id === id.trim());
    if (!task) return reply({ error: 'Задача не найдена' }, 404);
    const now = Date.now();
    task.statusChangedAt = taskStatusChangedAt(task, now);
    task.priority = priority;
    task.updatedAt = now;
    await putStoredTasks(env, tasks);
    return reply({ ok: true, task });
  }

  // 4. Удаление задачи навсегда (с удалением её файлов)
  if (path === '/api/admin/tasks/delete' && method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return reply({ error: 'Некорректный JSON' }, 400);
    }

    const { id } = body || {};
    if (!id || typeof id !== 'string') return reply({ error: 'Не указан ID задачи' }, 400);

    const tasks = await getStoredTasks(env);
    const idx = tasks.findIndex(t => t.id === id);
    if (idx === -1) return reply({ error: 'Задача не найдена' }, 404);

    const [deletedTask] = tasks.splice(idx, 1);
    await storeTasksAndCleanAttachments(env, tasks, [deletedTask], true);
    return reply({ ok: true, id });
  }

  // 5. Загрузка вложения (картинка или файл)
  if (path === '/api/admin/tasks/upload' && method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return reply({ error: 'Некорректный JSON' }, 400);
    }

    const { name, type, base64 } = body || {};
    if (!base64 || typeof base64 !== 'string') {
      return reply({ error: 'Отсутствуют данные файла' }, 400);
    }

    // Проверка размера (в base64 1 байт ~ 1.37 символа)
    if (base64.length > MAX_ATTACHMENT_SIZE * 1.4) {
      return reply({ error: 'Файл превышает максимальный размер (10 МБ)' }, 400);
    }

    const attId = crypto.randomUUID();
    const cleanName = (typeof name === 'string' && name.trim()) ? name.trim().slice(0, 255) : 'attachment';
    const cleanType = (typeof type === 'string' && type.trim()) ? type.trim().slice(0, 100) : 'application/octet-stream';
    const approxSize = Math.round((base64.length * 3) / 4);

    const record = {
      id: attId,
      name: cleanName,
      type: cleanType,
      size: approxSize,
      data: base64,
      createdAt: Date.now(),
    };

    if (env && env.INSTALLS) {
      await env.INSTALLS.put(KV_ATTACHMENT_PREFIX + attId, JSON.stringify(record));
    }

    return reply({
      ok: true,
      attachment: {
        id: attId,
        name: cleanName,
        type: cleanType,
        size: approxSize,
        url: `/api/admin/tasks/attachment/${attId}`,
      },
    });
  }

  // 6. Получение прикреплённого файла
  if (path.startsWith('/api/admin/tasks/attachment/') && method === 'GET') {
    const attId = path.slice('/api/admin/tasks/attachment/'.length).replace(/\/$/, '');
    if (!attId) return reply({ error: 'Не указан ID файла' }, 400);

    if (!env || !env.INSTALLS) {
      return reply({ error: 'Хранилище недоступно' }, 503);
    }

    const raw = await env.INSTALLS.get(KV_ATTACHMENT_PREFIX + attId);
    if (!raw) return reply({ error: 'Файл не найден' }, 404);

    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      return reply({ error: 'Ошибка чтения файла' }, 500);
    }

    // Если данные хранятся как base64 (возможно с префиксом data:...;base64,)
    let base64Data = parsed.data || '';
    if (base64Data.includes(',')) {
      base64Data = base64Data.split(',')[1];
    }

    try {
      const binaryString = atob(base64Data);
      const bytes = new Uint8Array(binaryString.length);
      for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
      }

      const mime = parsed.type || 'application/octet-stream';
      const isInline = mime.startsWith('image/') || mime === 'application/pdf';
      const disposition = isInline ? 'inline' : `attachment; filename="${encodeURIComponent(parsed.name || 'file')}"`;

      return new Response(bytes.buffer, {
        status: 200,
        headers: {
          'Content-Type': mime,
          'Content-Disposition': disposition,
          'Cache-Control': 'private, max-age=86400',
        },
      });
    } catch (err) {
      console.error('Failed to decode attachment', err);
      return reply({ error: 'Ошибка декодирования файла' }, 500);
    }
  }

  return reply({ error: 'Не найден эндпоинт' }, 404);
}
