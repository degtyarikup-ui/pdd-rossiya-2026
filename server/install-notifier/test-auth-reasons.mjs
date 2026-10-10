// Причина отказа входа в журнале и в уведомлении: только техническая метка,
// без токенов и текста ошибок; ответ клиенту не меняется.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleAuth, credentialReason } from './user_auth.js';

const env = () => ({ INSTALLS: { get: async () => null, put: async () => {} }, SHARED_SECRET: 'test-key', SESSION_SECRET: 'session-test-secret' });
const request = body => new Request('https://app.test/api/auth/session', {
  method: 'POST', headers: { 'content-type': 'application/json', 'x-install-secret': 'test-key' }, body: JSON.stringify(body),
});

test('метка причины берётся из кода ошибки проверки и не содержит текста', () => {
  const claim = Object.assign(new Error('unexpected "aud" claim value SECRET-TOKEN'), { code: 'ERR_JWT_CLAIM_VALIDATION_FAILED', claim: 'aud' });
  assert.equal(credentialReason(claim), 'ERR_JWT_CLAIM_VALIDATION_FAILED:aud');
  assert.equal(credentialReason(new Error('SECRET-TOKEN')), null);
  assert.equal(credentialReason({ authReason: 'yandex "x" 403' }), 'yandexx403');
  assert.equal(credentialReason(null), null);
});

test('отказ проверки попадает в журнал и в уведомление с меткой, ответ прежний', async () => {
  const logs = [], notified = [], original = console.log;
  console.log = text => logs.push(JSON.parse(text));
  try {
    const verify = async () => { throw Object.assign(new Error('bad aud SECRET-TOKEN'), { code: 'ERR_JWT_CLAIM_VALIDATION_FAILED', claim: 'aud' }); };
    const response = await handleAuth(request({ provider: 'apple', credential: 'SECRET-TOKEN' }), env(), verify, e => notified.push(e));
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: 'invalid credentials' });
    assert.equal(logs.at(-1).outcome, 'credential_rejected');
    assert.equal(logs.at(-1).reason, 'ERR_JWT_CLAIM_VALIDATION_FAILED:aud');
    assert.equal(notified.at(-1).code, 'credential_rejected:ERR_JWT_CLAIM_VALIDATION_FAILED:aud');
    assert.equal(JSON.stringify([logs, notified]).includes('SECRET-TOKEN'), false);
  } finally { console.log = original; }
});

test('статус ответа Яндекса (настоящая проверка, сеть подменена) попадает в метку', async () => {
  const logs = [], original = console.log, realFetch = globalThis.fetch;
  console.log = text => logs.push(JSON.parse(text));
  globalThis.fetch = async () => new Response('{"error":"invalid_token"}', { status: 403 });
  try {
    const response = await handleAuth(request({ provider: 'yandex', credential: 'SECRET-YA-TOKEN' }), env());
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: 'invalid credentials' });
    assert.equal(logs.at(-1).outcome, 'credential_rejected');
    assert.equal(logs.at(-1).reason, 'yandex_status_403');
    assert.equal(JSON.stringify(logs).includes('SECRET-YA-TOKEN'), false);
  } finally { console.log = original; globalThis.fetch = realFetch; }
});

test('успешный и прежние исходы без метки причины', async () => {
  const logs = [], original = console.log;
  console.log = text => logs.push(JSON.parse(text));
  try {
    await handleAuth(request({ provider: 'apple', credential: 'x' }), env(), async () => { throw new Error('wrong client'); });
    assert.equal(logs.at(-1).outcome, 'oauth_client_rejected');
    assert.equal('reason' in logs.at(-1), false);
  } finally { console.log = original; }
});

test('текст причины в уведомлении подбирается по базовому коду, метка остаётся в коде', async () => {
  const { incidentCopy } = await import('./incident_copy.js');
  const copy = incidentCopy({ origin: 'server', category: 'auth', operation: 'auth.session', code: 'credential_rejected:yandex_status_403', status: 401 });
  assert.equal(copy.reason, 'Сервис авторизации отклонил подтверждение входа.');
  const plain = incidentCopy({ origin: 'server', category: 'auth', operation: 'auth.session', code: 'credential_rejected', status: 401 });
  assert.equal(plain.reason, copy.reason);
});

test('сообщения о сбоях связи и о входе «не сразу» имеют понятный текст', async () => {
  const { incidentCopy } = await import('./incident_copy.js');
  const lost = incidentCopy({ origin: 'client', category: 'auth', operation: 'auth.provider', code: 'timeout:3x' });
  assert.match(lost.reason, /Ответ не получен/);
  const recovered = incidentCopy({ origin: 'client', category: 'auth', operation: 'auth.recovered', code: 'fallback_ok:2x' });
  assert.equal(recovered.title, 'Вход удался не сразу');
  assert.match(recovered.reason, /запасной адрес/);
  const retry = incidentCopy({ origin: 'client', category: 'auth', operation: 'auth.recovered', code: 'retry_ok:2x' });
  assert.match(retry.reason, /повтор/);
});
