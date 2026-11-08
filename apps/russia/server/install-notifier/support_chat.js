import { supportIdentity, supportImageUrl } from './support_access.js';
import { boundedJson, abuseBudget, HttpFailure } from './request_security.js';
// Чат техподдержки: создание отдельной ветки (Forum Topic) в Telegram на каждого
// пользователя, отправка сообщений и приём ответов от команды через Webhook/Updates.
import { telegramChatId, handleErrorExportUpdate, pollErrorCommands } from './telegram_queue.js';
import { processTelegramAuthMessage, telegramWebhookVerified, telegramWebhookSecret } from './telegram_auth.js';
import { readSession } from './user_auth.js';
import { pushConfigured, sendFcmMessage } from './notifications.js';
import { privatePushTopic } from './notification_identity.js';
import { durableRequest } from './durable_request.js';
import { errorCode } from './diagnostics.js';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, x-install-secret, authorization, x-support-secret',
  'Access-Control-Max-Age': '86400',
};

function jsonResponse(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json', 'Cache-Control': 'no-store', ...CORS_HEADERS, ...extraHeaders },
  });
}

// Messages of one client live in a Durable Object (support_thread.js): read right after a write.
// Without the binding they fall back to KV (eventually consistent, slower to show replies).
function threadStub(env, clientId) {
  return env.SUPPORT ? env.SUPPORT.get(env.SUPPORT.idFromName(clientId)) : null;
}

function supportReadUnavailable(stage, response) {
  const error = Object.assign(new Error('Support messages unavailable'), {
    code: 'ERR_SUPPORT_READ_UNAVAILABLE', supportStage: stage,
  });
  if (Number.isInteger(response?.status) && response.status >= 400 && response.status <= 599) error.upstreamStatus = response.status;
  return error;
}

async function supportReadResponse(response, stage) {
  if (!response?.ok) throw supportReadUnavailable(stage, response);
  let result;
  try { result = await response.json(); } catch { throw supportReadUnavailable(stage, response); }
  if (!result || typeof result !== 'object' || Array.isArray(result)
      || (stage === 'seed' ? result.ok !== true
        : !Array.isArray(result.messages) || (result.ok !== undefined && result.ok !== true)
          || result.messages.some(message => !message || typeof message !== 'object' || Array.isArray(message))
          || (result.initialized !== undefined && typeof result.initialized !== 'boolean'))) {
    throw supportReadUnavailable(stage, response);
  }
  return result;
}

async function supportReadRpc(stage, send) {
  try { return await send(); }
  catch (error) {
    // Preserve Cloudflare's error identity and overload/retryable flags.
    try { if (error && typeof error === 'object') error.supportStage = stage; } catch {}
    throw error;
  }
}

async function appendSupportMessage(env, clientId, msg) {
  const stub = threadStub(env, clientId);
  if (stub) {
    const response = await stub.fetch('https://support.internal/append', { method: 'POST', body: JSON.stringify(msg) });
    const result = response.ok ? await response.json().catch(() => null) : null;
    // A returned 5xx is not an exception. Never acknowledge an unsaved message
    // (or repeat an ambiguous write automatically).
    if (result?.ok !== true) throw new HttpFailure(503, 'support storage unavailable');
    return;
  }
  const key = 'support:messages:' + clientId;
  let msgs = env.INSTALLS ? ((await env.INSTALLS.get(key, { type: 'json' })) || []) : [];
  if (!msgs.some((m) => m.id === msg.id)) {
    msgs.push(msg);
    if (msgs.length > 200) msgs = msgs.slice(-200);
    if (env.INSTALLS) await env.INSTALLS.put(key, JSON.stringify(msgs));
  }
}

