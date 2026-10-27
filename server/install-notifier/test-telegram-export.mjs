// Выгрузка журнала ошибок: команды, порядок записей, время и CSV для Excel.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildErrorCsv, errorLogKey, errorLogRecord, errorLevelLabel, exportStart, mskStamp, parseExportCommand } from './telegram_export.js';

test('команды: сутки, всё время, справка; с именем бота; чужие сообщения не считаются', () => {
  assert.equal(parseExportCommand('/export_day'), 'day');
  assert.equal(parseExportCommand('/export_all'), 'all');
  assert.equal(parseExportCommand('/export_all@PddLogBot'), 'all');
  assert.equal(parseExportCommand('/EXPORT_DAY'), 'day');
  assert.equal(parseExportCommand('/export'), 'help');
  assert.equal(parseExportCommand('  /export_day  '), 'day');
  assert.equal(parseExportCommand('/export_daily'), null);
  assert.equal(parseExportCommand('/exporter'), null);
  assert.equal(parseExportCommand('выгрузи /export_day'), null);
  assert.equal(parseExportCommand(undefined), null);
});

test('ключи журнала идут по времени, а выборка за сутки начинается не раньше границы', () => {
  assert.ok(errorLogKey(999, 'a') < errorLogKey(1000, 'a'));
  assert.ok(errorLogKey(999999999999, 'z') < errorLogKey(1000000000000, 'a'));
  const now = Date.UTC(2026, 9, 11, 12);
  assert.equal(exportStart('day', now), now - 86400000);
  assert.equal(exportStart('all', now), 0);
  assert.equal(exportStart('day', 1000), 0);
});

test('время в файле — московское, без перехода на летнее', () => {
  assert.equal(mskStamp(Date.UTC(2026, 9, 11, 9, 57, 4)), '11.10.2026 12:57:04');
  assert.equal(mskStamp(Date.UTC(2026, 0, 31, 21, 30, 0)), '01.02.2026 00:30:00');
});

test('CSV: BOM, разделитель «;», кавычки для спецсимволов, формулы не исполняются', () => {
  const record = errorLogRecord({
    id: 'abc', origin: 'client', category: 'auth', operation: 'auth.provider', code: 'timeout',
    provider: 'google', platform: 'android', appVersion: '2.2.3+59', device: 'realme RMX5303',
    userName: '=HYPERLINK("https://x","k")', userEmail: 'a;b"c@mail.ru', country: 'RU',
  }, { ts: Date.UTC(2026, 9, 11, 6, 57, 4), sent: true, level: 'Важно' });
  const csv = buildErrorCsv([record]);
  assert.ok(csv.startsWith('﻿'));
  const [header, row] = csv.slice(1).trim().split('\r\n');
  assert.match(header, /^Время \(МСК\);Срочность;Ушло в чат;/);
  assert.equal(header.split(';').length, 44);
  assert.match(row, /^11\.10\.2026 09:57:04;Важно;да;приложение;auth;auth\.provider;timeout;Google;Android;2\.2\.3\+59;realme RMX5303;;RU;/);
  assert.ok(row.includes('"\'=HYPERLINK(""https://x"",""k"")"'), 'формула экранирована и кавычки удвоены');
  assert.ok(row.includes('"a;b""c@mail.ru"'), 'точка с запятой внутри ячейки заключена в кавычки');
});

