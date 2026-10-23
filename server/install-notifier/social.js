// ─────────────────────────────────────────────────────────────────────────────
// Автопостинг роликов в Instagram Reels и YouTube Shorts.
//
// Схема повторяет ту, что уже работает в админке Meerno, но целиком живёт
// внутри Cloudflare Worker:
//
//   Google Диск (папка с роликами)  →  очередь в KV  →  крон раз в час
//        ├─ Instagram: Meta сама скачивает видео по публичной ссылке
//        │             /s/v/<токен> — воркер проксирует её с Диска;
//        └─ YouTube:   воркер сам заливает файл resumable-загрузкой.
//
// Почему так: у воркера нет диска, поэтому ролик нигде не сохраняется —
// Instagram тянет его через прокси-ссылку, а для YouTube файл держится в
// памяти воркера только на время заливки (отсюда лимит MAX_UPLOAD_BYTES).
// ─────────────────────────────────────────────────────────────────────────────

import { socialGuard, beginSocialWrite, completeSocialWrite, abandonSocialWrite, withSocialPublicationLease } from './social_guard.js';

async function notifySocialFailure(notify, accountId, reason, text) {
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(accountId + '|' + reason));
  const fingerprint = [...new Uint8Array(hash)].map(v => v.toString(16).padStart(2, '0')).join('');
  return notify(text, { errorGroupKey: 'social:' + fingerprint });
}

const KV_SETTINGS = 'social:settings';
const KV_ACCOUNTS = 'social:accounts';
const KV_POSTS = 'social:posts';
const KV_LOG = 'social:log';
const KV_GOOGLE_TOKEN = 'social:google_token';
const KV_INSTAGRAM_COOLDOWN = 'social:instagram_cooldown';
const KV_EXCLUDED_PREFIX = 'social:excluded:';
const IG_COOLDOWN_MS = 60 * 60 * 1000;
const IG_MAX_COOLDOWN_MS = 24 * IG_COOLDOWN_MS;
const instagramCooldownMemory = new WeakMap();

const VIDEO_EXT = ['mp4', 'mov', 'm4v'];
const LOG_LIMIT = 120;

// Ролик заливается на YouTube из памяти воркера (лимит инстанса — 128 МБ).
// Вертикальные ролики до минуты весят единицы мегабайт, так что запас большой,
// но осмысленная ошибка лучше, чем падение воркера без объяснений.
const MAX_UPLOAD_BYTES = 90 * 1024 * 1024;

// Meta кодирует видео на своей стороне; ждём столько же, сколько Meerno.
// За раз вручную публикуем не больше стольких роликов: каждая публикация в
// Instagram занимает минуты, и очередь из тридцати растянулась бы на часы.
const MAX_MANUAL_BATCH = 5;

// Дольше этого времени публикация идти не может: Instagram отдаёт готовое
// видео максимум за несколько минут, YouTube — быстрее.
const STALE_PROCESSING_MS = 30 * 60 * 1000;

// Leave time to persist the publish response and release the lease before
// Cloudflare ends the 30-second waitUntil window. The cron resumes this container.
const IG_POLL_ATTEMPTS = 2;
const IG_POLL_INTERVAL_MS = 5000;

const GRAPH_VERSION = 'v21.0';

// ────────────────────────────── утилиты ──────────────────────────────

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function nowMsk(d = new Date()) {
  return new Date(d.getTime() + 3 * 3600 * 1000);
}

/** Дата в МСК в виде YYYY-MM-DD. */
function mskDay(d = new Date()) {
  return nowMsk(d).toISOString().slice(0, 10);
}

/** Минуты, прошедшие с полуночи по МСК. */
function mskMinutes(d = new Date()) {
  const m = nowMsk(d);
  return m.getUTCHours() * 60 + m.getUTCMinutes();
}

function parseTimeToMinutes(value, fallback = 19 * 60) {
  const match = String(value || '').match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return fallback;
  const h = Math.min(23, parseInt(match[1], 10));
  const min = Math.min(59, parseInt(match[2], 10));
  return h * 60 + min;
}

function newId(prefix) {
  return prefix + '_' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36).slice(-4);
}

function randomToken() {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
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

function extOf(name) {
  const m = String(name || '').match(/\.([A-Za-z0-9]+)$/);
  return m ? m[1].toLowerCase() : '';
}

function baseName(name) {
  return String(name || '').replace(/\.[^.]+$/, '');
}

/** «003_ostanovka-zapreshchena.mp4» → «Остановка запрещена» не сделать, но
 *  порядковый префикс и разделители убрать полезно. */
function humanTitle(fileName) {
  const clean = baseName(fileName).replace(/^\d+[_\-.\s]+/, '').replace(/[_\-]+/g, ' ').trim();
  if (!clean) return baseName(fileName);
  return clean.charAt(0).toUpperCase() + clean.slice(1);
}

function limit(str, max) {
  const s = String(str == null ? '' : str);
  return s.length <= max ? s : s.slice(0, max);
}

// ────────────────────────────── лог ──────────────────────────────

export async function socialLog(env, level, message, extra = {}) {
  const entries = await kvJson(env, KV_LOG, []);
  entries.unshift({
    ts: new Date().toISOString(),
    level,
    message: limit(message, 500),
    ...extra,
  });
  await kvPut(env, KV_LOG, entries.slice(0, LOG_LIMIT));
}

// ────────────────────────────── настройки и аккаунты ──────────────────────────────

const EMPTY_SETTINGS = {
  googleApiKey: '',
  googleClientId: '',
  googleClientSecret: '',
  googleRefreshToken: '',
  workerOrigin: '',
};

async function getSettings(env) {
  const stored = await kvJson(env, KV_SETTINGS, {});
  return {
    ...EMPTY_SETTINGS,
    ...stored,
    // Секреты из окружения (wrangler secret put) имеют приоритет над KV.
    googleClientId: env.GOOGLE_CLIENT_ID || stored.googleClientId || '',
    googleClientSecret: env.GOOGLE_CLIENT_SECRET || stored.googleClientSecret || '',
    googleRefreshToken: env.GOOGLE_REFRESH_TOKEN || stored.googleRefreshToken || '',
    googleApiKey: env.GOOGLE_API_KEY || stored.googleApiKey || '',
  };
}

/** Секреты наружу не отдаём — только признак «заполнено» и хвост значения. */
function maskSecret(value) {
  const v = String(value || '');
  if (!v) return '';
  return '••••••' + v.slice(-4);
}

function publicSettings(settings) {
  return {
    googleClientId: settings.googleClientId,
    googleApiKeyMask: maskSecret(settings.googleApiKey),
    hasGoogleApiKey: Boolean(settings.googleApiKey),
    // Диску хватает API-ключа, YouTube без OAuth заливать не даёт.
    driveMode: settings.googleRefreshToken ? 'oauth' : (settings.googleApiKey ? 'apikey' : 'none'),
    youtubeReady: Boolean(settings.googleRefreshToken),
    googleClientSecretMask: maskSecret(settings.googleClientSecret),
    googleRefreshTokenMask: maskSecret(settings.googleRefreshToken),
    hasGoogleClientSecret: Boolean(settings.googleClientSecret),
    hasGoogleRefreshToken: Boolean(settings.googleRefreshToken),
    workerOrigin: settings.workerOrigin,
  };
}

function publicAccount(a) {
  return {
    ...a,
    instagramToken: undefined,
    youtubeRefreshToken: undefined,
    instagramTokenMask: maskSecret(a.instagramToken),
    youtubeRefreshTokenMask: maskSecret(a.youtubeRefreshToken),
    hasInstagramToken: Boolean(a.instagramToken),
    hasYoutubeRefreshToken: Boolean(a.youtubeRefreshToken),
  };
}

const DEFAULT_ACCOUNT = {
  name: 'ПДД Россия',
  active: true,
  targets: ['instagram', 'youtube'],
  driveFolderId: '',
  captionTemplate: '',
  titleTemplate: '{title}',
  postTime: '19:00',
  instagramAccountId: '',
  instagramToken: '',
  instagramTokenUpdatedAt: null,
  youtubeRefreshToken: '',
  youtubeTags: 'пдд, автошкола, экзамен, дорожныезнаки, shorts',
  youtubeCategoryId: '27',
  youtubePrivacy: 'public',
  lastPostedAt: null,
  lastPostedDay: null,
};

async function getAccounts(env) {
  return await kvJson(env, KV_ACCOUNTS, []);
}

async function getPosts(env) {
  return await kvJson(env, KV_POSTS, []);
}

async function getExcludedVideos(env, accountId) {
  const raw = await env.INSTALLS.get(KV_EXCLUDED_PREFIX + accountId);
  if (raw === null || raw === undefined) return new Set();
  let ids;
  try { ids = JSON.parse(raw); } catch (_) {}
  if (!Array.isArray(ids) || ids.some(id => typeof id !== 'string' || !id)) {
    throw new Error('Не удалось проверить исключённые видео. Импорт остановлен.');
  }
  return new Set(ids);
}

async function excludeVideos(env, posts) {
  for (const accountId of new Set(posts.map(p => p.accountId))) {
    const ids = await getExcludedVideos(env, accountId);
    for (const post of posts) if (post.accountId === accountId && post.driveFileId) ids.add(post.driveFileId);
    await kvPut(env, KV_EXCLUDED_PREFIX + accountId, [...ids]);
  }
}

function requeuePost(post) {
  const next = { ...post, error: post.instagramNeedsReview ? post.error : null, markedManually: false };
  // Queueing is a retry of missing destinations, never permission to duplicate
  // an already successful publication or erase its identity.
  next.instagramStatus = post.instagramStatus === 'published' ? 'published' : 'queued';
  next.youtubeStatus = post.youtubeStatus === 'published' ? 'published' : 'queued';
  const targets = post.targets || ['instagram', 'youtube'];
  next.status = targets.every(t => next[t + 'Status'] === 'published') ? 'published' : 'queued';
  return next;
}

/** Точечное обновление ролика: очередь лежит одним значением в KV, поэтому
 *  всегда перечитываем её перед записью, чтобы не затереть соседние правки. */
async function patchPost(env, postId, patch) {
  const posts = await getPosts(env);
  const idx = posts.findIndex((p) => p.id === postId);
  if (idx === -1) return null;
  posts[idx] = { ...posts[idx], ...patch };
  await kvPut(env, KV_POSTS, posts);
  return posts[idx];
}

// ────────────────────────────── Google OAuth ──────────────────────────────

/**
 * Access-token Google по refresh-токену. Одна пара client_id/secret обслуживает
 * и Диск, и YouTube (скоупы drive.readonly + youtube.upload выданы вместе),
 * но у аккаунта может быть свой refresh-токен — например, если канал YouTube
 * заведён на другом Google-аккаунте, чем папка с роликами.
 */
async function googleAccessToken(env, refreshTokenOverride = null) {
  const settings = await getSettings(env);
  const refreshToken = refreshTokenOverride || settings.googleRefreshToken;

  if (!settings.googleClientId || !settings.googleClientSecret || !refreshToken) {
    throw new Error('Доступ к Google не настроен: заполни Client ID, Client Secret и Refresh token в разделе «Автопостинг».');
  }

  const cacheKey = KV_GOOGLE_TOKEN + ':' + refreshToken.slice(-12);
  const cached = await kvJson(env, cacheKey, null);
  if (cached && cached.token && cached.exp > Date.now() + 60000) {
    return cached.token;
  }

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: settings.googleClientId,
      client_secret: settings.googleClientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) {
    throw new Error(
      'Google отклонил обновление токена (HTTP ' + res.status + '): ' +
      (data.error_description || data.error || 'без объяснения')
    );
  }

  await kvPut(env, cacheKey, {
    token: data.access_token,
    exp: Date.now() + Math.max(60, (data.expires_in || 3600) - 120) * 1000,
  });

  return data.access_token;
}

// ────────────────────────────── Google Диск ──────────────────────────────

