// API раздела «Задачи» админки: Канбан-доска, список, статусы жизненного цикла,
// версии игры/приложения, приоритеты и вложения (скриншоты/файлы).
// Хранилище: KV env.INSTALLS.

export const TASK_STATUSES = ['idea', 'planned', 'in_progress', 'ready', 'released', 'archived'];
export const TASK_PRIORITIES = ['high', 'normal', 'low'];
export const MAX_TASK_TEXT_LENGTH = 10000;
export const MAX_ATTACHMENT_SIZE = 10 * 1024 * 1024; // 10 МБ

const KV_TASKS_KEY = 'tasks:items';
const KV_ATTACHMENT_PREFIX = 'task_att:';

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

export async function getStoredTasks(env) {
  if (!env || !env.INSTALLS) return [];
  try {
    const raw = await env.INSTALLS.get(KV_TASKS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (err) {
    console.error('getStoredTasks error:', err);
    return [];
  }
}

export async function putStoredTasks(env, tasks) {
  if (!env || !env.INSTALLS) return false;
  await env.INSTALLS.put(KV_TASKS_KEY, JSON.stringify(tasks));
  return true;
}

export function extractVersions(tasks) {
  const versions = new Set();
  for (const t of tasks) {
    if (t.version && typeof t.version === 'string' && t.version.trim()) {
      versions.add(t.version.trim());
    }
  }
  return Array.from(versions).sort((a, b) => b.localeCompare(a, undefined, { numeric: true, sensitivity: 'base' }));
}

export function validateTaskInput(input) {
  const text = typeof input?.text === 'string' ? input.text.trim() : '';
  if (!text) {
    return { error: 'Текст задачи не может быть пустым' };
  }
  if (text.length > MAX_TASK_TEXT_LENGTH) {
    return { error: `Текст задачи слишком длинный (максимум ${MAX_TASK_TEXT_LENGTH} символов)` };
  }

  const status = TASK_STATUSES.includes(input?.status) ? input.status : 'idea';
  const priority = TASK_PRIORITIES.includes(input?.priority) ? input.priority : 'normal';
  const version = typeof input?.version === 'string' ? input.version.trim().slice(0, 50) : '';

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
      version,
      attachments,
    },
  };
}

export async function handleTasksAdmin(request, env, url) {
  const path = url.pathname;
  const method = request.method;

  // 1. Получение списка всех задач
  if (path === '/api/admin/tasks' && method === 'GET') {
    const tasks = await getStoredTasks(env);
    const versions = extractVersions(tasks);
    return reply({ ok: true, tasks, versions });
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
          ...check.data,
          updatedAt: now,
        };
        targetTask = tasks[idx];
      }
    }

    if (!targetTask) {
      targetTask = {
        id: crypto.randomUUID(),
        ...check.data,
        createdAt: now,
        updatedAt: now,
      };
      // Новые задачи добавляем в начало списка
      tasks.unshift(targetTask);
    }

    await putStoredTasks(env, tasks);
    const versions = extractVersions(tasks);
    return reply({ ok: true, task: targetTask, versions });
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

    task.status = status;
    task.updatedAt = Date.now();
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
    await putStoredTasks(env, tasks);

    // Удаляем вложения из KV при наличии
    if (env && env.INSTALLS && Array.isArray(deletedTask.attachments)) {
      for (const att of deletedTask.attachments) {
        if (att && att.id) {
          try {
            await env.INSTALLS.delete(KV_ATTACHMENT_PREFIX + att.id);
          } catch (e) {
            console.error('Failed to delete attachment', att.id, e);
          }
        }
      }
    }

    const versions = extractVersions(tasks);
    return reply({ ok: true, id, versions });
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
