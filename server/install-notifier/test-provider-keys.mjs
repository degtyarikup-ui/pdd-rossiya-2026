import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { createProviderKeyService } from './provider_keys.js';
import { handleAuth } from './user_auth.js';

const pair = await generateKeyPair('RS256');
const other = await generateKeyPair('RS256');
const jwk = { ...await exportJWK(pair.publicKey), kid: 'fixture-key', alg: 'RS256', use: 'sig' };
const otherJwk = { ...await exportJWK(other.publicKey), kid: 'other-key', alg: 'RS256', use: 'sig' };
const options = { algorithms: ['RS256'], issuer: 'https://appleid.apple.com', audience: 'test-client', requiredClaims: ['sub', 'exp', 'iat'] };
const timeout = () => new DOMException('private upstream details', 'TimeoutError');
async function token({ kid = jwk.kid, issuer = options.issuer, audience = options.audience, expires = '5m', key = pair.privateKey } = {}) {
  return new SignJWT({}).setProtectedHeader({ alg: 'RS256', kid }).setIssuer(issuer).setAudience(audience)
    .setSubject('fixture-subject').setIssuedAt().setExpirationTime(expires).sign(key);
}
const validToken = await token();
function fixture(seed) {
  const data = new Map(seed === undefined ? [] : [['auth_jwks:v1:apple', JSON.stringify(seed)]]);
  const reads = [], writes = [];
  const env = { INSTALLS: {
    get: async key => { reads.push(key); return data.get(key) ?? null; },
    put: async (key, value) => { writes.push({ key, value: JSON.parse(value) }); data.set(key, value); },
  } };
  return { env, data, reads, writes };
}
const seed = (age = 0) => ({ uat: Date.now() - age, jwks: { keys: [jwk] } });

test('a cold service uses the fresh shared public keys during an origin outage without changing uat', async () => {
  const cached = seed(60000), { env, reads, writes } = fixture(cached);
  let fetches = 0;
  const service = createProviderKeyService({ fetchImpl: async () => { fetches++; throw timeout(); } });
  for (let i = 0; i < 2; i++) assert.equal((await service.verifyProviderJwt('apple', validToken, env, options)).payload.sub, 'fixture-subject');
  assert.equal(fetches, 0);
  assert.deepEqual(reads, ['auth_jwks:v1:apple']);
  assert.deepEqual(writes, []);
  assert.equal(cached.uat, JSON.parse(await env.INSTALLS.get('auth_jwks:v1:apple')).uat);
});

test('freshness is strict at ten minutes and rejects future or malformed cache snapshots', async t => {
  const stamp = Date.now();
  t.mock.method(Date, 'now', () => stamp);
  for (const [cached, accepted] of [
    [{ uat: stamp - 599999, jwks: { keys: [jwk] } }, true],
    [{ uat: stamp - 600000, jwks: { keys: [jwk] } }, false],
    [{ uat: stamp + 1, jwks: { keys: [jwk] } }, false],
    [{ uat: -1, jwks: { keys: [jwk] } }, false],
    [{ uat: String(stamp), jwks: { keys: [jwk] } }, false],
    [{ uat: Infinity, jwks: { keys: [jwk] } }, false],
    [{ uat: NaN, jwks: { keys: [jwk] } }, false],
    [{ uat: stamp, jwks: { keys: [] } }, false],
    [{ uat: stamp, jwks: { keys: [{ ...jwk, d: 'private' }] } }, false],
    [{ uat: stamp, jwks: { keys: [{ ...jwk, kty: 'oct', k: 'private' }] } }, false],
    [{ uat: stamp, jwks: { keys: [{ ...jwk, n: 'invalid' }] } }, false],
  ]) {
    const { env, writes } = fixture(cached);
    let fetches = 0;
    const service = createProviderKeyService({ now: () => stamp, fetchImpl: async () => { fetches++; throw timeout(); } });
    if (accepted) await service.verifyProviderJwt('apple', validToken, env, options);
    else await assert.rejects(service.verifyProviderJwt('apple', validToken, env, options), { code: 'ERR_JWKS_TIMEOUT' });
    assert.equal(fetches, accepted ? 0 : 2);
    assert.equal(writes.length, 0);
  }
});

test('invalid JSON cache falls back to the pinned origin and stores public keys only', async () => {
  const { env, data, writes } = fixture();
  data.set('auth_jwks:v1:apple', '{broken');
  const service = createProviderKeyService({ fetchImpl: async (url, init) => {
    assert.equal(url, 'https://appleid.apple.com/auth/keys');
    assert.equal(init.redirect, 'manual');
    assert.equal(init.method, 'GET');
    return Response.json({ keys: [jwk], ignored: 'private response field' });
  } });
  await service.verifyProviderJwt('apple', validToken, env, options);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].key, 'auth_jwks:v1:apple');
  assert.deepEqual(writes[0].value.jwks, { keys: [jwk] });
  assert.ok(writes[0].value.uat <= Date.now());
  assert.ok(!JSON.stringify(writes).includes(validToken));
  assert.ok(!JSON.stringify(writes).includes('fixture-subject'));
});