/**
 * Как ходим на Диск.
 *
 * OAuth (refresh token) читает и закрытые папки и он же нужен YouTube.
 * Если OAuth не настроен, но задан API-ключ — читаем папку, открытую «по
 * ссылке»: ключ получается в Cloud Console за пару минут, без экрана согласия.
 */
async function driveAuth(env) {
  const settings = await getSettings(env);
  if (settings.googleRefreshToken) {
    return { mode: 'oauth', token: await googleAccessToken(env) };
  }
  if (settings.googleApiKey) {
    return { mode: 'apikey', key: settings.googleApiKey };
  }
  throw new Error(
    'Доступ к Google Диску не настроен: заполни либо Refresh token (нужен и для YouTube), ' +
    'либо API-ключ — тогда папку надо открыть «Доступ по ссылке».'
  );
}

async function driveListFolder(env, folderId) {
  const auth = await driveAuth(env);
  const params = new URLSearchParams({
    q: `'${folderId}' in parents and trashed = false`,
    fields: 'files(id, name, mimeType, size, md5Checksum)',
    pageSize: '200',
    orderBy: 'name_natural',
  });
  if (auth.mode === 'apikey') params.set('key', auth.key);
  const res = await fetch('https://www.googleapis.com/drive/v3/files?' + params, {
    headers: auth.mode === 'oauth' ? { authorization: 'Bearer ' + auth.token } : {},
  });
  if (!res.ok) {
    const body = await res.text();
    const hint = auth.mode === 'apikey' && (res.status === 403 || res.status === 404)
      ? ' — с API-ключом видны только папки, открытые «Доступ по ссылке»'
      : '';
    throw new Error('Google Диск не отдал список файлов (HTTP ' + res.status + ')' + hint + ': ' + limit(body, 200));
  }
  const data = await res.json();
  return data.files || [];
}

async function driveDownloadResponse(env, fileId, rangeHeader = null) {
  const auth = await driveAuth(env);
  const headers = {};
  if (auth.mode === 'oauth') headers.authorization = 'Bearer ' + auth.token;
  if (rangeHeader) headers.range = rangeHeader;

  let url = 'https://www.googleapis.com/drive/v3/files/' + encodeURIComponent(fileId) +
            '?alt=media&supportsAllDrives=true';
  if (auth.mode === 'apikey') url += '&key=' + encodeURIComponent(auth.key);

  const res = await fetch(url, { headers });

  // Открытая ссылка на большой файл отдаёт не видео, а страницу «не удалось
  // проверить на вирусы». Молча отправить её в Instagram нельзя — он упадёт
  // на невнятной ошибке.
  const type = res.headers.get('content-type') || '';
  if (res.ok && type.includes('text/html')) {
    throw new Error(
      'Google Диск вернул страницу подтверждения вместо файла. Обычно так бывает с крупными ' +
      'роликами при доступе по ссылке — сожми видео или настрой доступ через Refresh token.'
    );
  }

  return res;
}

async function driveReadText(env, fileId) {
  const res = await driveDownloadResponse(env, fileId);
  if (!res.ok) return '';
  return (await res.text()).trim();
}

/**
 * Забрать новые ролики из папки Диска в очередь.
 * Рядом с «name.mp4» можно положить «name.txt» — его содержимое станет
 * подписью к посту (так же, как в Meerno).
 */
/**
 * Собрать файлы из папки и её подпапок.
 *
 * Ролики удобно раскладывать по форматам («вопрос из билета», «узнай знак»),
 * поэтому указывать в настройках одну папку, а видео держать во вложенных —
 * нормальный сценарий. Глубина ограничена, чтобы случайно указанный «Мой диск»
 * не превратился в обход всего хранилища.
 */
async function driveCollectVideos(env, folderId, depth = 0, prefix = '') {
  const entries = await driveListFolder(env, folderId);
  let result = entries
    .filter((f) => f.mimeType !== 'application/vnd.google-apps.folder')
    .map((f) => ({ ...f, folderPath: prefix }));

  if (depth < 2) {
    const subfolders = entries.filter((f) => f.mimeType === 'application/vnd.google-apps.folder');
    for (const sub of subfolders) {
      result = result.concat(await driveCollectVideos(env, sub.id, depth + 1, prefix + sub.name + '/'));
    }
  }
  return result;
}

export async function syncAccountVideos(env, account) {
  if (!account.driveFolderId) {
    return { status: 'error', message: 'У аккаунта не указана папка Google Диска' };
  }

  const files = await driveCollectVideos(env, account.driveFolderId);
  const videos = files.filter((f) => VIDEO_EXT.includes(extOf(f.name)));
  const captions = {};
  files
    .filter((f) => extOf(f.name) === 'txt')
    .forEach((f) => { captions[baseName(f.name)] = f.id; });

  videos.sort((a, b) => String(a.name).localeCompare(String(b.name), 'ru', { numeric: true }));

  const posts = await getPosts(env);
  const excluded = await getExcludedVideos(env, account.id);
  const known = new Set(posts.filter((p) => p.accountId === account.id).map((p) => p.driveFileId));
  const checksum = value => /^[a-f0-9]{32}$/.test(value || '') ? value : null;
  const fileHashes = new Map(videos.map(f => [f.id, checksum(f.md5Checksum)]));
  const knownHashes = new Set(posts.filter(p => p.accountId === account.id)
    .map(p => checksum(p.contentMd5) || fileHashes.get(p.driveFileId)).filter(Boolean));
  const stagedIds = new Set();

  let added = 0;
  for (const file of videos) {
    const contentMd5 = checksum(file.md5Checksum);
    if (known.has(file.id) || stagedIds.has(file.id) || excluded.has(file.id) || (contentMd5 && knownHashes.has(contentMd5))) continue;
    stagedIds.add(file.id);
    if (contentMd5) knownHashes.add(contentMd5);

    const name = baseName(file.name);
    let caption = '';
    if (captions[name]) {
      caption = await driveReadText(env, captions[name]);
    }
    if (!caption) {
      caption = String(account.captionTemplate || '').replace(/\{title\}/g, humanTitle(file.name));
    }

    const humanName = humanTitle(file.name);
    const title = String(account.titleTemplate || '{title}').replace(/\{title\}/g, humanName) || humanName;

    posts.push({
      id: newId('sp'),
      accountId: account.id,
      driveFileId: file.id,
      fileName: file.name,
      sizeBytes: file.size ? parseInt(file.size, 10) : null,
      ...(contentMd5 ? { contentMd5 } : {}),
      title,
      caption,
      streamToken: randomToken(),
      targets: Array.isArray(account.targets) ? [...account.targets] : ['instagram', 'youtube'],
      status: 'queued',
      instagramStatus: 'queued',
      youtubeStatus: 'queued',
      instagramMediaId: null,
      instagramPermalink: null,
      youtubeVideoId: null,
      youtubePermalink: null,
      error: null,
      scheduledAt: null,
      createdAt: new Date().toISOString(),
      publishedAt: null,
    });
    added += 1;
  }

  if (added) {
    // Downloads can take time. Merge into fresh state and recheck exclusions so
    // an import cannot restore a just-deleted post or overwrite another edit.
    const latest = await getPosts(env);
    const latestExcluded = await getExcludedVideos(env, account.id);
    const latestKnown = new Set(latest.filter(p => p.accountId === account.id).map(p => p.driveFileId));
    const latestHashes = new Set(latest.filter(p => p.accountId === account.id)
      .map(p => checksum(p.contentMd5) || fileHashes.get(p.driveFileId)).filter(Boolean));
    const imported = posts.filter(p => p.accountId === account.id && !known.has(p.driveFileId)
      && !latestKnown.has(p.driveFileId) && !latestExcluded.has(p.driveFileId)
      && !(p.contentMd5 && latestHashes.has(p.contentMd5)));
    added = imported.length;
    if (added) await kvPut(env, KV_POSTS, [...latest, ...imported]);
    await socialLog(env, 'info', `Синхронизация «${account.name}»: добавлено роликов — ${added}`);
  }

  return { status: 'ok', added, seen: videos.length };
}

// ────────────────────────────── Instagram ──────────────────────────────

function validInstagramCooldown(value, now = Date.now()) {
  return value?.reason === 'rate_limit' && Number.isSafeInteger(value.until)
    && value.until > now && value.until <= now + IG_MAX_COOLDOWN_MS ? value : null;
}

async function getInstagramCooldown(env) {
  const memory = validInstagramCooldown(instagramCooldownMemory.get(env.INSTALLS));
  let stored = null;
  try {
    const raw = await env.INSTALLS.get(KV_INSTAGRAM_COOLDOWN);
    try { stored = validInstagramCooldown(JSON.parse(raw)); } catch (_) {}
  } catch (_) {
    return memory || { until: Date.now() + 60000, reason: 'read_unavailable' };
  }
  const current = stored && (!memory || stored.until >= memory.until) ? stored : memory;
  if (current) instagramCooldownMemory.set(env.INSTALLS, current);
  return current;
}

function instagramRateLimitError(response, data) {
  if (response.status !== 429 && data?.error?.code !== 4) return null;
  const parts = ['HTTP ' + response.status];
  if (Number.isInteger(data?.error?.code)) parts.push('code ' + data.error.code);
  if (Number.isInteger(data?.error?.error_subcode)) parts.push('subcode ' + data.error.error_subcode);
  const error = new Error('Instagram временно ограничил запросы (' + parts.join(', ') + ')');
  error.code = 'ERR_IG_RATE_LIMITED';
  const retryAfter = response.headers?.get('retry-after')?.trim();
  let retryMs = 0;
  if (retryAfter && /^[0-9]+$/.test(retryAfter)) retryMs = Number(retryAfter) * 1000;
  else if (retryAfter && new Date(retryAfter).toUTCString() === retryAfter) retryMs = Date.parse(retryAfter) - Date.now();
  error.instagramCooldownMs = Number.isFinite(retryMs) && retryMs > 0
    ? Math.max(IG_COOLDOWN_MS, Math.min(retryMs, IG_MAX_COOLDOWN_MS)) : IG_COOLDOWN_MS;
  return error;
}

async function startInstagramCooldown(env, error) {
  const existing = await getInstagramCooldown(env);
  const current = { until: Math.max(existing?.until || 0, Date.now() + error.instagramCooldownMs), reason: 'rate_limit' };
  // Keep a bounded local fallback if KV is temporarily unavailable. Only public
  // rate-limit timing is held in memory; no request or credential is retained.
  instagramCooldownMemory.set(env.INSTALLS, current);
  try { await kvPut(env, KV_INSTAGRAM_COOLDOWN, current); }
  catch (_) { console.warn(JSON.stringify({ event: 'instagram_cooldown_unavailable', code: 'cache_write_failed' })); }
  return { ...current, first: !existing };
}

function onlyInstagramPending(post, defaultTargets = ['instagram', 'youtube']) {
  const targets = Array.isArray(post.targets) && post.targets.length ? post.targets : defaultTargets;
  return targets.includes('instagram') && post.instagramStatus !== 'published'
    && (!targets.includes('youtube') || post.youtubeStatus === 'published');
}

function instagramCooldownResult(cooldown) {
  return { ok: false, status: 'pending', code: 'instagram_rate_limited',
    retryAt: new Date(cooldown.until).toISOString(),
    message: cooldown.reason === 'read_unavailable'
      ? 'Instagram временно недоступен для проверки. Попробуйте позже.'
      : 'Instagram ограничил запросы. Публикация временно на паузе; попробуйте позже.' };
}

function instagramFailure(message) {
  const error = new Error(message);
  error.instagramSafeMessage = true;
  return error;
}

async function igRequest(url, form) {
  let res;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(form),
      signal: AbortSignal.timeout(20000),
    });
  } catch (_) { throw instagramFailure('Instagram не подтвердил ответ на запись. Необходимо проверить сохранённую попытку'); }
  const data = await res.json().catch(() => ({}));
  const rateLimit = instagramRateLimitError(res, data);
  if (rateLimit) throw rateLimit;
  return { ok: res.ok, status: res.status, data };
}

