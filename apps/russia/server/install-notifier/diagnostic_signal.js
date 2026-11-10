// Фоновые сигналы: сбои, причина которых — связь или устройство человека.
// По одному такому сообщению сделать ничего нельзя, поэтому в чат они не идут:
// пишутся в журнал (CSV), считаются по установкам и дают одно сообщение, когда
// их стало заметно больше обычного (всплеск), плюс строку в суточной сводке.
// Модуль без хранилища и сети: классификация, подсчёт и тексты.

const HOUR_MS = 3600000;
export const SIGNAL_STALE_MS = 24 * HOUR_MS;
export const SIGNAL_SPIKE_MIN_INSTALLS = 6;
export const SIGNAL_SPIKE_BASELINE_FACTOR = 4;
export const SIGNAL_SPIKE_COOLDOWN_MS = 3 * HOUR_MS;
const RECENT_LIMIT = 200;
const BASELINE_HOURS = 24;

// Подтверждение оплаты никогда не уходит в фон: человек мог заплатить и
// остаться без доступа. Список совпадает с CRITICAL_OPERATIONS в incident_copy.js.
const PROTECTED_OPERATIONS = new Set(['api.user.purchase', 'premium.verify', 'api.pay.platega.callback',
  'payment.check', 'iap.process', 'iap.complete']);

// timeout, timeout:3x, network, network:http, network:tls, network_error.
const NETWORK_CODE = /^(?:timeout|network|network_error)(?::[a-z0-9]{1,12})?$/;
// Окно входа закрылось без результата на стороне устройства: в Apple ID не вошли
// (apple_unknown), нет сервисов Google (gms_unavailable), окно Google вернулось
// без данных, нет связи с Google (7), внутренний сбой сервисов (8), вход уже
// идёт (12502). Ошибка настройки OAuth (10) и 12500 сюда не входят.
const PROVIDER_DEVICE_CODE = /^(?:apple_unknown|gms_unavailable(?::\d{1,5})?|sign_in_failed(?::(?:7|8|12502))?)$/;
const WEBVIEW_NETWORK_CODE = /^page_load_failed:(?:hostLookup|connect|timeout|io|failedSslHandshake|proxyAuthentication)$/;
const STORE_DEVICE_CODES = new Set(['store_unavailable', 'billing_unavailable', 'service_unavailable', 'storekit2_products_error']);
// Эмуляторы Android и симуляторы iOS: роботы проверки магазинов и тестовые стенды.
const TEST_DEVICE = /(?:\bsdk_gphone|\bAndroid SDK built for\b|\bemulator\b|\bgeneric_x86|^(?:arm64|x86_64|i386)$)/i;

export const SIGNAL_FAMILIES = {
  auth_server: {
    title: 'приложение не достаёт до нашего сервера при входе',
    line: 'Не достали до нашего сервера при входе',
    hint: 'Проверьте, открываются ли из России оба адреса сервера (workers.dev и api.pdd-drive.app) и статус Cloudflare. Если всплеск у одного оператора или региона — нужен маршрут вне Cloudflare.',
  },
  auth_provider: {
    title: 'не открывается или не завершается окно входа',
    line: 'Окно входа Google / Apple / Яндекс не завершилось',
    hint: 'Проверьте статус Google, Apple и Яндекса. Если всплеск на одной платформе сразу после релиза — проверьте настройки входа этой сборки.',
  },
  store: {
    title: 'магазин не отдаёт тарифы или недоступен',
    line: 'Магазин не ответил или недоступен на устройстве',
    hint: 'Проверьте статус App Store / Google Play и что подписки активны в консоли магазина.',
  },
  payment: {
    title: 'нет связи при оплате через СБП',
    line: 'Нет связи при оплате через СБП',
    hint: 'Проверьте доступность сервера и кабинет Platega. Оплаченные заказы подтверждаются по уведомлению Platega и без приложения.',
  },
  app: {
    title: 'сетевые сбои внутри приложения',
    line: 'Нет связи внутри приложения',
    hint: 'Проверьте доступность сервера и картинок уведомлений. Если всплеск на одной версии — смотрите кадры приложения в выгрузке.',
  },
};

