#!/usr/bin/env node
/**
 * Скрипт для настройки 3-х подгрупп (тем/форума) в Telegram-чате логов.
 *
 * Использование:
 *   node setup_telegram_topics.mjs [BOT_TOKEN] [CHAT_ID]
 *
 * Если аргументы не переданы, скрипт берёт их из окружения:
 *   BOT_TOKEN, CHAT_ID
 */

const token = process.argv[2] || process.env.BOT_TOKEN;
const chatId = process.argv[3] || process.env.CHAT_ID;

if (!token || !chatId) {
  console.log(`
Использование:
  node scripts/setup_telegram_topics.mjs <BOT_TOKEN> <CHAT_ID>

Или задайте переменные окружения BOT_TOKEN и CHAT_ID.

Перед запуском:
1. Откройте чат в Telegram -> Настройки -> Включите "Темы" (Topics).
2. Назначьте бота администратором с правом "Управление темами" (Manage Topics).
`);
  process.exit(1);
}

async function tgCall(method, body = {}) {
  const res = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (!res.ok || !data.ok) {
    throw new Error(data.description || `HTTP ${res.status}`);
  }
  return data.result;
}

async function run() {
  console.log(`Проверка чата ${chatId}...`);
  try {
    const chat = await tgCall('getChat', { chat_id: chatId });
    console.log(`Чат найден: "${chat.title || chat.username || chatId}" (тип: ${chat.type})`);
    if (!chat.is_forum) {
      console.warn(`\n⚠️ Внимание: в группе "${chat.title}" пока не включен режим тем (Форум)!`);
      console.warn(`Инструкция:`);
      console.warn(`1. Откройте группу в Telegram`);
      console.warn(`2. Нажмите «Изменить» (значок карандаша) -> включите переключатель «Темы» (Topics).`);
      console.warn(`3. Убедитесь, что у бота включено право администратора «Управление темами».\n`);
    }
  } catch (e) {
    console.warn(`Не удалось проверить чат: ${e.message}`);
  }

  const topicsToCreate = [
    { key: 'errors', name: '🔴 Ошибки и падения', color: 0xFB6F5F },
    { key: 'purchases', name: '💳 Покупки и премиум', color: 0xFFD67E },
    { key: 'registrations', name: '👤 Регистрации', color: 0x6FB9F0 },
  ];

  console.log('\nСоздание тем форума...');
  const results = {};

  for (const t of topicsToCreate) {
    try {
      const created = await tgCall('createForumTopic', {
        chat_id: chatId,
        name: t.name,
        icon_color: t.color,
      });
      console.log(`✅ Создана тема "${created.name}" -> thread_id: ${created.message_thread_id}`);
      results[t.key] = created.message_thread_id;
    } catch (e) {
      console.error(`❌ Не удалось создать тему "${t.name}": ${e.message}`);
    }
  }

  if (Object.keys(results).length > 0) {
    console.log('\n============================================================');
    console.log('Готово! ID созданных тем:');
    console.log(JSON.stringify(results, null, 2));
    console.log('============================================================');
    console.log('\nЧтобы подключить их к Cloudflare Worker, сохраните переменные:');
    if (results.errors) console.log(`  npx wrangler secret put TELEGRAM_TOPIC_ERRORS       # значение: ${results.errors}`);
    if (results.purchases) console.log(`  npx wrangler secret put TELEGRAM_TOPIC_PURCHASES    # значение: ${results.purchases}`);
    if (results.registrations) console.log(`  npx wrangler secret put TELEGRAM_TOPIC_REGISTRATIONS # значение: ${results.registrations}`);
    console.log('\n(Или пропишите их в [vars] в wrangler.toml)');
  }
}

run().catch(err => {
  console.error('\nОшибка:', err.message);
  process.exit(1);
});
