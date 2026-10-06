import { importPKCS8, SignJWT } from 'jose';

export const DEFAULT_NOTIFICATION_CONFIG = Object.freeze({ pushEnabled: false, popupEnabled: true, streakEnabled: true, gameEnabled: true });
const reply = (value, status = 200) => Response.json(value, { status, headers: { 'Cache-Control': 'no-store' } });
// popup  — modal window on the home screen (one show per device);
// banner — dismissible card at the top of the home screen (non-blocking);
// push   — system notification via FCM (optionally duplicated in-app as popup).
export const KINDS = ['popup', 'banner', 'push'];
export const ACTIONS = ['none', 'url', 'tickets', 'topics', 'game', 'feed', 'settings'];
export const LAYOUTS = ['standard', 'cover', 'compact'];
const choices = { kind: KINDS, app: ['all', 'ru', 'by', 'rs'], platform: ['all', 'ios', 'android', 'web'] };
const DAY = 86400000;
const str = (value, max, label, required = false) => {
  if (value === undefined || value === null || value === '') { if (required) throw new Error(label + ': обязательное поле'); return ''; }
  if (typeof value !== 'string' || value.trim().length > max) throw new Error(label + ': не более ' + max + ' символов');
  return value.trim();
};
const httpsUrl = (value, label) => {
  const raw = str(value, 500, label);
  if (!raw) return '';
  let url; try { url = new URL(raw); } catch { throw new Error(label + ': некорректная ссылка'); }
  if (url.protocol !== 'https:') throw new Error(label + ': нужна ссылка https://');
  return url.toString();
};
export function userTopic(value) {
  const bytes = new TextEncoder().encode(String(value || '').trim().toLowerCase());
  return 'pdd_u_' + Array.from(bytes.slice(0, 64), b => b.toString(16).padStart(2, '0')).join('');
}
export function validateCampaign(input, now = Date.now()) {
  const value = {};
  const normalized = { ...input, app: input?.app === undefined ? 'ru' : input.app };
  for (const [key, allowed] of Object.entries(choices)) {
    value[key] = normalized?.[key];
    if (!allowed.includes(value[key])) throw new Error('Некорректный тип или аудитория');
  }
  if (value.kind === 'push' && value.platform === 'web') throw new Error('Веб-пуши пока не поддерживаются');
  for (const [key, max] of [['title', 80], ['body', 1000]]) {
    if (typeof input[key] !== 'string' || !input[key].trim() || input[key].trim().length > max) throw new Error('Заполните заголовок и текст в пределах лимита');
    value[key] = input[key].trim();
  }
  if (value.kind === 'push' && value.body.length > 300) throw new Error('Текст пуша: не более 300 символов');
  if (value.kind === 'banner' && value.body.length > 200) throw new Error('Текст баннера: не более 200 символов');
  value.id = input.id;
  if (typeof value.id !== 'string' || !/^[a-f0-9-]{36}$/.test(value.id)) throw new Error('Некорректный ID сообщения');
  // Optional scheduling: start in the future (≤ 30 days), show until expiresAt.
  value.startAt = input.startAt === undefined || input.startAt === null || input.startAt === '' ? now : Number(input.startAt);
  if (!Number.isFinite(value.startAt) || value.startAt > now + 30 * DAY) throw new Error('Время старта: не позже чем через 30 дней');
  if (value.startAt < now) value.startAt = now;
  value.expiresAt = Number(input.expiresAt);
  if (!Number.isFinite(value.expiresAt) || value.expiresAt <= value.startAt || value.expiresAt > value.startAt + 30 * DAY) throw new Error('Срок показа: от времени старта до 30 дней');
  // Personal test account (email or user ID). Empty = broadcast to all users.
  value.target = str(input.target, 120, 'Аккаунт для теста').toLowerCase();
  if (value.target && /[\s'"<>]/.test(value.target)) throw new Error('Аккаунт для теста: укажите корректный email или ID');
  // Customization.
  value.imageUrl = httpsUrl(input.imageUrl, 'Картинка');
  value.emoji = str(input.emoji, 8, 'Эмодзи');
  value.accent = input.accent ? String(input.accent) : '';
  if (value.accent && !/^#[0-9a-fA-F]{6}$/.test(value.accent)) throw new Error('Цвет: формат #RRGGBB');
  value.layout = input.layout || 'standard';
  if (!LAYOUTS.includes(value.layout)) throw new Error('Некорректный макет');
  value.buttonText = str(input.buttonText, 24, 'Текст кнопки');
  value.dismissText = str(input.dismissText, 24, 'Текст второй кнопки');
  value.action = input.action || 'none';
  if (!ACTIONS.includes(value.action)) throw new Error('Некорректное действие');
  value.actionUrl = value.action === 'url' ? httpsUrl(input.actionUrl, 'Ссылка действия') : '';
  if (value.action === 'url' && !value.actionUrl) throw new Error('Укажите ссылку для кнопки');
  value.inApp = value.kind === 'push' && input.inApp === true;
  value.createdAt = now;
  value.enabled = true;
  value.status = value.kind === 'push' ? 'queued' : (value.startAt > now ? 'scheduled' : 'published');
  return value;
}
const SAME_FIELDS = ['kind', 'title', 'body', 'app', 'platform', 'expiresAt', 'target', 'imageUrl', 'emoji', 'accent', 'layout', 'buttonText', 'dismissText', 'action', 'actionUrl', 'inApp'];
export function campaignMatches(item, app, platform, now = Date.now(), user = {}) {
  if (!item.enabled || item.expiresAt <= now || (item.startAt || 0) > now) return false;
  if (item.app !== 'all' && item.app !== app) return false;
  if (item.platform !== 'all' && item.platform !== platform) return false;
  if (item.target) {
    const t = item.target.toLowerCase();
    const uid = String(user.userId || '').trim().toLowerCase();
    const email = String(user.email || '').trim().toLowerCase();
    return Boolean(t && (t === uid || t === email));
  }
  return true;
}
/** Shape sent to the app: only display fields, never internal state. */
export function clientMessage(item) {
  const kind = item.kind === 'push' ? 'popup' : item.kind;
  return { id: item.id, kind, title: item.title, body: item.body, expiresAt: item.expiresAt, createdAt: item.createdAt,
    imageUrl: item.imageUrl || '', emoji: item.emoji || '', accent: item.accent || '', layout: item.layout || 'standard',
    buttonText: item.buttonText || '', dismissText: item.dismissText || '', action: item.action || 'none', actionUrl: item.actionUrl || '' };
}
export function pushCondition(item) {
  if (item.target) {
    const topic = `'${userTopic(item.target)}' in topics`;
    if (item.platform === 'ios' || item.platform === 'android') {
      const app = item.app === 'all' ? 'ru' : item.app;
      return `${topic} && 'pdd_${app}_${item.platform}' in topics`;
    }
    return topic;
  }
  // Each installation subscribes to exactly one country/platform topic.
  const apps = item.app === 'all' ? ['ru', 'by', 'rs'] : [item.app];
  const platforms = item.platform === 'all' ? ['ios', 'android'] : [item.platform];
  const topics = apps.flatMap(app => platforms.map(platform => `'pdd_${app}_${platform}' in topics`));
  // FCM conditions allow at most five topics. All six use the common mobile topic.
  return topics.length === 6 ? "'pdd_mobile' in topics" : topics.join(' || ');
}
export function pushConfigured(env) {
  try { const key = JSON.parse(env.FCM_SERVICE_ACCOUNT || '{}'); return Boolean(key.project_id && key.client_email && key.private_key); } catch { return false; }
}
export function buildPushMessage(campaign, now = Date.now()) {
  const ttl = Math.max(1, Math.min(86400, Math.floor((campaign.expiresAt - now) / 1000)));
  const title = campaign.emoji ? campaign.emoji + ' ' + campaign.title : campaign.title;
  const notification = { title, body: campaign.body, ...(campaign.imageUrl ? { image: campaign.imageUrl } : {}) };
  const data = { campaignId: campaign.id, action: campaign.action || 'none', actionUrl: campaign.actionUrl || '', imageUrl: campaign.imageUrl || '', accent: campaign.accent || '' };
  const androidNotification = { tag: campaign.id, channel_id: 'admin_messages', icon: 'ic_notification', ...(campaign.accent ? { color: campaign.accent } : {}), ...(campaign.imageUrl ? { image: campaign.imageUrl } : {}) };
  return { condition: pushCondition(campaign), notification, data,
    android: { ttl: ttl + 's', notification: androidNotification },
    apns: { headers: { 'apns-expiration': String(Math.floor(campaign.expiresAt / 1000)), 'apns-collapse-id': campaign.id },
      // mutable-content lets the iOS Notification Service Extension attach the image.
      payload: { aps: { sound: 'default', ...(campaign.imageUrl ? { 'mutable-content': 1 } : {}) } },
      ...(campaign.imageUrl ? { fcm_options: { image: campaign.imageUrl } } : {}) } };
}
let accessCache;
export async function sendPush(env, campaign, fetcher = fetch) {
  const account = JSON.parse(env.FCM_SERVICE_ACCOUNT);
  if (!accessCache || accessCache.project !== account.project_id || accessCache.expires < Date.now()) {
    const key = await importPKCS8(account.private_key, 'RS256');
    const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' }).setIssuer(account.client_email)
      .setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('1h').sign(key);
    const response = await fetcher('https://oauth2.googleapis.com/token', { method: 'POST', body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }), signal: AbortSignal.timeout(10000) });
    const token = await response.json();
    if (!response.ok || !token.access_token) throw new Error('Не удалось подключиться к Firebase');
    accessCache = { project: account.project_id, token: token.access_token, expires: Date.now() + (Number(token.expires_in || 3600) - 120) * 1000 };
  }
  let response;
  try {
    response = await fetcher(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + accessCache.token, 'content-type': 'application/json' },
      body: JSON.stringify({ message: buildPushMessage(campaign) }),
      signal: AbortSignal.timeout(15000),
    });
  } catch { const error = new Error('Ответ Firebase не получен. Доставка неизвестна; автоматического повтора нет.'); error.unknown = true; throw error; }
  if (response.status === 401) accessCache = null;
  if (!response.ok) throw new Error('Firebase отклонил сообщение (HTTP ' + response.status + ')');
  const value = await response.json();
  if (!value.name) { const error = new Error('Firebase не подтвердил приём сообщения'); error.unknown = true; throw error; }
  return value.name;
}