/**
 * Узнать ID аккаунта по токену.
 *
 * В кабинете Meta этот номер лежит не рядом с кнопкой «сгенерировать токен», и
 * искать его вручную — лишний повод ошибиться. Раз токен уже есть, спрашиваем
 * ID у самой Meta.
 */
async function resolveInstagramAccountId(token) {
  const res = await fetch(
    `https://graph.instagram.com/${GRAPH_VERSION}/me?fields=user_id,username&access_token=` +
    encodeURIComponent(token)
  );
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw instagramFailure(limit(data?.error?.message || 'Instagram не принял токен (HTTP ' + res.status + ')', 200));
  }
  return { id: data.user_id ? String(data.user_id) : null, username: data.username || null };
}

function instagramPublicationUnconfirmed(reason) {
  const error = new Error('Meta считает загрузку опубликованной, но доступность ролика не подтверждена. Нужна проверка перед новой публикацией.');
  error.code = 'ERR_IG_PUBLICATION_UNCONFIRMED';
  error.instagramReviewReason = reason;
  return error;
}

function instagramPublicationCheckUnavailable(details = '') {
  const error = new Error('Instagram временно не дал проверить доступность опубликованного ролика' + details);
  error.code = 'ERR_IG_PUBLICATION_CHECK_UNAVAILABLE';
  return error;
}

function isInstagramPermalink(value) {
  if (typeof value !== 'string') return false;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && ['instagram.com', 'www.instagram.com'].includes(url.hostname)
      && !url.username && !url.password && !url.port && !url.search && !url.hash
      && /^\/(?:reel|p|tv)\/[A-Za-z0-9_-]+\/?$/.test(url.pathname);
  } catch (_) {
    return false;
  }
}

async function verifyPublishedInstagramMedia(env, post, account, api, statusDetails) {
  // The post can have changed while Meta processed the request. Verify only the
  // freshly stored media identity and never derive a media ID from a container.
  let raw;
  try { raw = await env.INSTALLS.get(KV_POSTS); }
  catch (_) { throw instagramPublicationCheckUnavailable(); }
  let posts;
  try { posts = JSON.parse(raw); }
  catch (_) { throw instagramPublicationUnconfirmed('media_unconfirmed'); }
  const current = Array.isArray(posts) ? posts.find(p => p.id === post.id) : null;
  const mediaId = current?.instagramMediaId;
  if (typeof mediaId !== 'string' || !/^[0-9]{1,32}$/.test(mediaId)) {
    throw instagramPublicationUnconfirmed('media_unconfirmed');
  }

  let response;
  try {
    response = await fetch(`${api}/${mediaId}?fields=id,permalink&access_token=${encodeURIComponent(account.instagramToken)}`, {
      signal: AbortSignal.timeout(10000),
    });
  } catch (_) {
    throw instagramPublicationCheckUnavailable();
  }
  let data = null;
  let bodyError = null;
  try { data = await response.json(); }
  catch (error) { bodyError = error; }
  const rateLimit = instagramRateLimitError(response, data);
  if (rateLimit) throw rateLimit;
  if (response.status === 429 || response.status >= 500) {
    throw instagramPublicationCheckUnavailable(statusDetails(response, data));
  }
  if (bodyError) {
    if (['AbortError', 'TimeoutError', 'TypeError'].includes(bodyError.name)) {
      throw instagramPublicationCheckUnavailable();
    }
    throw instagramPublicationUnconfirmed('media_unconfirmed');
  }
  if (!response.ok || data?.error) {
    const missing = response.status === 400 && data?.error?.code === 100 && data?.error?.error_subcode === 33;
    throw instagramPublicationUnconfirmed(missing ? 'media_unavailable' : 'media_unconfirmed');
  }
  if (data?.id !== mediaId || !isInstagramPermalink(data?.permalink)) {
    throw instagramPublicationUnconfirmed('media_unconfirmed');
  }
  return { alreadyPublished: true };
}

async function publishToInstagram(env, post, account, origin) {
  if (!account.instagramToken || !account.instagramAccountId) {
    throw instagramFailure('Не заполнены Instagram Account ID или токен доступа');
  }

  const api = `https://graph.instagram.com/${GRAPH_VERSION}`;
  const videoUrl = `${origin}/s/v/${post.streamToken}`;
  const form = {
    media_type: 'REELS',
    video_url: videoUrl,
    caption: post.caption || '',
    share_to_feed: 'true',
    access_token: account.instagramToken,
  };

  // The configured ID is resolved from the token's user_id. A failed or
  // ambiguous write is not replayed against a second endpoint.
  const write = await beginSocialWrite(env, post, 'instagram');
  if (write.result?.state === 'done') {
    await patchPost(env, post.id, { instagramContainerId: write.result.id });
    return finishInstagram(env, post, account, write.result.id);
  }
  let created;
  try { created = await igRequest(`${api}/${account.instagramAccountId}/media`, form); }
  catch (error) {
    // An explicit rate-limit rejection has no accepted upload. A network error
    // or 5xx is ambiguous and must retain the durable intent.
    if (error.code === 'ERR_IG_RATE_LIMITED') await abandonSocialWrite(env, post, write);
    throw error;
  }
  if (!created.ok || !created.data.id) {
    if (created.status >= 400 && created.status < 500 && created.status !== 408) await abandonSocialWrite(env, post, write);
    throw instagramFailure(
      'Instagram не принял видео (HTTP ' + created.status + ')'
    );
  }

  const containerId = created.data.id;
  await completeSocialWrite(env, post, write, containerId);
  // Cloudflare может оборвать фоновую задачу в любой момент — тогда контейнер
  // уже создан, и повтор обязан продолжить с него, а не залить второй раз.
  await patchPost(env, post.id, { instagramContainerId: containerId });

  return await finishInstagram(env, post, account, containerId);
}

/**
 * Дождаться готовности контейнера и опубликовать его.
 * Вынесено отдельно, чтобы повтор мог продолжить уже начатую публикацию.
 */
async function finishInstagram(env, post, account, containerId) {
  const api = `https://graph.instagram.com/${GRAPH_VERSION}`;

  // Meta errors may contain the private video URL. Keep only bounded technical
  // details in the post and social log, never the upstream error text.
  const statusDetails = (response, data) => {
    const parts = ['HTTP ' + response.status];
    if (Number.isInteger(data?.error?.code)) parts.push('code ' + data.error.code);
    if (Number.isInteger(data?.error?.error_subcode)) parts.push('subcode ' + data.error.error_subcode);
    return ' (' + parts.join(', ') + ')';
  };

  // Meta кодирует ролик у себя и параллельно скачивает его по нашей ссылке.
  let ready = false;
  for (let i = 0; i < IG_POLL_ATTEMPTS; i += 1) {
    if (i > 0) await sleep(IG_POLL_INTERVAL_MS);
    let statusRes;
    try {
      statusRes = await fetch(`${api}/${containerId}?fields=status_code,status&access_token=${encodeURIComponent(account.instagramToken)}`,
        { signal: AbortSignal.timeout(10000) });
    } catch (_) { throw instagramPublicationCheckUnavailable(); }
    const statusData = await statusRes.json().catch(() => null);
    const rateLimit = instagramRateLimitError(statusRes, statusData);
    if (rateLimit) throw rateLimit;
    if (!statusRes.ok || statusData?.error) {
      throw instagramFailure('Instagram не дал проверить статус видео' + statusDetails(statusRes, statusData));
    }
    const code = statusData?.status_code;
    if (code === 'PUBLISHED') {
      // PUBLISHED describes the container's history, not the current visibility
      // of a deleted or inaccessible media object. Reconcile with read-only API
      // checks; an unresolved identity must never trigger a replacement upload.
      return await verifyPublishedInstagramMedia(env, post, account, api, statusDetails);
    }
    if (code === 'FINISHED') { ready = true; break; }
    if (code === 'ERROR') {
      throw instagramFailure('Instagram не смог обработать видео' + statusDetails(statusRes, statusData));
    }
    if (code === 'EXPIRED') {
      throw instagramFailure('Контейнер Instagram истёк и не может быть опубликован' + statusDetails(statusRes, statusData));
    }
    if (code !== 'IN_PROGRESS') {
      throw instagramFailure('Instagram вернул неизвестный статус видео' + statusDetails(statusRes, statusData));
    }
  }
  if (!ready) {
    const pending = new Error('Instagram продолжает обработку видео');
    pending.code = 'ERR_IG_PROCESSING';
    throw pending;
  }

  const publishForm = { creation_id: containerId, access_token: account.instagramToken };
  const current = (await getPosts(env)).find(p => p.id === post.id);
  if (!current || current.instagramContainerId !== containerId
    || (current.driveFileId && (await getExcludedVideos(env, current.accountId)).has(current.driveFileId))) {
    throw instagramFailure('Публикация отменена или изменена в очереди');
  }
  const published = await igRequest(`${api}/${account.instagramAccountId}/media_publish`, publishForm);
  if (!published.ok || !published.data.id) {
    throw instagramFailure(
      'Ошибка публикации в Instagram (HTTP ' + published.status + ')'
    );
  }

  const mediaId = published.data.id;
  // Save the successful publish response before another network request. A
  // resumed PUBLISHED container can then verify its media even after a reset.
  await patchPost(env, post.id, { instagramMediaId: mediaId });
  let permalink = null;
  try {
    const details = await fetch(
      `${api}/${mediaId}?fields=permalink&access_token=${encodeURIComponent(account.instagramToken)}`
    );
    const detailsData = await details.json().catch(() => ({}));
    const rateLimit = instagramRateLimitError(details, detailsData);
    if (rateLimit) await startInstagramCooldown(env, rateLimit);
    else permalink = isInstagramPermalink(detailsData?.permalink) ? detailsData.permalink : null;
  } catch (_) { /* ссылка не обязательна */ }

  return { mediaId, permalink };
}

function instagramReplacementError(message) {
  const error = new Error(message);
  error.code = 'ERR_IG_REPLACEMENT_CHECK';
  return error;
}