test('CSV appends sanitized support diagnostics and preserves explicit false platform flags', () => {
  const meta = { ts: Date.UTC(2026, 9, 22, 15), sent: true, level: 'Важно' };
  const base = { category: 'infrastructure', operation: 'api.support.messages', code: 'support_read_unavailable' };
  const rows = [
    errorLogRecord({ ...base, context: { supportStage: 'list', upstreamStatus: 503, retryable: false, overloaded: true } }, meta),
    errorLogRecord({ ...base, context: { supportStage: 'seed', upstreamStatus: 599, retryable: true, overloaded: false } }, meta),
    errorLogRecord(base, meta),
  ];
  const [header, ...data] = buildErrorCsv(rows).slice(1).trim().split('\r\n');
  assert.deepEqual(header.split(';').slice(39, 43), ['Этап чтения поддержки', 'HTTP хранилища поддержки', 'Повторяемый сбой (retryable)', 'Перегрузка (overloaded)']);
  assert.equal(header.split(';')[38], 'Тип исключения', 'existing column positions stay unchanged');
  assert.deepEqual(data.map(row => row.split(';').slice(39, 43)), [
    ['list', '503', 'false', 'true'], ['seed', '599', 'true', 'false'], ['', '', '', ''],
  ]);
  // Re-sanitize at export too: stored or caller-supplied context is untrusted.
  const injected = { ...rows[0], context: { supportStage: 'list TOP_SECRET', upstreamStatus: '503 TOP_SECRET',
    retryable: 'TOP_SECRET', overloaded: { message: 'TOP_SECRET' }, message: 'TOP_SECRET',
    url: 'https://private.test', body: 'TOP_SECRET', userId: 'private-user', frames: ['https://private.test'] } };
  const csv = buildErrorCsv([injected]);
  assert.deepEqual(csv.slice(1).trim().split('\r\n')[1].split(';').slice(39, 43), ['', '', '', '']);
  assert.doesNotMatch(csv, /TOP_SECRET|private\.test|private-user/);
});

test('пустой журнал даёт только заголовок, неотправленные повторы помечены', () => {
  const csv = buildErrorCsv([]);
  assert.equal(csv.trim().split('\r\n').length, 1);
  const suppressed = errorLogRecord({ id: 'x', category: 'app', operation: 'startup.premium', code: 'timeout' }, { ts: 1, sent: false, level: 'Не срочно' });
  assert.match(buildErrorCsv([suppressed]), /;нет \(повтор, свёрнуто\);/);
});

test('срочность в журнале совпадает с Telegram-сообщением', () => {
  assert.equal(errorLevelLabel({ category: 'purchase', operation: 'api.pay.platega.callback', code: 'operation_failed' }), 'Срочно');
  assert.equal(errorLevelLabel({ category: 'auth', operation: 'auth.provider', code: 'timeout' }), 'Важно');
});

test('CSV сохраняет детали неудачной оплаты, включая свёрнутые сообщения', () => {
  const orderId = crypto.randomUUID(), txId = crypto.randomUUID();
  const record = errorLogRecord({ category: 'purchase', operation: 'payment.check', code: 'payment_provider_unavailable',
    payment: { orderId, txId, tier: 'threeMonths', amountRub: 290, method: 'sbp', client: 'web', providerOperation: 'status', providerStatus: 503 },
  }, { ts: Date.UTC(2026, 9, 15), sent: false, level: 'Срочно' });
  const csv = buildErrorCsv([record]);
  assert.match(csv, /Заказ оплаты;Транзакция Platega;Тариф;Сумма \(RUB\)/);
  assert.ok(csv.includes(`${orderId};${txId};threeMonths;290;sbp;web;status;503`));
  assert.match(csv, /нет \(повтор, свёрнуто\)/);
});

import { TelegramQueue } from './telegram_queue.js';
import { handleTelegramWebhook, handleSupportGetMessages, resetSupportPollThrottle } from './support_chat.js';
import { telegramWebhookSecret } from './telegram_auth.js';

class ExportStorage {
  data = new Map();
  async get(key, options) {
    const value = this.data.get(key);
    return options?.type === 'json' && typeof value === 'string' ? JSON.parse(value) : structuredClone(value);
  }
  async put(key, value) { this.data.set(key, structuredClone(value)); }
  async delete(key) { this.data.delete(key); }
  async list({ prefix = '', start = '', limit = Infinity } = {}) {
    return new Map([...this.data].filter(([key]) => key.startsWith(prefix) && key >= start).sort().slice(0, limit));
  }
}
function exportSetup() {
  const storage = new ExportStorage();
  const env = { BOT_TOKEN: 'test', CHAT_ID: '-100123', SESSION_SECRET: crypto.randomUUID(),
    TELEGRAM_TOPIC_ERRORS: '7', INSTALLS: new ExportStorage() };
  const queue = new TelegramQueue({ storage }, env);
  env.TELEGRAM = { idFromName: name => name, get: () => ({ fetch: (url, options) => queue.fetch(new Request(url, options)) }) };
  return { storage, env, queue };
}
const exportUpdate = (id = 42, text = '/export_day') => ({ update_id: id, message: {
  message_id: id, text, date: Math.floor(Date.now() / 1000),
  chat: { id: -100123 }, message_thread_id: 7, from: { id: 123 },
} });
async function webhookRequest(env, update, verified = true) {
  return new Request('https://test/api/telegram/webhook', { method: 'POST',
    headers: { 'content-type': 'application/json', ...(verified ? { 'x-telegram-bot-api-secret-token': await telegramWebhookSecret(env) } : {}) },
    body: JSON.stringify(update) });
}

