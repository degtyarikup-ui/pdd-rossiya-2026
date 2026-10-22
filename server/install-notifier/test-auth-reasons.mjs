// Причина отказа входа в журнале и в уведомлении: только техническая метка,
// без токенов и текста ошибок; временный сбой отделён от отклонённого credential.
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

test('JWKS timeouts and provider network failures return retryable 503 without accepting credentials', async () => {
  const logs = [], original = console.log;
  console.log = text => logs.push(JSON.parse(text));
  try {
    for (const error of [
      Object.assign(new Error('PRIVATE TOKEN MUST NOT LEAK'), { code: 'ERR_JWKS_TIMEOUT' }),
      new DOMException('PRIVATE TOKEN MUST NOT LEAK', 'TimeoutError'),
      new TypeError('PRIVATE TOKEN MUST NOT LEAK'),
      new SyntaxError('PRIVATE TOKEN MUST NOT LEAK'),
    ]) {
      const response = await handleAuth(request({ provider: 'apple', credential: 'PRIVATE-TOKEN' }), env(), async () => { throw error; });
      assert.equal(response.status, 503);
      assert.equal(response.headers.get('Retry-After'), '1');
      assert.deepEqual(await response.json(), { error: 'provider unavailable' });
      assert.ok(['provider_timeout', 'provider_request_failed'].includes(logs.at(-1).outcome));
    }
    assert.equal(JSON.stringify(logs).includes('PRIVATE'), false);
  } finally { console.log = original; }
});

test('OAuth provider outages are service failures; invalid tokens remain 401 and Retry-After is preserved', async () => {
  const original = globalThis.fetch;
  try {
    for (const provider of ['google', 'yandex']) {
      for (const status of [429, 500, 503]) {
        globalThis.fetch = async () => new Response('{}', { status, headers: { 'Retry-After': '30' } });
        const response = await handleAuth(request({ provider, credential: 'PRIVATE-TOKEN' }), env());
        assert.equal(response.status, 503);
        assert.equal(response.headers.get('Retry-After'), '30');
        assert.deepEqual(await response.json(), { error: 'provider unavailable' });
      }
      for (const status of [400, 401, 403]) {
        globalThis.fetch = async () => new Response('{}', { status });
        const response = await handleAuth(request({ provider, credential: 'PRIVATE-TOKEN' }), env());
        assert.equal(response.status, 401);
        assert.equal(response.headers.has('Retry-After'), false);
        assert.deepEqual(await response.json(), { error: 'invalid credentials' });
      }
    }
  } finally { globalThis.fetch = original; }
});

test('a failing trusted JWKS endpoint is retryable and recovered keys still enforce audience', async () => {
  const { generateKeyPair, exportJWK, SignJWT } = await import('jose');
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const jwk = { ...await exportJWK(publicKey), kid: 'auth-outage-fixture', alg: 'RS256', use: 'sig' };
  const token = await new SignJWT({}).setProtectedHeader({ alg: 'RS256', kid: jwk.kid })
    .setIssuer('https://appleid.apple.com').setAudience('foreign-app').setSubject('fixture')
    .setIssuedAt().setExpirationTime('5m').sign(privateKey);
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async url => { assert.equal(String(url), 'https://appleid.apple.com/auth/keys'); return new Response('{}', { status: 503 }); };
    const unavailable = await handleAuth(request({ provider: 'apple', credential: token }), env());
    assert.equal(unavailable.status, 503);
    globalThis.fetch = async () => Response.json({ keys: [jwk] });
    const rejected = await handleAuth(request({ provider: 'apple', credential: token }), env());
    assert.equal(rejected.status, 401);
    assert.deepEqual(await rejected.json(), { error: 'invalid credentials' });
  } finally { globalThis.fetch = original; }
});
