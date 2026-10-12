// Авторизация через Telegram-бота (@pdda_bot): генерация одноразовой ссылки,
// приём команды /start через Webhook и подтверждение сессии для мобильного приложения.

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, x-install-secret, authorization',
  'Access-Control-Max-Age': '86400',
};

function reply(body, status = 200) {
  return Response.json(body, {
    status,
    headers: { 'Cache-Control': 'no-store', ...CORS_HEADERS },
  });
}

function escapeHtml(s) {
  return String(s ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

export function telegramAuthToken(env) {
  return env?.TELEGRAM_AUTH_BOT_TOKEN || env?.BOT_TOKEN || '';
}

export function telegramBotUsername(env) {
  return env?.TELEGRAM_BOT_USERNAME || 'pdda_bot';
}

const SESSION_SECONDS = 30 * 86400;

// Секрет вебхука Telegram (заголовок X-Telegram-Bot-Api-Secret-Token): без него
// любой, кто знает ключ приложения, мог подделать «нажатие Start» от чужого id.
export async function telegramWebhookSecret(env) {
  const base = env?.TELEGRAM_WEBHOOK_SECRET || env?.SESSION_SECRET;
  if (!base) return '';
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(base), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode('tg-webhook-v1')));
  return [...sig].map(b => b.toString(16).padStart(2, '0')).join('');
}

export async function telegramWebhookVerified(request, env) {
  const expected = await telegramWebhookSecret(env);
  const got = request.headers.get('x-telegram-bot-api-secret-token') || '';
  if (!expected || got.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ got.charCodeAt(i);
  return diff === 0;
}

// Регистрирует вебхук с секретом (раз в сутки, при попытке входа).
async function ensureWebhookSecret(request, env) {
  const token = telegramAuthToken(env);
  const secret = await telegramWebhookSecret(env);
  if (!token || !secret || await env.INSTALLS.get('tg:webhook_secret_set')) return;
  const resp = await fetch(`https://api.telegram.org/bot${token}/setWebhook`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      url: `https://${new URL(request.url).host}/api/telegram/webhook`,
      allowed_updates: ['message'],
      secret_token: secret,
    }),
    signal: AbortSignal.timeout(8000),
  }).catch(() => null);
  const data = await resp?.json().catch(() => ({}));
  if (data?.ok) await env.INSTALLS.put('tg:webhook_secret_set', '1', { expirationTtl: 86400 });
}

/**
 * POST /api/auth/telegram/request
 * Генерирует одноразовый nonce и ссылки для перехода в бота.
 */
