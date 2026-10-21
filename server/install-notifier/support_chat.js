// Чат техподдержки: создание отдельной ветки (Forum Topic) в Telegram на каждого
// пользователя, отправка сообщений и приём ответов от команды через Webhook/Updates.
import { telegramChatId, handleErrorExportUpdate, pollErrorCommands } from './telegram_queue.js';
import { processTelegramAuthMessage, telegramWebhookVerified, telegramWebhookSecret } from './telegram_auth.js';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, x-install-secret, authorization',
  'Access-Control-Max-Age': '86400',
};

function jsonResponse(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json', ...CORS_HEADERS, ...extraHeaders },
  });
}

// Messages of one client live in a Durable Object (support_thread.js): read right after a write.
// Without the binding they fall back to KV (eventually consistent, slower to show replies).
function threadStub(env, clientId) {
  return env.SUPPORT ? env.SUPPORT.get(env.SUPPORT.idFromName(clientId)) : null;
}

async function appendSupportMessage(env, clientId, msg) {
  const stub = threadStub(env, clientId);
  if (stub) {
    await stub.fetch('https://support.internal/append', { method: 'POST', body: JSON.stringify(msg) });
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
  const read = async () => (await (await stub.fetch(`https://support.internal/list?since=${since}`)).json()).messages || [];
  let messages = await read();
  if (messages.length === 0 && env.INSTALLS) {
    // Messages kept in KV before the thread existed: copy them once.
    const legacy = await env.INSTALLS.get('support:messages:' + clientId, { type: 'json' });
    if (Array.isArray(legacy) && legacy.length) {
      await stub.fetch('https://support.internal/seed', { method: 'POST', body: JSON.stringify(legacy) });
      messages = await read();
    }
  }
  return messages;
}

function escapeHtml(s) {
  return String(s ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

async function sendToTelegram(env, text, threadId = null) {
  const chatId = telegramChatId(env);
  if (!env.BOT_TOKEN || !chatId) return null;
  const payload = {
    chat_id: chatId,
    text,
    parse_mode: 'HTML',
    disable_web_page_preview: true,
  };
  if (threadId) {
    payload.message_thread_id = Number(threadId);
  }
  return fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/sendMessage`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10000),
  }).catch((err) => {
    console.error('sendToTelegram error:', err);
    return null;
  });
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
    if (data?.ok && data.result) {
      return data.result;
    }
    console.warn('sendPhotoToTelegram error:', data?.description || resp.status);
    return null;
  } catch (err) {
    console.error('sendPhotoToTelegram exception:', err);
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
    await env.INSTALLS.put(clientKey, JSON.stringify(client));
  }
  await sendToTelegram(env, '✅ Обращение завершено, пользователю отправлено уведомление. Новое сообщение откроет тему снова.', threadId);
  if (env.BOT_TOKEN) {
    await telegramCall(env, 'closeForumTopic', { chat_id: telegramChatId(env), message_thread_id: Number(threadId) });
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

  // Обновляем метку последней активности клиента
  const clientKey = 'support:client:' + clientId;
  if (env.INSTALLS) {
    const client = await env.INSTALLS.get(clientKey, { type: 'json' });
    if (client) {
      client.lastMsgAt = replyMsg.ts;
      await env.INSTALLS.put(clientKey, JSON.stringify(client));
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
export const resetSupportPollThrottle = () => { lastDurablePollAt = 0; };

/**
 * Проверка накопившихся обновлений Telegram (getUpdates) при отсутствии Webhook
 */
async function checkPendingTelegramUpdates(env) {
  if (!env.BOT_TOKEN || !env.CHAT_ID) return;
  const isWebhookActive = env.INSTALLS ? await env.INSTALLS.get('tg:webhook_active') : null;
  if (isWebhookActive === '1') return;

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

  let body = {};
  try {
    body = await request.json();
  } catch (_) {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }

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

  const rawName = String(body.userName || '').trim();
  const displayName = rawName || 'Пользователь';
  const platform = String(body.platform || 'unknown').trim();
  const appVersion = String(body.appVersion || '').trim();
  const isPremium = Boolean(body.isPremium);

  const clientKey = 'support:client:' + clientId;
  let client = env.INSTALLS ? await env.INSTALLS.get(clientKey, { type: 'json' }) : null;
  let threadId = client?.threadId || null;

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
      };
      if (env.INSTALLS) {
        await env.INSTALLS.put(clientKey, JSON.stringify(client));
        await env.INSTALLS.put('support:thread:' + threadId, clientId);
      }

      // Отправляем карточку с информацией о пользователе
      const introText =
        `💬 <b>Новое обращение в техподдержку</b>\n` +
        `👤 <b>Пользователь:</b> ${escapeHtml(displayName)}\n` +
        `🆔 <b>ID:</b> <code>${escapeHtml(clientId)}</code>\n` +
        `📱 <b>Платформа:</b> ${escapeHtml(platform)} ${escapeHtml(appVersion ? '(' + appVersion + ')' : '')}\n` +
        `⭐ <b>Премиум:</b> ${isPremium ? 'Да' : 'Нет'}`;
      await sendToTelegram(env, introText, threadId);
    }
  }

  if (client?.closed && threadId) {
    // Обращение было закрыто командой /close — новое сообщение открывает его снова.
    client.closed = false;
    if (env.BOT_TOKEN) {
      await telegramCall(env, 'reopenForumTopic', { chat_id: telegramChatId(env), message_thread_id: Number(threadId) });
    }
    if (env.INSTALLS) await env.INSTALLS.put(clientKey, JSON.stringify(client));
  }

  let imageUrl = null;
  if (imageBase64) {
    const caption = text
      ? `<b>${escapeHtml(displayName)}:</b>\n${escapeHtml(text)}`
      : `<b>${escapeHtml(displayName)}</b>`;
    const tgPhotoResult = await sendPhotoToTelegram(env, imageBase64, imageMimeType, caption, threadId);
    if (tgPhotoResult?.photo && Array.isArray(tgPhotoResult.photo) && tgPhotoResult.photo.length > 0) {
      const fileId = tgPhotoResult.photo[tgPhotoResult.photo.length - 1].file_id;
      imageUrl = `/api/support/file?fileId=${encodeURIComponent(fileId)}`;
    }
    // Если текст длиннее лимита caption в Telegram, досылаем его отдельным сообщением
    if (text && caption.length > 1024) {
      const tgUserText = `<b>${escapeHtml(displayName)}:</b>\n${escapeHtml(text)}`;
      await sendToTelegram(env, tgUserText, threadId);
    }
  } else {
    // Отправляем обычный текст пользователя в Telegram
    const tgUserText = `<b>${escapeHtml(displayName)}:</b>\n${escapeHtml(text)}`;
    await sendToTelegram(env, tgUserText, threadId);
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
    await env.INSTALLS.put(clientKey, JSON.stringify(client));
  }

  return jsonResponse({ ok: true, message: newMsg });
}

/**
 * GET /api/support/messages?clientId=<id>&since=<ts>
 */
export async function handleSupportGetMessages(request, env) {
  const url = new URL(request.url);
  const clientId = String(url.searchParams.get('clientId') || '').trim();
  if (!clientId) return jsonResponse({ error: 'missing_client_id' }, 400);

  // Проверяем новые сообщения из Telegram через getUpdates, если webhook не настроен
  await checkPendingTelegramUpdates(env);

  const since = Number(url.searchParams.get('since') || 0);
  const result = await listSupportMessages(env, clientId, since);

  return jsonResponse({ ok: true, messages: result });
}

/**
 * POST /api/telegram/webhook
 */
export async function handleTelegramWebhook(request, env) {
  if (request.method !== 'POST') return jsonResponse({ error: 'method_not_allowed' }, 405);

  let update = null;
  try {
    update = await request.json();
  } catch (_) {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }

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

  // Проверяем кэш Cloudflare (при наличии)
  const cacheKey = new Request(url.toString(), request);
  let cache = null;
  try {
    cache = caches.default;
    const cached = await cache.match(cacheKey);
    if (cached) return cached;
  } catch (_) {}

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

    const contentType = imgRes.headers.get('content-type') || 'image/jpeg';
    const responseHeaders = {
      'content-type': contentType,
      'cache-control': 'public, max-age=604800, s-maxage=604800, immutable',
      ...CORS_HEADERS,
    };

    const response = new Response(imgRes.body, {
      status: 200,
      headers: responseHeaders,
    });

    if (cache) {
      try {
        await cache.put(cacheKey, response.clone());
      } catch (_) {}
    }

    return response;
  } catch (err) {
    console.error('handleSupportGetFile error:', err);
    return jsonResponse({ error: 'internal_error' }, 500);
  }
}
