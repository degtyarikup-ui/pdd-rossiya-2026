// Сообщения об ошибках в Telegram: срочность, «что делать» и разбор причин.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { incidentCopy, incidentGuide, platformLabel } from './incident_copy.js';
import { buildIncidentMessage, errorCode, reportIncident } from './diagnostics.js';

const base = { ts: Date.UTC(2026, 9, 10, 12), origin: 'client', category: 'auth', operation: 'auth.provider', code: 'timeout', userId: 'google_1', userName: 'Анна', userEmail: 'a@b.ru' };
const guide = overrides => incidentGuide({ ...base, ...overrides });

test('срочность: деньги и доступ — красным, вход — оранжевым, фон — жёлтым, успех — зелёным', () => {
  assert.equal(guide({ category: 'purchase', operation: 'premium.verify', code: 'store_verification_unavailable' }).level, 'critical');
  assert.equal(guide({ category: 'purchase', operation: 'api.pay.platega.callback', code: 'operation_failed' }).level, 'critical');
  assert.equal(guide({ operation: 'auth.session', code: 'credential_rejected' }).level, 'high');
  assert.equal(guide({ category: 'purchase', operation: 'iap.products', code: 'sdk_error' }).level, 'high');
  assert.equal(guide({ category: 'infrastructure', operation: 'analytics.flush', code: 'storage_quota' }).level, 'low');
  assert.equal(guide({ operation: 'auth.recovered', code: 'fallback_ok:2x' }).level, 'info');
  // Не настроенный секрет блокирует всех — срочно, чем бы ни была операция.
  assert.equal(guide({ origin: 'server', operation: 'auth.session', code: 'session_secret_not_configured' }).level, 'critical');
});

test('метки причины входа расшифрованы и ведут к действию', () => {
  const aud = guide({ origin: 'server', operation: 'auth.session', code: 'credential_rejected:ERR_JWT_CLAIM_VALIDATION_FAILED:aud', status: 401 });
  assert.match(aud.what, /другого приложения/);
  assert.match(aud.steps.join(' '), /GOOGLE_CLIENT_IDS/);
  const yandex = guide({ origin: 'server', operation: 'auth.session', code: 'credential_rejected:yandex_status_403' });
  assert.match(yandex.what, /Яндекс отклонил токен входа \(HTTP 403\)/);
  const google = guide({ origin: 'server', operation: 'auth.session', code: 'credential_rejected:google_tokeninfo_400' });
  assert.match(google.what, /HTTP 400/);
  const signIn = guide({ operation: 'auth.provider', code: 'sign_in_failed:10', store: 'rustore' });
  assert.match(signIn.what, /подпись/);
  assert.match(signIn.steps.join(' '), /SHA-1/);
});

test('сбой связи показывает число попыток, успешный повтор — тоже', () => {
  assert.match(guide({ code: 'timeout:3x' }).what, /Попыток входа: 3/);
  assert.match(guide({ operation: 'auth.recovered', code: 'fallback_ok:2x' }).what, /Попыток до успеха: 2/);
  assert.match(guide({ code: 'timeout:3x' }).steps.join(' '), /другую сеть/);
});

test('покупки: у критичных сбоев есть путь «выдать Premium вручную», у StoreKit — подсказка про App Store', () => {
  const verify = guide({ category: 'purchase', operation: 'premium.verify', code: 'store_verification_unavailable' });
  assert.match(verify.steps.join(' '), /Выдать Premium/);
  const store = guide({ category: 'purchase', operation: 'iap.products', code: 'storekit_getproductrequest_platform_exception' });
  assert.match(store.steps.join(' '), /App Store/);
  const another = guide({ category: 'purchase', operation: 'api.user.purchase', code: 'purchase_belongs_to_another_account' });
  assert.match(another.steps.join(' '), /тем аккаунтом/);
});

test('неизвестные операции и коды не ломают сообщение и не дают выдуманных советов', () => {
  const unknown = guide({ operation: 'new.unknown', code: 'sdk_error' });
  assert.deepEqual(unknown.steps, []);
  const weird = guide({ operation: 'constructor', code: '__proto__' });
  assert.deepEqual(weird.steps, []);
  assert.ok(buildIncidentMessage({ ...base, operation: 'constructor', code: '__proto__' }).length > 0);
});