test('unknown kid preserves the standard cooldown and refreshes from origin after thirty seconds', async () => {
  const rotated = { ...jwk, kid: 'rotated-key' }, credential = await token({ kid: rotated.kid });
  for (const age of [0, 31000]) {
    const { env, writes } = fixture(seed(age));
    let fetches = 0;
    const service = createProviderKeyService({ fetchImpl: async () => { fetches++; return Response.json({ keys: [rotated] }); } });
    if (age === 0) await assert.rejects(service.verifyProviderJwt('apple', credential, env, options), { code: 'ERR_JWKS_NO_MATCHING_KEY' });
    else assert.equal((await service.verifyProviderJwt('apple', credential, env, options)).protectedHeader.kid, rotated.kid);
    assert.equal(fetches, age === 0 ? 0 : 1);
    assert.equal(writes.length, fetches);
  }
});

test('cached keys still reject wrong audience, issuer, expiry and forged signatures with HTTP 401', async () => {
  const { env } = fixture(seed());
  const fixtureSecret = crypto.randomUUID();
  Object.assign(env, { SHARED_SECRET: fixtureSecret, SESSION_SECRET: crypto.randomUUID() });
  const service = createProviderKeyService({ fetchImpl: async () => { throw new Error('must not fetch'); } });
  const credentials = [
    await token({ audience: 'other-client' }), await token({ issuer: 'https://untrusted.invalid' }),
    await token({ expires: '-1s' }), await token({ key: other.privateKey }),
  ];
  for (const credential of credentials) {
    const request = new Request('https://fixture.invalid/api/auth/session', { method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-secret': fixtureSecret }, body: JSON.stringify({ provider: 'apple', credential }) });
    const response = await handleAuth(request, env, body => service.verifyProviderJwt('apple', body.credential, env, options));
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: 'invalid credentials' });
  }
});

test('two origin timeouts have a bounded budget and no stale-auth fallback', async () => {
  for (const stalled of ['headers', 'body']) {
    const { env } = fixture(seed(600001));
    let attempts = 0;
    const service = createProviderKeyService({ timeoutDuration: 20, fetchImpl: async () => {
      attempts++;
      return stalled === 'headers' ? new Promise(() => {}) : new Response(new ReadableStream({ start() {} }));
    } });
    const start = Date.now();
    await assert.rejects(service.verifyProviderJwt('apple', validToken, env, options), { code: 'ERR_JWKS_TIMEOUT' });
    assert.equal(attempts, 2);
    assert.ok(Date.now() - start < 500, stalled + ' must remain bounded even if the origin ignores abort');
  }
});

test('KV read/write failures or hangs never discard a valid origin verification', async () => {
  for (const operation of ['get', 'put']) for (const failure of ['reject', 'hang', 'missing']) {
    const { env } = fixture();
    if (failure === 'missing') delete env.INSTALLS[operation];
    else env.INSTALLS[operation] = async () => {
      if (failure === 'reject') throw new Error('private KV failure');
      return new Promise(() => {});
    };
    const service = createProviderKeyService({ cacheTimeout: 15, fetchImpl: async () => Response.json({ keys: [jwk] }) });
    const start = Date.now();
    assert.equal((await service.verifyProviderJwt('apple', validToken, env, options)).payload.sub, 'fixture-subject');
    assert.ok(Date.now() - start < 500);
  }
});

test('refresh isolates providers, follows no redirects and returns only fixed outcomes', async () => {
  const { env, writes } = fixture();
  const urls = [];
  const service = createProviderKeyService({ fetchImpl: async (url, init) => {
    urls.push(url); assert.equal(init.redirect, 'manual');
    return Response.json({ keys: [url.includes('appleid') ? jwk : otherJwk] });
  } });
  assert.deepEqual(await service.refreshProviderKeyCaches(env), { apple: { ok: true, code: 'updated' }, google: { ok: true, code: 'updated' } });
  assert.deepEqual(urls.sort(), ['https://appleid.apple.com/auth/keys', 'https://www.googleapis.com/oauth2/v3/certs'].sort());
  assert.deepEqual(writes.map(item => item.key).sort(), ['auth_jwks:v1:apple', 'auth_jwks:v1:google']);
  const failed = createProviderKeyService({ fetchImpl: async url => url.includes('appleid')
    ? new Response('private location', { status: 302, headers: { Location: 'https://untrusted.invalid' } }) : Response.json({ keys: [] }) });
  assert.deepEqual(await failed.refreshProviderKeyCaches(env), { apple: { ok: false, code: 'jwks_http' }, google: { ok: false, code: 'jwks_invalid' } });
});