function environmentFamily(operation, code) {
  const network = NETWORK_CODE.test(code);
  switch (operation) {
    case 'auth.session': case 'telegram.request': case 'telegram.check':
      return network ? 'auth_server' : null;
    case 'auth.provider':
      return network || PROVIDER_DEVICE_CODE.test(code) ? 'auth_provider' : null;
    case 'google.web_button':
      return network ? 'auth_provider' : null;
    case 'yandex.webview':
      return WEBVIEW_NETWORK_CODE.test(code) ? 'auth_provider' : null;
    case 'iap.products': case 'iap.init':
      return network || STORE_DEVICE_CODES.has(code) ? 'store' : null;
    case 'web_payment.start': case 'web_payment.check':
      return network ? 'payment' : null;
    case 'flutter.framework': case 'dart.unhandled': case 'support.send': case 'startup.inbox':
      return network ? 'app' : null;
    default:
      return null;
  }
}

/// null — обычный инцидент: уведомление по прежним правилам.
/// Иначе { kind: 'environment', family } | { kind: 'stale' } | { kind: 'test_device' }.
export function diagnosticSignal(event, now = Date.now()) {
  if (event?.origin !== 'client' || typeof event.operation !== 'string') return null;
  if (PROTECTED_OPERATIONS.has(event.operation)) return null;
  if (typeof event.device === 'string' && TEST_DEVICE.test(event.device)) return { kind: 'test_device' };
  const receivedAt = Number.isFinite(event.receivedAt) ? event.receivedAt : now;
  if (Number.isFinite(event.ts) && receivedAt - event.ts > SIGNAL_STALE_MS) return { kind: 'stale' };
  const family = environmentFamily(event.operation, String(event.code ?? ''));
  return family ? { kind: 'environment', family } : null;
}

export const SIGNAL_REASONS = ['environment', 'stale', 'test_device'];

const emptyFamilyState = () => ({ recent: [], hours: {}, alertedAt: 0 });
const baseCode = code => String(code ?? '').replace(/:\d{1,2}x$/, '');

/// Учитывает сигнал и решает, пора ли сообщить о всплеске. Порог — не меньше
/// SIGNAL_SPIKE_MIN_INSTALLS разных установок за час и в SIGNAL_SPIKE_BASELINE_FACTOR
/// раз больше среднего за предыдущие сутки: с ростом аудитории обычный фон
/// сам поднимает порог. Возвращает новое состояние и описание всплеска или null.
export function trackSignal(previous, event, now) {
  const state = previous && typeof previous === 'object' && Array.isArray(previous.recent)
    ? { recent: previous.recent, hours: { ...previous.hours }, alertedAt: previous.alertedAt || 0 }
    : emptyFamilyState();
  const hour = Math.floor(now / HOUR_MS);
  const installation = /^[a-f0-9]{16}$/.test(event.installation || '') ? event.installation : 'unknown';
  state.recent = state.recent.filter(item => Array.isArray(item) && now - item[0] < HOUR_MS);
  // Одна установка считается один раз за календарный час: повторные нажатия
  // одного человека не должны выглядеть как массовый сбой.
  if (!state.recent.some(item => item[1] === installation && Math.floor(item[0] / HOUR_MS) === hour)) {
    state.hours[hour] = (state.hours[hour] || 0) + 1;
  }
  state.recent.push([now, installation, String(event.operation).slice(0, 40) + ' · ' + baseCode(event.code).slice(0, 40),
    String(event.platform ?? '').toLowerCase().slice(0, 10), String(event.appVersion ?? '').slice(0, 16)]);
  if (state.recent.length > RECENT_LIMIT) state.recent = state.recent.slice(-RECENT_LIMIT);
  for (const key of Object.keys(state.hours)) if (Number(key) < hour - BASELINE_HOURS) delete state.hours[key];
  let previousTotal = 0;
  for (const [key, count] of Object.entries(state.hours)) if (Number(key) < hour) previousTotal += count;
  const usual = previousTotal / BASELINE_HOURS;
  const installs = new Set(state.recent.map(item => item[1])).size;
  const threshold = Math.max(SIGNAL_SPIKE_MIN_INSTALLS, Math.ceil(usual * SIGNAL_SPIKE_BASELINE_FACTOR));
  if (installs < threshold || now - state.alertedAt < SIGNAL_SPIKE_COOLDOWN_MS) return { state, spike: null };
  state.alertedAt = now;
  return { state, spike: { installs, events: state.recent.length, usual, recent: state.recent } };
}