async function listSupportMessages(env, clientId, since) {
  const stub = threadStub(env, clientId);
  if (!stub) {
    const key = 'support:messages:' + clientId;
    const msgs = env.INSTALLS ? ((await env.INSTALLS.get(key, { type: 'json' })) || []) : [];
    return since > 0 ? msgs.filter((m) => m.ts > since) : msgs;
  }
  const read = async () => {
    const response = await supportReadRpc('list', () => durableRequest(env.SUPPORT, env.SUPPORT.idFromName(clientId),
      fresh => fresh.fetch(`https://support.internal/list?since=${since}`), { retryableRead: true }));
    return supportReadResponse(response, 'list');
  };
  let result = await read();
  if (result.initialized === false && env.INSTALLS) {
    // Empty incremental results are normal. Only an uninitialized thread needs
    // migration; persist an empty seed too, so idle polls never recheck old KV.
    let legacy;
    try { legacy = await supportReadRpc('seed', () => env.INSTALLS.get('support:messages:' + clientId, { type: 'json' })); }
    catch (error) {
      // A JSON decoding failure proves corruption, not an empty old history.
      if (error instanceof SyntaxError) {
        try { error.code = 'ERR_SUPPORT_READ_UNAVAILABLE'; } catch {}
      }
      throw error;
    }
    if (legacy != null && (!Array.isArray(legacy)
        || legacy.some(message => !message || typeof message !== 'object' || Array.isArray(message)))) {
      throw supportReadUnavailable('seed');
    }
    const seed = await supportReadRpc('seed', () => threadStub(env, clientId).fetch('https://support.internal/seed', { method: 'POST', body: JSON.stringify(legacy ?? []) }));
    await supportReadResponse(seed, 'seed');
    result = await read();
  }
  return result.messages;
}

function escapeHtml(s) {
  return String(s ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

async function sendToTelegram(env, text, threadId = null, required = false) {
  const chatId = telegramChatId(env);
  if (!env.BOT_TOKEN || !chatId) {
    if (required) throw new HttpFailure(503, 'support delivery unavailable');
    return null;
  }
  const payload = {
    chat_id: chatId,
    text,
    parse_mode: 'HTML',
    disable_web_page_preview: true,
  };
  if (threadId) {
    payload.message_thread_id = Number(threadId);
  }
  const response = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/sendMessage`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10000),
  }).catch((err) => {
    console.warn('support text delivery unavailable');
    return null;
  });
  if (required) {
    const data = response?.ok ? await response.json().catch(() => null) : null;
    if (data?.ok !== true) throw new HttpFailure(503, 'support delivery unavailable');
  }
  return response;
}

async function sendPhotoToTelegram(env, base64Data, mimeType, caption = '', threadId = null) {
  const chatId = telegramChatId(env);
  if (!env.BOT_TOKEN || !chatId) return null;
  try {
    const binaryStr = atob(base64Data);
    const len = binaryStr.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
      bytes[i] = binaryStr.charCodeAt(i);
    }
    const cleanMime = mimeType || 'image/jpeg';
    const blob = new Blob([bytes], { type: cleanMime });
    const ext = cleanMime.includes('png') ? 'png' : 'jpg';

    const formData = new FormData();
    formData.append('chat_id', chatId);
    if (threadId) {
      formData.append('message_thread_id', String(threadId));
    }
    formData.append('photo', blob, `photo.${ext}`);
    if (caption) {
      formData.append('caption', caption.slice(0, 1024));
      formData.append('parse_mode', 'HTML');
    }

    const resp = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/sendPhoto`, {
      method: 'POST',
      body: formData,
      signal: AbortSignal.timeout(20000),
    });
    const data = await resp.json().catch(() => null);
    if (resp.ok && data?.ok && data.result) {
      return data.result;
    }
    console.warn('support photo delivery unavailable');
    return null;
  } catch (err) {
    console.warn('support photo delivery unavailable');
    return null;
  }
}

// /close (или /close@ИмяБота) в теме пользователя — обращение завершено.
const CLOSE_COMMAND = /^\/close(@\w+)?$/i;
const CLOSED_TEXT = 'Обращение завершено. Если появятся вопросы — просто напишите сюда.';