export async function handleTelegramAuthRequest(request, env) {
  if (request.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
  if (!env.SHARED_SECRET || request.headers.get('x-install-secret') !== env.SHARED_SECRET) {
    return reply({ error: 'forbidden' }, 403);
  }
  if (!env.INSTALLS) {
    return reply({ error: 'storage_not_configured' }, 503);
  }

  await ensureWebhookSecret(request, env);
  const nonce = 'auth_' + crypto.randomUUID().replace(/-/g, '');
  const username = telegramBotUsername(env);

  await env.INSTALLS.put(
    'tg_auth:' + nonce,
    JSON.stringify({ status: 'pending', createdAt: Date.now() }),
    { expirationTtl: 300 } // 5 минут на подтверждение
  );

  return reply({
    ok: true,
    nonce,
    botUsername: username,
    botUrl: `https://t.me/${username}?start=${nonce}`,
    tgUrl: `tg://resolve?domain=${username}&start=${nonce}`,
  });
}

/**
 * POST /api/auth/telegram/check
 * Проверяет статус входа по nonce и выдаёт подписанную сессию при подтверждении.
 */
export async function handleTelegramAuthCheck(request, env, signSessionFn) {
  if (request.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
  if (!env.SHARED_SECRET || request.headers.get('x-install-secret') !== env.SHARED_SECRET) {
    return reply({ error: 'forbidden' }, 403);
  }
  if (!env.INSTALLS) {
    return reply({ error: 'storage_not_configured' }, 503);
  }

  let body = {};
  try {
    body = await request.json();
  } catch (_) {
    return reply({ error: 'invalid_json' }, 400);
  }

  const nonce = String(body?.nonce || '').trim();
  if (!nonce || !nonce.startsWith('auth_') || nonce.length > 80) {
    return reply({ error: 'invalid_nonce' }, 400);
  }

  const key = 'tg_auth:' + nonce;
  const raw = await env.INSTALLS.get(key);
  if (!raw) {
    return reply({ ok: false, status: 'expired' });
  }

  let entry;
  try {
    entry = JSON.parse(raw);
  } catch (_) {
    return reply({ ok: false, status: 'expired' });
  }

  if (entry?.status === 'pending') {
    return reply({ ok: false, status: 'pending' });
  }

  if (entry?.status === 'confirmed' && entry?.user?.id) {
    // Однократное использование кода: удаляем сразу при первой успешной выдаче сессии.
    await env.INSTALLS.delete(key);

    const user = entry.user;
    const expiresAt = Date.now() + SESSION_SECONDS * 1000;
    const generation = (await env.INSTALLS.get('auth_generation:' + user.id)) || '';

    // Подписание сессии через переданную функцию или модуль user_auth
    const sign = signSessionFn || ((await import('./user_auth.js')).signSession);
    const token = await sign(env, { user, expiresAt, generation });
    if (!token) {
      return reply({ error: 'session_secret_not_configured' }, 503);
    }

    return reply({
      ok: true,
      status: 'confirmed',
      token,
      expiresAt: new Date(expiresAt).toISOString(),
      user,
    });
  }

  return reply({ ok: false, status: 'invalid' });
}

/**
 * Обработка входящего сообщения от Telegram (webhook).
 * Если это команда /start login_... от пользователя в ЛС бота — подтверждаем вход.
 */
export async function processTelegramAuthMessage(msg, env, verified = false) {
  if (!msg) return false;
  const text = String(msg.text || '').trim();
  if (!text.startsWith('/start')) return false;

  // Игнорируем сообщения от ботов
  if (msg.from?.is_bot) return false;

  const param = text.replace(/^\/start\s*/, '').trim();
  const token = telegramAuthToken(env);

  // 1. Команда /start с кодом авторизации auth_...
  if (param.startsWith('auth_')) {
    // Подтверждать вход можно только запросом, подписанным секретом вебхука.
    if (!verified || msg.chat?.type !== 'private') return true;
    const key = 'tg_auth:' + param;
    let entry = null;
    if (env.INSTALLS) {
      const raw = await env.INSTALLS.get(key);
      if (raw) {
        try { entry = JSON.parse(raw); } catch (_) {}
      }
    }

    if (entry?.status === 'pending') {
      const from = msg.from || {};
      const tgId = String(from.id || msg.chat?.id || '');
      if (!tgId) return false;

      const firstName = String(from.first_name || '').trim();
      const lastName = String(from.last_name || '').trim();
      const username = String(from.username || '').trim();
      const name = [firstName, lastName].filter(Boolean).join(' ') || username || 'Пользователь Telegram';

      const user = {
        id: 'telegram_' + tgId,
        name: name.slice(0, 120),
        email: '',
        avatarUrl: null,
        provider: 'telegram',
        createdAt: new Date().toISOString(),
      };

      if (env.INSTALLS) {
        await env.INSTALLS.put(
          key,
          JSON.stringify({ status: 'confirmed', user, confirmedAt: Date.now() }),
          { expirationTtl: 300 }
        );
      }

      if (token) {
        await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            chat_id: msg.chat.id,
            text: `✅ <b>Вход подтверждён!</b>\n\nВы успешно авторизовались в приложении <b>ПДД Россия 2026</b>.\n\nВернитесь в приложение — вход выполнится автоматически.`,
            parse_mode: 'HTML',
          }),
          signal: AbortSignal.timeout(5000),
        }).catch(() => null);
      }
      return true;
    }

    // Если код уже использован или истёк
    if (token) {
      await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          chat_id: msg.chat.id,
          text: `⚠️ Срок действия ссылки для входа истёк или она уже была использована.\n\nПожалуйста, нажмите «Войти через Telegram» в приложении ещё раз.`,
          parse_mode: 'HTML',
        }),
        signal: AbortSignal.timeout(5000),
      }).catch(() => null);
    }
    return true;
  }

  // 2. Обычная команда /start без параметров в личном чате с ботом
  if (msg.chat?.type === 'private' && token) {
    await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        chat_id: msg.chat.id,
        text: `👋 Здравствуйте, ${escapeHtml(msg.from?.first_name || 'водитель')}!\n\nЭто официальный бот приложения <b>ПДД Россия 2026</b>.\n\nЧтобы войти в свой аккаунт, откройте приложение на телефоне и нажмите <b>«Войти через Telegram»</b>.`,
        parse_mode: 'HTML',
      }),
      signal: AbortSignal.timeout(5000),
    }).catch(() => null);
    return true;
  }

  return false;
}