test('verified webhook exports CSV from the log-owning DO immediately and deduplicates redelivery', async () => {
  const { env, queue } = exportSetup(), original = globalThis.fetch, calls = [];
  await queue.logIncident({ id: 'incident-1', category: 'app', operation: 'startup.premium', code: 'timeout' }, true, Date.now());
  globalThis.fetch = async (url, options) => {
    calls.push({ url, body: options.body });
    return Response.json({ ok: true });
  };
  try {
    for (let i = 0; i < 2; i++) {
      assert.equal((await handleTelegramWebhook(await webhookRequest(env, exportUpdate()), env)).status, 200);
    }
    assert.equal(calls.length, 1);
    assert.match(calls[0].url, /sendDocument$/);
    const form = calls[0].body;
    assert.equal(form.get('chat_id'), env.CHAT_ID);
    assert.equal(form.get('message_thread_id'), '7');
    assert.match(form.get('caption'), /записей 1/);
    assert.match(await form.get('document').text(), /startup\.premium;timeout/);
  } finally { globalThis.fetch = original; }
});

test('unsigned, stale, wrong-chat and bot-authored commands never export the log', async () => {
  const { env } = exportSetup(), original = globalThis.fetch;
  let sends = 0;
  globalThis.fetch = async () => { sends++; return Response.json({ ok: true }); };
  try {
    await handleTelegramWebhook(await webhookRequest(env, exportUpdate(), false), env);
    const stale = exportUpdate(); stale.message.date -= 601;
    const wrongChat = exportUpdate(); wrongChat.message.chat.id = -100999;
    const bot = exportUpdate(); bot.message.from.is_bot = true;
    for (const update of [stale, wrongChat, bot]) await handleTelegramWebhook(await webhookRequest(env, update), env);
    assert.equal(sends, 0);
  } finally { globalThis.fetch = original; }
});

test('failed export is not acknowledged and the same webhook can retry successfully', async () => {
  const { env, queue, storage } = exportSetup(), original = globalThis.fetch;
  await queue.logIncident({ id: 'retry', operation: 'iap.products', code: 'sdk_error' }, true, Date.now());
  let sends = 0;
  globalThis.fetch = async () => ++sends === 1 ? Response.json({ ok: false }, { status: 429 }) : Response.json({ ok: true });
  try {
    await assert.rejects(handleTelegramWebhook(await webhookRequest(env, exportUpdate()), env), /export upload failed/);
    assert.equal(await storage.get('export:completed'), undefined);
    assert.equal((await handleTelegramWebhook(await webhookRequest(env, exportUpdate()), env)).status, 200);
    assert.deepEqual(await storage.get('export:completed'), [42]);
    assert.equal(sends, 2);
  } finally { globalThis.fetch = original; }
});

test('cron detects active webhook and does not call the incompatible getUpdates API', async () => {
  const { queue } = exportSetup(), original = globalThis.fetch, calls = [];
  globalThis.fetch = async url => {
    calls.push(url);
    return Response.json({ ok: true, result: { url: 'https://test/api/telegram/webhook' } });
  };
  try {
    assert.deepEqual(await queue.pollErrorCommands(), { ok: true, webhook: true });
    assert.equal(calls.length, 1);
    assert.match(calls[0], /getWebhookInfo$/);
  } finally { globalThis.fetch = original; }
});