const escape = value => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const PLATFORM_LABELS = { android: 'Android', ios: 'iOS', web: 'Веб' };

function top(items, limit) {
  const counts = new Map();
  for (const item of items) if (item) counts.set(item, (counts.get(item) || 0) + 1);
  return [...counts].sort((a, b) => b[1] - a[1] || String(a[0]).localeCompare(String(b[0]))).slice(0, limit);
}

export function buildSpikeMessage(family, spike) {
  const copy = SIGNAL_FAMILIES[family];
  const usual = spike.usual >= 0.95 ? 'обычно около ' + Math.round(spike.usual) + ' в час' : 'обычно меньше одной в час';
  return [
    '📈 <b>Всплеск: ' + copy.title + '</b>',
    `За последний час — ${spike.installs} разных установок (${usual}), событий: ${spike.events}.`,
    'По одному такие сбои в чат не приходят: обычно это связь или устройство человека. Сейчас их заметно больше обычного.',
    '',
    'Что чаще всего:',
    ...top(spike.recent.map(item => item[2]), 4).map(([label, count]) => '• <code>' + escape(label) + '</code> — ' + count),
    'Платформы: ' + top(spike.recent.map(item => PLATFORM_LABELS[item[3]] || 'не определена'), 3).map(([label, count]) => label + ' — ' + count).join(' · '),
    'Версии: ' + top(spike.recent.map(item => item[4] || 'не определена'), 3).map(([label, count]) => escape(label) + ' — ' + count).join(' · '),
    '',
    '→ ' + copy.hint,
    'Все строки: /export_day. Следующее сообщение об этом всплеске — не раньше чем через 3 часа.',
  ].join('\n');
}

/// Суточная сводка по записям журнала, которые не приходили в чат отдельно.
/// null — таких записей не было, сообщение не нужно.
export function buildSignalDigest(records, now = Date.now()) {
  const quiet = records.filter(record => !record.sent && SIGNAL_REASONS.includes(record.notificationReason));
  if (!quiet.length) return null;
  const installs = items => new Set(items.map(record => record.installation).filter(Boolean)).size;
  const lines = [];
  for (const [family, copy] of Object.entries(SIGNAL_FAMILIES)) {
    const items = quiet.filter(record => record.notificationReason === 'environment'
      && diagnosticSignal({ ...record, origin: 'client', ts: now, receivedAt: now, device: '' }, now)?.family === family);
    if (items.length) lines.push(`• ${copy.line} — ${items.length} (установок: ${installs(items)})`);
  }
  const stale = quiet.filter(record => record.notificationReason === 'stale').length;
  if (stale) lines.push('• Пришли с опозданием больше суток — ' + stale);
  const testDevices = quiet.filter(record => record.notificationReason === 'test_device').length;
  if (testDevices) lines.push('• Эмуляторы и тестовые устройства — ' + testDevices);
  return [
    '🗂 <b>Фоновые сбои за сутки — ' + quiet.length + '</b>',
    'В чат по отдельности не приходили: причина — связь или устройство человека. Затронуто установок: ' + installs(quiet) + '.',
    '',
    ...lines,
    '',
    'Чаще всего: ' + top(quiet.map(record => record.operation + ' · ' + baseCode(record.code)), 3)
      .map(([label, count]) => '<code>' + escape(label) + '</code> — ' + count).join('; '),
    'Ошибки, которые можем исправить мы, и всплески приходят сразу отдельными сообщениями. Все строки: /export_day',
  ].join('\n');
}
