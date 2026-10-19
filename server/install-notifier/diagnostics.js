import { sanitizeDiagnosticContext, diagnosticOs } from './diagnostic_context.js';
import { readSession, tokenHash } from './user_auth.js';
import { incidentCopy, incidentGuide, providerLabel, platformLabel, storeLabel } from './incident_copy.js';

const escape = value => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const tag = (value, fallback = 'unknown') => typeof value === 'string' && /^[a-zA-Z0-9_.:-]{1,80}$/.test(value) ? value : fallback;
const GROUPS = { auth: 'Не удалось войти', purchase: 'Ошибка Premium / оплаты', app: 'Ошибка приложения', infrastructure: 'Сбой инфраструктуры' };
const text = (value, max) => typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, max) : null;
const reportedResponses = new WeakSet();
export const isIncidentReported = response => reportedResponses.has(response);
export function markIncidentReported(response) { reportedResponses.add(response); return response; }

// Only server-built payment details are accepted. Never forward provider bodies,
// exception messages, checkout URLs, credentials or arbitrary metadata.
function paymentContext(value) {
  if (!value || typeof value !== 'object') return null;
  return {
    orderId: typeof value.orderId === 'string' && /^[0-9a-f-]{36}$/.test(value.orderId) ? value.orderId : null,
    txId: typeof value.txId === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(value.txId) ? value.txId : null,
    tier: ['weekly', 'threeMonths'].includes(value.tier) ? value.tier : null,
    amountRub: Number.isFinite(value.amountRub) && value.amountRub > 0 && value.amountRub <= 1000000 ? value.amountRub : null,
    method: value.method === 'sbp' ? 'sbp' : null,
    client: ['android', 'web'].includes(value.client) ? value.client : null,
    providerOperation: ['create', 'status'].includes(value.providerOperation) ? value.providerOperation : null,
    providerStatus: Number.isInteger(value.providerStatus) && value.providerStatus >= 400 && value.providerStatus <= 599 ? value.providerStatus : null,
  };
}
export function errorCode(error) {
  // Never forward exception messages: SDK errors can contain URLs and tokens.
  if (/too many requests.*same key|(?:put|write).*429|(?:put|write).*rate.?limit/i.test(String(error?.message || ''))) return 'storage_rate_limited';
  if (/quota|limit exceeded|too many writes/i.test(String(error?.message || ''))) return 'storage_quota';
  if (error?.name === 'TimeoutError' || error?.name === 'AbortError') return 'timeout';
  return 'operation_failed';
}
export function buildIncidentMessage(event, repeats = 0, overflow = 0) {
  const copy = incidentCopy(event);
  const guide = incidentGuide(event);
  const account = event.userName || (event.userId ? 'Имя не получено' : 'Аккаунт ещё не определён');
  const authProvider = event.authProvider || (['google', 'apple', 'yandex'].includes(event.provider) ? event.provider : null);
  const ids = [
    event.userId ? 'ID аккаунта: <code>' + escape(event.userId) + '</code>' : null,
    event.installation ? 'Установка: <code>' + escape(event.installation) + '</code>' : null,
    event.diagnosticId ? 'Диагностика: <code>' + escape(event.diagnosticId) + '</code>' : null,
  ];
  return [
    guide.emoji + ' <b>' + copy.title + '</b>',
    '<b>Причина:</b> ' + copy.reason + (guide.what ? ' ' + guide.what : ''),
    guide.steps[0] ? '→ ' + guide.steps[0] : null,
    event.payment ? (event.operation === 'api.user.pay-intent'
      ? 'Форма оплаты не выдана: человек не смог начать оплату.'
      : 'Подтверждение оплаты не завершено. Если человек уже оплатил, повторно платить не нужно.') : null,
    event.payment ? '💳 ' + [event.payment.method === 'sbp' ? 'СБП' : null, event.payment.amountRub ? event.payment.amountRub + ' ₽' : null,
      ({ weekly: '1 неделя', threeMonths: '3 месяца' })[event.payment.tier]].filter(Boolean).join(' · ') : null,
    event.payment?.client ? '🌐 Оплата из: ' + (event.payment.client === 'android' ? 'приложения Android' : 'веб-версии') : null,
    event.payment?.providerOperation ? 'Запрос Platega: ' + (event.payment.providerOperation === 'create' ? 'POST /transaction/process' : 'GET /transaction/{id}') +
      (event.payment.providerStatus ? ' · HTTP ' + event.payment.providerStatus : '') : null,
    event.payment?.orderId ? 'Заказ: <code>' + escape(event.payment.orderId) + '</code>' : null,
    event.payment?.txId ? 'Транзакция Platega: <code>' + escape(event.payment.txId) + '</code>' : null,
    '',
    event.userId || event.category !== 'infrastructure' ? '👤 ' + escape(account) : null,
    event.userEmail ? '✉️ ' + escape(event.userEmail) : null,
    authProvider ? '🔑 Вход: ' + providerLabel(authProvider) : null,
    event.provider && event.provider !== authProvider ? '🧩 Сервис: ' + providerLabel(event.provider) : null,
    event.platform ? '📱 ' + platformLabel(event.platform) + (event.appVersion ? ' v' + escape(event.appVersion) : '') : null,
    event.store ? '🏪 ' + storeLabel(event.store) : null,
    event.device ? '📟 ' + escape(event.device) : null,
    event.context?.errorType ? 'Исключение: ' + escape(event.context.errorType) : null,
    event.os ? 'ОС: ' + escape(event.os) : null,
    event.context?.phase ? 'Загрузка: ' + ({ background: 'в фоне', paywall: 'экран оплаты', purchase: 'попытка покупки' })[event.context.phase] : null,
    event.context?.stage ? 'Этап: ' + escape(event.context.stage) + (event.context.attempt ? ' · попытка ' + event.context.attempt : '') : null,
    Number.isInteger(event.context?.returnedCount) ? `Товары: запрошено ${event.context.requestedCount ?? '—'}, получено ${event.context.returnedCount}, не найдено ${event.context.missingCount ?? '—'}` : null,
    event.context?.sdkCodeHash ? 'Код SDK (отпечаток): ' + escape(event.context.sdkCodeHash) : null,
    event.context?.frames?.length ? 'Место: <code>' + escape(event.context.frames[0]) + '</code>' : null,
    event.country ? '🌍 ' + escape(event.country) : null,
    '',
    (event.origin === 'client' ? 'Приложение' : 'Сервер') + ': <code>' + escape(event.operation) + '</code>',
    'Код: <code>' + escape(event.code) + '</code>' + (event.status ? ' · HTTP ' + event.status : ''),
    repeats ? '🔁 Повторов с прошлого сообщения: ' + repeats : null,
    overflow ? 'Других сообщений ограничено: ' + overflow : null,
    ...ids,
    '🕒 ' + new Date(event.ts).toLocaleString('ru-RU', { timeZone: 'Europe/Moscow' }) + ' МСК',
  ].filter(line => line !== null).join('\n');
}