test('сообщение: уровень, «Что делать», страна; имена экранируются; влезает в Telegram', () => {
  const text = buildIncidentMessage({ ...base, userName: 'Анна <b>', country: 'BY', platform: 'ios', appVersion: '2.2.3+59', device: 'iPhone14,5', code: 'timeout:3x' });
  assert.match(text, /🟠 <b>Не удалось войти в аккаунт<\/b>/);
  assert.match(text, /→ /);
  assert.match(text, / BY/);
  assert.match(text, /Анна &lt;b&gt;/);
  assert.ok(text.indexOf('→ ') < text.indexOf('👤'));
  // Самый длинный вариант: максимум советов и длинные данные пользователя.
  const longest = buildIncidentMessage({ ...base, userName: '&'.repeat(120), userEmail: '&'.repeat(160), device: '&'.repeat(100), userId: '&'.repeat(200), country: 'BY', platform: 'android', appVersion: '2.2.3+59', store: 'rustore', installation: 'a'.repeat(16), diagnosticId: 'a'.repeat(8) + '-' + 'a'.repeat(4) + '-' + 'a'.repeat(4) + '-' + 'a'.repeat(4) + '-' + 'a'.repeat(12), category: 'purchase', operation: 'premium.verify', code: 'purchase_belongs_to_another_account', status: 403 }, 99, 99);
  assert.ok(longest.length < 4096, 'длина ' + longest.length);
});

test('платформа приходит из приложения именем enum («iOS», «macOS»), а не строчными буквами', () => {
  assert.equal(platformLabel('iOS'), 'iOS');
  assert.equal(platformLabel('macOS'), 'macOS');
  assert.equal(platformLabel('android'), 'Android');
  assert.equal(platformLabel('plan9'), 'Не определена');
  assert.equal(platformLabel(undefined), 'Не определена');
  assert.match(buildIncidentMessage({ ...base, platform: 'iOS' }), /📱 iOS/);
});

test('пустой ответ магазина объясняется понятной причиной, а не «Точная причина не определена»', () => {
  const copy = incidentCopy({ ...base, category: 'purchase', operation: 'iap.products', code: 'products_not_found' });
  assert.match(copy.reason, /не вернул наш тариф Premium/);
  assert.match(incidentCopy({ ...base, category: 'purchase', operation: 'iap.products', code: 'channel-error' }).reason, /Модуль покупок/);
});

test('частичный каталог отличают от полностью недоступного магазина', () => {
  const partial = { ...base, category: 'purchase', operation: 'iap.products', code: 'products_incomplete', context: { phase: 'paywall', requestedCount: 2, returnedCount: 1, missingCount: 1 } };
  const copy = incidentCopy(partial);
  assert.equal(copy.title, 'Не все тарифы Premium загрузились');
  assert.match(copy.reason, /только часть тарифов/);
  assert.doesNotMatch(copy.reason, /ни одного|не вернул наш тариф|не определена/);
  assert.equal(incidentGuide(partial).level, 'high');
  assert.match(incidentGuide(partial).steps.join(' '), /базовый план Google Play/);
  const message = buildIncidentMessage(partial);
  assert.match(message, /запрошено 2, получено 1, не найдено 1/);
  assert.match(message, /Не все тарифы Premium загрузились/);
});

test('ошибки Durable Object классифицируются по точному сообщению и булевым флагам', () => {
  const timeout = 'Durable Object storage operation exceeded timeout which caused object to be reset.';
  assert.equal(errorCode(new Error(timeout)), 'durable_storage_timeout');
  assert.equal(errorCode({ message: timeout, retryable: true }), 'durable_storage_timeout');
  // Overload must prevent retry guidance even if both platform flags are set.
  assert.equal(errorCode({ message: timeout, retryable: true, overloaded: true }), 'durable_overloaded');
  assert.equal(errorCode({ message: 'private provider response', retryable: true }), 'durable_retryable');
  assert.equal(errorCode({ message: 'quota exceeded', overloaded: true }), 'durable_overloaded');
  assert.equal(errorCode({ message: 'private response', retryable: 'true', overloaded: 1 }), 'operation_failed');
  assert.equal(errorCode({ message: 'Durable Object storage timed out' }), 'operation_failed');
  assert.equal(errorCode({ message: 'object reset because of a timeout' }), 'operation_failed');
  assert.equal(errorCode(undefined), 'operation_failed');
  // Existing generic timeout and KV classifications remain distinct.
  assert.equal(errorCode({ name: 'TimeoutError' }), 'timeout');
  assert.equal(errorCode(new Error('KV put 429')), 'storage_rate_limited');
  assert.equal(errorCode(new Error('KV quota exceeded')), 'storage_quota');
});