async function telegramCall(env, method, payload) {
  return fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/${method}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10000),
  }).catch((err) => {
    console.error(method + ' error:', err);
    return null;
  });
}

/**
 * Оператор закрыл обращение: пользователь получает служебное сообщение (kind: closed,
 * приложение показывает его на своём языке), тема в Telegram закрывается. Новое сообщение
 * пользователя открывает её снова (handleSupportSendMessage).
 */
async function closeSupportTicket(env, clientId, messageId, threadId) {
  const ts = Date.now();
  await appendSupportMessage(env, clientId, {
    id: 'tg_' + messageId,
    sender: 'support',
    kind: 'closed',
    text: CLOSED_TEXT,
    ts,
    authorName: 'Менеджер Сергей',
  });
  const clientKey = 'support:client:' + clientId;
  const client = env.INSTALLS ? await env.INSTALLS.get(clientKey, { type: 'json' }) : null;
  if (client) {
    client.closed = true;
    client.closedAt = ts;
    client.lastMsgAt = ts;
    await env.INSTALLS.put(clientKey, JSON.stringify(client), { expirationTtl: 90 * 86400 });
  }
  await sendToTelegram(env, '✅ Обращение завершено, пользователю отправлено уведомление. Новое сообщение откроет тему снова.', threadId);
  if (env.BOT_TOKEN) {
    await telegramCall(env, 'closeForumTopic', { chat_id: telegramChatId(env), message_thread_id: Number(threadId) });
  }
}

/**
 * Ответ оператора пушем на устройства аккаунта (личная тема FCM). Приложение
 * при открытом экране само заберёт ответ, иначе покажет системное уведомление;
 * нажатие открывает чат. Сбой пуша не мешает ответу: его заберёт опрос.
 */
export async function sendSupportReplyPush(env, clientId, msg, fetcher = fetch) {
  if (!env.INSTALLS || !pushConfigured(env)) return false;
  try {
    const client = await env.INSTALLS.get('support:client:' + clientId, { type: 'json' });
    if (!client?.replyPush) return false;
    const preview = msg.text && msg.text !== '[Вложение]' ? msg.text : (msg.imageUrl ? '📷 Фото' : 'Новое сообщение');
    const body = preview.length > 150 ? preview.slice(0, 147) + '…' : preview;
    await sendFcmMessage(env, {
      topic: await privatePushTopic(env, clientId),
      notification: { title: '💬 Ответ поддержки', body },
      data: { kind: 'support_reply', action: 'support', actionUrl: '' },
      android: { ttl: '86400s', notification: { tag: 'support_reply', channel_id: 'admin_messages', icon: 'ic_notification' } },
      apns: { headers: { 'apns-collapse-id': 'support_reply' }, payload: { aps: { sound: 'default' } } },
    }, fetcher);
    return true;
  } catch (error) {
    console.error('Support reply push failed', error?.name || 'unknown');
    return false;
  }
}

/**
 * Обработка входящего сообщения от Telegram (webhook или getUpdates).
 */