async function incidentUser(env, userId, fallback) {
  if (!userId) return null;
  const trusted = fallback?.id === userId ? fallback : {};
  try {
    const raw = await env.INSTALLS?.get('user:' + userId);
    const stored = raw ? JSON.parse(raw) : null;
    if (stored?.id === userId) return { ...trusted, ...stored };
  } catch (_) {
    // A failed account lookup must not hide a storage outage notification.
  }
  return trusted;
}

export async function reportIncident(env, incident) {
  try {
    if (!env.TELEGRAM || !env.BOT_TOKEN || !env.CHAT_ID) return false;
    const userId = text(incident.userId, 200);
    const user = await incidentUser(env, userId, incident.user);
    const event = {
      id: tag(incident.id, crypto.randomUUID()), ts: Number.isFinite(incident.ts) ? incident.ts : Date.now(),
      origin: incident.origin === 'client' ? 'client' : 'server',
      category: Object.hasOwn(GROUPS, incident.category) ? incident.category : 'infrastructure',
      operation: tag(incident.operation), code: tag(incident.code),
      provider: incident.provider ? tag(incident.provider) : null,
      platform: tag(incident.platform || user?.platform, null),
      store: tag(incident.store, null),
      appVersion: typeof (incident.appVersion || user?.appVersion) === 'string' && /^[\d.+-]{1,32}$/.test(incident.appVersion || user?.appVersion) ? incident.appVersion || user.appVersion : null,
      device: text(incident.device || user?.device, 100),
      os: diagnosticOs(incident.os),
      context: sanitizeDiagnosticContext(incident.context),
      userId,
      userName: text(user?.name, 120), userEmail: text(user?.email, 160),
      country: /^[A-Z]{2}$/.test(String(user?.ipCountry ?? '')) ? user.ipCountry : null,
      authProvider: tag(user?.provider, null),
      installation: typeof incident.installation === 'string' && /^[a-f0-9]{16}$/.test(incident.installation) ? incident.installation : null,
      diagnosticId: typeof incident.diagnosticId === 'string' && /^[a-f0-9-]{36}$/.test(incident.diagnosticId) ? incident.diagnosticId : null,
      status: Number.isInteger(incident.status) && incident.status >= 400 && incident.status <= 599 ? incident.status : null,
      payment: incident.origin === 'client' ? null : paymentContext(incident.payment),
    };
    if (event.diagnosticId) console.log(JSON.stringify({ event: 'incident', diagnosticId: event.diagnosticId, operation: event.operation, code: event.code, status: event.status }));
    // Group the same failure across accounts to keep a widespread outage readable.
    const contextKey = [event.context.phase || '', event.context.stage || '', event.context.sdkCodeHash || '', event.context.frames?.[0] || ''];
    // Preserve existing durable groups for clients that have no new context.
    const fingerprint = await tokenHash([event.origin, event.category, event.operation, event.code, event.provider, event.platform, event.appVersion, ...(contextKey.some(Boolean) ? contextKey : [])].join('|'));
    const response = await env.TELEGRAM.get(env.TELEGRAM.idFromName(String(env.CHAT_ID))).fetch('https://telegram/incident', {
      method: 'POST', body: JSON.stringify({ incident: event, fingerprint }),
    });
    return response.ok;
  } catch (_) {
    // Reporting must never change the outcome or recursively report itself.
    console.error('Incident notification unavailable');
    return false;
  }
}