/** An explicit replacement is separate from retrying the same container. */
async function prepareInstagramReplacement(env, postId, origin, notify) {
  const post = (await getPosts(env)).find(p => p.id === postId);
  if (!post || post.status === 'processing' || post.instagramNeedsReview !== true) {
    throw instagramReplacementError('Сначала обновите состояние ролика: новая публикация сейчас не разрешена');
  }
  if (post.driveFileId && (await getExcludedVideos(env, post.accountId)).has(post.driveFileId)) throw instagramReplacementError('Ролик исключён из очереди');
  if (post.instagramPreviousAttempts != null && !Array.isArray(post.instagramPreviousAttempts)) throw instagramReplacementError('История попыток повреждена. Новая загрузка остановлена');
  if (post.instagramReplacementAttempt && post.instagramReplacementAttempt.stage !== 'published') {
    throw instagramReplacementError('Новая попытка уже сохранена. Повторная загрузка остановлена до проверки её результата');
  }
  if (!/^[0-9]{1,32}$/.test(post.instagramContainerId || '') || !/^[0-9]{1,32}$/.test(post.instagramMediaId || '')) {
    throw instagramReplacementError('Не сохранены данные прежней публикации. Нужна проверка Instagram перед новой загрузкой');
  }
  const account = (await getAccounts(env)).find(a => a.id === post.accountId);
  const targets = post.targets || account?.targets || [];
  if (!account?.instagramToken || !account.instagramAccountId || !targets.includes('instagram')) {
    throw instagramReplacementError('Instagram не настроен для этого ролика');
  }
  const api = `https://graph.instagram.com/${GRAPH_VERSION}`;
  const read = async path => {
    let response, data;
    try {
      response = await fetch(`${api}/${path}`, { headers: { authorization: 'Bearer ' + account.instagramToken }, signal: AbortSignal.timeout(10000) });
      data = await response.json();
    } catch (_) { throw instagramReplacementError('Instagram временно не дал проверить прежнюю публикацию. Новая загрузка не начата'); }
    const rateLimit = instagramRateLimitError(response, data);
    if (rateLimit) throw rateLimit;
    return { response, data };
  };
  const identity = await read('me?fields=user_id,username');
  if (!identity.response.ok || identity.data?.error || String(identity.data?.user_id) !== String(account.instagramAccountId)) {
    throw instagramReplacementError('Не удалось подтвердить аккаунт Instagram. Новая загрузка не начата');
  }
  const container = await read(post.instagramContainerId + '?fields=status_code');
  if (!container.response.ok || container.data?.error || container.data?.status_code !== 'PUBLISHED') {
    throw instagramReplacementError('Прежняя загрузка ещё не подтверждена как опубликованная. Новая загрузка не начата');
  }
  const media = await read(post.instagramMediaId + '?fields=id,permalink');
  const fresh = (await getPosts(env)).find(p => p.id === postId);
  const binding = p => JSON.stringify(['accountId', 'driveFileId', 'streamToken', 'caption', 'targets',
    'instagramContainerId', 'instagramMediaId', 'instagramPermalink', 'instagramReplacementAttempt', 'instagramPreviousAttempts'].map(k => p[k] ?? null));
  if (!fresh || fresh.status === 'processing' || fresh.instagramNeedsReview !== true || binding(fresh) !== binding(post)) {
    throw instagramReplacementError('Ролик изменился во время проверки. Обновите очередь');
  }
  if (media.response.ok && !media.data?.error && media.data?.id === post.instagramMediaId && isInstagramPermalink(media.data?.permalink)) {
    await patchPost(env, postId, { instagramStatus: 'published', instagramNeedsReview: false, instagramReviewReason: null,
      ...(fresh.youtubeStatus === 'published' || !targets.includes('youtube') ? { status: 'published', error: null } : {}) });
    return { response: { ok: true, message: 'Прежняя публикация доступна. Новую запись не создавал' } };
  }
  if (!(media.response.status === 400 && media.data?.error?.code === 100 && media.data.error.error_subcode === 33)) {
    throw instagramReplacementError('Instagram не подтвердил отсутствие прежнего ролика. Новая загрузка не начата');
  }
  const attempt = { id: crypto.randomUUID(), sourceContainerId: post.instagramContainerId, stage: 'create_started', startedAt: new Date().toISOString() };
  await patchPost(env, postId, { status: 'processing', instagramStatus: 'processing', instagramNeedsReview: true,
    instagramReviewReason: 'replacement_in_progress', instagramReplacementAttempt: attempt,
    processingSince: attempt.startedAt, publishMode: 'manual', error: null });
  const run = () => withSocialPublicationLease(env, post.accountId, async env => {
    try {
      const claimed = (await getPosts(env)).find(p => p.id === postId);
      if (!claimed || claimed.instagramReplacementAttempt?.id !== attempt.id) return;
      if (claimed.caption !== post.caption || claimed.streamToken !== post.streamToken || claimed.accountId !== post.accountId
        || (claimed.driveFileId && (await getExcludedVideos(env, claimed.accountId)).has(claimed.driveFileId))) {
        throw instagramReplacementError('Ролик изменился или исключён из очереди. Новая загрузка остановлена');
      }
      // One create request, no /me fallback or blind retry after a lost response.
      const replacementPost = { ...post, instagramReplacementAttempt: attempt };
      const write = await beginSocialWrite(env, replacementPost, 'instagram');
      const created = write.result?.state === 'done' ? { ok: true, data: { id: write.result.id } } : await igRequest(`${api}/${account.instagramAccountId}/media`, {
        media_type: 'REELS', video_url: `${origin}/s/v/${post.streamToken}`,
        caption: post.caption || '', share_to_feed: 'true', access_token: account.instagramToken,
      });
      if (!created.ok || !/^[0-9]{1,32}$/.test(created.data?.id || '')) {
        throw instagramReplacementError('Instagram не подтвердил новую загрузку. Повтор остановлен до проверки результата');
      }
      if (write.result?.state !== 'done') await completeSocialWrite(env, replacementPost, write, created.data.id);
      const current = (await getPosts(env)).find(p => p.id === postId);
      if (!current || current.instagramReplacementAttempt?.id !== attempt.id) return;
      const previous = { containerId: post.instagramContainerId, mediaId: post.instagramMediaId,
        permalink: post.instagramPermalink || null, recordedAt: attempt.startedAt, reason: 'media_unavailable' };
      await patchPost(env, postId, { instagramContainerId: created.data.id, instagramMediaId: null, instagramPermalink: null,
        instagramPreviousAttempts: [...(Array.isArray(current.instagramPreviousAttempts) ? current.instagramPreviousAttempts : []), previous],
        instagramReplacementAttempt: { ...attempt, stage: 'container_saved' }, instagramNeedsReview: false, instagramReviewReason: null });
      // Only Instagram; a successful YouTube publication is never replayed.
      await publishPost(env, postId, origin, notify, ['instagram']);
    } catch (error) {
      if (error.code === 'ERR_IG_RATE_LIMITED') await startInstagramCooldown(env, error);
      const current = (await getPosts(env)).find(p => p.id === postId);
      if (!current || current.instagramReplacementAttempt?.id !== attempt.id) return;
      const message = error.code === 'ERR_IG_RATE_LIMITED' ? error.message
        : 'Новая публикация Instagram не подтверждена. Сохранённая попытка требует проверки; повторная загрузка остановлена';
      await patchPost(env, postId, { status: 'failed', instagramStatus: 'failed', instagramNeedsReview: true,
        instagramReviewReason: 'replacement_unconfirmed', error: message });
      await socialLog(env, 'error', message);
      if (notify) { try { await notifySocialFailure(notify, post.accountId, 'instagram.replacement_unconfirmed', '⚠️ Новая публикация Instagram не подтверждена. Проверьте сохранённую попытку в админке.'); } catch (_) {} }
    }
  });
  return { response: { ok: true, message: 'Создаю новую публикацию только в Instagram' }, run };
}

/**
 * Продлить долгоживущий токен Instagram.
 *
 * Такой токен живёт 60 дней и продлевается запросом к самому Meta — иначе
 * автопостинг однажды просто перестал бы публиковать, а причину пришлось бы
 * искать в логе. Обновляем раз в 30 дней: Meta не продлевает токен моложе
 * суток, а запас в месяц переживает любые паузы в работе крона.
 */
export async function refreshInstagramTokens(env) {
  if (await getInstagramCooldown(env)) return;
  const accounts = await getAccounts(env);
  const monthAgo = Date.now() - 30 * 24 * 3600 * 1000;
  let changed = false;

  for (let i = 0; i < accounts.length; i += 1) {
    const account = accounts[i];
    if (!account.active || !account.instagramToken) continue;
    if (!(account.targets || []).includes('instagram')) continue;

    const updatedAt = account.instagramTokenUpdatedAt ? Date.parse(account.instagramTokenUpdatedAt) : 0;
    if (updatedAt && updatedAt > monthAgo) continue;

    try {
      const res = await fetch(
        'https://graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token&access_token=' +
        encodeURIComponent(account.instagramToken)
      );
      const data = await res.json().catch(() => ({}));
      const rateLimit = instagramRateLimitError(res, data);
      if (rateLimit) {
        const cooldown = await startInstagramCooldown(env, rateLimit);
        if (cooldown.first) await socialLog(env, 'error', rateLimit.message);
        break;
      }
      if (res.ok && data.access_token) {
        accounts[i] = {
          ...account,
          instagramToken: data.access_token,
          instagramTokenUpdatedAt: new Date().toISOString(),
        };
        changed = true;
        await socialLog(env, 'info', `Instagram: токен «${account.name}» продлён ещё на 60 дней`);
      } else {
        await socialLog(env, 'error',
          `Instagram: не удалось продлить токен «${account.name}» — ` +
          limit(data?.error?.message || 'HTTP ' + res.status, 200));
      }
    } catch (e) {
      await socialLog(env, 'error', `Instagram: продление токена «${account.name}» — ${e.message}`);
    }
  }

  if (changed) await kvPut(env, KV_ACCOUNTS, accounts);
}

// ────────────────────────────── YouTube ──────────────────────────────

function buildYoutubeTitle(post) {
  const raw = post.title || humanTitle(post.fileName);
  if (raw.toLowerCase().includes('#shorts')) return limit(raw, 100);
  return limit(raw, 90).trim() + ' #shorts';
}

async function publishToYouTube(env, post, account) {
  // Check the durable outcome before downloading/uploading anything.
  // Reserve immediately before sending bytes; session initialization is safe.
  const saved = await beginSocialWrite(env, post, 'youtube', false);
  if (saved.result?.state === 'done') return {
    videoId: saved.result.id, permalink: 'https://youtube.com/shorts/' + saved.result.id,
  };
  if (post.youtubeNeedsReview) {
    const error = new Error('Предыдущая загрузка YouTube требует проверки. Повторная отправка остановлена');
    error.code = 'ERR_YT_PUBLICATION_UNCONFIRMED';
    throw error;
  }
  const accessToken = await googleAccessToken(env, account.youtubeRefreshToken || null);

  const videoRes = await driveDownloadResponse(env, post.driveFileId);
  if (!videoRes.ok) {
    throw new Error('Не удалось скачать ролик с Google Диска (HTTP ' + videoRes.status + ')');
  }
  const bytes = await videoRes.arrayBuffer();
  if (bytes.byteLength < 1000) {
    throw new Error('С Google Диска пришёл пустой файл');
  }
  if (bytes.byteLength > MAX_UPLOAD_BYTES) {
    throw new Error(
      'Ролик весит ' + Math.round(bytes.byteLength / 1048576) + ' МБ — больше лимита заливки ' +
      Math.round(MAX_UPLOAD_BYTES / 1048576) + ' МБ. Сожми видео и положи на Диск заново.'
    );
  }

  const tags = String(account.youtubeTags || '')
    .split(',').map((t) => t.trim()).filter(Boolean);

  const initRes = await fetch(
    'https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status',
    {
      method: 'POST',
      headers: {
        authorization: 'Bearer ' + accessToken,
        'content-type': 'application/json; charset=UTF-8',
        'x-upload-content-length': String(bytes.byteLength),
        'x-upload-content-type': 'video/mp4',
      },
      body: JSON.stringify({
        snippet: {
          title: buildYoutubeTitle(post),
          description: limit(post.caption || '', 4900),
          tags,
          categoryId: account.youtubeCategoryId || '27',
        },
        status: {
          privacyStatus: account.youtubePrivacy || 'public',
          selfDeclaredMadeForKids: false,
        },
      }),
    }
  );

  if (!initRes.ok) {
    const body = await initRes.text();
    throw new Error('YouTube не открыл загрузку (HTTP ' + initRes.status + '): ' + limit(body, 300));
  }

  const uploadUrl = initRes.headers.get('location');
  if (!uploadUrl) {
    throw new Error('YouTube не вернул адрес загрузки');
  }

  const write = await beginSocialWrite(env, post, 'youtube');
  if (write.result?.state === 'done') return {
    videoId: write.result.id, permalink: 'https://youtube.com/shorts/' + write.result.id,
  };
  await patchPost(env, post.id, { youtubeNeedsReview: true });

  // Заливку не повторяем: если YouTube принял ролик, а ответ потерялся,
  // повтор создал бы дубль на канале.
  const uploadRes = await fetch(uploadUrl, {
    method: 'PUT',
    headers: { 'content-type': 'video/mp4' },
    body: bytes,
  });

  const uploadData = await uploadRes.json().catch(() => ({}));
  if (!uploadRes.ok || !uploadData.id) {
    throw new Error(
      'YouTube не принял файл (HTTP ' + uploadRes.status + '): ' +
      limit(uploadData?.error?.message || JSON.stringify(uploadData), 300)
    );
  }

  await completeSocialWrite(env, post, write, uploadData.id);

  return {
    videoId: uploadData.id,
    permalink: 'https://youtube.com/shorts/' + uploadData.id,
  };
}