test('without webhook one durable poll handles both exports and support replies', async () => {
  const { queue, env, storage } = exportSetup(), original = globalThis.fetch;
  await env.INSTALLS.put('support:thread:22', 'client-1');
  const support = exportUpdate(43, 'Ответ оператора'); support.message.message_thread_id = 22;
  const updates = [exportUpdate(), support];
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push(url);
    if (url.endsWith('/getWebhookInfo')) return Response.json({ ok: true, result: { url: '' } });
    if (url.endsWith('/getUpdates')) return Response.json({ ok: true, result: updates });
    assert.match(url, /sendMessage$/); // Empty log explanation.
    return Response.json({ ok: true });
  };
  try {
    assert.deepEqual(await queue.pollErrorCommands(), { ok: true, updates: 2, handled: 1 });
    assert.equal(await storage.get('tg:offset'), 44);
    const messages = JSON.parse(await env.INSTALLS.get('support:messages:client-1'));
    assert.equal(messages[0].text, 'Ответ оператора');
    // The app fallback uses the same DO poll, rather than a competing offset.
    const count = calls.length;
    resetSupportPollThrottle();
    await handleSupportGetMessages(new Request('https://test/api/support/messages?clientId=client-1'), env);
    assert.ok(calls.slice(count).some(url => url.endsWith('/getWebhookInfo')));
    assert.equal(await env.INSTALLS.get('tg:support_offset'), undefined);
  } finally { globalThis.fetch = original; }
});

test('app polls remember a found webhook and stop asking the durable queue', async () => {
  const { env } = exportSetup(), original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async url => {
    calls.push(url);
    return Response.json({ ok: true, result: { url: 'https://test/api/telegram/webhook' } });
  };
  try {
    resetSupportPollThrottle();
    const first = await handleSupportGetMessages(new Request('https://test/api/support/messages?clientId=c1'), env);
    assert.equal(first.status, 200);
    assert.equal(await env.INSTALLS.get('tg:webhook_active'), '1');
    resetSupportPollThrottle();
    await handleSupportGetMessages(new Request('https://test/api/support/messages?clientId=c1'), env);
    assert.equal(calls.length, 1);
  } finally { globalThis.fetch = original; }
});

test('app polls ask the durable queue at most once per interval', async () => {
  const { env } = exportSetup(), original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async url => {
    calls.push(url);
    if (url.endsWith('/getWebhookInfo')) return Response.json({ ok: true, result: { url: '' } });
    return Response.json({ ok: true, result: [] });
  };
  try {
    resetSupportPollThrottle();
    for (let i = 0; i < 3; i++) {
      await handleSupportGetMessages(new Request('https://test/api/support/messages?clientId=c1'), env);
    }
    assert.equal(calls.filter(url => url.endsWith('/getWebhookInfo')).length, 1);
  } finally { globalThis.fetch = original; }
});

test('a failing durable queue still returns stored support replies', async () => {
  const { env } = exportSetup();
  await env.INSTALLS.put('support:messages:c2', JSON.stringify([{ id: 'm1', text: 'Ответ', from: 'support', ts: 1 }]));
  env.TELEGRAM.get = () => ({ fetch: async () => { throw new Error('Durable Object is overloaded'); } });
  resetSupportPollThrottle();
  const response = await handleSupportGetMessages(new Request('https://test/api/support/messages?clientId=c2'), env);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.messages[0].text, 'Ответ');
});

test('polling leaves the cursor unchanged when Telegram rejects an export', async () => {
  const { queue, storage } = exportSetup(), original = globalThis.fetch;
  globalThis.fetch = async url => {
    if (url.endsWith('/getWebhookInfo')) return Response.json({ ok: true, result: { url: '' } });
    if (url.endsWith('/getUpdates')) return Response.json({ ok: true, result: [exportUpdate()] });
    return Response.json({ ok: false }, { status: 503 });
  };
  try {
    assert.deepEqual(await queue.pollErrorCommands(), { ok: false, reason: 'poll failed' });
    assert.equal(await storage.get('tg:offset'), undefined);
    assert.equal(await storage.get('export:completed'), undefined);
  } finally { globalThis.fetch = original; }
});


test('migrated Telegram group still exports from the original log storage identity', async () => {
  const { env, queue } = exportSetup(), original = globalThis.fetch;
  env.CHAT_ID = '-5556420560';
  const names = [];
  env.TELEGRAM.idFromName = name => { names.push(name); return name; };
  await queue.logIncident({ id: 'migration', operation: 'iap.products' }, true, Date.now());
  const update = exportUpdate(); update.message.chat.id = -1004472386966;
  globalThis.fetch = async (_, options) => {
    assert.equal(options.body.get('chat_id'), '-1004472386966');
    assert.match(await options.body.get('document').text(), /iap.products/);
    return Response.json({ ok: true });
  };
  try {
    assert.equal((await handleTelegramWebhook(await webhookRequest(env, update), env)).status, 200);
    assert.deepEqual(names, ['-5556420560']);
  } finally { globalThis.fetch = original; }
});