export async function processTelegramMessageUpdate(msg, env) {
  if (!msg) return false;
  const chatId = telegramChatId(env);
  if (String(msg.chat?.id) !== chatId) return false;

  // Игнорируем сообщения от самого бота
  if (msg.from?.is_bot) return false;

  const threadId = msg.message_thread_id;
  if (!threadId) return false;

  // Ищем пользователя, к которому привязан данный threadId
  const clientId = env.INSTALLS ? await env.INSTALLS.get('support:thread:' + threadId) : null;
  if (!clientId) return false;

  let text = msg.caption ? msg.caption.trim() : (msg.text ? msg.text.trim() : '');
  let imageUrl = null;

  if (!msg.caption && CLOSE_COMMAND.test(text)) {
    await closeSupportTicket(env, clientId, msg.message_id, threadId);
    return true;
  }

  if (Array.isArray(msg.photo) && msg.photo.length > 0) {
    const largestPhoto = msg.photo[msg.photo.length - 1];
    if (largestPhoto?.file_id) {
      imageUrl = `/api/support/file?fileId=${encodeURIComponent(largestPhoto.file_id)}`;
    }
  } else if (msg.document && msg.document.mime_type?.startsWith('image/') && msg.document.file_id) {
    imageUrl = `/api/support/file?fileId=${encodeURIComponent(msg.document.file_id)}`;
  } else if (msg.sticker) {
    text = (text ? text + ' ' : '') + '[Стикер]';
  } else if (msg.voice) {
    text = (text ? text + ' ' : '') + '[Голосовое сообщение]';
  } else if (msg.document) {
    text = (text ? text + ' ' : '') + '[Документ]';
  }

  if (!text && !imageUrl) {
    text = '[Вложение]';
  }

  const replyMsg = {
    id: 'tg_' + msg.message_id,
    sender: 'support',
    text,
    ...(imageUrl ? { imageUrl } : {}),
    // Время прихода на сервер, а не время Telegram: оно в секундах и может быть раньше
    // сообщения пользователя, которое мы уже сохранили; приложение показывает только ts > since.
    ts: Date.now(),
    // Всегда один и тот же подписанный ответ, а не имя аккаунта Telegram оператора.
    authorName: 'Менеджер Сергей',
  };

  await appendSupportMessage(env, clientId, replyMsg);
  await sendSupportReplyPush(env, clientId, replyMsg);

  // Обновляем метку последней активности клиента
  const clientKey = 'support:client:' + clientId;
  if (env.INSTALLS) {
    const client = await env.INSTALLS.get(clientKey, { type: 'json' });
    if (client) {
      client.lastMsgAt = replyMsg.ts;
      await env.INSTALLS.put(clientKey, JSON.stringify(client), { expirationTtl: 90 * 86400 });
    }
  }

  return true;
}

// Каждое открытое приложение спрашивает сообщения раз в несколько секунд, а
// durable-опрос Telegram — одна последовательная очередь вместе с уведомлениями
// об ошибках. Поэтому из одного экземпляра воркера спрашиваем её не чаще раза в
// интервал, а найденный вебхук запоминаем на час.
const DURABLE_POLL_INTERVAL_MS = 5000;
let lastDurablePollAt = 0;
let webhookChecks = new WeakMap();
export const resetSupportPollThrottle = () => { lastDurablePollAt = 0; webhookChecks = new WeakMap(); };

/**
 * Проверка накопившихся обновлений Telegram (getUpdates) при отсутствии Webhook
 */