/** Explicitly replace an unavailable YouTube video, retaining the old identity. */
async function replaceYoutube(env, postId, origin, notify) {
  return withSocialPublicationLease(env, (await getPosts(env)).find(p => p.id === postId)?.accountId, async env => {
    const post = (await getPosts(env)).find(p => p.id === postId);
    if (!post || post.status === 'processing') return;
    const account = (await getAccounts(env)).find(a => a.id === post.accountId);
    const fail = message => { const error = new Error(message); error.youtubeSafeMessage = true; throw error; };
    try {
      if (!account || !(post.targets || account.targets || []).includes('youtube')) fail('YouTube не настроен для этого ролика');
      if (!/^[A-Za-z0-9_-]{11}$/.test(post.youtubeVideoId || '')) fail('Не сохранён ID прежнего ролика YouTube. Нужна ручная проверка');
      if (post.youtubeReplacementAttempt && post.youtubeReplacementAttempt.stage !== 'published') fail('Новая попытка YouTube уже сохранена. Сначала проверьте её результат');
      if (post.youtubePreviousAttempts != null && !Array.isArray(post.youtubePreviousAttempts)) fail('История YouTube повреждена');
      if (post.driveFileId && (await getExcludedVideos(env, post.accountId)).has(post.driveFileId)) fail('Ролик исключён из очереди');
      const token = await googleAccessToken(env, account.youtubeRefreshToken || null);
      const read = async path => {
        const res = await fetch('https://www.googleapis.com/youtube/v3/' + path, {
          headers: { authorization: 'Bearer ' + token }, signal: AbortSignal.timeout(10000),
        });
        const data = await res.json();
        if (!res.ok || data.error || !Array.isArray(data.items)) fail('YouTube не дал проверить прежнюю публикацию. Новая загрузка не начата');
        return data.items;
      };
      const channels = await read('channels?part=id&mine=true');
      if (channels.length !== 1 || !channels[0].id) fail('Не удалось подтвердить канал YouTube');
      const videos = await read('videos?part=status,snippet&id=' + encodeURIComponent(post.youtubeVideoId));
      const fresh = (await getPosts(env)).find(p => p.id === postId);
      if (!fresh || JSON.stringify(fresh) !== JSON.stringify(post)) fail('Ролик изменился во время проверки. Обновите очередь');
      if (videos.length) {
        const video = videos[0];
        if (video.id !== post.youtubeVideoId || video.snippet?.channelId !== channels[0].id) fail('Не удалось подтвердить владельца прежнего ролика');
        if (video.status?.uploadStatus !== 'processed' || !['public', 'unlisted'].includes(video.status?.privacyStatus)) fail('Прежний ролик существует, но недоступен для просмотра. Проверьте его в YouTube Studio');
        await patchPost(env, postId, { youtubeStatus: 'published', youtubeNeedsReview: false,
          ...(!((post.targets || account.targets || []).includes('instagram')) || post.instagramStatus === 'published'
            ? { status: 'published', error: null } : {}) });
        return;
      }
      // A successful authenticated read returned no video. Only this explicit
      // action may start a new generation; ordinary retries retain durable IDs.
      const attempt = { id: crypto.randomUUID(), sourceVideoId: post.youtubeVideoId, stage: 'started', startedAt: new Date().toISOString() };
      await patchPost(env, postId, { youtubePreviousAttempts: [...(post.youtubePreviousAttempts || []), {
        videoId: post.youtubeVideoId, permalink: post.youtubePermalink || null, recordedAt: attempt.startedAt,
      }], youtubeReplacementAttempt: attempt, youtubeVideoId: null, youtubePermalink: null,
        youtubeNeedsReview: false, youtubeStatus: 'queued', status: 'processing', error: null,
        processingSince: attempt.startedAt, publishMode: 'manual' });
      await publishPost(env, postId, origin, notify, ['youtube']);
    } catch (error) {
      // Do not expose OAuth or upstream responses in the admin log.
      await patchPost(env, postId, { status: 'failed', youtubeNeedsReview: true,
        error: error.youtubeSafeMessage ? 'YouTube: ' + error.message : 'YouTube: не удалось подтвердить или заменить прежнюю публикацию. Проверьте доступ и состояние ролика; новая попытка автоматически не повторяется' });
    }
  });
}

// ────────────────────────────── публикация ──────────────────────────────

/**
 * Опубликовать ролик на выбранных площадках.
 *
 * Площадку, куда ролик уже ушёл, пропускаем — поэтому «Повторить» после
 * частичной ошибки дозаливает только недостающее, а не дублирует пост.
 */
/**
 * @param {string[]} only Площадки, которые нужно обработать в этот заход.
 *                        Пустой список = все, куда ролик ещё не ушёл.
 */
export async function publishPost(env, postId, origin, notify = null, only = ['instagram', 'youtube']) {
  const post = (await getPosts(env)).find(p => p.id === postId);
  if (!post) return { status: 'error', message: 'Ролик не найден' };
  return withSocialPublicationLease(env, post.accountId,
    ownedEnv => publishPostWithLease(ownedEnv, postId, origin, notify, only));
}

async function publishPostWithLease(env, postId, origin, notify, only) {
  const posts = await getPosts(env);
  const post = posts.find((p) => p.id === postId);
  if (!post) return { status: 'error', message: 'Ролик не найден' };
  if (post.driveFileId && (await getExcludedVideos(env, post.accountId)).has(post.driveFileId)) return { status: 'error', message: 'Ролик исключён из очереди' };
  if (post.instagramNeedsReview === true && only.includes('instagram')) return { status: 'error', message: post.error || 'Публикация Instagram требует проверки' };

  const accounts = await getAccounts(env);
  const account = accounts.find((a) => a.id === post.accountId);
  if (!account) {
    await patchPost(env, postId, { status: 'failed', error: 'Аккаунт удалён' });
    return { status: 'error', message: 'Аккаунт удалён' };
  }

  const targets = Array.isArray(post.targets) && post.targets.length
    ? post.targets
    : (account.targets || ['instagram', 'youtube']);

  const errors = [];
  let notifyFailure = true;
  let igResult = null;
  let ytResult = null;
  let instagramProcessing = false;
  const igPending = only.includes('instagram') && targets.includes('instagram') && post.instagramStatus !== 'published';
  const cooldown = igPending ? await getInstagramCooldown(env) : null;
  if (cooldown && (!only.includes('youtube') || !targets.includes('youtube') || post.youtubeStatus === 'published')) {
    return instagramCooldownResult(cooldown);
  }

  if (cooldown) {
    errors.push('Instagram: действует временный перерыв после ограничения запросов');
    notifyFailure = false;
  } else if (igPending) {
    try {
      if (post.instagramMediaId && !post.instagramContainerId) throw instagramPublicationUnconfirmed('media_unconfirmed');
      await patchPost(env, postId, { instagramStatus: 'processing' });
      igResult = post.instagramContainerId
        ? await finishInstagram(env, post, account, post.instagramContainerId)
        : await publishToInstagram(env, post, account, origin);
      await patchPost(env, postId, {
        instagramStatus: 'published',
        instagramNeedsReview: false,
        instagramReviewReason: null,
        ...(post.instagramReplacementAttempt ? {
          instagramReplacementAttempt: { ...post.instagramReplacementAttempt, stage: 'published' },
        } : {}),
        // A concurrent attempt can have saved newer metadata. Reconciliation
        // changes only status; never overwrite those fields with an old snapshot.
        ...(!igResult.alreadyPublished ? {
          instagramMediaId: igResult.mediaId,
          instagramPermalink: igResult.permalink,
        } : {}),
      });
      await socialLog(env, 'ok', igResult.alreadyPublished
        ? `Instagram: подтверждена прежняя публикация ${post.fileName}`
        : `Instagram: опубликован ${post.fileName}`, igResult.alreadyPublished ? {} : { url: igResult.permalink });
    } catch (e) {
      if (e.code === 'ERR_IG_PROCESSING') {
        instagramProcessing = true;
        notifyFailure = false;
        await patchPost(env, postId, { instagramStatus: 'processing' });
      } else {
        if (e.code === 'ERR_IG_RATE_LIMITED') notifyFailure = (await startInstagramCooldown(env, e)).first;
        const safeMessage = e.instagramSafeMessage === true || ['ERR_IG_RATE_LIMITED', 'ERR_IG_PUBLICATION_UNCONFIRMED',
          'ERR_IG_PUBLICATION_CHECK_UNAVAILABLE', 'ERR_IG_REPLACEMENT_CHECK'].includes(e.code)
          ? e.message : 'Не удалось завершить публикацию Instagram. Сохранённую попытку необходимо проверить';
        errors.push('Instagram: ' + safeMessage);
        await patchPost(env, postId, {
          instagramStatus: 'failed',
          ...(e.code === 'ERR_IG_PUBLICATION_UNCONFIRMED' ? {
            instagramNeedsReview: true,
            instagramReviewReason: e.instagramReviewReason,
          } : {}),
        });
        await socialLog(env, 'error', `Instagram: ${post.fileName} — ${safeMessage}`);
      }
    }
  }

  if (only.includes('youtube') && targets.includes('youtube') && post.youtubeStatus !== 'published') {
    try {
      if (!(await getPosts(env)).some(p => p.id === postId)) throw new Error('Ролик удалён из очереди');
      if (post.youtubeVideoId) {
        await patchPost(env, postId, { youtubeNeedsReview: true });
        throw new Error('Уже сохранена прежняя публикация YouTube. Проверьте ссылку и статус площадки перед повтором');
      }
      await patchPost(env, postId, { youtubeStatus: 'processing' });
      ytResult = await publishToYouTube(env, post, account);
      await patchPost(env, postId, {
        youtubeStatus: 'published',
        youtubeNeedsReview: false,
        ...(post.youtubeReplacementAttempt ? { youtubeReplacementAttempt: { ...post.youtubeReplacementAttempt, stage: 'published' } } : {}),
        youtubeVideoId: ytResult.videoId,
        youtubePermalink: ytResult.permalink,
      });
      await socialLog(env, 'ok', `YouTube: опубликован ${post.fileName}`, { url: ytResult.permalink });
    } catch (e) {
      notifyFailure = true;
      errors.push('YouTube: ' + e.message);
      await patchPost(env, postId, { youtubeStatus: 'failed',
        ...(e.code === 'ERR_YT_PUBLICATION_UNCONFIRMED' ? { youtubeNeedsReview: true } : {}) });
      await socialLog(env, 'error', `YouTube: ${post.fileName} — ${e.message}`);
    }
  }

  const fresh = (await getPosts(env)).find((p) => p.id === postId) || post;
  const igDone = !targets.includes('instagram') || fresh.instagramStatus === 'published';
  const ytDone = !targets.includes('youtube') || fresh.youtubeStatus === 'published';

  if (igDone && ytDone) {
    await patchPost(env, postId, {
      status: 'published',
      publishedAt: new Date().toISOString(),
      error: null,
    });
    const accountsNow = await getAccounts(env);
    const idx = accountsNow.findIndex((a) => a.id === account.id);
    if (idx !== -1) {
      accountsNow[idx] = {
        ...accountsNow[idx],
        lastPostedAt: new Date().toISOString(),
        lastPostedDay: mskDay(),
      };
      await kvPut(env, KV_ACCOUNTS, accountsNow);
    }
    return { status: 'ok', instagram: igResult, youtube: ytResult };
  }

  if (instagramProcessing && !errors.length) {
    await patchPost(env, postId, { status: 'processing', error: null, processingSince: new Date().toISOString() });
    await socialLog(env, 'info', `Instagram: обработка ${post.fileName} продолжается, загрузка сохранена`);
    return { status: 'processing', message: 'Instagram продолжает обработку видео' };
  }

  const summary = errors.join('; ') || 'Публикация не завершилась';
  await patchPost(env, postId, {
    status: 'failed', error: limit(summary, 500),
    ...(cooldown && fresh.instagramStatus === 'processing' ? { instagramStatus: 'queued' } : {}),
  });

  // Об упавшей автопубликации иначе можно узнать, только открыв админку.
  if (notify && notifyFailure) {
    try {
      await notifySocialFailure(notify, account.id, summary,
        '⚠️ <b>Автопостинг: ролик не опубликован</b>\n' +
        `Аккаунт: ${account.name}\nФайл: ${post.fileName}\nПричина: ${limit(summary, 300)}`
      );
    } catch (_) { /* уведомление не должно ронять публикацию */ }
  }

  return { status: 'error', message: summary };
}

