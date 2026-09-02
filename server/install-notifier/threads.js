// ─────────────────────────────────────────────────────────────────────────────
// Публикация в Threads.
//
// Схема та же, что у Instagram Reels: сначала создаём «контейнер» с текстом,
// затем публикуем его. Meta требует паузу между шагами — контейнеру нужно
// время, чтобы стать готовым.
//
// Токен и id аккаунта берутся в кабинете Meta (сценарий «Threads API»),
// хранятся в KV и продлеваются сами, как у Instagram.
// ─────────────────────────────────────────────────────────────────────────────

const KV_SETTINGS = 'threads:settings';
const KV_QUEUE = 'threads_queue';       // ключ исторический — очередь уже жила в нём
const KV_LOG = 'threads:log';

const API = 'https://graph.threads.net/v1.0';
const LOG_LIMIT = 60;

// Между созданием контейнера и публикацией Meta просит подождать: сразу после
// создания контейнер ещё не готов и публикация падает.
const CONTAINER_WAIT_MS = 30000;
const MAX_TEXT = 500;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function nowMsk(d = new Date()) {
  return new Date(d.getTime() + 3 * 3600 * 1000);
}

function newId() {
  return 'th_' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36).slice(-4);
}

function limit(str, max) {
  const s = String(str == null ? '' : str);
  return s.length <= max ? s : s.slice(0, max);
}

async function kvJson(env, key, fallback) {
  try {
    const raw = await env.INSTALLS.get(key);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw);
    return parsed === null || parsed === undefined ? fallback : parsed;
  } catch (_) {
    return fallback;
  }
}

async function kvPut(env, key, value) {
  await env.INSTALLS.put(key, JSON.stringify(value));
}

async function threadsLog(env, level, message) {
  const entries = await kvJson(env, KV_LOG, []);
  entries.unshift({ ts: new Date().toISOString(), level, message: limit(message, 400) });
  await kvPut(env, KV_LOG, entries.slice(0, LOG_LIMIT));
}

// ────────────────────────────── настройки ──────────────────────────────

async function getSettings(env) {
  const stored = await kvJson(env, KV_SETTINGS, {});
  return {
    token: env.THREADS_TOKEN || stored.token || '',
    userId: stored.userId || '',
    username: stored.username || '',
    tokenUpdatedAt: stored.tokenUpdatedAt || null,
    postTime: stored.postTime || '10:00',
  };
}

function publicSettings(s) {
  return {
    userId: s.userId,
    username: s.username,
    postTime: s.postTime,
    hasToken: Boolean(s.token),
    tokenMask: s.token ? '••••••' + s.token.slice(-4) : '',
  };
}

/** Узнать id и имя аккаунта по токену — вручную их искать не нужно. */
async function resolveAccount(token) {
  const res = await fetch(`${API}/me?fields=id,username&access_token=${encodeURIComponent(token)}`);
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.id) {
    throw new Error(limit(data?.error?.message || 'Threads не принял токен (HTTP ' + res.status + ')', 200));
  }
  return { id: String(data.id), username: data.username || '' };
}

// ────────────────────────────── очередь ──────────────────────────────

/** Приводим записи к одному виду: очередь пережила прежнюю версию раздела. */
function normalize(post) {
  return {
    id: post.id || newId(),
    text: post.text || '',
    imageUrl: post.imageUrl || '',
    scheduledAt: post.scheduledAt || null,
    // Старые записи хранили только дату — считаем её временем публикации.
    scheduledDate: post.scheduledDate || null,
    status: post.status === 'published' ? 'published' : (post.status === 'failed' ? 'failed' : 'queued'),
    permalink: post.permalink || null,
    publishedAt: post.publishedAt || null,
    error: post.error || null,
    createdAt: post.createdAt || new Date().toISOString(),
  };
}

async function getQueue(env) {
  const raw = await kvJson(env, KV_QUEUE, []);
  return raw.map(normalize);
}

