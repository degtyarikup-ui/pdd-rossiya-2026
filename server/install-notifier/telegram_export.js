import { sanitizeDiagnosticContext, diagnosticOs } from './diagnostic_context.js';
// Журнал ошибок и выгрузка по команде из подчата «Ошибки и падения».
// Одна запись = один инцидент (то, что ушло или было свёрнуто в Telegram).
// Модуль без обращения к хранилищу и сети: разбор команд, ключи и CSV.
import { incidentGuide, platformLabel, providerLabel, storeLabel } from './incident_copy.js';

export const ERROR_LOG_PREFIX = 'log:';
export const EXPORT_COMMAND_MAX_AGE_MS = 10 * 60000;
const DAY_MS = 86400000;
const MSK_OFFSET_MS = 3 * 3600000;

// /export_day, /export_all, /export (справка), в том числе с @имя_бота.
export function parseExportCommand(text) {
  const match = /^\/(export(?:_day|_all)?)(?:@\w+)?(?:\s|$)/i.exec(String(text || '').trim());
  if (!match) return null;
  const name = match[1].toLowerCase();
  if (name === 'export_day') return 'day';
  if (name === 'export_all') return 'all';
  return 'help';
}

// Ключ сортируется по времени: записи лежат в хранилище по порядку.
export function errorLogKey(ts, id) {
  return ERROR_LOG_PREFIX + String(Math.max(0, Math.floor(ts))).padStart(15, '0') + ':' + id;
}

// С какого времени читать журнал для режима выгрузки.
export function exportStart(mode, now) {
  return mode === 'day' ? Math.max(0, now - DAY_MS) : 0;
}

export function errorLogRecord(incident, { ts, sent, level, reason }) {
  return {
    ts,
    id: String(incident.id || ''),
    level: level || '',
    sent: Boolean(sent),
    notificationReason: ['sent', 'grouped', 'burst_limit', 'info_only'].includes(reason) ? reason : '',
    origin: incident.origin || '',
    category: incident.category || '',
    operation: incident.operation || '',
    code: incident.code || '',
    provider: incident.provider || '',
    authProvider: incident.authProvider || '',
    platform: incident.platform || '',
    appVersion: incident.appVersion || '',
    device: incident.device || '',
    store: incident.store || '',
    country: incident.country || '',
    userId: incident.userId || '',
    userName: incident.userName || '',
    userEmail: incident.userEmail || '',
    status: Number.isInteger(incident.status) ? incident.status : '',
    diagnosticId: incident.diagnosticId || '',
    installation: /^[a-f0-9]{16}$/.test(incident.installation || '') ? incident.installation : '',
    os: diagnosticOs(incident.os) || '',
    context: sanitizeDiagnosticContext(incident.context),
    paymentOrderId: incident.payment?.orderId || '',
    paymentTxId: incident.payment?.txId || '',
    paymentTier: incident.payment?.tier || '',
    paymentAmountRub: incident.payment?.amountRub || '',
    paymentMethod: incident.payment?.method || '',
    paymentClient: incident.payment?.client || '',
    paymentProviderOperation: incident.payment?.providerOperation || '',
    paymentProviderStatus: incident.payment?.providerStatus || '',
  };
}

// Уровень срочности так же, как в Telegram-сообщении (подпись, без эмодзи).
export function errorLevelLabel(incident) {
  try {
    return incidentGuide(incident).label;
  } catch (_) {
    return '';
  }
}

// Время по Москве без перехода на летнее: в России его давно нет.
export function mskStamp(ts) {
  const d = new Date(Number(ts) + MSK_OFFSET_MS);
  const p = n => String(n).padStart(2, '0');
  return `${p(d.getUTCDate())}.${p(d.getUTCMonth() + 1)}.${d.getUTCFullYear()} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}`;
}

const HEADER = [
  'Время (МСК)', 'Срочность', 'Ушло в чат', 'Источник', 'Раздел', 'Операция', 'Код',
  'Провайдер входа', 'Платформа', 'Версия приложения', 'Устройство', 'Магазин', 'Страна по IP',
  'ID пользователя', 'Имя', 'Почта', 'HTTP-статус', 'ID диагностики',
  'Заказ оплаты', 'Транзакция Platega', 'Тариф', 'Сумма (RUB)', 'Метод оплаты', 'Клиент оплаты', 'Запрос Platega', 'HTTP Platega',
  'ID установки (обезличенный)', 'ОС', 'Контекст загрузки', 'Этап', 'Попытка',
  'Товаров запрошено', 'Товаров получено', 'Товаров не найдено', 'Не найденные ID товаров',
  'Источник SDK', 'Отпечаток кода SDK', 'Кадры приложения', 'Тип исключения',
  'Этап чтения поддержки', 'HTTP хранилища поддержки', 'Повторяемый сбой (retryable)', 'Перегрузка (overloaded)',
];

function rowOf(record) {
  record = { ...record, context: sanitizeDiagnosticContext(record.context) };
  return [
    mskStamp(record.ts),
    record.level,
    record.sent ? 'да' : record.notificationReason === 'info_only' ? 'нет (для сведения)' : record.notificationReason === 'burst_limit' ? 'нет (ограничение потока)' : 'нет (повтор, свёрнуто)',
    record.origin === 'client' ? 'приложение' : record.origin === 'server' ? 'сервер' : '',
    record.category,
    record.operation,
    record.code,
    record.provider ? providerLabel(record.provider) : '',
    record.platform ? platformLabel(record.platform) : '',
    record.appVersion,
    record.device,
    record.store ? storeLabel(record.store) : '',
    record.country,
    record.userId,
    record.userName,
    record.userEmail,
    record.status,
    record.diagnosticId,
    record.paymentOrderId,
    record.paymentTxId,
    record.paymentTier,
    record.paymentAmountRub,
    record.paymentMethod,
    record.paymentClient,
    record.paymentProviderOperation,
    record.paymentProviderStatus,
    record.installation, record.os, record.context?.phase, record.context?.stage, record.context?.attempt,
    record.context?.requestedCount, record.context?.returnedCount, record.context?.missingCount,
    record.context?.missingIds?.join(', '), record.context?.sdkSource, record.context?.sdkCodeHash, record.context?.frames?.join('\n'), record.context?.errorType,
    record.context?.supportStage, record.context?.upstreamStatus, record.context?.retryable, record.context?.overloaded,
  ];
}

// Значения, которые Excel может принять за формулу, получают апостроф.
function csvCell(value) {
  let text = value === null || value === undefined ? '' : String(value);
  if (/^[=+\-@\t\r]/.test(text)) text = "'" + text;
  return /[";\r\n]/.test(text) ? '"' + text.replaceAll('"', '""') + '"' : text;
}

// UTF-8 с BOM и разделителем «;» — так файл сразу открывается в Excel и Numbers.
export function buildErrorCsv(records) {
  const lines = [HEADER, ...records.map(rowOf)].map(cells => cells.map(csvCell).join(';'));
  return '﻿' + lines.join('\r\n') + '\r\n';
}