// One serialized durable object: immediate toggles, idempotent publication,
// persistent push queue. No KV user-profile scans or per-recipient writes.
export class NotificationsState {
  constructor(state, env) { this.state = state; this.env = env; this.tail = Promise.resolve(); }
  serial(fn) { const result = this.tail.then(fn); this.tail = result.catch(() => {}); return result; }
  fetch(request) { return this.serial(() => this.handle(request)); }
  async scheduleNext() {
    const records = await this.state.storage.list({ prefix: 'message:' });
    const queued = [...records.values()].filter(x => x.kind === 'push' && x.status === 'queued' && x.enabled);
    if (!queued.length) return;
    const next = Math.min(...queued.map(x => x.startAt || 0));
    await this.state.storage.setAlarm(Math.max(Date.now() + 1000, next));
  }
  async handle(request) {
    const path = new URL(request.url).pathname;
    const config = { ...DEFAULT_NOTIFICATION_CONFIG, ...await this.state.storage.get('config') };
    if (path === '/client') {
      const url = new URL(request.url), app = url.searchParams.get('app'), platform = url.searchParams.get('platform');
      const user = { userId: url.searchParams.get('userId') || '', email: url.searchParams.get('email') || '' };
      if (!['ru','by','rs'].includes(app) || !['ios','android','web'].includes(platform)) return reply({ error: 'invalid audience' }, 400);
      const records = await this.state.storage.list({ prefix: 'message:' });
      const visible = config.popupEnabled ? [...records.values()].filter(item => (item.kind !== 'push' || item.inApp) && campaignMatches(item, app, platform, Date.now(), user)) : [];
      return reply({ config, messages: visible.sort((a,b) => b.createdAt-a.createdAt).slice(0, 10).map(clientMessage) });
    }
    if (path === '/alarm') {
      await this._runAlarm();
      return reply({ ok: true });
    }
    if (request.method === 'GET') {
      const records = await this.state.storage.list({ prefix: 'message:' });
      return reply({ config, pushConfigured: pushConfigured(this.env), messages: [...records.values()].sort((a,b) => b.createdAt-a.createdAt) });
    }
    let body;
    try { body = await request.json(); } catch { return reply({ error: 'Некорректный запрос' }, 400); }
    if (path === '/config') {
      for (const key of Object.keys(DEFAULT_NOTIFICATION_CONFIG)) if (typeof body[key] !== 'boolean') return reply({ error: 'Некорректные переключатели' }, 400);
      if (body.pushEnabled && !pushConfigured(this.env)) return reply({ error: 'Сначала подключите Firebase' }, 409);
      const next = Object.fromEntries(Object.keys(DEFAULT_NOTIFICATION_CONFIG).map(key => [key, body[key]]));
      await this.state.storage.put('config', next);
      if (next.pushEnabled) await this.scheduleNext();
      return reply({ ok: true, config: next });
    }
    if (path === '/toggle') {
      const key = 'message:' + body.id, item = await this.state.storage.get(key);
      if (!item || typeof body.enabled !== 'boolean') return reply({ error: 'Сообщение не найдено' }, 404);
      if (item.kind === 'push' && item.status !== 'queued' && !item.inApp) return reply({ error: 'Отправленный пуш нельзя отозвать' }, 409);
      item.enabled = body.enabled;
      await this.state.storage.put(key, item);
      if (item.kind === 'push' && item.enabled) await this.scheduleNext();
      return reply({ ok: true });
    }
    if (path === '/delete') {
      const key = 'message:' + body.id, item = await this.state.storage.get(key);
      if (!item) return reply({ error: 'Сообщение не найдено' }, 404);
      if (item.kind === 'push' && item.status === 'sending') return reply({ error: 'Пуш отправляется — удалить нельзя' }, 409);
      await this.state.storage.delete(key);
      return reply({ ok: true });
    }
    if (path === '/publish') {
      let item;
      try { item = validateCampaign(body); } catch (error) { return reply({ error: error.message }, 400); }
      const key = 'message:' + item.id, existing = await this.state.storage.get(key);
      if (existing) {
        if (SAME_FIELDS.some(field => (existing[field] ?? '') !== (item[field] ?? ''))) return reply({ error: 'ID уже принадлежит другому сообщению' }, 409);
        return reply({ ok: true, message: existing, duplicate: true });
      }
      if (item.kind === 'push' && (!config.pushEnabled || !pushConfigured(this.env))) return reply({ error: 'Пуши отключены или Firebase не подключён' }, 409);
      if (item.kind !== 'push' && !config.popupEnabled) return reply({ error: 'Сообщения в приложении отключены' }, 409);
      const records = await this.state.storage.list({ prefix: 'message:' });
      // Keep the latest 100 completed/expired messages, never evict active popups/queued pushes.
      const removable = [...records.entries()].filter(([,x]) => x.expiresAt < Date.now() || (x.kind === 'push' && x.status !== 'queued' && !x.inApp)).sort((a,b)=>b[1].createdAt-a[1].createdAt).slice(100);
      for (const [oldKey] of removable) await this.state.storage.delete(oldKey);
      if (records.size - removable.length >= 250) return reply({ error: 'Слишком много активных сообщений' }, 409);
      await this.state.storage.put(key, item);
      if (item.kind === 'push') await this.scheduleNext();
      return reply({ ok: true, message: item });
    }
    return reply({ error: 'not found' }, 404);
  }
  async _runAlarm() {
    const config = { ...DEFAULT_NOTIFICATION_CONFIG, ...await this.state.storage.get('config') };
    if (!config.pushEnabled || !pushConfigured(this.env)) return;
    const records = await this.state.storage.list({ prefix: 'message:' });
    const now = Date.now();
    const due = [...records.entries()].filter(([,x]) => x.kind === 'push' && x.status === 'queued' && x.enabled && (x.startAt || 0) <= now);
    const next = due.sort((a,b)=>(a[1].startAt||a[1].createdAt)-(b[1].startAt||b[1].createdAt))[0];
    if (next) {
      const [key, item] = next;
      if (item.expiresAt <= now) item.status = 'expired';
      else {
        // Persist sending before the network request. A restart must not repeat a broadcast.
        item.status = 'sending'; await this.state.storage.put(key, item);
        try { item.providerId = await sendPush(this.env, item); item.status = 'accepted'; item.sentAt = Date.now(); }
        catch (error) { item.status = error.unknown ? 'unknown' : 'failed'; item.error = error.message; }
      }
      await this.state.storage.put(key, item);
    }
    await this.scheduleNext();
  }
  alarm() { return this.serial(() => this._runAlarm()); }
}
export async function notificationRequest(env, path, method = 'GET', body) {
  if (!env.NOTIFICATIONS) return reply({ error: 'Уведомления не подключены' }, 503);
  const stub = env.NOTIFICATIONS.get(env.NOTIFICATIONS.idFromName('admin-notifications'));
  return stub.fetch('https://notifications' + path, { method, ...(body ? { body: JSON.stringify(body) } : {}) });
}