async function patchPost(env, id, patch) {
  const queue = await getQueue(env);
  const idx = queue.findIndex((p) => p.id === id);
  if (idx === -1) return null;
  queue[idx] = { ...queue[idx], ...patch };
  await kvPut(env, KV_QUEUE, queue);
  return queue[idx];
}

// ────────────────────────────── публикация ──────────────────────────────

export async function publishThreadsPost(env, postId, notify = null) {
  const settings = await getSettings(env);
  const queue = await getQueue(env);
  const post = queue.find((p) => p.id === postId);
  if (!post) return { status: 'error', message: 'Пост не найден' };

  if (!settings.token || !settings.userId) {
    await patchPost(env, postId, { status: 'failed', error: 'Threads не подключён' });
    return { status: 'error', message: 'Threads не подключён' };
  }

  const text = String(post.text || '').trim();
  if (!text) {
    await patchPost(env, postId, { status: 'failed', error: 'Пустой текст' });
    return { status: 'error', message: 'Пустой текст' };
  }

  try {
    const form = {
      media_type: post.imageUrl ? 'IMAGE' : 'TEXT',
      text: limit(text, MAX_TEXT),
      access_token: settings.token,
    };
    if (post.imageUrl) form.image_url = post.imageUrl;

    const createRes = await fetch(`${API}/${settings.userId}/threads`, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(form),
    });
    const created = await createRes.json().catch(() => ({}));
    if (!createRes.ok || !created.id) {
      throw new Error(limit(created?.error?.message || 'HTTP ' + createRes.status, 250));
    }

    // Контейнер сохраняем сразу: если фоновую задачу оборвёт Cloudflare,
    // повтор опубликует уже созданный, а не сделает второй пост.
    await patchPost(env, postId, { containerId: created.id });
    await sleep(CONTAINER_WAIT_MS);

    const pubRes = await fetch(`${API}/${settings.userId}/threads_publish`, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ creation_id: created.id, access_token: settings.token }),
    });
    const published = await pubRes.json().catch(() => ({}));
    if (!pubRes.ok || !published.id) {
      throw new Error(limit(published?.error?.message || 'HTTP ' + pubRes.status, 250));
    }

    let permalink = null;
    try {
      const info = await fetch(`${API}/${published.id}?fields=permalink&access_token=${encodeURIComponent(settings.token)}`);
      const infoData = await info.json().catch(() => ({}));
      permalink = infoData.permalink || null;
    } catch (_) { /* ссылка не обязательна */ }

    await patchPost(env, postId, {
      status: 'published',
      publishedAt: new Date().toISOString(),
      permalink,
      error: null,
      containerId: null,
    });
    await threadsLog(env, 'ok', 'Опубликовано: ' + limit(text, 60));
    return { status: 'ok', permalink };
  } catch (e) {
    await patchPost(env, postId, { status: 'failed', error: limit(e.message, 400) });
    await threadsLog(env, 'error', 'Не опубликовалось: ' + e.message);
    if (notify) {
      try {
        await notify('⚠️ <b>Threads: пост не опубликован</b>\n' + limit(e.message, 250));
      } catch (_) { /* уведомление не должно ронять публикацию */ }
    }
    return { status: 'error', message: e.message };
  }
}

