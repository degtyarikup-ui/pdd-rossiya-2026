import { retainAppleAuthorization } from './apple_account.js';
import { accountRead, accountReadMany, accountWrite } from './account_state.js';
import { createRemoteJWKSet, customFetch, jwtVerify } from 'jose';

// Keep jose's signature, key rotation and claim checks. Its fetch hook only
// distinguishes an unavailable trusted key endpoint from a rejected credential.
async function fetchProviderKeys(url, options) {
  const response = await fetch(url, options);
  if (response.status !== 200) throw providerHttpFailure('jwks_status_', response, true);
  return response;
}
const googleKeys = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'), { [customFetch]: fetchProviderKeys });
const appleKeys = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'), { [customFetch]: fetchProviderKeys });
// Ключи Google и Apple иногда отдаются дольше обычного: один повтор вместо отказа во входе.
async function verifyWithKeys(credential, keys, options) {
  try {
    return await jwtVerify(credential, keys, options);
  } catch (error) {
    if (error?.code !== 'ERR_JWKS_TIMEOUT') throw error;
    return jwtVerify(credential, keys, options);
  }
}
const GOOGLE_CLIENT = '513938972930-3lclc5epsnm12druv86ut2o89pj71cu9.apps.googleusercontent.com,513938972930-a7sh1di6odgf77ijltu31lvpuhijcis1.apps.googleusercontent.com';
const YANDEX_CLIENT = '94aa539db4634e44bf0b209d9a2205d2';
const SESSION_SECONDS = 30 * 86400;
const audiences = (value, fallback) => String(value || fallback).split(',').map(s => s.trim()).filter(Boolean);
const randomToken = () => Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, '0')).join('');
export async function tokenHash(token) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token))), b => b.toString(16).padStart(2, '0')).join('');
}
const reply = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
// Причина отказа для журнала: техническая метка (код ошибки библиотеки или
// статус ответа провайдера), без текста ошибки, токенов и данных пользователя.
const authFailure = (message, authReason) => Object.assign(new Error(message), { authReason });
function providerHttpFailure(prefix, response, keyEndpoint = false) {
  const error = authFailure('provider response rejected', prefix + response.status);
  if (keyEndpoint || response.status === 429 || response.status >= 500) {
    error.authTemporary = true;
    const value = response.headers.get('retry-after');
    const seconds = /^\d+$/.test(value || '') ? Number(value)
      : value ? Math.ceil((Date.parse(value) - Date.now()) / 1000) : 1;
    error.authRetryAfter = Number.isSafeInteger(seconds) && seconds >= 0 ? seconds : 1;
  }
  return error;
}
export function credentialReason(error) {
  const raw = typeof error?.authReason === 'string'
    ? error.authReason
    : [error?.code, error?.claim].filter(value => typeof value === 'string').join(':');
  return raw.replace(/[^A-Za-z0-9_.:-]/g, '').slice(0, 60) || null;
}

