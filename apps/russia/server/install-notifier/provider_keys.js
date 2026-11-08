import { createRemoteJWKSet, customFetch, jwksCache, jwtVerify } from 'jose';

const ENDPOINTS = Object.freeze({
  apple: 'https://appleid.apple.com/auth/keys',
  google: 'https://www.googleapis.com/oauth2/v3/certs',
});
const MAX_AGE = 600000;
const MAX_BYTES = 65536;
const invalidKeys = () => Object.assign(new Error('Invalid provider keys'), { code: 'ERR_JWKS_INVALID' });
const timedOut = () => new DOMException('Provider keys timed out', 'TimeoutError');

async function bounded(promise, milliseconds) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(timedOut()), milliseconds);
    })]);
  } finally { clearTimeout(timer); }
}

// The cache contains public signing keys only, never credentials or account data.
// Copy the fields needed by jose and reject private, malformed or unrelated keys.
function publicKeys(value) {
  if (!value || !Array.isArray(value.keys) || !value.keys.length || value.keys.length > 20) throw invalidKeys();
  const keys = value.keys.map(key => {
    if (!key || key.kty !== 'RSA' || ['d', 'p', 'q', 'dp', 'dq', 'qi', 'oth'].some(name => Object.hasOwn(key, name))
        || typeof key.n !== 'string' || !/^[A-Za-z0-9_-]{256,2048}$/.test(key.n)
        || typeof key.e !== 'string' || !/^[A-Za-z0-9_-]{1,16}$/.test(key.e)
        || typeof key.kid !== 'string' || !key.kid.length || key.kid.length > 200
        || (key.alg !== undefined && key.alg !== 'RS256') || (key.use !== undefined && key.use !== 'sig')
        || (key.key_ops !== undefined && (!Array.isArray(key.key_ops) || key.key_ops.length !== 1 || key.key_ops[0] !== 'verify'))) throw invalidKeys();
    return { kty: 'RSA', n: key.n, e: key.e, kid: key.kid,
      ...(key.alg === undefined ? {} : { alg: key.alg }),
      ...(key.use === undefined ? {} : { use: key.use }),
      ...(key.key_ops === undefined ? {} : { key_ops: ['verify'] }) };
  });
  const result = { keys };
  if (JSON.stringify(result).length > MAX_BYTES) throw invalidKeys();
  return result;
}

function freshSnapshot(value, now) {
  if (!value || !Number.isSafeInteger(value.uat) || value.uat < 0 || value.uat > now || now - value.uat >= MAX_AGE) return null;
  try { return { uat: value.uat, jwks: publicKeys(value.jwks) }; } catch { return null; }
}

function httpFailure(response) {
  const value = response.headers.get('retry-after');
  const seconds = /^\d+$/.test(value || '') ? Number(value)
    : value ? Math.ceil((Date.parse(value) - Date.now()) / 1000) : 1;
  return Object.assign(new Error('Provider keys unavailable'), {
    authTemporary: true, authReason: 'jwks_status_' + response.status,
    authRetryAfter: Number.isSafeInteger(seconds) && seconds >= 0 ? seconds : 1,
  });
}

export function createProviderKeyService({
  fetchImpl = (url, options) => fetch(url, options), now = () => Date.now(),
  timeoutDuration = 2500, cacheTimeout = 500, refreshCacheTimeout = 5000,
} = {}) {
  // Only JSON snapshots survive requests. Network promises/resolvers are local
  // to each invocation because Cloudflare I/O belongs to its creating request.
  const snapshots = new Map();
  const keyFor = provider => 'auth_jwks:v1:' + provider;
  const endpoint = provider => {
    if (!Object.hasOwn(ENDPOINTS, provider)) throw new TypeError('Unknown identity provider');
    return ENDPOINTS[provider];
  };
  async function load(env, provider) {
    const memory = freshSnapshot(snapshots.get(provider), now());
    if (memory) return memory;
    snapshots.delete(provider);
    try {
      if (typeof env.INSTALLS?.get !== 'function') return null;
      const raw = await bounded(Promise.resolve().then(() => env.INSTALLS.get(keyFor(provider))), cacheTimeout);
      if (typeof raw !== 'string' || raw.length > MAX_BYTES) return null;
      const cached = freshSnapshot(JSON.parse(raw), now());
      if (cached) snapshots.set(provider, cached);
      return cached;
    } catch { return null; }
  }
  async function persist(env, provider, value, budget = cacheTimeout) {
    const snapshot = freshSnapshot(value, now());
    if (!snapshot) return false;
    snapshots.set(provider, snapshot);
    try {
      if (typeof env.INSTALLS?.put !== 'function') return false;
      await bounded(Promise.resolve().then(() => env.INSTALLS.put(keyFor(provider), JSON.stringify(snapshot))), budget);
      return true;
    } catch { return false; }
  }
  async function origin(provider, options) {
    const url = endpoint(provider);
    return bounded((async () => {
      const response = await fetchImpl(url, { ...options, method: 'GET', redirect: 'manual' });
      if (response.status !== 200) throw httpFailure(response);
      const raw = await response.text();
      if (raw.length > MAX_BYTES) throw invalidKeys();
      let parsed;
      try { parsed = JSON.parse(raw); } catch { throw invalidKeys(); }
      return publicKeys(parsed);
    })(), timeoutDuration);
  }
  async function verifyProviderJwt(provider, credential, env, options) {
    endpoint(provider);
    const cache = await load(env, provider) || {};
    const initialUat = cache.uat;
    const keys = createRemoteJWKSet(new URL(endpoint(provider)), {
      timeoutDuration, cacheMaxAge: MAX_AGE, [jwksCache]: cache,
      [customFetch]: async (url, fetchOptions) => {
        if (url !== endpoint(provider)) throw invalidKeys();
        return Response.json(await origin(provider, fetchOptions));
      },
    });
    try {
      try { return await jwtVerify(credential, keys, options); }
      catch (error) {
        if (error?.code !== 'ERR_JWKS_TIMEOUT') throw error;
        return await jwtVerify(credential, keys, options);
      }
    } finally {
      if (cache.uat !== initialUat) await persist(env, provider, cache);
    }
  }
  async function refreshProviderKeyCaches(env) {
    return Object.fromEntries(await Promise.all(Object.keys(ENDPOINTS).map(async provider => {
      try {
        const jwks = await origin(provider, { signal: AbortSignal.timeout(timeoutDuration) });
        const saved = await persist(env, provider, { uat: now(), jwks }, refreshCacheTimeout);
        return [provider, { ok: saved, code: saved ? 'updated' : 'cache_write_failed' }];
      } catch (error) {
        const code = error?.name === 'TimeoutError' || error?.name === 'AbortError' ? 'jwks_timeout'
          : error?.code === 'ERR_JWKS_INVALID' ? 'jwks_invalid'
          : error?.authTemporary === true ? 'jwks_http' : 'jwks_unavailable';
        return [provider, { ok: false, code }];
      }
    })));
  }
  return { verifyProviderJwt, refreshProviderKeyCaches };
}

const service = createProviderKeyService();
export const verifyProviderJwt = (...args) => service.verifyProviderJwt(...args);
export const refreshProviderKeyCaches = (...args) => service.refreshProviderKeyCaches(...args);