/** Продлить токен Threads: он живёт 60 дней и обновляется запросом к Meta. */
async function refreshToken(env) {
  const settings = await getSettings(env);
  if (!settings.token) return;
  const updatedAt = settings.tokenUpdatedAt ? Date.parse(settings.tokenUpdatedAt) : 0;
  if (updatedAt && Date.now() - updatedAt < 30 * 24 * 3600 * 1000) return;

  try {
    const res = await fetch(
      `${API}/refresh_access_token?grant_type=th_refresh_token&access_token=${encodeURIComponent(settings.token)}`
    );
    const data = await res.json().catch(() => ({}));
    if (res.ok && data.access_token) {
      const stored = await kvJson(env, KV_SETTINGS, {});
      await kvPut(env, KV_SETTINGS, {
        ...stored, token: data.access_token, tokenUpdatedAt: new Date().toISOString(),
      });
      await threadsLog(env, 'info', 'Токен Threads продлён на 60 дней');
    } else {
      await threadsLog(env, 'error', 'Токен Threads продлить не вышло: ' + limit(data?.error?.message || res.status, 150));
    }
  } catch (e) {
    await threadsLog(env, 'error', 'Токен Threads: ' + e.message);
  }
}

/**
 * Крон: публикуем посты, у которых подошло время.
 * За один заход — один пост: Threads не любит очередей подряд, да и растянуть
 * ленту во времени полезнее, чем вывалить всё сразу.
 */
export async function runThreadsSchedule(env, notify = null) {
  const settings = await getSettings(env);
  if (!settings.token || !settings.userId) return;

  await refreshToken(env);

  const nowIso = new Date().toISOString();
  const queue = await getQueue(env);
  const due = queue
    .filter((p) => p.status === 'queued' && p.scheduledAt && p.scheduledAt <= nowIso)
    .sort((a, b) => a.scheduledAt.localeCompare(b.scheduledAt));

  if (!due.length) return;
  await publishThreadsPost(env, due[0].id, notify);
}

// ────────────────────────────── админ-API ──────────────────────────────