// Identity always comes from the provider, never from a client-supplied userId.
export async function verifyIdentity(body, env) {
  const { provider, credential } = body || {};
  if (typeof credential !== 'string' || !credential || credential.length > 16384) throw authFailure('invalid credential', 'credential_format');
  let claims;
  if (provider === 'google' && credential.split('.').length !== 3) {
    // Android and the custom web button use OAuth access tokens. Google
    // validates the token; the configured allowlist includes the web client.
    const info = await fetch('https://oauth2.googleapis.com/tokeninfo?access_token=' + encodeURIComponent(credential), { signal: AbortSignal.timeout(6000) });
    if (!info.ok) throw providerHttpFailure('google_tokeninfo_', info);
    const tok = await info.json();
    const androidClients = audiences(env.GOOGLE_ANDROID_CLIENT_IDS, '');
    const allowed = [...androidClients, ...audiences(env.GOOGLE_CLIENT_IDS, GOOGLE_CLIENT)];
    if (!allowed.includes(tok.aud) && !allowed.includes(tok.azp)) {
      // Client IDs are public; logging them identifies an OAuth client missing from the allowlist.
      console.warn('google access token client rejected', JSON.stringify({ aud: tok.aud || null, azp: tok.azp || null }));
      throw new Error('wrong client');
    }
    if (!tok.sub || !Number.isFinite(Number(tok.expires_in)) || Number(tok.expires_in) <= 0) throw authFailure('invalid credential', 'google_tokeninfo_claims');
    let profile = {};
    try {
      const user = await fetch('https://openidconnect.googleapis.com/v1/userinfo', { headers: { Authorization: 'Bearer ' + credential }, signal: AbortSignal.timeout(4000) });
      if (user.ok) profile = await user.json();
    } catch (_) {}
    if (profile.sub && profile.sub !== tok.sub) throw authFailure('invalid credential', 'google_userinfo_subject');
    claims = { sub: tok.sub, name: profile.name, email: tok.email || profile.email || '',
      email_verified: tok.email_verified === 'true' || profile.email_verified === true, picture: profile.picture };
  } else if (provider === 'google') {
    ({ payload: claims } = await verifyWithKeys(credential, googleKeys, {
      algorithms: ['RS256'], issuer: ['https://accounts.google.com', 'accounts.google.com'],
      audience: audiences(env.GOOGLE_CLIENT_IDS, GOOGLE_CLIENT), requiredClaims: ['sub', 'exp', 'iat'],
    }));
  } else if (provider === 'apple') {
    ({ payload: claims } = await verifyWithKeys(credential, appleKeys, {
      algorithms: ['RS256'], issuer: 'https://appleid.apple.com',
      audience: audiences(env.APPLE_CLIENT_IDS, 'ru.pdd.pddApp,ru.pdd.pddapp.auth'),
      requiredClaims: ['sub', 'exp', 'iat'],
    }));
  } else if (provider === 'yandex') {
    const response = await fetch('https://login.yandex.ru/info?format=json', {
      headers: { Authorization: `OAuth ${credential}` }, signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw providerHttpFailure('yandex_status_', response);
    const info = await response.json();
    if (info.client_id !== (env.YANDEX_CLIENT_ID || YANDEX_CLIENT) || !info.id) throw new Error('wrong client');
    claims = { sub: String(info.id), name: info.real_name || info.display_name,
      email: info.default_email || '', email_verified: true,
      picture: !info.is_avatar_empty && info.default_avatar_id
        ? `https://avatars.yandex.net/get-yapic/${encodeURIComponent(info.default_avatar_id)}/islands-200` : null };
  } else if (provider === 'telegram') {
    const token = env.TELEGRAM_AUTH_BOT_TOKEN || env.BOT_TOKEN;
    if (!token) throw authFailure('bot not configured', 'telegram_bot_unconfigured');
    let data;
    try { data = typeof credential === 'object' ? credential : JSON.parse(credential); } catch {
      data = Object.fromEntries(new URLSearchParams(credential));
    }
    const hash = data?.hash;
    if (!hash || !data?.id || !data?.auth_date) throw authFailure('invalid credential', 'telegram_missing_fields');
    if (Math.abs(Date.now() / 1000 - Number(data.auth_date)) > 86400) throw authFailure('expired credential', 'telegram_expired');
    const checkString = Object.keys(data)
      .filter(k => k !== 'hash')
      .sort()
      .map(k => `${k}=${data[k]}`)
      .join('\n');
    const secretKey = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
    const hmacKey = await crypto.subtle.importKey('raw', secretKey, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const sig = new Uint8Array(await crypto.subtle.sign('HMAC', hmacKey, new TextEncoder().encode(checkString)));
    const calculatedHash = [...sig].map(b => b.toString(16).padStart(2, '0')).join('');
    if (calculatedHash !== hash) throw authFailure('invalid signature', 'telegram_invalid_hash');
    claims = {
      sub: String(data.id),
      name: [data.first_name, data.last_name].filter(Boolean).join(' ') || data.username || 'Пользователь',
      picture: typeof data.photo_url === 'string' && data.photo_url.startsWith('https://') ? data.photo_url : null,
    };
  } else throw new Error('invalid provider');
  if (typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 180) throw authFailure('invalid identity', 'identity_subject');
  return {
    id: `${provider}_${claims.sub}`, provider,
    name: String(claims.name || (provider === 'apple' && body.name) || claims.email?.split('@')[0] || provider).slice(0, 120),
    email: claims.email_verified === true || claims.email_verified === 'true' ? String(claims.email || '') : '',
    avatarUrl: typeof claims.picture === 'string' && claims.picture.startsWith('https://') ? claims.picture : null,
    createdAt: new Date().toISOString(),
  };
}

// v1.<base64url payload>.<hex HMAC-SHA256>; key = SESSION_SECRET (worker
// secret, never shipped in the app). Without the secret no sessions are issued.
const b64url = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const fromB64url = text => Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((text.length + 3) % 4)), c => c.charCodeAt(0));
async function hmacHex(env, data) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.SESSION_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)));
  return [...sig].map(b => b.toString(16).padStart(2, '0')).join('');
}
export async function signSession(env, entry) {
  if (!env.SESSION_SECRET) return null;
  const body = 'v1.' + b64url(new TextEncoder().encode(JSON.stringify({ sessionId: randomToken(), ...entry })));
  return body + '.' + await hmacHex(env, body);
}
async function readSignedSession(env, token) {
  if (!env.SESSION_SECRET) return null;
  const m = /^(v1\.[A-Za-z0-9_-]+)\.([a-f0-9]{64})$/.exec(token);
  if (!m) return null;
  const expected = await hmacHex(env, m[1]);
  let diff = 0; for (let i = 0; i < 64; i++) diff |= expected.charCodeAt(i) ^ m[2].charCodeAt(i);
  if (diff) return null;
  try { return JSON.parse(new TextDecoder().decode(fromB64url(m[1].slice(3)))); } catch { return null; }
}