export function deferIncident(ctx, env, event) {
  const task = reportIncident(env, event);
  if (ctx?.waitUntil) ctx.waitUntil(task);
  return task;
}

export async function handleClientIncident(request, env) {
  if (!env.SHARED_SECRET || request.headers.get('x-install-secret') !== env.SHARED_SECRET) return Response.json({ error: 'forbidden' }, { status: 403 });
  // Bound actual bytes as well as the declared length (chunked requests included).
  const reader = request.body?.getReader();
  if (!reader) return Response.json({ error: 'invalid body' }, { status: 400 });
  const chunks = []; let size = 0;
  while (true) {
    const { done, value } = await reader.read(); if (done) break;
    size += value.length;
    if (size > 16384) { await reader.cancel(); return Response.json({ error: 'too large' }, { status: 413 }); }
    chunks.push(value);
  }
  let body;
  try { const bytes = new Uint8Array(size); let i = 0; for (const c of chunks) { bytes.set(c, i); i += c.length; } body = JSON.parse(new TextDecoder().decode(bytes)); }
  catch { return Response.json({ error: 'invalid json' }, { status: 400 }); }
  if (!body || typeof body.installId !== 'string' || !/^[a-f0-9]{32}$/.test(body.installId) || !Array.isArray(body.events) || !body.events.length || body.events.length > 10) return Response.json({ error: 'invalid events' }, { status: 400 });
  const now = Date.now();
  if (body.events.some(e => !e || typeof e.id !== 'string' || !/^[a-f0-9]{32}$/.test(e.id) || !Number.isFinite(e.ts) || e.ts > now + 300000 || e.ts < now - 7 * 86400000 || !['auth', 'purchase', 'app'].includes(e.category) || tag(e.operation) === 'unknown' || tag(e.code) === 'unknown')) return Response.json({ error: 'invalid event' }, { status: 400 });
  const session = await readSession(request, env);
  const installation = (await tokenHash(body.installId)).slice(0, 16);
  for (const event of body.events) {
    const accepted = await reportIncident(env, {
      ...event, origin: 'client', installation,
      // Account identity is verified, including when an offline outbox retries.
      userId: session?.user?.id && event.userId === session.user.id ? session.user.id : null,
      user: session?.user?.id && event.userId === session.user.id ? session.user : null,
    });
    if (!accepted) return Response.json({ error: 'unavailable' }, { status: 503 });
  }
  return Response.json({ ok: true });
}
