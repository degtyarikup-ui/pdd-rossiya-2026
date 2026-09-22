import { createRemoteJWKSet, jwtVerify } from 'jose';

const googleKeys = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));
const appleKeys = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
const GOOGLE_CLIENT = '513938972930-3lclc5epsnm12druv86ut2o89pj71cu9.apps.googleusercontent.com';
const YANDEX_CLIENT = '94aa539db4634e44bf0b209d9a2205d2';
const SESSION_SECONDS = 30 * 86400;
const audiences = (value, fallback) => String(value || fallback).split(',').map(s => s.trim()).filter(Boolean);
const randomToken = () => Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, '0')).join('');
export async function tokenHash(token) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token))), b => b.toString(16).padStart(2, '0')).join('');
}
const reply = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });

// Identity always comes from the provider, never from a client-supplied userId.
export async function verifyIdentity(body, env) {
  const { provider, credential } = body || {};
  if (typeof credential !== 'string' || !credential || credential.length > 16384) throw new Error('invalid credential');
  let claims;
  if (provider === 'google' && credential.split('.').length !== 3) {
    // Android: an OAuth access token (no Web client is configured for the app,
    // so there is no ID token). Google itself validates it; the audience must
    // be one of our Android client IDs once GOOGLE_ANDROID_CLIENT_IDS is set.
    const info = await fetch('https://oauth2.googleapis.com/tokeninfo?access_token=' + encodeURIComponent(credential), { signal: AbortSignal.timeout(8000) });
    if (!info.ok) throw new Error('invalid credential');
    const tok = await info.json();
    const allowed = audiences(env.GOOGLE_ANDROID_CLIENT_IDS, '');
    console.log('google access token aud', tok.aud || tok.azp);
    if (allowed.length && !allowed.includes(tok.aud) && !allowed.includes(tok.azp)) throw new Error('wrong client');
    if (!tok.sub || Number(tok.expires_in) <= 0) throw new Error('invalid credential');
    const user = await fetch('https://openidconnect.googleapis.com/v1/userinfo', { headers: { Authorization: 'Bearer ' + credential }, signal: AbortSignal.timeout(8000) });
    const profile = user.ok ? await user.json() : {};
    if (profile.sub && profile.sub !== tok.sub) throw new Error('invalid credential');
    claims = { sub: tok.sub, name: profile.name, email: tok.email || profile.email || '',
      email_verified: tok.email_verified === 'true' || profile.email_verified === true, picture: profile.picture };
  } else if (provider === 'google') {
    ({ payload: claims } = await jwtVerify(credential, googleKeys, {
      algorithms: ['RS256'], issuer: ['https://accounts.google.com', 'accounts.google.com'],
      audience: audiences(env.GOOGLE_CLIENT_IDS, GOOGLE_CLIENT), requiredClaims: ['sub', 'exp', 'iat'],
    }));
  } else if (provider === 'apple') {
    ({ payload: claims } = await jwtVerify(credential, appleKeys, {
      algorithms: ['RS256'], issuer: 'https://appleid.apple.com',
      audience: audiences(env.APPLE_CLIENT_IDS, 'ru.pdd.pddApp,ru.pdd.pddapp.auth'),
      requiredClaims: ['sub', 'exp', 'iat'],
    }));
  } else if (provider === 'yandex') {
    const response = await fetch('https://login.yandex.ru/info?format=json', {
      headers: { Authorization: `OAuth ${credential}` }, signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new Error('invalid credential');
    const info = await response.json();
    if (info.client_id !== (env.YANDEX_CLIENT_ID || YANDEX_CLIENT) || !info.id) throw new Error('wrong client');
    claims = { sub: String(info.id), name: info.real_name || info.display_name,
      email: info.default_email || '', email_verified: true,
      picture: !info.is_avatar_empty && info.default_avatar_id
        ? `https://avatars.yandex.net/get-yapic/${encodeURIComponent(info.default_avatar_id)}/islands-200` : null };
  } else throw new Error('invalid provider');
  if (typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 180) throw new Error('invalid identity');
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
  const body = 'v1.' + b64url(new TextEncoder().encode(JSON.stringify(entry)));
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
    const generation = await env.INSTALLS.get('auth_generation:' + entry.user.id);
    if ((generation || '') !== entry.generation) return null;
    return { ...entry, key: null };
  }
  const token = /^[a-f0-9]{64}$/.test(raw) ? raw : null;
  if (!token) return null;
  const key = 'auth_session:' + await tokenHash(token);
  let entry;
  try { entry = JSON.parse(await env.INSTALLS.get(key)); } catch { return null; }
  if (!entry?.user?.id || !Number.isFinite(entry.expiresAt) || entry.expiresAt <= Date.now()) return null;
  const generation = await env.INSTALLS.get('auth_generation:' + entry.user.id);
  if ((generation || '') !== entry.generation) return null;
  return { ...entry, key };
}

export async function revokeUserSessions(env, userId) {
  await env.INSTALLS.put('auth_generation:' + userId, randomToken());
}

export async function handleAuth(request, env, verify = verifyIdentity) {
  const path = new URL(request.url).pathname;
  if (path === '/api/auth/session' && request.method === 'POST') {
    // No legacy or missing-secret bypass for issuing sessions.
    if (!env.SHARED_SECRET || request.headers.get('x-install-secret') !== env.SHARED_SECRET) return reply({ error: 'forbidden' }, 403);
    if (!env.INSTALLS) return reply({ error: 'unavailable' }, 503);
    let body;
    try { body = await request.json(); } catch { return reply({ error: 'invalid json' }, 400); }
    let user;
    try { user = await verify(body, env); } catch { return reply({ error: 'invalid credentials' }, 401); }
    const expiresAt = Date.now() + SESSION_SECONDS * 1000;
    const generation = await env.INSTALLS.get('auth_generation:' + user.id) || '';
    // Stateless signed session: issuing it needs no KV write, so sign-in keeps
    // working when the free KV daily write quota is exhausted.
    const token = await signSession(env, { user, expiresAt, generation });
    if (!token) return reply({ error: 'unavailable' }, 503);
    return reply({ ok: true, token, expiresAt: new Date(expiresAt).toISOString(), user });
  }
  if (path === '/api/auth/logout' && request.method === 'POST') {
    const session = await readSession(request, env);
    // Legacy KV sessions are deleted; signed ones simply expire on the client.
    if (session?.key) { try { await env.INSTALLS.delete(session.key); } catch {} }
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