export async function readSession(request, env) {
  if (!env.INSTALLS) return null;
  const raw = request.headers.get('authorization')?.match(/^Bearer (\S{1,4096})$/)?.[1];
  if (!raw) return null;
  if (raw.startsWith('v1.')) {
    const entry = await readSignedSession(env, raw);
    if (!entry?.user?.id || !Number.isFinite(entry.expiresAt) || entry.expiresAt <= Date.now()) return null;
    const sessionTokenHash = await tokenHash(raw);
    const [generation, revoked] = await accountReadMany(env, entry.user.id, [
      'auth_generation:' + entry.user.id, 'revoked_session:' + entry.user.id + ':' + sessionTokenHash,
    ]);
    if ((generation || '') !== entry.generation) return null;
    if (revoked && Number(revoked) > Date.now()) return null;
    return { ...entry, key: null, sessionTokenHash };
  }
  const token = /^[a-f0-9]{64}$/.test(raw) ? raw : null;
  if (!token) return null;
  const key = 'auth_session:' + await tokenHash(token);
  let entry;
  try { entry = JSON.parse(await env.INSTALLS.get(key)); } catch { return null; }
  if (!entry?.user?.id || !Number.isFinite(entry.expiresAt) || entry.expiresAt <= Date.now()) return null;
  const sessionTokenHash = await tokenHash(raw);
  const [generation, revoked] = await accountReadMany(env, entry.user.id, [
    'auth_generation:' + entry.user.id, 'revoked_session:' + entry.user.id + ':' + sessionTokenHash,
  ]);
  if ((generation || '') !== entry.generation) return null;
  if (revoked && Number(revoked) > Date.now()) return null;
  return { ...entry, key, sessionTokenHash };
}

// Routing is not authorization. Verify the credential before choosing an object,
// then let authorizeUserRequest check revocation INSIDE that same account request.
// This avoids two extra DO invocations before every /api/user/* operation.
export async function sessionAccountId(request, env) {
  if (!env.INSTALLS) return null;
  const raw = request.headers.get('authorization')?.match(/^Bearer (\S{1,4096})$/)?.[1];
  if (!raw) return null;
  let entry;
  if (raw.startsWith('v1.')) entry = await readSignedSession(env, raw);
  else if (/^[a-f0-9]{64}$/.test(raw)) {
    try { entry = JSON.parse(await env.INSTALLS.get('auth_session:' + await tokenHash(raw))); } catch { return null; }
  }
  return entry?.user?.id && Number.isFinite(entry.expiresAt) && entry.expiresAt > Date.now() ? entry.user.id : null;
}

export async function revokeUserSessions(env, userId) {
  await accountWrite(env, userId, 'auth_generation:' + userId, randomToken());
}

