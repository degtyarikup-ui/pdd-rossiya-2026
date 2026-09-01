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

const KV_SETTINGS = 'social:settings';
const KV_ACCOUNTS = 'social:accounts';
const KV_POSTS = 'social:posts';
const KV_LOG = 'social:log';
const KV_GOOGLE_TOKEN = 'social:google_token';

const VIDEO_EXT = ['mp4', 'mov', 'm4v'];
const LOG_LIMIT = 120;

// Ролик заливается на YouTube из памяти воркера (лимит инстанса — 128 МБ).
// Вертикальные ролики до минуты весят единицы мегабайт, так что запас большой,
// но осмысленная ошибка лучше, чем падение воркера без объяснений.
const MAX_UPLOAD_BYTES = 90 * 1024 * 1024;

// Meta кодирует видео на своей стороне; ждём столько же, сколько Meerno.
const IG_POLL_ATTEMPTS = 40;
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
    fields: 'files(id, name, mimeType, size)',
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
export async function syncAccountVideos(env, account) {
  if (!account.driveFolderId) {
    return { status: 'error', message: 'У аккаунта не указана папка Google Диска' };
  }

  const files = await driveListFolder(env, account.driveFolderId);
  const videos = files.filter((f) => VIDEO_EXT.includes(extOf(f.name)));
  const captions = {};
  files
    .filter((f) => extOf(f.name) === 'txt')
    .forEach((f) => { captions[baseName(f.name)] = f.id; });

  videos.sort((a, b) => String(a.name).localeCompare(String(b.name), 'ru', { numeric: true }));

  const posts = await getPosts(env);
  const known = new Set(posts.filter((p) => p.accountId === account.id).map((p) => p.driveFileId));

  let added = 0;
  for (const file of videos) {
    if (known.has(file.id)) continue;

    const name = baseName(file.name);
    let caption = '';
    if (captions[name]) {
      caption = await driveReadText(env, captions[name]);
    }
    if (!caption) {
      caption = String(account.captionTemplate || '').replace(/\{title\}/g, humanTitle(file.name));
    }

    posts.push({
      id: newId('sp'),
      accountId: account.id,
      driveFileId: file.id,
      fileName: file.name,
      sizeBytes: file.size ? parseInt(file.size, 10) : null,
      title: humanTitle(file.name),
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
    await kvPut(env, KV_POSTS, posts);
    await socialLog(env, 'info', `Синхронизация «${account.name}»: добавлено роликов — ${added}`);
  }

  return { status: 'ok', added, seen: videos.length };
}

// ────────────────────────────── Instagram ──────────────────────────────

async function igRequest(url, form) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(form),
  });
  const data = await res.json().catch(() => ({}));
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
    throw new Error(limit(data?.error?.message || 'Instagram не принял токен (HTTP ' + res.status + ')', 200));
  }
  return { id: data.user_id ? String(data.user_id) : null, username: data.username || null };
}