async function checkPendingTelegramUpdates(env) {
  if (!env.BOT_TOKEN || !env.CHAT_ID) return;
  // The installed webhook handles replies immediately. Its configuration flag
  // need not cost a KV read for every idle client poll. Never cache messages.
  if (env.INSTALLS && (webhookChecks.get(env.INSTALLS) || 0) > Date.now()) return;
  let isWebhookActive;
  try { isWebhookActive = env.INSTALLS ? await env.INSTALLS.get('tg:webhook_active') : null; }
  catch (error) {
    const flags = {};
    for (const key of ['retryable', 'overloaded']) if (typeof error?.[key] === 'boolean') flags[key] = error[key];
    console.warn(JSON.stringify({ event: 'support_optional_poll_unavailable', stage: 'webhook_flag', code: errorCode(error), ...flags }));
    return;
  }
  if (isWebhookActive === '1') {
    webhookChecks.set(env.INSTALLS, Date.now() + 60000);
    return;
  }

  if (env.TELEGRAM) {
    const now = Date.now();
    if (now - lastDurablePollAt < DURABLE_POLL_INTERVAL_MS) return;
    lastDurablePollAt = now;
    try {
      // One durable consumer dispatches both exports and support replies.
      const result = await pollErrorCommands(env);
      if (result?.webhook && env.INSTALLS) {
        await env.INSTALLS.put('tg:webhook_active', '1', { expirationTtl: 3600 });
      }
    } catch (_) {
      // Уже сохранённые сообщения отдаём как есть; Telegram спросим при следующем опросе.
    }
    return;
  }

  try {
    const offset = (env.INSTALLS ? Number(await env.INSTALLS.get('tg:support_offset')) : 0) || 0;
    const resp = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/getUpdates`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ offset, timeout: 0, limit: 20, allowed_updates: ['message'] }),
      signal: AbortSignal.timeout(5000),
    });

    if (resp.status === 409) {
      // Telegram сообщил, что активен webhook — запоминаем и больше getUpdates не вызываем
      // Флаг живёт час, потом getUpdates проверяется снова: иначе устаревший флаг отключал
      // опрос навсегда (так и случилось: вебхук был пуст, а сообщения копились в Telegram).
      if (env.INSTALLS) await env.INSTALLS.put('tg:webhook_active', '1', { expirationTtl: 3600 });
      return;
    }

    const data = await resp.json().catch(() => null);
    if (data?.ok && Array.isArray(data.result)) {
      let maxId = offset;
      for (const update of data.result) {
        if (update.update_id >= maxId) maxId = update.update_id + 1;
        if (update.message) {
          await processTelegramMessageUpdate(update.message, env);
        }
      }
      if (maxId > offset && env.INSTALLS) {
        await env.INSTALLS.put('tg:support_offset', String(maxId));
      }
    }
  } catch (e) {
    // Тихо игнорируем сетевые сбои поллинга
  }
}

/**
 * POST /api/support/send
 * Тело: { clientId, userName, platform, appVersion, isPremium, text }
 */
export async function handleSupportSendMessage(request, env) {
  if (request.method !== 'POST') return jsonResponse({ error: 'method_not_allowed' }, 405);

  const body = await boundedJson(request, 16 * 1024 * 1024);
  const clientId = String(body.clientId || '').trim();
  const text = String(body.text || '').trim();
  const imageBase64 = body.imageBase64 ? String(body.imageBase64).trim() : null;
  const imageMimeType = body.imageMimeType ? String(body.imageMimeType).trim() : 'image/jpeg';

  if (!clientId || (!text && !imageBase64)) {
    return jsonResponse({ error: 'missing_fields' }, 400);
  }
  if (text.length > 4000) {
    return jsonResponse({ error: 'message_too_long' }, 400);
  }
  if (imageBase64 && imageBase64.length > 15 * 1024 * 1024) {
    return jsonResponse({ error: 'image_too_large' }, 400);
  }

  const identity = await supportIdentity(request, env, clientId);
  await abuseBudget(request, env, 'support-send', { identity: identity.session?.user.id, limit: 6, windowMs: 60000, globalLimit: 300 });
  await abuseBudget(request, env, 'support-daily', { identity: identity.session?.user.id, limit: 50, windowMs: 86400000, globalLimit: 2000 });
  if (imageBase64 && !['image/jpeg', 'image/png', 'image/webp'].includes(imageMimeType)) throw new HttpFailure(400, 'unsupported image type');

  const rawName = String(body.userName || '').trim();
  const displayName = String(identity.session?.user.name || rawName || 'Пользователь').slice(0, 120);
  const platform = String(body.platform || 'unknown').trim();
  const appVersion = String(body.appVersion || '').trim();
  const isPremium = Boolean(body.isPremium);

  const clientKey = 'support:client:' + clientId;
  let client = env.INSTALLS ? await env.INSTALLS.get(clientKey, { type: 'json' }) : null;
  let threadId = client?.threadId || null;
  let introduction = null;
  // Ответ пушем — только если переписка точно этого аккаунта (сессия входа),
  // приложение умеет такие пуши и они у него включены.
  const session = identity.session;
  const replyPush = body.replyPush === true && Boolean(session?.user?.id) && session.user.id === clientId;

  // Если у пользователя ещё нет топика в Telegram — создаём его
  if (!threadId && env.BOT_TOKEN && telegramChatId(env)) {
    const chatId = telegramChatId(env);
    const shortId = clientId.length > 8 ? clientId.slice(-6) : clientId;
    const topicTitle = ('💬 ' + displayName + ' (#' + shortId + ')').slice(0, 128);

    try {
      const topicRes = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/createForumTopic`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          chat_id: chatId,
          name: topicTitle,
          icon_color: 0x6FB9F0, // Светло-голубой
        }),
        signal: AbortSignal.timeout(10000),
      });

      const topicData = await topicRes.json().catch(() => null);
      if (topicData?.ok && topicData.result?.message_thread_id) {
        threadId = topicData.result.message_thread_id;
      } else {
        console.warn('createForumTopic failed (group may not have forum enabled):', topicData?.description || topicRes.status);
      }
    } catch (e) {
      console.error('createForumTopic error:', e);
    }

    if (threadId) {
      client = {
        threadId,
        userName: displayName,
        platform,
        appVersion,
        isPremium,
        createdAt: Date.now(),
        lastMsgAt: Date.now(),
        replyPush,
      };
      if (env.INSTALLS) {
        await env.INSTALLS.put(clientKey, JSON.stringify(client), { expirationTtl: 90 * 86400 });
        await env.INSTALLS.put('support:thread:' + threadId, clientId, { expirationTtl: 90 * 86400 });
      }

      // Отправляем карточку с информацией о пользователе
      introduction =
        `💬 <b>Новое обращение в техподдержку</b>\n` +
        `👤 <b>Пользователь:</b> ${escapeHtml(displayName)}\n` +
        `🆔 <b>ID:</b> <code>${escapeHtml(clientId)}</code>\n` +
        `📱 <b>Платформа:</b> ${escapeHtml(platform)} ${escapeHtml(appVersion ? '(' + appVersion + ')' : '')}\n` +
        `⭐ <b>Премиум:</b> ${isPremium ? 'Да' : 'Нет'}`;
    }
  }

  if (client?.closed && threadId) {
    // Обращение было закрыто командой /close — новое сообщение открывает его снова.
    client.closed = false;
    if (env.BOT_TOKEN) {
      await telegramCall(env, 'reopenForumTopic', { chat_id: telegramChatId(env), message_thread_id: Number(threadId) });
    }
    if (env.INSTALLS) await env.INSTALLS.put(clientKey, JSON.stringify(client), { expirationTtl: 90 * 86400 });
  }

  let imageUrl = null;
  if (imageBase64) {
    if (introduction) await sendToTelegram(env, introduction, threadId);
    const caption = text
      ? `<b>${escapeHtml(displayName)}:</b>\n${escapeHtml(text)}`
      : `<b>${escapeHtml(displayName)}</b>`;
    // Truncating escaped HTML can cut an entity/tag and make Telegram reject
    // the entire photo. Send a complete short caption, then the full text.
    const photoCaption = caption.length > 1024 ? `<b>${escapeHtml(displayName)}</b>` : caption;
    const tgPhotoResult = await sendPhotoToTelegram(env, imageBase64, imageMimeType, photoCaption, threadId);
    if (tgPhotoResult?.photo && Array.isArray(tgPhotoResult.photo) && tgPhotoResult.photo.length > 0) {
      const fileId = tgPhotoResult.photo[tgPhotoResult.photo.length - 1].file_id;
      imageUrl = `/api/support/file?fileId=${encodeURIComponent(fileId)}`;
    }
    if (!imageUrl) throw new HttpFailure(503, 'support delivery unavailable');
    // Если текст длиннее лимита caption в Telegram, досылаем его отдельным сообщением
    if (text && caption.length > 1024) {
      const tgUserText = `<b>${escapeHtml(displayName)}:</b>\n${escapeHtml(text)}`;
      await sendToTelegram(env, tgUserText, threadId, true);
    }
  } else {
    // Отправляем обычный текст пользователя в Telegram
    const tgUserText = `<b>${escapeHtml(displayName)}:</b>\n${escapeHtml(text)}`;
    const combined = introduction ? introduction + '\n\n' + tgUserText : tgUserText;
    // Most first contacts fit into one message. Avoid a second 10-second
    // Telegram round trip before delivering the user's actual question.
    if (combined.length <= 4096) await sendToTelegram(env, combined, threadId, true);
    else {
      if (introduction) await sendToTelegram(env, introduction, threadId);
      await sendToTelegram(env, tgUserText, threadId, true);
    }
  }

  // Сохраняем сообщение в локальной истории
  const newMsg = {
    id: 'usr_' + Date.now() + '_' + Math.random().toString(36).slice(2, 7),
    sender: 'user',
    text,
    ...(imageUrl ? { imageUrl } : {}),
    ts: Date.now(),
    authorName: displayName,
  };

  await appendSupportMessage(env, clientId, newMsg);
  if (env.INSTALLS && client) {
    client.lastMsgAt = Date.now();
    client.replyPush = replyPush;
    // The message is already delivered and stored. Failure of auxiliary
    // metadata must not invite the user to resend it.
    try { await env.INSTALLS.put(clientKey, JSON.stringify(client), { expirationTtl: 90 * 86400 }); }
    catch { console.warn('support client metadata unavailable'); }
  }

  return jsonResponse({ ok: true, message: { ...newMsg, ...(newMsg.imageUrl ? { imageUrl: supportImageUrl(newMsg.imageUrl, clientId) } : {}) } });
}