export async function handleAuth(request, env, verify = verifyIdentity, onFailure = () => {}) {
  const path = new URL(request.url).pathname;
  if (path === '/api/auth/session' && request.method === 'POST') {
    const started = Date.now();
    const requestId = crypto.randomUUID();
    let provider = 'unknown';
    let metadata = {};
    const finish = (body, status, outcome, reason = null, retryAfter = null) => {
      // Never record credentials, headers, user IDs, names or provider errors.
      console.log(JSON.stringify({ event: 'auth_session', requestId, provider,
        status, outcome, durationMs: Date.now() - started, ...(reason ? { reason } : {}) }));
      if (status >= 400 && env.SHARED_SECRET && request.headers.get('x-install-secret') === env.SHARED_SECRET && provider !== 'unknown') {
        onFailure({ ...metadata, category: 'auth', operation: 'auth.session', code: reason ? `${outcome}:${reason}` : outcome, provider, status, diagnosticId: requestId });
      }
      const response = reply(body, status);
      response.headers.set('x-auth-diagnostic-id', requestId);
      if (retryAfter !== null) response.headers.set('Retry-After', String(retryAfter));
      return response;
    };
    // No legacy or missing-secret bypass for issuing sessions.
    if (!env.SHARED_SECRET || request.headers.get('x-install-secret') !== env.SHARED_SECRET) return finish({ error: 'forbidden' }, 403, 'app_key_rejected');
    let body;
    try { body = await request.json(); } catch { return finish({ error: 'invalid json' }, 400, 'invalid_json'); }
    if (['google', 'yandex', 'apple', 'telegram'].includes(body?.provider)) provider = body.provider;
    metadata = { platform: body?.platform, appVersion: body?.appVersion, device: body?.device };
    if (!env.INSTALLS) return finish({ error: 'unavailable' }, 503, 'storage_not_configured');
    let user;
    try { user = await verify(body, env); } catch (error) {
      const timeout = error?.code === 'ERR_JWKS_TIMEOUT' || error?.name === 'TimeoutError' || error?.name === 'AbortError';
      const requestFailed = error?.name === 'TypeError' || error?.name === 'SyntaxError' || error?.code === 'ERR_JWKS_INVALID';
      const temporary = timeout || requestFailed || error?.authTemporary === true;
      const outcome = error?.message === 'wrong client' ? 'oauth_client_rejected'
        : timeout ? 'provider_timeout'
        : requestFailed || error?.authTemporary === true ? 'provider_request_failed'
        : error?.code === 'ERR_JWT_EXPIRED' ? 'credential_expired'
        : 'credential_rejected';
      // A network outage does not prove that the user's credential is invalid.
      // Return a retryable service failure, while invalid signatures/audiences
      // and expired credentials continue to fail closed with 401.
      if (temporary) return finish({ error: 'provider unavailable' }, 503, outcome, credentialReason(error), error.authRetryAfter ?? 1);
      return finish({ error: 'invalid credentials' }, 401, outcome, credentialReason(error));
    }
    try { await retainAppleAuthorization(env, user, body); }
    catch { return finish({ error: 'provider unavailable' }, 503, 'apple_authorization_unavailable'); }
    const expiresAt = Date.now() + SESSION_SECONDS * 1000;
    try {
      const generation = await accountRead(env, user.id, 'auth_generation:' + user.id) || '';
      // Stateless signed session: issuing it needs no KV write, so sign-in keeps
      // working when the free KV daily write quota is exhausted.
      const token = await signSession(env, { user, expiresAt, generation });
      if (!token) return finish({ error: 'unavailable' }, 503, 'session_secret_not_configured');
      return finish({ ok: true, token, expiresAt: new Date(expiresAt).toISOString(), user }, 200, 'session_issued');
    } catch (error) {
      return finish({ error: 'unavailable' }, 500, 'session_creation_failed');
    }
  }
  if (path === '/api/auth/logout' && request.method === 'POST') {
    const session = await readSession(request, env);
    // Legacy KV sessions are deleted; signed ones simply expire on the client.
    if (session?.key) { try { await env.INSTALLS.delete(session.key); } catch {} }
    if (session?.sessionTokenHash) await accountWrite(env, session.user.id, 'revoked_session:' + session.user.id + ':' + session.sessionTokenHash, String(session.expiresAt), { expiration: Math.ceil(session.expiresAt / 1000) });
    return reply({ ok: true });
  }
  return null;
}

export async function authorizeUserRequest(request, env) {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/api/user/') && url.pathname !== '/api/game/score') return { session: null };
  const session = await readSession(request, env);
  if (!session) return { response: reply({ error: 'authentication required' }, 401) };
  let body = {};
  if (request.method === 'POST') {
    try { body = await request.clone().json(); } catch { return { response: reply({ error: 'invalid json' }, 400) }; }
  }
  for (const id of [body?.id, body?.userId, url.searchParams.get('userId'), url.searchParams.get('id')]) {
    if (id != null && id !== session.user.id) return { response: reply({ error: 'wrong account' }, 403) };
  }
  return { session };
}