async function publishToInstagram(env, post, account, origin) {
  if (!account.instagramToken || !account.instagramAccountId) {
    throw new Error('Не заполнены Instagram Account ID или токен доступа');
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

  // Основной путь — /<account_id>/media; на некоторых типах токенов работает
  // только /me/media, поэтому он остаётся запасным (как в Meerno).
  let created = await igRequest(`${api}/${account.instagramAccountId}/media`, form);
  if (!created.ok) {
    created = await igRequest(`${api}/me/media`, form);
  }
  if (!created.ok || !created.data.id) {
    throw new Error(
      'Instagram не принял видео (HTTP ' + created.status + '): ' +
      limit(created.data?.error?.message || JSON.stringify(created.data), 300)
    );
  }

  const containerId = created.data.id;

  // Meta кодирует ролик у себя и параллельно скачивает его по нашей ссылке.
  let ready = false;
  for (let i = 0; i < IG_POLL_ATTEMPTS; i += 1) {
    await sleep(IG_POLL_INTERVAL_MS);
    const statusRes = await fetch(
      `${api}/${containerId}?fields=status_code,status&access_token=${encodeURIComponent(account.instagramToken)}`
    );
    const statusData = await statusRes.json().catch(() => ({}));
    const code = statusData.status_code;
    if (code === 'FINISHED') { ready = true; break; }
    if (code === 'ERROR') {
      throw new Error('Instagram не смог обработать видео: ' + limit(statusData.status || JSON.stringify(statusData), 300));
    }
  }
  if (!ready) {
    throw new Error('Instagram обрабатывал видео дольше ' + (IG_POLL_ATTEMPTS * IG_POLL_INTERVAL_MS / 1000) + ' секунд и не ответил');
  }

  const publishForm = { creation_id: containerId, access_token: account.instagramToken };
  let published = await igRequest(`${api}/${account.instagramAccountId}/media_publish`, publishForm);
  if (!published.ok) {
    published = await igRequest(`${api}/me/media_publish`, publishForm);
  }
  if (!published.ok || !published.data.id) {
    throw new Error(
      'Ошибка публикации в Instagram (HTTP ' + published.status + '): ' +
      limit(published.data?.error?.message || JSON.stringify(published.data), 300)
    );
  }

  const mediaId = published.data.id;
  let permalink = null;
  try {
    const details = await fetch(
      `${api}/${mediaId}?fields=permalink&access_token=${encodeURIComponent(account.instagramToken)}`
    );
    const detailsData = await details.json().catch(() => ({}));
    permalink = detailsData.permalink || null;
  } catch (_) { /* ссылка не обязательна */ }

  return { mediaId, permalink };
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

  return {
    videoId: uploadData.id,
    permalink: 'https://youtube.com/shorts/' + uploadData.id,
  };
}

// ────────────────────────────── публикация ──────────────────────────────

/**
 * Опубликовать ролик на выбранных площадках.
 *
 * Площадку, куда ролик уже ушёл, пропускаем — поэтому «Повторить» после
 * частичной ошибки дозаливает только недостающее, а не дублирует пост.
 */
export async function publishPost(env, postId, origin, notify = null) {
  const posts = await getPosts(env);
  const post = posts.find((p) => p.id === postId);
  if (!post) return { status: 'error', message: 'Ролик не найден' };

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
  let igResult = null;
  let ytResult = null;

  if (targets.includes('instagram') && post.instagramStatus !== 'published') {
    try {
      await patchPost(env, postId, { instagramStatus: 'processing' });
      igResult = await publishToInstagram(env, post, account, origin);
      await patchPost(env, postId, {
        instagramStatus: 'published',
        instagramMediaId: igResult.mediaId,
        instagramPermalink: igResult.permalink,
      });
      await socialLog(env, 'ok', `Instagram: опубликован ${post.fileName}`, { url: igResult.permalink });
    } catch (e) {
      errors.push('Instagram: ' + e.message);
      await patchPost(env, postId, { instagramStatus: 'failed' });
      await socialLog(env, 'error', `Instagram: ${post.fileName} — ${e.message}`);
    }
  }

  if (targets.includes('youtube') && post.youtubeStatus !== 'published') {
    try {
      await patchPost(env, postId, { youtubeStatus: 'processing' });
      ytResult = await publishToYouTube(env, post, account);
      await patchPost(env, postId, {
        youtubeStatus: 'published',
        youtubeVideoId: ytResult.videoId,
        youtubePermalink: ytResult.permalink,
      });
      await socialLog(env, 'ok', `YouTube: опубликован ${post.fileName}`, { url: ytResult.permalink });
    } catch (e) {
      errors.push('YouTube: ' + e.message);
      await patchPost(env, postId, { youtubeStatus: 'failed' });
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

  const summary = errors.join('; ') || 'Публикация не завершилась';
  await patchPost(env, postId, { status: 'failed', error: limit(summary, 500) });

  // Об упавшей автопубликации иначе можно узнать, только открыв админку.
  if (notify) {
    try {
      await notify(
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
export async function runAutoPost(env, origin, notify = null) {
  await refreshInstagramTokens(env);

  const accounts = await getAccounts(env);
  const today = mskDay();
  const minutesNow = mskMinutes();
  const results = [];

  for (const account of accounts) {
    if (!account.active) continue;
    if (account.lastPostedDay === today) continue;

    const slot = parseTimeToMinutes(account.postTime);
    if (minutesNow < slot || minutesNow > slot + 180) continue;

    try {
      await syncAccountVideos(env, account);
    } catch (e) {
      await socialLog(env, 'error', `Синхронизация «${account.name}»: ${e.message}`);
    }

    const posts = await getPosts(env);
    const due = posts
      .filter((p) => p.accountId === account.id && (p.status === 'queued' || p.status === 'failed'))
      .filter((p) => !p.scheduledAt || p.scheduledAt <= new Date().toISOString())
      .sort((a, b) => {
        if (a.scheduledAt && b.scheduledAt) return a.scheduledAt.localeCompare(b.scheduledAt);
        if (a.scheduledAt) return -1;
        if (b.scheduledAt) return 1;
        return String(a.fileName).localeCompare(String(b.fileName), 'ru', { numeric: true });
      });

    const next = due[0];
    if (!next) {
      await socialLog(env, 'info', `«${account.name}»: очередь пуста, публиковать нечего`);
      continue;
    }

    await patchPost(env, next.id, { status: 'processing', error: null });
    const res = await publishPost(env, next.id, origin, notify);
    results.push({ account: account.name, file: next.fileName, ...res });
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
        const files = await driveListFolder(env, account.driveFolderId);
        const videos = files.filter((f) => VIDEO_EXT.includes(extOf(f.name)));
        checks.push({
          name: `Папка Диска — ${account.name}`,
          ok: true,
          message: `видно файлов: ${files.length}, из них роликов: ${videos.length}`,
        });
      } catch (e) {
        checks.push({ name: `Папка Диска — ${account.name}`, ok: false, message: e.message });
      }
    }

    if ((account.targets || []).includes('instagram')) {
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
    const idx = incoming.id ? accounts.findIndex((a) => a.id === incoming.id) : -1;
    const base = idx === -1 ? { ...DEFAULT_ACCOUNT, id: newId('acc') } : accounts[idx];

    const merged = {
      ...base,
      name: incoming.name != null ? String(incoming.name).trim() || base.name : base.name,
      active: incoming.active != null ? Boolean(incoming.active) : base.active,
      targets: Array.isArray(incoming.targets) && incoming.targets.length ? incoming.targets : base.targets,
      driveFolderId: incoming.driveFolderId != null ? String(incoming.driveFolderId).trim() : base.driveFolderId,
      captionTemplate: incoming.captionTemplate != null ? String(incoming.captionTemplate) : base.captionTemplate,
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
    await socialLog(env, 'info', `Аккаунт «${merged.name}» сохранён`);
    return jsonResponse({ ok: true, account: publicAccount(merged), note: resolvedNote });
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
    if (Array.isArray(body.targets)) patch.targets = body.targets;
    if (body.scheduledAt !== undefined) patch.scheduledAt = body.scheduledAt || null;
    const updated = await patchPost(env, body.id, patch);
    return jsonResponse(updated ? { ok: true } : { error: 'not found' }, updated ? 200 : 404);
  }

  if (path === '/api/admin/social/posts/delete' && request.method === 'POST') {
    const posts = (await getPosts(env)).filter((p) => p.id !== body.id);
    await kvPut(env, KV_POSTS, posts);
    return jsonResponse({ ok: true });
  }

  if (path === '/api/admin/social/posts/publish' && request.method === 'POST') {
    const posts = await getPosts(env);
    const post = posts.find((p) => p.id === body.id);
    if (!post) return jsonResponse({ error: 'not found' }, 404);
    if (post.status === 'processing') {
      return jsonResponse({ ok: false, message: 'Этот ролик уже публикуется' });
    }
    await patchPost(env, post.id, { status: 'processing', error: null });
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