/**
 * GET /api/support/messages?clientId=<id>&since=<ts>
 */
export async function handleSupportGetMessages(request, env) {
  const url = new URL(request.url);
  const clientId = String(url.searchParams.get('clientId') || '').trim();
  if (!clientId) return jsonResponse({ error: 'missing_client_id' }, 400);

  try { await supportIdentity(request, env, clientId); }
  catch (error) {
    // Installed clients sent only the public app key on GET. Keep their
    // poll protocol valid, while never returning private history or touching a thread.
    if (error instanceof HttpFailure && error.status === 401 && !request.headers.has('authorization') && env.SHARED_SECRET && request.headers.get('x-install-secret') === env.SHARED_SECRET) return jsonResponse({ ok: true, messages: [], requiresUpdate: true });
    throw error;
  }

  // Проверяем новые сообщения из Telegram через getUpdates, если webhook не настроен
  await checkPendingTelegramUpdates(env);

  const since = Number(url.searchParams.get('since') || 0);
  const result = await listSupportMessages(env, clientId, since);

  return jsonResponse({ ok: true, messages: result.map(m => ({ ...m, ...(m.imageUrl ? { imageUrl: supportImageUrl(m.imageUrl, clientId) } : {}) })) });
}

/**
 * POST /api/telegram/webhook
 */