// ────────────────────────────── крон ──────────────────────────────

/**
 * Часовой крон: у каждого активного аккаунта своё время поста (МСК).
 * Публикуем не больше одного ролика в день на аккаунт; окно опоздания — 3 часа,
 * чтобы пропущенный из-за сбоя слот подхватился следующим запуском, а не ночью.
 */
/**
 * Расклинить ролики, зависшие в «публикуется».
 *
 * Публикация идёт фоном на стороне воркера: браузер можно закрыть, это ей не
 * мешает. Но если фоновую задачу оборвёт сам Cloudflare (перезапуск, лимит
 * времени), ролик останется в «публикуется» навсегда: крон такие не берёт, и
 * очередь встанет молча. Через полчаса считаем, что публикация не состоялась,
 * и возвращаем ролик в работу — площадку, куда он уже ушёл, повтор пропустит.
 */
async function recoverStalePosts(env, cooldown = null) {
  const posts = await getPosts(env);
  const cutoff = Date.now() - STALE_PROCESSING_MS;
  let changed = false;

  posts.forEach((post, i) => {
    if (post.status === 'processing' && post.instagramNeedsReview === true
      && post.instagramReplacementAttempt?.stage === 'create_started'
      && Date.parse(post.instagramReplacementAttempt.startedAt) < Date.now() - 60000) {
      posts[i] = { ...post, status: 'failed', instagramStatus: 'failed', instagramReviewReason: 'replacement_unconfirmed',
        error: 'Новая загрузка Instagram прервалась. Повтор остановлен до проверки сохранённой попытки' };
      changed = true;
      return;
    }
    if (post.status !== 'processing' || post.instagramNeedsReview === true || (cooldown && onlyInstagramPending(post))) return;
    const startedAt = Date.parse(post.processingSince || post.createdAt || '') || 0;
    if (startedAt && startedAt > cutoff) return;
    posts[i] = {
      ...post,
      status: 'failed',
      instagramStatus: post.instagramStatus === 'processing' ? 'failed' : post.instagramStatus,
      youtubeStatus: post.youtubeStatus === 'processing' ? 'failed' : post.youtubeStatus,
      error: 'Публикация оборвалась на стороне сервера — ролик снова можно опубликовать',
    };
    changed = true;
  });

  if (changed) {
    await kvPut(env, KV_POSTS, posts);
    await socialLog(env, 'error', 'Зависшие публикации возвращены в работу');
  }
}

/**
 * Доделать публикации, которые оборвались на полпути.
 *
 * Публикация запускается фоновой задачей воркера, а её время жизни Cloudflare
 * может урезать: у Instagram уходит несколько минут только на кодирование.
 * Поэтому каждые пять минут проверяем «зависшие» и продолжаем с того места,
 * где остановились — контейнер Instagram и уже залитое видео не потеряются.
 */
function isScheduledPostDue(post, now = Date.now()) {
  const scheduled = typeof post.scheduledAt === 'string' ? Date.parse(post.scheduledAt) : NaN;
  return Number.isFinite(scheduled) && scheduled <= now;
}

async function resumeInFlight(env, origin, notify, cooldown = null) {
  const posts = await getPosts(env);
  // Только назначенные даты или явный ручной запуск. Старые задачи без даты
  // не должны возобновлять автоматическую публикацию после обновления.
  const stuck = posts.filter((p) => p.status === 'processing' && p.instagramNeedsReview !== true
    && !(cooldown && onlyInstagramPending(p))
    && (isScheduledPostDue(p) || p.publishMode === 'manual'));

  for (const post of stuck) {
    const startedAt = Date.parse(post.processingSince || '') || 0;
    // Совсем свежие не трогаем: скорее всего публикация прямо сейчас идёт.
    if (startedAt && Date.now() - startedAt < 3 * 60 * 1000) continue;
    await socialLog(env, 'info', `Продолжаю публикацию: ${post.fileName}`);
    await publishPost(env, post.id, origin, notify);
  }
}

export async function runAutoPost(env, origin, notify = null) {
  const cooldown = await getInstagramCooldown(env);
  await resumeInFlight(env, origin, notify, cooldown);
  await recoverStalePosts(env, cooldown);
  if (!(await getInstagramCooldown(env))) await refreshInstagramTokens(env);

  const accounts = await getAccounts(env);
  const results = [];

  for (const account of accounts) {
    if (!account.active) continue;

    // Импорт только пополняет очередь. Разрешение на автоматический выпуск —
    // явная дата ролика, назначенная администратором.
    try {
      await syncAccountVideos(env, account);
    } catch (e) {
      await socialLog(env, 'error', `Синхронизация «${account.name}»: ${e.message}`);
    }

    const now = Date.now();
    const posts = await getPosts(env);
    const due = posts
      .filter((p) => p.accountId === account.id && (p.status === 'queued' || p.status === 'failed'))
      .filter((p) => p.instagramNeedsReview !== true)
      .filter((p) => !(cooldown && onlyInstagramPending(p, account.targets)))
      .filter((p) => isScheduledPostDue(p, now))
      .sort((a, b) => {
        if (a.scheduledAt && b.scheduledAt) return a.scheduledAt.localeCompare(b.scheduledAt);
        if (a.scheduledAt) return -1;
        if (b.scheduledAt) return 1;
        return String(a.fileName).localeCompare(String(b.fileName), 'ru', { numeric: true });
      });

    if (!due.length) {
      await socialLog(env, 'info', `«${account.name}»: публиковать нечего`);
      continue;
    }

    // Публикуем по очереди, не параллельно: Instagram кодирует каждый ролик
    // минуты, и параллельные заливки на один аккаунт площадки не любят.
    for (const post of due) {
      // Пока предыдущий ролик кодировался, администратор мог снять или перенести дату.
      const current = (await getPosts(env)).find(p => p.id === post.id);
      if (!current || current.instagramNeedsReview === true || !['queued', 'failed'].includes(current.status) || !isScheduledPostDue(current)) continue;
      if (onlyInstagramPending(current, account.targets) && await getInstagramCooldown(env)) continue;
      await patchPost(env, post.id, { status: 'processing', error: null, processingSince: new Date().toISOString(), publishMode: 'scheduled' });
      const res = await publishPost(env, post.id, origin, notify);
      results.push({ account: account.name, file: post.fileName, ...res });
    }
  }

  return results;
}

// ────────────────────────────── проверка настроек ──────────────────────────────

async function runDiagnostics(env) {
  const checks = [];
  const settings = await getSettings(env);

  if (settings.googleRefreshToken) {
    try {
      await googleAccessToken(env);
      checks.push({ name: 'Google (Диск и YouTube)', ok: true, message: 'полный доступ, токен обновляется' });
    } catch (e) {
      checks.push({ name: 'Google (Диск и YouTube)', ok: false, message: e.message });
    }
  } else if (settings.googleApiKey) {
    checks.push({
      name: 'Google',
      ok: true,
      message: 'только Диск по API-ключу (папка должна быть открыта по ссылке). ' +
               'Для заливки на YouTube нужен Refresh token — без него YouTube отключён.',
    });
  } else {
    checks.push({ name: 'Google', ok: false, message: 'не настроен ни Refresh token, ни API-ключ' });
  }

  const accounts = await getAccounts(env);
  for (const account of accounts) {
    if (account.driveFolderId) {
      try {
        const files = await driveCollectVideos(env, account.driveFolderId);
        const videos = files.filter((f) => VIDEO_EXT.includes(extOf(f.name)));
        checks.push({
          name: `Папка Диска — ${account.name}`,
          ok: true,
          message: `роликов видно: ${videos.length}`,
        });
      } catch (e) {
        checks.push({ name: `Папка Диска — ${account.name}`, ok: false, message: e.message });
      }
    }

    if ((account.targets || []).includes('instagram') || account.instagramToken) {
      if (!account.instagramToken || !account.instagramAccountId) {
        checks.push({ name: `Instagram — ${account.name}`, ok: false, message: 'не заполнены Account ID или токен' });
      } else {
        try {
          const res = await fetch(
            `https://graph.instagram.com/${GRAPH_VERSION}/${account.instagramAccountId}` +
            `?fields=username,account_type&access_token=${encodeURIComponent(account.instagramToken)}`
          );
          const data = await res.json().catch(() => ({}));
          checks.push({
            name: `Instagram — ${account.name}`,
            ok: res.ok && Boolean(data.username),
            message: res.ok ? `аккаунт @${data.username} (${data.account_type || 'тип не указан'})`
                            : limit(data?.error?.message || 'ошибка запроса', 200),
          });
        } catch (e) {
          checks.push({ name: `Instagram — ${account.name}`, ok: false, message: e.message });
        }
      }
    }

    if ((account.targets || []).includes('youtube')) {
      try {
        const token = await googleAccessToken(env, account.youtubeRefreshToken || null);
        const res = await fetch(
          'https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true',
          { headers: { authorization: 'Bearer ' + token } }
        );
        const data = await res.json().catch(() => ({}));
        const channel = (data.items || [])[0];
        checks.push({
          name: `YouTube — ${account.name}`,
          ok: res.ok && Boolean(channel),
          message: channel ? `канал «${channel.snippet.title}»`
                           : limit(data?.error?.message || 'канал не найден — проверь, что доступ выдан нужным Google-аккаунтом', 200),
        });
      } catch (e) {
        checks.push({ name: `YouTube — ${account.name}`, ok: false, message: e.message });
      }
    }
  }

  if (!settings.workerOrigin) {
    checks.push({ name: 'Адрес воркера', ok: false, message: 'откроется автоматически при первой загрузке раздела' });
  }

  return checks;
}

// ────────────────────────────── публичный поток видео ──────────────────────────────

/**
 * Отдать ролик с Диска по одноразовой ссылке — по ней Instagram скачивает
 * видео. Токен случайный и живёт вместе с роликом в очереди, поэтому папка
 * Диска остаётся закрытой.
 */
/**
 * Обложка ролика для админки.
 *
 * Диск сам делает превью видео и отдаёт ссылку на него; ссылка живёт недолго и
 * привязана к доступу, поэтому картинку проксируем через воркер — иначе она бы
 * не открылась в браузере.
 */
export async function handleVideoThumb(env, request, streamToken) {
  const posts = await getPosts(env);
  const post = posts.find((p) => p.streamToken === streamToken);
  if (!post) return new Response('Not found', { status: 404 });

  try {
    const auth = await driveAuth(env);
    let url = 'https://www.googleapis.com/drive/v3/files/' + encodeURIComponent(post.driveFileId) +
              '?fields=thumbnailLink';
    if (auth.mode === 'apikey') url += '&key=' + encodeURIComponent(auth.key);
    const metaRes = await fetch(url, {
      headers: auth.mode === 'oauth' ? { authorization: 'Bearer ' + auth.token } : {},
    });
    const meta = await metaRes.json().catch(() => ({}));
    if (!meta.thumbnailLink) return new Response('No thumbnail', { status: 404 });

    // Просим картинку покрупнее: по умолчанию Диск отдаёт совсем мелкую.
    const imgRes = await fetch(meta.thumbnailLink.replace(/=s\d+$/, '=s400'));
    if (!imgRes.ok) return new Response('Upstream error', { status: 502 });

    return new Response(imgRes.body, {
      status: 200,
      headers: {
        'content-type': imgRes.headers.get('content-type') || 'image/jpeg',
        'cache-control': 'private, max-age=3600',
      },
    });
  } catch (e) {
    return new Response('Error: ' + e.message, { status: 500 });
  }
}

