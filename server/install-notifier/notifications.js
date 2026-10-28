import { updateKey, validateRelease } from './app_updates.js';
import { reportIncident, errorCode } from './diagnostics.js';
import { durableRequest } from './durable_request.js';
import { importPKCS8, SignJWT } from 'jose';

export const DEFAULT_NOTIFICATION_CONFIG = Object.freeze({ pushEnabled: false, popupEnabled: true, streakEnabled: true, gameEnabled: true });
const reply = (value, status = 200) => Response.json(value, { status, headers: { 'Cache-Control': 'no-store' } });
// popup  — modal window on the home screen (one show per device);
// banner — dismissible card at the top of the home screen (non-blocking);
// push   — system notification via FCM. In the app it is listed in the inbox
//          or, on devices the push did not reach, shown as a window or banner
//          (`inAppKind`).
// news   — entry in the app's notification inbox only (no window, no push).
export const KINDS = ['popup', 'banner', 'push', 'news'];
export const IN_APP_KINDS = ['news', 'popup', 'banner'];
// What a campaign is in the app. Pushes saved before `inAppKind` had `inApp`.
export const placement = item => item.kind !== 'push' ? item.kind : (IN_APP_KINDS.includes(item.inAppKind) ? item.inAppKind : item.inApp ? 'popup' : 'news');
// Push display budget (iOS ≈ one line of title and four of text on the lock
// screen, Android ≈ one line each when collapsed). Longer text is cut there.
export const PUSH_TITLE_MAX = 50;
export const PUSH_BODY_MAX = 300;
export const ACTIONS = ['none', 'url', 'tickets', 'topics', 'game', 'feed', 'settings', 'premium'];
export const LAYOUTS = ['standard', 'cover', 'compact', 'image'];
const choices = { kind: KINDS, app: ['all', 'ru', 'by', 'rs'], platform: ['all', 'ios', 'android', 'web', 'some'] };
export const PLATFORMS = ['ios', 'android', 'web'];
// Any set of platforms. One or all three keep the single `platform` value;
// two are stored as platform 'some' plus `platforms` ("ios,web").
export const platformsOf = item => item.platform === 'all' ? PLATFORMS
  : item.platform === 'some' ? String(item.platforms || '').split(',').filter(p => PLATFORMS.includes(p)) : [item.platform];