export async function handleTelegramWebhook(request, env) {
  if (request.method !== 'POST') return jsonResponse({ error: 'method_not_allowed' }, 405);

  if (!await telegramWebhookVerified(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
  const update = await boundedJson(request, 1024 * 1024);

  if (env.INSTALLS) {
    // Вебхук присылает сообщения — пока они идут, getUpdates не нужен.
    await env.INSTALLS.put('tg:webhook_active', '1', { expirationTtl: 86400 });
  }

  if (update?.message) {
    const verified = await telegramWebhookVerified(request, env);
    if (verified && await handleErrorExportUpdate(env, update)) return jsonResponse({ ok: true });
    const handledAuth = await processTelegramAuthMessage(update.message, env, verified);
    if (!handledAuth) {
      await processTelegramMessageUpdate(update.message, env);
    }
  }

  return jsonResponse({ ok: true });
}

/**
 * POST /api/admin/support/setup-webhook
 */
export async function handleSupportSetupWebhook(request, env) {
  const chatId = telegramChatId(env);
  if (!env.BOT_TOKEN || !chatId) return jsonResponse({ error: 'bot not configured' }, 503);

  const host = new URL(request.url).host;
  const webhookUrl = `https://${host}/api/telegram/webhook`;

  const resp = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/setWebhook`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ url: webhookUrl, allowed_updates: ['message'], secret_token: await telegramWebhookSecret(env) || undefined }),
    signal: AbortSignal.timeout(10000),
  });

  const data = await resp.json().catch(() => ({}));
  if (data.ok && env.INSTALLS) {
    await env.INSTALLS.put('tg:webhook_active', '1', { expirationTtl: 3600 });
  }

  return jsonResponse({ ok: Boolean(data.ok), webhookUrl, description: data.description });
}

/**
 * GET /api/admin/support/webhook-info
 */
export async function handleSupportWebhookInfo(request, env) {
  if (!env.BOT_TOKEN) return jsonResponse({ error: 'bot not configured' }, 503);
  const resp = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/getWebhookInfo`);
  const data = await resp.json().catch(() => ({}));
  return jsonResponse(data);
}

/**
 * GET /api/support/file?fileId=<id>
 * Проксирует загрузку изображений из Telegram Bot API без раскрытия токена клиентам.
 */
export async function handleSupportGetFile(request, env) {
  if (request.method !== 'GET') return jsonResponse({ error: 'method_not_allowed' }, 405);
  const url = new URL(request.url);
  const fileId = url.searchParams.get('fileId');
  if (!fileId || !env.BOT_TOKEN) {
    return jsonResponse({ error: 'invalid_request' }, 400);
  }

  const clientId = url.searchParams.get('clientId');
  await supportIdentity(request, env, clientId);
  const messages = await listSupportMessages(env, clientId, 0);
  const belongs = messages.some(m => {
    try { return m.imageUrl && new URL(m.imageUrl, 'https://support.internal').searchParams.get('fileId') === fileId; } catch { return false; }
  });
  if (!belongs) return jsonResponse({ error: 'file_not_found' }, 404);

  try {
    // 1. Получаем путь к файлу у Telegram Bot API
    const fileRes = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/getFile?file_id=${encodeURIComponent(fileId)}`, {
      signal: AbortSignal.timeout(10000),
    });
    const fileData = await fileRes.json().catch(() => null);
    if (!fileData?.ok || !fileData.result?.file_path) {
      return jsonResponse({ error: 'file_not_found' }, 404);
    }

    const filePath = fileData.result.file_path;

    // 2. Скачиваем файл из Telegram
    const imgRes = await fetch(`https://api.telegram.org/file/bot${env.BOT_TOKEN}/${filePath}`, {
      signal: AbortSignal.timeout(15000),
    });

    if (!imgRes.ok) {
      return jsonResponse({ error: 'failed_to_fetch_file' }, imgRes.status);
    }

    const contentType = imgRes.headers.get('content-type')?.split(';')[0] || 'image/jpeg';
    if (!['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(contentType)) return jsonResponse({ error: 'unsupported image type' }, 415);
    const responseHeaders = {
      'content-type': contentType,
      'cache-control': 'private, no-store',
      'x-content-type-options': 'nosniff',
      ...CORS_HEADERS,
    };

    const response = new Response(imgRes.body, {
      status: 200,
      headers: responseHeaders,
    });

    return response;
  } catch (err) {
    console.error('handleSupportGetFile error:', err);
    return jsonResponse({ error: 'internal_error' }, 500);
  }
}