export async function handleVideoStream(env, request, streamToken) {
  const posts = await getPosts(env);
  const post = posts.find((p) => p.streamToken === streamToken);
  if (!post) return new Response('Not found', { status: 404 });

  try {
    const range = request.headers.get('range');
    const driveRes = await driveDownloadResponse(env, post.driveFileId, range);
    if (!driveRes.ok && driveRes.status !== 206) {
      return new Response('Upstream error', { status: 502 });
    }

    const headers = new Headers();
    headers.set('content-type', 'video/mp4');
    headers.set('accept-ranges', 'bytes');
    headers.set('cache-control', 'private, max-age=600');
    ['content-length', 'content-range'].forEach((h) => {
      const value = driveRes.headers.get(h);
      if (value) headers.set(h, value);
    });

    return new Response(request.method === 'HEAD' ? null : driveRes.body, {
      status: driveRes.status,
      headers,
    });
  } catch (e) {
    return new Response('Error: ' + e.message, { status: 500 });
  }
}

// Площадки задаются явно: пустой список не должен превращаться в публикацию везде.
function validTargets(value) {
  if (!Array.isArray(value) || !value.length || value.some(t => !['instagram', 'youtube'].includes(t))) return null;
  return [...new Set(value)];
}

function canChangeTargets(post) {
  return ['queued', 'failed'].includes(post.status)
    && post.instagramStatus !== 'processing' && post.youtubeStatus !== 'processing';
}

// ────────────────────────────── админ-API ──────────────────────────────

/**
 * Роутер раздела «Автопостинг». Возвращает null, если путь не наш —
 * так worker.js остаётся единственным местом, где живёт общая маршрутизация.
 */
