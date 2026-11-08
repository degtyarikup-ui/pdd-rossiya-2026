import { getTopicThreadId, resolveTopicThreadId, telegramChatId } from './telegram_queue.js';
import { errorCode } from './diagnostics.js';

export const TELEGRAM_TOPICS = [
  { key: 'errors', name: '🔴 Ошибки и падения', color: 0xFB6F5F, description: 'Сюда будут приходить падения приложения и серверные сбои.' },
  { key: 'purchases', name: '💳 Покупки и премиум', color: 0xFFD67E, description: 'Сюда будут приходить покупки в сторах, оплата по СБП и выдачи Premium.' },
  { key: 'registrations', name: '👤 Регистрации', color: 0x6FB9F0, description: 'Сюда будут приходить новые пользователи.' },
  { key: 'reports', name: '🚩 Жалобы на вопросы', color: 0xCB86DB, description: 'Сюда будут приходить жалобы на вопросы. Для вошедших пользователей указываются имя и почта из аккаунта.' },
];

export async function readTelegramTopics(env) {
  return Object.fromEntries(await Promise.all(TELEGRAM_TOPICS.map(async ({ key }) => [key, await getTopicThreadId(env, key)])));
}

// Reuse existing topics and save once, also on partial Telegram failure. KV
// permits only one write per second to a key, so never write inside the loop.
export async function setupTelegramTopics(request, env, sendTelegram) {
  if (!env.BOT_TOKEN || !telegramChatId(env)) return Response.json({ error: 'bot not configured' }, { status: 503 });
  if (!env.INSTALLS) return Response.json({ error: 'storage unavailable' }, { status: 503 });
  let body;
  try { body = await request.json(); } catch (_) { return Response.json({ error: 'invalid json' }, { status: 400 }); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) return Response.json({ error: 'invalid topics' }, { status: 400 });
  for (const { key } of TELEGRAM_TOPICS) {
    if (body[key] === undefined) continue;
    const numeric = typeof body[key] === 'number' || (typeof body[key] === 'string' && /^\d+$/.test(body[key]));
    if (!numeric || !Number.isSafeInteger(Number(body[key])) || Number(body[key]) <= 0) return Response.json({ error: 'invalid topic', topic: key }, { status: 400 });
    const configured = resolveTopicThreadId(env, key);
    if (configured && Number(body[key]) !== configured) return Response.json({ error: 'topic configured in environment', topic: key }, { status: 409 });
  }
  const raw = await env.INSTALLS.get('telegram_topics');
  const saved = raw ? JSON.parse(raw) : {};
  const topics = await readTelegramTopics(env);
  const changed = [];
  const persist = async () => {
    const next = { ...saved, ...Object.fromEntries(Object.entries(topics).filter(([, id]) => id !== null)) };
    if (JSON.stringify(next) === JSON.stringify(saved)) return;
    for (let attempt = 0; ; attempt++) {
      try { await env.INSTALLS.put('telegram_topics', JSON.stringify(next)); return; }
      catch (error) {
        if (errorCode(error) !== 'storage_rate_limited' || attempt >= 2) throw error;
        // A fast retry after partial setup may still hit KV's per-key limit.
        // Retain the IDs already created in Telegram while waiting to persist.
        await new Promise(resolve => setTimeout(resolve, 1100));
      }
    }
  };
  for (const topic of TELEGRAM_TOPICS) {
    const old = topics[topic.key];
    if (body[topic.key] !== undefined) topics[topic.key] = Number(body[topic.key]);
    if (!topics[topic.key]) {
      let data;
      try {
        const response = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/createForumTopic`, {
          method: 'POST', headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ chat_id: telegramChatId(env), name: topic.name, icon_color: topic.color }),
          signal: AbortSignal.timeout(10000),
        });
        data = await response.json();
        if (!response.ok || !data?.ok || !Number.isSafeInteger(data.result?.message_thread_id) || data.result.message_thread_id <= 0) throw new Error('topic unavailable');
      } catch (_) {
        await persist();
        return Response.json({ error: 'create_topic_failed', topic: topic.key, topics }, { status: 502 });
      }
      topics[topic.key] = data.result.message_thread_id;
    }
    if (topics[topic.key] !== old) changed.push(topic);
  }
  await persist();
  for (const topic of changed) {
    await sendTelegram(env, `<b>Тема «${topic.name}» подключена</b>\n${topic.description}`, null, { threadId: topics[topic.key] });
  }
  return Response.json({ ok: true, topics });
}