test('диагностика Durable Object не называет сбой квотой KV и не предлагает повторно платить', () => {
  for (const code of ['durable_storage_timeout', 'durable_overloaded', 'durable_retryable']) {
    const incident = { ...base, origin: 'server', category: 'purchase', operation: 'api.user.purchase', code };
    const copy = incidentCopy(incident);
    assert.match(copy.reason, /Durable Object/);
    assert.doesNotMatch(copy.reason, /квот|не определена/);
    const advice = incidentGuide(incident);
    assert.equal(advice.level, 'critical');
    assert.match(advice.steps.join(' '), /повторно не платить/);
    assert.match(advice.steps.join(' '), /Выдать Premium/);
  }
  assert.match(guide({ code: 'durable_overloaded' }).steps[0], /не повторяйте запрос немедленно/);
  assert.match(guide({ code: 'durable_retryable' }).steps[0], /только для идемпотентной/);
  assert.match(guide({ code: 'durable_storage_timeout' }).steps[0], /не дневная квота KV/);
});

test('классификация исключения не передаёт произвольное сообщение в инцидент', async () => {
  const events = [];
  const env = { BOT_TOKEN: 'test', CHAT_ID: 'test', TELEGRAM: { idFromName: value => value, get: () => ({ fetch: async (_, init) => {
    events.push(JSON.parse(init.body).incident); return new Response('ok');
  } }) } };
  const error = Object.assign(new Error('private token https://private.test/credential'), { retryable: true });
  assert.equal(await reportIncident(env, { category: 'infrastructure', operation: 'analytics.flush', code: errorCode(error) }), true);
  assert.equal(events[0].code, 'durable_retryable');
  assert.doesNotMatch(JSON.stringify(events[0]), /private|token|credential/);
  assert.doesNotMatch(buildIncidentMessage(events[0]), /private|token|credential/);
});

test('ошибка СБП показывает сумму, тариф, заказ, этап и честное последствие', () => {
  const payment = { orderId: crypto.randomUUID(), txId: crypto.randomUUID(), amountRub: 290, tier: 'threeMonths', method: 'sbp', client: 'android', providerOperation: 'create', providerStatus: 401 };
  const message = buildIncidentMessage({ ...base, origin: 'server', category: 'purchase', operation: 'api.user.pay-intent', code: 'payment_provider_auth', provider: 'platega', payment });
  assert.match(message, /Platega отклонила доступ кассы/);
  assert.match(message, /СБП · 290 ₽ · 3 месяца/);
  assert.match(message, /Оплата из: приложения Android/);
  assert.match(message, /POST \/transaction\/process · HTTP 401/);
  assert.ok(message.includes(payment.orderId)); assert.ok(message.includes(payment.txId));
  assert.match(message, /человек не смог начать оплату/);
  assert.doesNotMatch(message, /Деньги не списаны/i);
  const check = buildIncidentMessage({ ...base, category: 'purchase', operation: 'payment.check', code: 'payment_provider_timeout', payment: { ...payment, providerOperation: 'status', providerStatus: null } });
  assert.match(check, /GET \/transaction\/\{id\}/);
  assert.match(check, /повторно платить не нужно/);
  assert.ok(message.length < 4096);
});

test('контекст оплаты пропускает только безопасные серверные поля', async () => {
  const events = [];
  const env = { BOT_TOKEN: 'test', CHAT_ID: 'test', TELEGRAM: { idFromName: value => value, get: () => ({ fetch: async (_, init) => {
    events.push(JSON.parse(init.body).incident); return new Response('ok');
  } }) } };
  const payment = { orderId: 'https://private.test', txId: '<secret>', tier: 'custom', amountRub: Infinity, method: 'secret', client: 'secret', providerOperation: 'POST /secret', providerStatus: 1000, raw: 'private body' };
  assert.equal(await reportIncident(env, { category: 'purchase', operation: 'api.user.pay-intent', code: 'payment_provider_error', payment }), true);
  assert.deepEqual(events[0].payment, { orderId: null, txId: null, tier: null, amountRub: null, method: null, client: null, providerOperation: null, providerStatus: null });
  assert.doesNotMatch(JSON.stringify(events[0]), /private|secret|Infinity/);
  assert.equal(await reportIncident(env, { origin: 'client', category: 'purchase', operation: 'web_payment.start', code: 'timeout', payment: { tier: 'weekly', amountRub: 99 } }), true);
  assert.equal(events[1].payment, null);
});