export async function handleSocialAdmin(request, env, ctx, url, helpers) {
  const { jsonResponse, notify } = helpers;
  const path = url.pathname.replace(/\/$/, '');
  const origin = url.origin;

  // Адрес воркера нужен крону: у него нет запроса, из которого его взять,
  // а Instagram скачивает видео именно по этой ссылке.
  const settings = await getSettings(env);
  if (settings.workerOrigin !== origin) {
    const stored = await kvJson(env, KV_SETTINGS, {});
    await kvPut(env, KV_SETTINGS, { ...stored, workerOrigin: origin });
  }

  const body = request.method === 'POST' ? await request.json().catch(() => ({})) : {};

  if (path === '/api/admin/social/state' && request.method === 'GET') {
    const [accounts, posts, log] = await Promise.all([
      getAccounts(env), getPosts(env), kvJson(env, KV_LOG, []),
    ]);
    return jsonResponse({
      settings: publicSettings(await getSettings(env)),
      accounts: accounts.map(publicAccount),
      posts: posts.slice().sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))),
      log: log.slice(0, 40),
      serverTimeMsk: nowMsk().toISOString().slice(0, 16).replace('T', ' '),
    });
  }

  if (path === '/api/admin/social/settings' && request.method === 'POST') {
    const stored = await kvJson(env, KV_SETTINGS, {});
    const next = { ...stored, workerOrigin: origin };
    // Пустое поле = «не меняем»: в форму секреты приходят замаскированными.
    ['googleClientId', 'googleClientSecret', 'googleRefreshToken', 'googleApiKey'].forEach((key) => {
      if (typeof body[key] === 'string' && body[key].trim()) next[key] = body[key].trim();
    });
    await kvPut(env, KV_SETTINGS, next);
    await socialLog(env, 'info', 'Настройки Google обновлены');
    return jsonResponse({ ok: true, settings: publicSettings(await getSettings(env)) });
  }

  if (path === '/api/admin/social/accounts' && request.method === 'POST') {
    const accounts = await getAccounts(env);
    const incoming = body.account || {};
    if (incoming.targets !== undefined && !validTargets(incoming.targets)) {
      return jsonResponse({ error: 'Выберите Instagram или YouTube' }, 400);
    }
    const idx = incoming.id ? accounts.findIndex((a) => a.id === incoming.id) : -1;
    const base = idx === -1 ? { ...DEFAULT_ACCOUNT, id: newId('acc') } : accounts[idx];

    const merged = {
      ...base,
      name: incoming.name != null ? String(incoming.name).trim() || base.name : base.name,
      active: incoming.active != null ? Boolean(incoming.active) : base.active,
      targets: incoming.targets !== undefined ? validTargets(incoming.targets) : base.targets,
      driveFolderId: incoming.driveFolderId != null ? String(incoming.driveFolderId).trim() : base.driveFolderId,
      captionTemplate: incoming.captionTemplate != null ? String(incoming.captionTemplate) : base.captionTemplate,
      titleTemplate: incoming.titleTemplate != null ? String(incoming.titleTemplate) : base.titleTemplate,
      postTime: incoming.postTime != null ? String(incoming.postTime) : base.postTime,
      instagramAccountId: incoming.instagramAccountId != null ? String(incoming.instagramAccountId).trim() : base.instagramAccountId,
      youtubeTags: incoming.youtubeTags != null ? String(incoming.youtubeTags) : base.youtubeTags,
      youtubeCategoryId: incoming.youtubeCategoryId != null ? String(incoming.youtubeCategoryId) : base.youtubeCategoryId,
      youtubePrivacy: incoming.youtubePrivacy != null ? String(incoming.youtubePrivacy) : base.youtubePrivacy,
    };
    // Секреты перезаписываем только если пришло непустое значение.
    if (typeof incoming.instagramToken === 'string' && incoming.instagramToken.trim()) {
      merged.instagramToken = incoming.instagramToken.trim();
      merged.instagramTokenUpdatedAt = new Date().toISOString();
    }
    if (typeof incoming.youtubeRefreshToken === 'string' && incoming.youtubeRefreshToken.trim()) {
      merged.youtubeRefreshToken = incoming.youtubeRefreshToken.trim();
    }

    // Ссылка на папку Диска вместо «голого» ID — частая и понятная ошибка.
    const folderMatch = merged.driveFolderId.match(/\/folders\/([A-Za-z0-9_-]+)/);
    if (folderMatch) merged.driveFolderId = folderMatch[1];

    // ID аккаунта Instagram подтягиваем сами: у пользователя на руках есть
    // токен, а номер аккаунта в кабинете Meta лежит в другом разделе.
    let resolvedNote = null;
    if (merged.instagramToken && !merged.instagramAccountId) {
      try {
        const info = await resolveInstagramAccountId(merged.instagramToken);
        if (info.id) {
          merged.instagramAccountId = info.id;
          resolvedNote = info.username
            ? `Instagram определён автоматически: @${info.username}`
            : 'Instagram ID определён автоматически';
          await socialLog(env, 'info', `${resolvedNote} (аккаунт «${merged.name}»)`);
        }
      } catch (e) {
        resolvedNote = 'ID Instagram определить не удалось: ' + e.message;
        await socialLog(env, 'error', `Аккаунт «${merged.name}»: ${resolvedNote}`);
      }
    }

    if (idx === -1) accounts.push(merged); else accounts[idx] = merged;
    await kvPut(env, KV_ACCOUNTS, accounts);
    let updatedQueued = 0;
    if (body.applyToQueued === true && incoming.targets !== undefined) {
      const posts = await getPosts(env);
      for (const post of posts) {
        // Завершённые и частично опубликованные ролики сохраняют свою историю.
        if (post.accountId !== merged.id || post.status !== 'queued' || !canChangeTargets(post)
            || post.instagramStatus === 'published' || post.youtubeStatus === 'published') continue;
        post.targets = [...merged.targets];
        updatedQueued += 1;
      }
      if (updatedQueued) await kvPut(env, KV_POSTS, posts);
    }
    await socialLog(env, 'info', `Аккаунт «${merged.name}» сохранён`);
    return jsonResponse({ ok: true, account: publicAccount(merged), note: resolvedNote, updatedQueued });
  }

  if (path === '/api/admin/social/accounts/delete' && request.method === 'POST') {
    const accounts = (await getAccounts(env)).filter((a) => a.id !== body.id);
    const posts = (await getPosts(env)).filter((p) => p.accountId !== body.id);
    await kvPut(env, KV_ACCOUNTS, accounts);
    await kvPut(env, KV_POSTS, posts);
    return jsonResponse({ ok: true });
  }

  if (path === '/api/admin/social/sync' && request.method === 'POST') {
    const accounts = await getAccounts(env);
    const targets = body.accountId ? accounts.filter((a) => a.id === body.accountId) : accounts;
    const results = [];
    for (const account of targets) {
      try {
        results.push({ account: account.name, ...(await syncAccountVideos(env, account)) });
      } catch (e) {
        results.push({ account: account.name, status: 'error', message: e.message });
        await socialLog(env, 'error', `Синхронизация «${account.name}»: ${e.message}`);
      }
    }
    return jsonResponse({ ok: true, results });
  }

  if (path === '/api/admin/social/check' && request.method === 'POST') {
    return jsonResponse({ ok: true, checks: await runDiagnostics(env) });
  }

  if (path === '/api/admin/social/posts/update' && request.method === 'POST') {
    const patch = {};
    ['title', 'caption'].forEach((key) => {
      if (typeof body[key] === 'string') patch[key] = body[key];
    });
    if (body.targets !== undefined) {
      const targets = validTargets(body.targets);
      if (!targets) return jsonResponse({ error: 'Выберите Instagram или YouTube' }, 400);
      const post = (await getPosts(env)).find(p => p.id === body.id);
      if (post && !canChangeTargets(post)) return jsonResponse({ error: 'Площадки этого ролика уже нельзя изменить' }, 409);
      patch.targets = targets;
    }
    if (body.scheduledAt !== undefined) patch.scheduledAt = body.scheduledAt || null;
    const updated = await patchPost(env, body.id, patch);
    return jsonResponse(updated ? { ok: true } : { error: 'not found' }, updated ? 200 : 404);
  }

  // Пометить ролик выложенным, не публикуя его.
  //
  // Нужно, когда часть роликов уже ушла в соцсети руками: удалять файлы с
  // Диска ради этого не хочется, а публиковать их повторно нельзя.
  // Проставить статус одной площадки вручную.
  //
  // Нужно, когда ролик на площадку ушёл, а до записи об этом дело не дошло —
  // например, публикацию оборвало на полпути. Без этого повтор залил бы дубль.
  if (path === '/api/admin/social/posts/platform-status' && request.method === 'POST') {
    const platform = body.platform === 'youtube' ? 'youtube' : 'instagram';
    const value = ['published', 'queued', 'failed'].includes(body.status) ? body.status : 'queued';
    const patch = { [platform === 'youtube' ? 'youtubeStatus' : 'instagramStatus']: value };
    if (platform === 'instagram' && body.permalink) patch.instagramPermalink = String(body.permalink);
    if (platform === 'youtube' && body.permalink) patch.youtubePermalink = String(body.permalink);
    if (body.postStatus) patch.status = String(body.postStatus);
    const updated = await patchPost(env, body.id, patch);
    return jsonResponse(updated ? { ok: true } : { error: 'not found' }, updated ? 200 : 404);
  }

  // An explicitly confirmed replacement never replays the unavailable old
  // container. Preflight checks are reads; only the returned job creates media.
  if (path === '/api/admin/social/posts/replace-instagram' && request.method === 'POST') {
    const cooldown = await getInstagramCooldown(env);
    if (cooldown) return jsonResponse(instagramCooldownResult(cooldown));
    if (body.confirmReplacement !== true) return jsonResponse({ ok: false, message: 'Нужно подтвердить создание новой записи Instagram' }, 400);
    try {
      const replacement = await prepareInstagramReplacement(env, body.id, origin, notify);
      if (replacement.run) ctx.waitUntil(replacement.run());
      return jsonResponse(replacement.response);
    } catch (error) {
      if (error.code === 'ERR_IG_RATE_LIMITED') {
        const pause = await startInstagramCooldown(env, error);
        return jsonResponse(instagramCooldownResult(pause));
      }
      return jsonResponse({ ok: false, message: error.code === 'ERR_IG_REPLACEMENT_CHECK' ? error.message
        : 'Не удалось проверить или сохранить попытку Instagram. Новая загрузка не запущена' });
    }
  }

  if (path === '/api/admin/social/posts/replace-youtube' && request.method === 'POST') {
    if (body.confirmReplacement !== true) return jsonResponse({ ok: false, message: 'Подтвердите новую публикацию YouTube' }, 400);
    const post = (await getPosts(env)).find(p => p.id === body.id);
    if (!post || post.status === 'processing') return jsonResponse({ ok: false, message: 'Обновите состояние ролика' }, 409);
    const lease = await socialGuard(env, post.accountId, '/claim');
    if (lease?.busy) return jsonResponse({ ok: false, retryAt: new Date(lease.until).toISOString(),
      message: 'Аккаунт занят предыдущей публикацией. Повторите после ' + new Date(lease.until).toLocaleTimeString('ru-RU', { timeZone: 'Europe/Moscow' }) + ' МСК' }, 409);
    ctx.waitUntil((async () => {
      try { await replaceYoutube(lease ? { ...env, __SOCIAL_OWNER: lease.owner } : env, post.id, origin, notify); }
      finally {
        if (lease) {
          try { await socialGuard(env, post.accountId, '/release', { owner: lease.owner }); }
          catch (_) { console.warn('YouTube replacement lease release deferred'); }
        }
      }
    })());
    return jsonResponse({ ok: true, message: 'Проверяю прежний ролик YouTube; если он недоступен, создам новую публикацию' });
  }

  // Повторить публикацию только в одну площадку — вторую не трогаем.
  if (path === '/api/admin/social/posts/publish-platform' && request.method === 'POST') {
    const posts = await getPosts(env);
    const post = posts.find((p) => p.id === body.id);
    const platform = body.platform === 'youtube' ? 'youtube' : 'instagram';
    if (!post) return jsonResponse({ error: 'not found' }, 404);
    if (post[platform + 'Status'] === 'published') return jsonResponse({ ok: true, message: 'Ролик уже опубликован на этой площадке' });
    if (post.status === 'processing') return jsonResponse({ ok: false, message: 'Ролик уже публикуется' }, 409);
    if (platform === 'instagram') {
      const cooldown = await getInstagramCooldown(env);
      if (cooldown) return jsonResponse(instagramCooldownResult(cooldown));
      if (post.instagramNeedsReview === true) return jsonResponse({ ok: false, code: 'instagram_review_required',
        message: 'Для недоступной прежней записи используйте «Новая публикация»; обычный повтор её не заменяет' });
    }

    await patchPost(env, post.id, {
      status: 'processing',
      error: null,
      processingSince: new Date().toISOString(),
      publishMode: 'manual',
      ...(platform === 'instagram' ? { instagramNeedsReview: false, instagramReviewReason: null } : {}),
      [platform === 'youtube' ? 'youtubeStatus' : 'instagramStatus']: 'queued',
    });
    ctx.waitUntil(publishPost(env, post.id, origin, notify, [platform]));
    return jsonResponse({ ok: true, message: platform === 'youtube' ? 'Заливаю на YouTube' : 'Публикую в Instagram' });
  }

  // Опубликовать выбранные прямо сейчас, минуя расписание.
  //
  // Публикуем по очереди, а не разом: Instagram кодирует каждый ролик минуты,
  // и параллельные заливки на один аккаунт площадки не любят. Ограничение
  // сверху — чтобы случайно выбранная «вся очередь» не ушла в эфир целиком.
  if (path === '/api/admin/social/posts/publish-now' && request.method === 'POST') {
    const ids = Array.isArray(body.ids) ? body.ids : [];
    const posts = await getPosts(env);
    const ready = posts.filter((p) => ids.includes(p.id) && p.status !== 'processing');
    const cooldown = await getInstagramCooldown(env);
    const held = ready.filter(p => p.instagramNeedsReview === true || (cooldown && onlyInstagramPending(p)));
    const take = ready.filter(p => !held.includes(p)).slice(0, MAX_MANUAL_BATCH);

    if (!take.length) return jsonResponse(held.length ? cooldown ? { ...instagramCooldownResult(cooldown), held: held.length }
      : { ok: false, held: held.length, message: 'Прежние публикации требуют проверки. Используйте действие в карточке Instagram' }
      : { ok: false, message: 'Нечего публиковать' });

    for (const post of take) {
      await patchPost(env, post.id, { status: 'processing', error: null, scheduledAt: null, processingSince: new Date().toISOString(), publishMode: 'manual', instagramNeedsReview: false, instagramReviewReason: null });
    }

    ctx.waitUntil((async () => {
      for (const post of take) {
        await publishPost(env, post.id, origin, notify);
      }
    })());

    return jsonResponse({
      ok: true,
      started: take.length,
      skipped: ready.length - take.length,
      held: held.length,
      message: take.length === 1
        ? 'Публикую ролик'
        : `Публикую ${take.length} роликов по очереди`,
    });
  }

  // Массовые операции: расставить даты, заменить подпись, сменить площадки,
  // пометить выложенными, убрать из очереди. Иначе тридцать роликов пришлось бы
  // править по одному.
  if (path === '/api/admin/social/posts/bulk' && request.method === 'POST') {
    const ids = Array.isArray(body.ids) ? body.ids : [];
    const posts = await getPosts(env);
    const targetPosts = posts.filter((p) => ids.includes(p.id));
    if (body.action === 'delete' && targetPosts.some(p => p.status === 'processing')) {
      return jsonResponse({ ok: false, message: 'Дождитесь завершения текущей публикации перед удалением ролика' }, 409);
    }
    let changed = 0;
    if (body.action === 'targets' && !validTargets(body.targets)) {
      return jsonResponse({ error: 'Выберите Instagram или YouTube' }, 400);
    }

    if (body.action === 'schedule') {
      // Дата и время приходят по МСК, храним в UTC.
      const startMsk = new Date(String(body.startAt) + ':00.000Z');
      if (isNaN(startMsk.getTime())) return jsonResponse({ error: 'bad date' }, 400);
      const stepDays = Math.max(1, parseInt(body.everyDays, 10) || 1);
      const ordered = targetPosts.slice().sort((a, b) =>
        String(a.fileName).localeCompare(String(b.fileName), 'ru', { numeric: true }));
      ordered.forEach((post, i) => {
        const when = new Date(startMsk.getTime() + i * stepDays * 86400000 - 3 * 3600000);
        const idx = posts.findIndex((p) => p.id === post.id);
        posts[idx] = { ...posts[idx], scheduledAt: when.toISOString() };
        changed += 1;
      });
    } else {
      targetPosts.forEach((post) => {
        const idx = posts.findIndex((p) => p.id === post.id);
        if (body.action === 'caption') {
          // {title} подставляем от «человеческого» имени файла, а не от текущего
          // заголовка: иначе при второй правке подставился бы уже собранный текст.
          const humanName = humanTitle(posts[idx].fileName);
          const patch = { ...posts[idx] };
          if (typeof body.caption === 'string') {
            // Одно и то же описание уходит в подпись Instagram и в описание
            // YouTube — редактировать их порознь незачем.
            patch.caption = body.caption.replace(/\{title\}/g, humanName);
          }
          if (typeof body.titleTemplate === 'string' && body.titleTemplate.trim()) {
            patch.title = body.titleTemplate.replace(/\{title\}/g, humanName);
          }
          posts[idx] = patch;
        } else if (body.action === 'targets') {
          if (!canChangeTargets(post)) return;
          posts[idx] = { ...posts[idx], targets: validTargets(body.targets) };
        } else if (body.action === 'mark') {
          posts[idx] = { ...posts[idx], status: 'published', instagramStatus: 'published',
                         youtubeStatus: 'published', publishedAt: new Date().toISOString(),
                         error: null, markedManually: true };
        } else if (body.action === 'requeue') {
          if (post.status === 'processing') return;
          posts[idx] = requeuePost(posts[idx]);
        } else if (body.action === 'unschedule') {
          posts[idx] = { ...posts[idx], scheduledAt: null };
        }
        changed += 1;
      });
    }

    if (body.action === 'delete') await excludeVideos(env, targetPosts);
    const kept = body.action === 'delete' ? (await getPosts(env)).filter((p) => !ids.includes(p.id)) : posts;
    await kvPut(env, KV_POSTS, kept);
    return jsonResponse({ ok: true, changed: body.action === 'delete' ? ids.length : changed });
  }

  if (path === '/api/admin/social/posts/mark' && request.method === 'POST') {
    const asPublished = body.status !== 'queued';
    const post = (await getPosts(env)).find(p => p.id === body.id);
    if (!post) return jsonResponse({ error: 'not found' }, 404);
    if (!asPublished && post.status === 'processing') return jsonResponse({ ok: false, message: 'Ролик ещё публикуется' }, 409);
    const updated = await patchPost(env, body.id, asPublished ? {
      status: 'published',
      instagramStatus: 'published',
      youtubeStatus: 'published',
      publishedAt: new Date().toISOString(),
      error: null,
      markedManually: true,
    } : requeuePost(post));
    return jsonResponse(updated ? { ok: true } : { error: 'not found' }, updated ? 200 : 404);
  }

  if (path === '/api/admin/social/posts/delete' && request.method === 'POST') {
    const posts = await getPosts(env);
    if (posts.some(p => p.id === body.id && p.status === 'processing')) {
      return jsonResponse({ ok: false, message: 'Дождитесь завершения текущей публикации перед удалением ролика' }, 409);
    }
    await excludeVideos(env, posts.filter(p => p.id === body.id));
    await kvPut(env, KV_POSTS, (await getPosts(env)).filter(p => p.id !== body.id));
    return jsonResponse({ ok: true });
  }

  if (path === '/api/admin/social/posts/publish' && request.method === 'POST') {
    const posts = await getPosts(env);
    const post = posts.find((p) => p.id === body.id);
    if (!post) return jsonResponse({ error: 'not found' }, 404);
    if (post.status === 'processing') {
      return jsonResponse({ ok: false, message: 'Этот ролик уже публикуется' });
    }
    if (post.instagramNeedsReview === true) return jsonResponse({ ok: false, message: 'Прежняя запись Instagram требует проверки. Используйте действие в карточке Instagram' });
    const cooldown = onlyInstagramPending(post) ? await getInstagramCooldown(env) : null;
    if (cooldown) return jsonResponse(instagramCooldownResult(cooldown));
    await patchPost(env, post.id, { status: 'processing', error: null, processingSince: new Date().toISOString(), publishMode: 'manual', instagramNeedsReview: false, instagramReviewReason: null });
    // Instagram кодирует видео минуты — ответ ждать нельзя, публикуем в фоне,
    // а панель подтягивает статус опросом.
    ctx.waitUntil(publishPost(env, post.id, origin, notify));
    return jsonResponse({ ok: true, message: 'Публикация запущена' });
  }

  if (path === '/api/admin/social/run' && request.method === 'POST') {
    ctx.waitUntil(runAutoPost(env, origin, notify));
    return jsonResponse({ ok: true, message: 'Проверка расписания запущена' });
  }

  return null;
}

export const socialInternals = { mskDay, mskMinutes, parseTimeToMinutes, humanTitle, buildYoutubeTitle };
