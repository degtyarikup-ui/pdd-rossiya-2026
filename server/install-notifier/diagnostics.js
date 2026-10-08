import { readSession, tokenHash } from './user_auth.js';

const escape = value => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const tag = (value, fallback = 'unknown') => typeof value === 'string' && /^[a-zA-Z0-9_.:-]{1,80}$/.test(value) ? value : fallback;
const GROUPS = { auth: 'Не удалось войти', purchase: 'Ошибка Premium / оплаты', app: 'Ошибка приложения', infrastructure: 'Сбой инфраструктуры' };
export function errorCode(error) {
  // Never forward exception messages: SDK errors can contain URLs and tokens.
  if (/quota|limit exceeded|too many writes/i.test(String(error?.message || ''))) return 'storage_quota';
  if (error?.name === 'TimeoutError' || error?.name === 'AbortError') return 'timeout';
  return 'operation_failed';
}
export function buildIncidentMessage(event, repeats = 0, overflow = 0) {
  return [
    '🚨 <b>' + (GROUPS[event.category] || GROUPS.infrastructure) + '</b>',
    '',
    '• <b>Источник:</b> ' + (event.origin === 'client' ? 'Приложение' : 'Сервер'),
    '• <b>Этап:</b> <code>' + escape(event.operation) + '</code>',
    '• <b>Код:</b> <code>' + escape(event.code) + '</code>',
    event.status ? '• <b>HTTP:</b> ' + event.status : null,
    event.provider ? '• <b>Вход / магазин:</b> ' + escape(event.provider) : null,
    event.platform ? '• <b>Платформа:</b> ' + escape(event.platform) + (event.appVersion ? ' · v' + escape(event.appVersion) : '') : null,
    event.device ? '• <b>Устройство:</b> ' + escape(event.device) : null,
    event.userId ? '• <b>Аккаунт:</b> <code>' + escape(event.userId) + '</code>' : null,
    event.installation ? '• <b>Установка:</b> <code>' + escape(event.installation) + '</code>' : null,
    event.diagnosticId ? '• <b>Диагностика:</b> <code>' + escape(event.diagnosticId) + '</code>' : null,
    repeats ? '• <b>Повторов с прошлого сообщения:</b> ' + repeats : null,
    overflow ? '• <b>Других сообщений ограничено:</b> ' + overflow : null,
    '',
    '🕒 ' + new Date(event.ts).toLocaleString('ru-RU', { timeZone: 'Europe/Moscow' }) + ' МСК',
  ].filter(line => line !== null).join('\n');
}

export async function reportIncident(env, incident) {
  try {
    if (!env.TELEGRAM || !env.BOT_TOKEN || !env.CHAT_ID) return false;
    const event = {
      id: tag(incident.id, crypto.randomUUID()), ts: Number.isFinite(incident.ts) ? incident.ts : Date.now(),
      origin: incident.origin === 'client' ? 'client' : 'server',
      category: Object.hasOwn(GROUPS, incident.category) ? incident.category : 'infrastructure',
      operation: tag(incident.operation), code: tag(incident.code),
      provider: incident.provider ? tag(incident.provider) : null,
      platform: incident.platform ? tag(incident.platform) : null,
      appVersion: typeof incident.appVersion === 'string' && /^[\d.+-]{1,32}$/.test(incident.appVersion) ? incident.appVersion : null,
      device: typeof incident.device === 'string' ? incident.device.slice(0, 100) : null,
      userId: typeof incident.userId === 'string' ? incident.userId.slice(0, 200) : null,
      installation: typeof incident.installation === 'string' && /^[a-f0-9]{16}$/.test(incident.installation) ? incident.installation : null,
      diagnosticId: typeof incident.diagnosticId === 'string' && /^[a-f0-9-]{36}$/.test(incident.diagnosticId) ? incident.diagnosticId : null,
      status: Number.isInteger(incident.status) && incident.status >= 400 && incident.status <= 599 ? incident.status : null,
    };
    // Group the same failure across accounts to keep a widespread outage readable.
    const fingerprint = await tokenHash([event.origin, event.category, event.operation, event.code, event.provider, event.platform, event.appVersion].join('|'));
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
    });
    if (!accepted) return Response.json({ error: 'unavailable' }, { status: 503 });
  }
  return Response.json({ ok: true });
}