const DAY = 86400000;
// Numeric on the wire so existing inbox clients can also keep permanent news.
const PERMANENT_EXPIRES_AT = 253402300799999;
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
  if (Array.isArray(input?.platforms)) {
    const picked = PLATFORMS.filter(p => input.platforms.includes(p));
    if (!picked.length || input.platforms.some(p => !PLATFORMS.includes(p))) throw new Error('Выберите платформу');
    normalized.platform = picked.length === 3 ? 'all' : picked.length === 1 ? picked[0] : 'some';
    value.platforms = normalized.platform === 'some' ? picked.join(',') : '';
  } else if (input?.platform === 'some') throw new Error('Некорректный тип или аудитория');
  else value.platforms = '';
  for (const [key, allowed] of Object.entries(choices)) {
    value[key] = normalized?.[key];
    if (!allowed.includes(value[key])) throw new Error('Некорректный тип или аудитория');
  }
  // A push to 'all' means every phone; the web is never a push target.
  if (value.kind === 'push' && value.platform !== 'all' && platformsOf(value).includes('web')) throw new Error('Веб-пуши пока не поддерживаются');
  // Android store (Google Play / RuStore) for in-app messages only: push topics
  // are per platform. Builds that do not report a store never match a store.
  value.store = input.store === undefined || input.store === '' ? 'all' : input.store;
  if (!['all', 'play', 'rustore'].includes(value.store)) throw new Error('Некорректный магазин');
  if (value.store !== 'all' && !platformsOf(value).includes('android')) throw new Error('Магазин выбирается только для Android');
  if (value.store !== 'all' && value.kind === 'push') throw new Error('Пуш нельзя отправить в один магазин — выберите окно или баннер');
  value.layout = input.layout || 'standard';
  if (!LAYOUTS.includes(value.layout)) throw new Error('Некорректный макет');
  if (value.kind === 'push') {
    // A system notification needs text: a picture alone shows nothing.
    if (value.layout === 'image') throw new Error('Пуш не может состоять только из картинки');
    value.title = str(input.title, PUSH_TITLE_MAX, 'Заголовок пуша');
    value.body = str(input.body, PUSH_BODY_MAX, 'Текст пуша');
    if (!value.title && !value.body) throw new Error('Пушу нужен заголовок или текст');
  } else {
    // Windows and banners are composed from optional parts: picture, title,
    // text and button. Without any text the message is the picture itself.
    value.title = str(input.title, 80, 'Заголовок');
    value.body = str(input.body, 1000, 'Текст');
    value.layout = value.title || value.body ? (value.layout === 'image' ? 'standard' : value.layout) : 'image';
  }
  const imageBanner = value.layout === 'image';
  // Shown in the app on devices without the push. Old saves had only `inApp`.
  value.inAppKind = value.kind !== 'push' ? '' : input.inAppKind === undefined || input.inAppKind === '' ? (input.inApp === true ? 'popup' : 'news') : input.inAppKind;
  if (value.kind === 'push' && !IN_APP_KINDS.includes(value.inAppKind)) throw new Error('Некорректный вид в приложении');
  value.inApp = value.inAppKind === 'popup';
  if (placement(value) === 'banner' && value.body.length > 200) throw new Error('Текст баннера: не более 200 символов');
  value.id = input.id;
  if (typeof value.id !== 'string' || !/^[a-f0-9-]{36}$/.test(value.id)) throw new Error('Некорректный ID сообщения');
  // Optional scheduling: start in the future (≤ 30 days), show until expiresAt.
  value.startAt = input.startAt === undefined || input.startAt === null || input.startAt === '' ? now : Number(input.startAt);
  if (!Number.isFinite(value.startAt) || value.startAt > now + 30 * DAY) throw new Error('Время старта: не позже чем через 30 дней');
  if (value.startAt < now) value.startAt = now;
  if (input.persistent !== undefined && typeof input.persistent !== 'boolean') throw new Error('Некорректный срок показа');
  value.persistent = input.persistent === true;
  if (value.persistent && value.kind !== 'news') throw new Error('Постоянные уведомления доступны только в списке');
  value.expiresAt = value.persistent ? PERMANENT_EXPIRES_AT : Number(input.expiresAt);
  if (!value.persistent && (!Number.isFinite(value.expiresAt) || value.expiresAt <= value.startAt || value.expiresAt > value.startAt + 30 * DAY)) throw new Error('Срок показа: от времени старта до 30 дней');
  // Personal test account (email or user ID). Empty = broadcast to all users.
  value.target = str(input.target, 120, 'Аккаунт для теста').toLowerCase();
  value.targetTopic = typeof input.targetTopic === 'string' && /^pdd_account_[a-f0-9]{64}$/.test(input.targetTopic) ? input.targetTopic : '';
  if (value.target && /[\s'"<>]/.test(value.target)) throw new Error('Аккаунт для теста: укажите корректный email или ID');
  // Customization.
  value.imageUrl = httpsUrl(input.imageUrl, 'Картинка');
  if (imageBanner && !value.imageUrl) throw new Error('Добавьте картинку, заголовок или текст');
  value.emoji = str(input.emoji, 8, 'Эмодзи');
  value.accent = input.accent ? String(input.accent) : '';
  if (value.accent && !/^#[0-9a-fA-F]{6}$/.test(value.accent)) throw new Error('Цвет: формат #RRGGBB');
  // Absent on campaigns saved before buttons became optional: they had one.
  value.button = !imageBanner && input.button !== false;
  value.buttonText = value.button ? str(input.buttonText, 24, 'Текст кнопки') : '';
  value.dismissText = value.button ? str(input.dismissText, 24, 'Текст второй кнопки') : '';
  value.action = input.action || 'none';
  if (!ACTIONS.includes(value.action)) throw new Error('Некорректное действие');
  value.actionUrl = value.action === 'url' ? httpsUrl(input.actionUrl, 'Ссылка действия') : '';
  if (value.action === 'url' && !value.actionUrl) throw new Error('Укажите ссылку для кнопки');
  value.createdAt = now;
  value.enabled = true;
  value.status = value.kind === 'push' ? 'queued' : (value.startAt > now ? 'scheduled' : 'published');
  return value;
}
const SAME_FIELDS = ['kind', 'title', 'body', 'app', 'platform', 'store', 'platforms', 'expiresAt', 'persistent', 'target', 'imageUrl', 'emoji', 'accent', 'layout', 'button', 'buttonText', 'dismissText', 'action', 'actionUrl', 'inApp', 'inAppKind'];
export function campaignMatches(item, app, platform, now = Date.now(), user = {}, store = '') {
  if (!item.enabled || item.expiresAt <= now || (item.startAt || 0) > now) return false;
  if (item.app !== 'all' && item.app !== app) return false;
  if (!platformsOf(item).includes(platform)) return false;
  // The Android store only narrows Android devices.
  if (platform === 'android' && item.store && item.store !== 'all' && item.store !== store) return false;
  if (item.target) {
    const t = item.target.toLowerCase();
    const uid = String(user.userId || '').trim().toLowerCase();
    const email = String(user.email || '').trim().toLowerCase();
    return Boolean(t && (t === uid || t === email));
  }
  return true;
}
/** Shape sent to the app: only display fields, never internal state. `push`
 *  marks a campaign also sent as a push: devices that receive pushes list it
 *  in the inbox only, without a window or banner. */
export function clientMessage(item, seenIds = []) {
  return { id: item.id, kind: placement(item), push: item.kind === 'push', title: item.title, body: item.body, expiresAt: item.expiresAt, createdAt: item.createdAt,
    ...(item.persistent ? { persistent: true } : {}), ...(seenIds.length ? { seenIds } : {}),
    imageUrl: item.imageUrl || '', emoji: item.emoji || '', accent: item.accent || '', layout: item.layout || 'standard',
    button: item.button !== false && item.layout !== 'image', buttonText: item.buttonText || '', dismissText: item.dismissText || '', action: item.action || 'none', actionUrl: item.actionUrl || '' };
}
// A test followed by an identical broadcast is one message for its recipient.
// Keep independent broadcasts and subsequent explicit tests separate. Aliases
// carry the already-seen test ID into the broadcast's one-time display state.
function clientFeed(records, visible, app, platform, user, store) {
  const presentation = item => {
    const { id, createdAt, expiresAt, ...fields } = clientMessage(item);
    return JSON.stringify(fields);
  };
  const audienceMatches = item => campaignMatches(
    { ...item, enabled: true, startAt: 0, expiresAt: PERMANENT_EXPIRES_AT }, app, platform, Date.now(), user, store,
  );
  const candidates = [...records.values()].filter(audienceMatches).map(item => ({ item, signature: presentation(item) }));
  const broadcasts = candidates.filter(({ item }) => !item.target).sort((a,b) => a.item.createdAt-b.item.createdAt || a.item.id.localeCompare(b.item.id));
  const aliasesById = new Map();
  for (const test of candidates.filter(({ item }) => item.target)) {
    const broadcast = broadcasts.find(candidate => candidate.signature === test.signature
      && test.item.createdAt <= candidate.item.createdAt && test.item.expiresAt > candidate.item.createdAt);
    if (broadcast) {
      const aliases = aliasesById.get(broadcast.item.id) || [];
      aliases.push(test.item.id);
      aliasesById.set(broadcast.item.id, aliases);
    }
  }
  const covered = new Set();
  const result = visible.map(item => {
    const aliases = aliasesById.get(item.id) || [];
    aliases.forEach(id => covered.add(id));
    return clientMessage(item, aliases);
  });
  return result.filter(item => !covered.has(item.id));
}
export function pushCondition(item) {
  if (item.target) {
    if (!/^pdd_account_[a-f0-9]{64}$/.test(item.targetTopic || '')) throw new Error('Пересоздайте адресный пуш с защищённым аккаунтом');
    const topic = `'${item.targetTopic}' in topics`;
    const mobile = platformsOf(item).filter(p => p !== 'web');
    if (mobile.length === 1) {
      const app = item.app === 'all' ? 'ru' : item.app;
      return `${topic} && 'pdd_${app}_${mobile[0]}' in topics`;
    }
    return topic;
  }
  // Each installation subscribes to exactly one country/platform topic.
  const apps = item.app === 'all' ? ['ru', 'by', 'rs'] : [item.app];
  const platforms = platformsOf(item).filter(p => p !== 'web');
  const topics = apps.flatMap(app => platforms.map(platform => `'pdd_${app}_${platform}' in topics`));
  // FCM conditions allow at most five topics. All six use the common mobile topic.
  return topics.length === 6 ? "'pdd_mobile' in topics" : topics.join(' || ');
}
export function pushConfigured(env) {
  try { const key = JSON.parse(env.FCM_SERVICE_ACCOUNT || '{}'); return Boolean(key.project_id && key.client_email && key.private_key); } catch { return false; }
}
export function buildPushMessage(campaign, now = Date.now()) {
  const ttl = Math.max(1, Math.min(86400, Math.floor((campaign.expiresAt - now) / 1000)));
  const title = campaign.emoji && campaign.title ? campaign.emoji + ' ' + campaign.title : campaign.title;
  // Title-only and text-only pushes omit the empty line.
  const notification = { ...(title ? { title } : {}), ...(campaign.body ? { body: campaign.body } : {}), ...(campaign.imageUrl ? { image: campaign.imageUrl } : {}) };
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
  return sendFcmMessage(env, buildPushMessage(campaign), fetcher);
}
// One FCM v1 message (campaigns, support replies): shared OAuth token cache.
export async function sendFcmMessage(env, message, fetcher = fetch) {
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
      body: JSON.stringify({ message }),
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
  serial(fn) { const result = this.tail.then(fn); this.tail = result.then(() => {}, () => {}); return result; }
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
    if (path === '/updates') {
      const url = new URL(request.url);
      try {
        const key = updateKey(url.searchParams.get('app'), url.searchParams.get('platform'));
        return reply({ release: await this.state.storage.get(key) || null });
      } catch { return reply({ error: 'invalid audience' }, 400); }
    }
    if (path === '/updates/admin' && request.method === 'GET') {
      const releases = await this.state.storage.list({ prefix: 'release:' });
      return reply({ releases: [...releases.values()] });
    }
    if (path === '/updates/save' && request.method === 'POST') {
      try {
        const release = validateRelease(await request.json());
        await this.state.storage.put(updateKey(release.app, release.platform), release);
        return reply({ ok: true, release });
      } catch (error) { return reply({ error: error.message }, 400); }
    }
    if (path === '/client') {
      const url = new URL(request.url), app = url.searchParams.get('app'), platform = url.searchParams.get('platform');
      const user = { userId: url.searchParams.get('userId') || '', email: url.searchParams.get('email') || '' };
      if (!['ru','by','rs'].includes(app) || !['ios','android','web'].includes(platform)) return reply({ error: 'invalid audience' }, 400);
      const records = await this.state.storage.list({ prefix: 'message:' });
      // Older clients treat unknown layouts as standard cards and would show an
      // empty card. Only send image banners to builds declaring support.
      const imageBanners = url.searchParams.get('imageBanners') === '1';
      // Picture-only windows arrived later than picture-only banners.
      const imagePopups = imageBanners && url.searchParams.get('imagePopups') === '1';
      // Older clients would show inbox news as a popup window.
      const inbox = url.searchParams.get('inbox') === '1';
      // A sent push also lands in the inbox of builds that have one. Its window
      // or banner is visible before sending: devices without pushes need it.
      const sent = item => ['accepted', 'unknown'].includes(item.status);
      const visible = config.popupEnabled ? [...records.values()].filter(item => {
        const shown = placement(item);
        if (item.kind === 'push' && shown === 'news' && !sent(item)) return false;
        return (shown !== 'news' || inbox) && (item.layout !== 'image' || (shown === 'banner' ? imageBanners : imagePopups))
          && campaignMatches(item, app, platform, Date.now(), user, url.searchParams.get('store') || '');
      }) : [];
      const messages = clientFeed(records, visible, app, platform, user, url.searchParams.get('store') || '');
      return reply({ config, messages: messages.sort((a,b) => b.createdAt-a.createdAt).slice(0, inbox ? 250 : 10) });
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
      // A sent push cannot be recalled from devices; disabling hides it from the
      // in-app list. A push still sending or failed has no list entry to hide.
      if (item.kind === 'push' && !['queued', 'accepted', 'unknown'].includes(item.status) && placement(item) === 'news') return reply({ error: 'Отправленный пуш нельзя отозвать' }, 409);
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
        if (SAME_FIELDS.some(field => (existing[field] ?? (field === 'persistent' ? false : '')) !== (item[field] ?? (field === 'persistent' ? false : '')))) return reply({ error: 'ID уже принадлежит другому сообщению' }, 409);
        return reply({ ok: true, message: existing, duplicate: true });
      }
      if (item.kind === 'push' && (!config.pushEnabled || !pushConfigured(this.env))) return reply({ error: 'Пуши отключены или Firebase не подключён' }, 409);
      if (item.kind !== 'push' && !config.popupEnabled) return reply({ error: 'Сообщения в приложении отключены' }, 409);
      const records = await this.state.storage.list({ prefix: 'message:' });
      // Keep the latest 100 completed/expired messages, never evict active popups/queued pushes.
      const removable = [...records.entries()].filter(([,x]) => x.expiresAt < Date.now() || (x.kind === 'push' && x.status !== 'queued' && placement(x) === 'news')).sort((a,b)=>b[1].createdAt-a[1].createdAt).slice(100);
      for (const [oldKey] of removable) await this.state.storage.delete(oldKey);
      if (records.size - removable.length >= 250) return reply({ error: 'Слишком много активных сообщений' }, 409);
      // Images uploaded before permanent news had a 120-day KV expiration.
      // Remove that expiration when such an image is used by permanent news.
      const imageId = item.persistent && new URL(item.imageUrl || 'https://unused.invalid').pathname.match(/^\/api\/notifications\/image\/([a-f0-9-]{36})$/)?.[1];
      if (imageId && this.env.INSTALLS) {
        const image = await this.env.INSTALLS.getWithMetadata('ntimg:' + imageId, { type: 'arrayBuffer' });
        if (image.value) await this.env.INSTALLS.put('ntimg:' + imageId, image.value, { metadata: image.metadata });
      }
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
        catch (error) {
          item.status = error.unknown ? 'unknown' : 'failed'; item.error = error.message;
          await reportIncident(this.env, { category: 'infrastructure', operation: 'notifications.push', code: error.unknown ? 'delivery_unknown' : errorCode(error), provider: 'firebase' });
        }
      }
      await this.state.storage.put(key, item);
    }
    await this.scheduleNext();
  }
  alarm() { return this.serial(() => this._runAlarm()); }
}
export async function notificationRequest(env, path, method = 'GET', body) {
  if (!env.NOTIFICATIONS) return reply({ error: 'Уведомления не подключены' }, 503);
  const retryableRead = method === 'GET' && ['/client', '/admin', '/updates', '/updates/admin']
    .includes(new URL('https://notifications' + path).pathname);
  return durableRequest(env.NOTIFICATIONS, env.NOTIFICATIONS.idFromName('admin-notifications'),
    stub => stub.fetch('https://notifications' + path, { method, ...(body ? { body: JSON.stringify(body) } : {}) }),
    { retryableRead });
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
