import { boundedJson, checkAdminCredential, equal, digest, HttpFailure } from './request_security.js';
export const ADMIN_SESSION_TTL_SEC = 7 * 86400;
const IDLE_MS = 12 * 3600000, RENEW_MS = 30 * 60000;
export function adminCookieToken(request) {
  const cookie = request.headers.get('cookie') || '';
  const match = /(?:^|;\s*)pdd_admin_token=([a-f0-9]{64})(?:;|$)/.exec(cookie);
  return match?.[1] || null;
}
async function version(env) { return digest('admin-session-v2:' + (env.SESSION_SECRET || '') + ':' + env.ADMIN_PASSWORD); }
export async function adminCsrfToken(env, token) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.SESSION_SECRET || env.ADMIN_PASSWORD), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return [...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode('admin-csrf-v1:' + token)))].map(b => b.toString(16).padStart(2, '0')).join('');
}
export async function createAdminSession(env) {
  const token = [...crypto.getRandomValues(new Uint8Array(32))].map(b => b.toString(16).padStart(2, '0')).join('');
  const now = Date.now();
  await env.INSTALLS.put('admin_session:' + token, JSON.stringify({ created: now, seenAt: now, expiresAt: now + ADMIN_SESSION_TTL_SEC * 1000, version: await version(env) }), { expirationTtl: ADMIN_SESSION_TTL_SEC });
  return token;
}
export async function verifyAdminAuth(request, env) {
  if (!env.ADMIN_PASSWORD || !env.INSTALLS) return false;
  const bearer = request.headers.get('authorization')?.match(/^Bearer (.{1,1024})$/)?.[1];
  if (bearer) return checkAdminCredential(request, env, bearer);
  const token = adminCookieToken(request); if (!token) return false;
  const raw = await env.INSTALLS.get('admin_session:' + token);
  let session; try { session = JSON.parse(raw); } catch { return false; }
  const now = Date.now();
  if (!session || !equal(session.version, await version(env)) || !Number.isFinite(session.expiresAt) || session.expiresAt <= now || !Number.isFinite(session.seenAt) || now - session.seenAt > IDLE_MS) return false;
  if (!['GET', 'HEAD', 'OPTIONS'].includes(request.method)) {
    const origin = request.headers.get('origin');
    if ((origin && origin !== new URL(request.url).origin) || request.headers.get('sec-fetch-site') === 'cross-site' || !equal(request.headers.get('x-admin-csrf'), await adminCsrfToken(env, token))) throw new HttpFailure(403, 'csrf rejected');
  }
  if (now - session.seenAt > RENEW_MS) {
    await env.INSTALLS.put('admin_session:' + token, JSON.stringify({ ...session, seenAt: now }), { expirationTtl: Math.max(1, Math.ceil((session.expiresAt - now) / 1000)) });
  }
  return true;
}
export async function adminLogin(request, env) {
  if (!env.ADMIN_PASSWORD || !env.INSTALLS) throw new HttpFailure(503, 'admin password is not configured');
  const origin = request.headers.get('origin');
  if ((origin && origin !== new URL(request.url).origin) || request.headers.get('sec-fetch-site') === 'cross-site') throw new HttpFailure(403, 'csrf rejected');
  const body = await boundedJson(request, 4096);
  if (!await checkAdminCredential(request, env, String(body.password || '').trim())) throw new HttpFailure(401, 'invalid password');
  const token = await createAdminSession(env);
  return Response.json({ ok: true, csrfToken: await adminCsrfToken(env, token) }, { headers: { 'Cache-Control': 'no-store', 'Set-Cookie': `pdd_admin_token=${token}; Path=/; Max-Age=${ADMIN_SESSION_TTL_SEC}; HttpOnly; Secure; SameSite=Lax` } });
}
// Installed before the historical client and all feature modules. Never sends
// the token to another origin, and obtains a fresh token after session changes.
export const ADMIN_SECURITY_CLIENT_JS = `
(function () {
  var nativeFetch = window.fetch.bind(window), csrf = '';
  window.fetch = async function (input, init) {
    var target = new URL(typeof input === 'string' ? input : input.url, location.href);
    var method = ((init && init.method) || (input && input.method) || 'GET').toUpperCase();
    var admin = target.origin === location.origin && (target.pathname.indexOf('/api/admin/') === 0 || target.pathname === '/api/threads/import');
    if (admin && !['GET','HEAD','OPTIONS'].includes(method) && target.pathname !== '/api/admin/login') {
      if (!csrf) {
        var session = await nativeFetch('/api/admin/session', { cache: 'no-store' });
        if (session.ok) csrf = (await session.json()).csrfToken || '';
      }
      init = Object.assign({}, init || {});
      var headers = new Headers(init.headers || (input && input.headers));
      headers.set('x-admin-csrf', csrf); init.headers = headers;
    }
    var response = await nativeFetch(input, init);
    if (admin && ['/api/admin/session','/api/admin/login'].includes(target.pathname) && response.ok) {
      var data = await response.clone().json().catch(function () { return {}; }); csrf = data.csrfToken || csrf;
    }
    if (response.status === 401 || target.pathname === '/api/admin/logout') csrf = '';
    return response;
  };
})();
`;