export async function handleThreadsAdmin(request, env, ctx, url, helpers) {
  const { jsonResponse, notify } = helpers;
  const path = url.pathname.replace(/\/$/, '');
  const body = request.method === 'POST' ? await request.json().catch(() => ({})) : {};

  if (path === '/api/admin/threads/state' && request.method === 'GET') {
    const [settings, queue, log] = await Promise.all([
      getSettings(env), getQueue(env), kvJson(env, KV_LOG, []),
    ]);
    return jsonResponse({
      settings: publicSettings(settings),
      posts: queue,
      log: log.slice(0, 20),
      serverTimeMsk: nowMsk().toISOString().slice(0, 16).replace('T', ' '),
    });
  }

  if (path === '/api/admin/threads/settings' && request.method === 'POST') {
    const stored = await kvJson(env, KV_SETTINGS, {});
    const next = { ...stored };
    if (typeof body.postTime === 'string' && body.postTime) next.postTime = body.postTime;

    let note = null;
    if (typeof body.token === 'string' && body.token.trim()) {
      next.token = body.token.trim();
      next.tokenUpdatedAt = new Date().toISOString();
      try {
        const account = await resolveAccount(next.token);
        next.userId = account.id;
        next.username = account.username;
        note = 'Аккаунт определён: @' + account.username;
      } catch (e) {
        note = 'Токен сохранён, но аккаунт определить не вышло: ' + e.message;
      }
    }
    await kvPut(env, KV_SETTINGS, next);
    return jsonResponse({ ok: true, note, settings: publicSettings(await getSettings(env)) });
  }

  if (path === '/api/admin/threads/check' && request.method === 'POST') {
    const settings = await getSettings(env);
    const checks = [];
    if (!settings.token) {
      checks.push({ name: 'Threads', ok: false, message: 'токен не задан' });
    } else {
      try {
        const account = await resolveAccount(settings.token);
        checks.push({ name: 'Threads', ok: true, message: 'аккаунт @' + account.username });
      } catch (e) {
        checks.push({ name: 'Threads', ok: false, message: e.message });
      }
    }
    const queue = await getQueue(env);
    checks.push({
      name: 'Очередь',
      ok: true,
      message: `запланировано: ${queue.filter((p) => p.status === 'queued' && p.scheduledAt).length}, `
        + `без даты: ${queue.filter((p) => p.status === 'queued' && !p.scheduledAt).length}, `
        + `опубликовано: ${queue.filter((p) => p.status === 'published').length}`,
    });
    return jsonResponse({ ok: true, checks });
  }

  // Добавление пачкой: посты разделяются пустой строкой — так удобно
  // вставлять сразу десяток заготовок из заметок.
  if (path === '/api/admin/threads/add' && request.method === 'POST') {
    const chunks = String(body.text || '')
      .split(/\n\s*\n/)
      .map((t) => t.trim())
      .filter(Boolean);
    if (!chunks.length) return jsonResponse({ ok: false, message: 'Пусто' });

    const queue = await getQueue(env);
    chunks.forEach((text) => {
      queue.push(normalize({ id: newId(), text, status: 'queued', createdAt: new Date().toISOString() }));
    });
    await kvPut(env, KV_QUEUE, queue);
    return jsonResponse({ ok: true, added: chunks.length });
  }

  if (path === '/api/admin/threads/update' && request.method === 'POST') {
    const patch = {};
    if (typeof body.text === 'string') patch.text = body.text;
    if (typeof body.imageUrl === 'string') patch.imageUrl = body.imageUrl;
    if (body.scheduledAt !== undefined) patch.scheduledAt = body.scheduledAt || null;
    const updated = await patchPost(env, body.id, patch);
    return jsonResponse(updated ? { ok: true } : { error: 'not found' }, updated ? 200 : 404);
  }

  if (path === '/api/admin/threads/bulk' && request.method === 'POST') {
    const ids = Array.isArray(body.ids) ? body.ids : [];
    let queue = await getQueue(env);
    let changed = 0;

    if (body.action === 'schedule') {
      const startMsk = new Date(String(body.startAt) + ':00.000Z');
      if (isNaN(startMsk.getTime())) return jsonResponse({ error: 'bad date' }, 400);
      const stepDays = Math.max(1, parseInt(body.everyDays, 10) || 1);
      const ordered = queue.filter((p) => ids.includes(p.id));
      ordered.forEach((post, i) => {
        const idx = queue.findIndex((p) => p.id === post.id);
        const when = new Date(startMsk.getTime() + i * stepDays * 86400000 - 3 * 3600000);
        queue[idx] = { ...queue[idx], scheduledAt: when.toISOString(), status: 'queued', error: null };
        changed += 1;
      });
    } else if (body.action === 'delete') {
      const before = queue.length;
      queue = queue.filter((p) => !ids.includes(p.id));
      changed = before - queue.length;
    } else {
      queue.forEach((post, idx) => {
        if (!ids.includes(post.id)) return;
        if (body.action === 'unschedule') queue[idx] = { ...post, scheduledAt: null };
        else if (body.action === 'mark') queue[idx] = { ...post, status: 'published', publishedAt: new Date().toISOString(), error: null };
        else if (body.action === 'requeue') queue[idx] = { ...post, status: 'queued', publishedAt: null, error: null };
        changed += 1;
      });
    }

    await kvPut(env, KV_QUEUE, queue);
    return jsonResponse({ ok: true, changed });
  }

  if (path === '/api/admin/threads/publish-now' && request.method === 'POST') {
    const ids = Array.isArray(body.ids) ? body.ids : [];
    const queue = await getQueue(env);
    // Больше трёх подряд не публикуем: у каждого поста пауза на готовность
    // контейнера, да и лента не должна превращаться в свалку.
    const take = queue.filter((p) => ids.includes(p.id) && p.status !== 'published').slice(0, 3);
    if (!take.length) return jsonResponse({ ok: false, message: 'Нечего публиковать' });

    ctx.waitUntil((async () => {
      for (const post of take) {
        await publishThreadsPost(env, post.id, notify);
      }
    })());

    return jsonResponse({
      ok: true,
      message: take.length === 1 ? 'Публикую пост' : `Публикую ${take.length} поста подряд`,
    });
  }

  return null;
}
