// Сообщения об ошибках в Telegram: срочность, «что делать» и разбор причин.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { incidentGuide } from './incident_copy.js';
import { buildIncidentMessage } from './diagnostics.js';

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
  assert.match(text, /<b>Что делать:<\/b>/);
  assert.match(text, /Страна по IP:<\/b> BY/);
  assert.match(text, /Анна &lt;b&gt;/);
  assert.ok(text.indexOf('Что делать:') < text.indexOf('Пользователь:'));
  assert.ok(text.indexOf('Пользователь:') < text.indexOf('Для диагностики:'));
  // Самый длинный вариант: максимум советов и длинные данные пользователя.
  const longest = buildIncidentMessage({ ...base, userName: '&'.repeat(120), userEmail: '&'.repeat(160), device: '&'.repeat(100), userId: '&'.repeat(200), country: 'BY', platform: 'android', appVersion: '2.2.3+59', store: 'rustore', installation: 'a'.repeat(16), diagnosticId: 'a'.repeat(8) + '-' + 'a'.repeat(4) + '-' + 'a'.repeat(4) + '-' + 'a'.repeat(4) + '-' + 'a'.repeat(12), category: 'purchase', operation: 'premium.verify', code: 'purchase_belongs_to_another_account', status: 403 }, 99, 99);
  assert.ok(longest.length < 4096, 'длина ' + longest.length);
});
