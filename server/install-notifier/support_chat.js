// Чат техподдержки: создание отдельной ветки (Forum Topic) в Telegram на каждого
// пользователя, отправка сообщений и приём ответов от команды через Webhook/Updates.
import { telegramChatId } from './telegram_queue.js';

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

  let text = msg.text || msg.caption || '';
  if (msg.photo) text = (text ? text + ' ' : '') + '[Фотография]';
  if (msg.sticker) text = (text ? text + ' ' : '') + '[Стикер]';
  if (msg.voice) text = (text ? text + ' ' : '') + '[Голосовое сообщение]';
  if (msg.document) text = (text ? text + ' ' : '') + '[Документ]';
  if (!text) text = '[Вложение]';

  const authorName = [msg.from?.first_name, msg.from?.last_name].filter(Boolean).join(' ') || 'Поддержка';
  const replyMsg = {
    id: 'tg_' + msg.message_id,
    sender: 'support',
    text,
    // Время прихода на сервер, а не время Telegram: оно в секундах и может быть раньше
    // сообщения пользователя, которое мы уже сохранили; приложение показывает только ts > since.
    ts: Date.now(),
    authorName,
  };

  const msgKey = 'support:messages:' + clientId;
  let msgs = env.INSTALLS ? ((await env.INSTALLS.get(msgKey, { type: 'json' })) || []) : [];
  if (!msgs.some((m) => m.id === replyMsg.id)) {
    msgs.push(replyMsg);
    if (msgs.length > 200) msgs = msgs.slice(-200);
    if (env.INSTALLS) await env.INSTALLS.put(msgKey, JSON.stringify(msgs));
  }

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

/**
 * Проверка накопившихся обновлений Telegram (getUpdates) при отсутствии Webhook
 */
async function checkPendingTelegramUpdates(env) {
  if (!env.BOT_TOKEN || !env.CHAT_ID) return;
  const isWebhookActive = env.INSTALLS ? await env.INSTALLS.get('tg:webhook_active') : null;
  if (isWebhookActive === '1') return;

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
      if (env.INSTALLS) await env.INSTALLS.put('tg:webhook_active', '1');
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
  if (!clientId || !text) {
    return jsonResponse({ error: 'missing_fields' }, 400);
  }
  if (text.length > 4000) {
    return jsonResponse({ error: 'message_too_long' }, 400);
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

  // Отправляем текст пользователя в Telegram
  const tgUserText = `<b>${escapeHtml(displayName)}:</b>\n${escapeHtml(text)}`;
  await sendToTelegram(env, tgUserText, threadId);

  // Сохраняем сообщение в локальной истории
  const newMsg = {
    id: 'usr_' + Date.now() + '_' + Math.random().toString(36).slice(2, 7),
    sender: 'user',
    text,
    ts: Date.now(),
    authorName: displayName,
  };

  const msgKey = 'support:messages:' + clientId;
  let msgs = env.INSTALLS ? ((await env.INSTALLS.get(msgKey, { type: 'json' })) || []) : [];
  msgs.push(newMsg);
  if (msgs.length > 200) msgs = msgs.slice(-200);

  if (env.INSTALLS) {
    await env.INSTALLS.put(msgKey, JSON.stringify(msgs));
    if (client) {
      client.lastMsgAt = Date.now();
      await env.INSTALLS.put(clientKey, JSON.stringify(client));
    }
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

  const msgKey = 'support:messages:' + clientId;
  const msgs = env.INSTALLS ? ((await env.INSTALLS.get(msgKey, { type: 'json' })) || []) : [];

  const since = Number(url.searchParams.get('since') || 0);
  const result = since > 0 ? msgs.filter((m) => m.ts > since) : msgs;

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
    await env.INSTALLS.put('tg:webhook_active', '1');
  }

  if (update?.message) {
    await processTelegramMessageUpdate(update.message, env);
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
    body: JSON.stringify({ url: webhookUrl, allowed_updates: ['message'] }),
    signal: AbortSignal.timeout(10000),
  });

  const data = await resp.json().catch(() => ({}));
  if (data.ok && env.INSTALLS) {
    await env.INSTALLS.put('tg:webhook_active', '1');
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