// ── Images: uploaded from the admin, stored in KV, served publicly (FCM and
// the app download them by URL). 1 MB, JPEG/PNG/WebP/GIF only.
export const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
export const IMAGE_MAX_BYTES = 1024 * 1024;
export async function uploadNotificationImage(request, env, origin) {
  if (!env.INSTALLS) return reply({ error: 'Хранилище недоступно' }, 503);
  const type = (request.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
  if (!IMAGE_TYPES.includes(type)) return reply({ error: 'Поддерживаются JPEG, PNG, WebP, GIF' }, 400);
  const bytes = await request.arrayBuffer();
  if (!bytes.byteLength) return reply({ error: 'Пустой файл' }, 400);
  if (bytes.byteLength > IMAGE_MAX_BYTES) return reply({ error: 'Картинка больше 1 МБ — сожмите её' }, 413);
  const id = crypto.randomUUID();
  await env.INSTALLS.put('ntimg:' + id, bytes, { metadata: { type }, expirationTtl: 120 * 86400 });
  return reply({ ok: true, url: origin + '/api/notifications/image/' + id });
}
export async function serveNotificationImage(env, id) {
  if (!/^[a-f0-9-]{36}$/.test(id) || !env.INSTALLS) return new Response('not found', { status: 404 });
  const { value, metadata } = await env.INSTALLS.getWithMetadata('ntimg:' + id, { type: 'arrayBuffer' });
  if (!value) return new Response('not found', { status: 404 });
  return new Response(value, { headers: { 'content-type': metadata?.type || 'image/jpeg', 'cache-control': 'public, max-age=31536000, immutable', 'Access-Control-Allow-Origin': '*' } });
}
