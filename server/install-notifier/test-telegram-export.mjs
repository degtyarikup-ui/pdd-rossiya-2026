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
  assert.equal(header.split(';').length, 26);
  assert.match(row, /^11\.10\.2026 09:57:04;Важно;да;приложение;auth;auth\.provider;timeout;Google;Android;2\.2\.3\+59;realme RMX5303;;RU;/);
  assert.ok(row.includes('"\'=HYPERLINK(""https://x"",""k"")"'), 'формула экранирована и кавычки удвоены');
  assert.ok(row.includes('"a;b""c@mail.ru"'), 'точка с запятой внутри ячейки заключена в кавычки');
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
