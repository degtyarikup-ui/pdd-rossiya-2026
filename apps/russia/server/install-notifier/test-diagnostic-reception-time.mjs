import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleClientIncident, reportIncident, buildIncidentMessage } from './diagnostics.js';
import { TelegramQueue } from './telegram_queue.js';
import { buildErrorCsv, errorLogKey, errorLogRecord, errorLogTime, exportStart, mskStamp } from './telegram_export.js';

class Storage {
  data = new Map(); alarm = null;
  async get(key) { return structuredClone(this.data.get(key)); }
  async put(key, value) { this.data.set(key, structuredClone(value)); }
  async delete(key) { this.data.delete(key); }
  async list({ prefix = '', start = '', limit = Infinity } = {}) {
    return new Map([...this.data].filter(([key]) => key.startsWith(prefix) && key >= start)
      .sort(([a], [b]) => a.localeCompare(b)).slice(0, limit).map(([key, value]) => [key, structuredClone(value)]));
  }
  async getAlarm() { return this.alarm; }
  async setAlarm(value) { this.alarm = value; }
  async transaction(fn) { return fn(this); }
}
const RECEIVED = Date.parse('2026-10-27T10:06:00Z');
const OCCURRED = Date.parse('2026-10-22T10:37:17Z');
function setup(t) {
  const originalNow = Date.now, originalFetch = globalThis.fetch;
  let now = RECEIVED;
  Date.now = () => now;
  globalThis.fetch = async () => { throw new Error('unexpected external network call'); };
  t.after(() => { Date.now = originalNow; globalThis.fetch = originalFetch; });
  const env = { SHARED_SECRET: 'test', BOT_TOKEN: 'test', CHAT_ID: 'test', TELEGRAM_TOPIC_ERRORS: '7' };
  const state = { storage: new Storage() };
  let queue = new TelegramQueue(state, env);
  env.TELEGRAM = { idFromName: x => x, get: () => ({ fetch: (url, options) => queue.fetch(new Request(url, options)) }) };
  return { env, state, get queue() { return queue; }, setNow(value) { now = value; },
    restart() { queue = new TelegramQueue(state, env); } };
}
const event = (overrides = {}) => ({ id: 'a'.repeat(32), ts: OCCURRED, category: 'purchase',
  operation: 'iap.products', code: 'storekit_no_response', provider: 'appstore', platform: 'ios',
  appVersion: '2.2.6+67', context: { phase: 'paywall', stage: 'query' }, ...overrides });
const request = events => new Request('https://test/api/diagnostics', { method: 'POST',
  headers: { 'x-install-secret': 'test', 'content-type': 'application/json' },
  body: JSON.stringify({ installId: 'b'.repeat(32), events }) });
const messages = async f => [...(await f.state.storage.list({ prefix: 'q:' })).values()].map(item => item.text);

test('old client event received today keeps original time and appears in today export with trusted receipt', async t => {
  const f = setup(t);
  assert.equal((await handleClientIncident(request([event({ receivedAt: 1 })]), f.env)).status, 200);
  const records = await f.queue.readErrorLog(exportStart('day', RECEIVED));
  assert.equal(records.length, 1);
  assert.equal(records[0].ts, OCCURRED);
  assert.equal(records[0].receivedAt, RECEIVED, 'client cannot choose the reception time');
  assert.equal(records[0].code, 'storekit_no_response', 'catalog failure remains actionable');
  const message = (await messages(f))[0];
  assert.match(message, /Время события на устройстве: 22\.10\.2026, 13:37:17 МСК/);
  assert.match(message, /Получено сервером: 27\.10\.2026, 13:06:00 МСК/);
  assert.match(message, /отложенная отправка.*неточные часы/);
  let exported;
  f.queue.sendBotDocument = async (_thread, fileName, csv) => { exported = { fileName, csv }; };
  assert.equal(await f.queue.handleErrorCommand({ text: '/export_day', from: { is_bot: false },
    chat: { id: 'test' }, date: RECEIVED / 1000, message_thread_id: 7 }), true);
  assert.match(exported.fileName, /sutki-2026-10-27/);
  const [header, row] = exported.csv.slice(1).trim().split('\r\n').map(line => line.split(';'));
  assert.equal(header.length, 44);
  assert.equal(row[0], '22.10.2026 13:37:17');
  assert.equal(header[43], 'Получено сервером (МСК)');
  assert.equal(row[43], '27.10.2026 13:06:00');
});

test('first 43 CSV columns remain in the existing order and legacy receipt is blank', () => {
  const expected = ['Время (МСК)', 'Срочность', 'Ушло в чат', 'Источник', 'Раздел', 'Операция', 'Код',
    'Провайдер входа', 'Платформа', 'Версия приложения', 'Устройство', 'Магазин', 'Страна по IP',
    'ID пользователя', 'Имя', 'Почта', 'HTTP-статус', 'ID диагностики', 'Заказ оплаты', 'Транзакция Platega',
    'Тариф', 'Сумма (RUB)', 'Метод оплаты', 'Клиент оплаты', 'Запрос Platega', 'HTTP Platega',
    'ID установки (обезличенный)', 'ОС', 'Контекст загрузки', 'Этап', 'Попытка', 'Товаров запрошено',
    'Товаров получено', 'Товаров не найдено', 'Не найденные ID товаров', 'Источник SDK', 'Отпечаток кода SDK',
    'Кадры приложения', 'Тип исключения', 'Этап чтения поддержки', 'HTTP хранилища поддержки',
    'Повторяемый сбой (retryable)', 'Перегрузка (overloaded)'];
  const legacy = errorLogRecord(event(), { ts: OCCURRED, sent: true, level: 'Важно', reason: 'sent' });
  const [header, row] = buildErrorCsv([legacy]).slice(1).trim().split('\r\n').map(line => line.split(';'));
  assert.deepEqual(header.slice(0, 43), expected);
  assert.equal(row.length, 44);
  assert.equal(row[43], '');
});

test('normal clock and server messages retain short timestamp while five-minute difference is labelled neutrally', async t => {
  const f = setup(t);
  const base = event({ origin: 'client', receivedAt: RECEIVED, ts: RECEIVED - 299999 });
  assert.doesNotMatch(buildIncidentMessage(base), /Получено сервером|неточные часы/);
  assert.match(buildIncidentMessage({ ...base, ts: RECEIVED - 300000 }), /Получено сервером/);
  assert.match(buildIncidentMessage({ ...base, ts: RECEIVED + 300000 }), /неточные часы устройства/);
  assert.doesNotMatch(buildIncidentMessage({ ...base, origin: 'server', ts: OCCURRED }), /Получено сервером/);
  assert.equal((await handleClientIncident(request([event({ ts: RECEIVED + 300000 })]), f.env)).status, 200);
  assert.match((await messages(f))[0], /Получено сервером/);
  assert.equal((await handleClientIncident(request([event({ id: 'c'.repeat(32), ts: RECEIVED + 300001 })]), f.env)).status, 400,
    'existing clock validation remains unchanged');
});

test('server overwrites claimed receipt and captures arrival before asynchronous profile lookup', async t => {
  const f = setup(t);
  f.env.INSTALLS = { get: async () => { f.setNow(RECEIVED + 2000); return null; } };
  assert.equal(await reportIncident(f.env, event({ userId: 'google_fixture', receivedAt: RECEIVED + 60000 })), true);
  const [record] = await f.queue.readErrorLog(0);
  assert.equal(record.receivedAt, RECEIVED);
  assert.equal(record.ts, OCCURRED);
});

test('retry of original event after queue restart does not add a message or reset first receipt', async t => {
  const f = setup(t);
  assert.equal((await handleClientIncident(request([event()]), f.env)).status, 200);
  f.restart(); f.setNow(RECEIVED + 30 * 60000);
  assert.equal((await handleClientIncident(request([event()]), f.env)).status, 200);
  assert.equal((await messages(f)).length, 1);
  const records = await f.queue.readErrorLog(0);
  assert.equal(records.length, 1);
  assert.equal(records[0].receivedAt, RECEIVED);
  assert.equal(records[0].ts, OCCURRED);
});

test('legacy records fall back to event time without rewriting existing keys', async t => {
  const f = setup(t);
  const recent = RECEIVED - 23 * 3600000, old = RECEIVED - 25 * 3600000;
  for (const [ts, id] of [[recent, 'legacy-recent'], [old, 'legacy-old']]) {
    await f.state.storage.put(errorLogKey(ts, id), { ts, id });
  }
  const records = await f.queue.readErrorLog(exportStart('day', RECEIVED));
  assert.deepEqual(records, [{ ts: recent, id: 'legacy-recent' }]);
  assert.equal(errorLogTime(records[0]), recent);
  assert.equal((await f.state.storage.list({ prefix: 'log:' })).size, 2);
  assert.equal(mskStamp(errorLogTime(records[0])), mskStamp(recent));
});

test('delayed auth batches stay within Telegram size limit and retain all original event records', async t => {
  const f = setup(t);
  const events = Array.from({ length: 8 }, (_, i) => event({ id: (i + 1).toString(16).padStart(32, '0'),
    category: 'auth', operation: i % 2 ? 'auth.session' : 'auth.provider', code: 'timeout:' + (i + 1) + 'x',
    provider: ['google', 'apple', 'yandex', 'telegram'][i % 4], device: '&'.repeat(100),
    context: { stage: 'provider', attempt: i + 1, errorType: 'TimeoutException', frames: ['auth_service.dart:1234:56'] } }));
  assert.equal((await handleClientIncident(request(events), f.env)).status, 200);
  const queued = await messages(f);
  assert.ok(queued.length >= 1);
  assert.ok(queued.length < events.length, 'related events still coalesce');
  for (const text of queued) {
    assert.ok(text.length <= 4096, 'delayed receipt lines must fit the existing limit');
    assert.match(text, /Получено сервером/);
  }
  assert.equal((await f.queue.readErrorLog(exportStart('day', RECEIVED))).length, events.length);
  for (const item of events) assert.equal(queued.filter(text => text.includes('Код: <code>' + item.code + '</code>')).length, 1);
});
