// App sessions and provider credentials stay on the app origin and its API.
const reply = (body, status = 200) => Response.json(body, {
  status, headers: { 'Cache-Control': 'no-store' },
});
const validToken = value => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
const providers = new Set(['google', 'yandex', 'telegram', 'apple']);

export class SchoolLoginGrant {
  constructor(ctx) { this.ctx = ctx; }

  async fetch(request) {
    const storage = this.ctx.storage;
    const body = await request.json();
    if (body.identity) {
      const expires = Date.now() + 120000;
      await storage.setAlarm(expires);
      await storage.put('grant', { ...body, expires });
      return reply({ ok: true });
    }
    return storage.transaction(async tx => {
      const grant = await tx.get('grant');
      if (!grant || grant.expires <= Date.now() || grant.challenge !== body.challenge) {
        return reply({ error: 'invalid_grant' }, 400);
      }
      await tx.delete('grant');
      return reply(grant.identity);
    });
  }

  async alarm() { await this.ctx.storage.deleteAll(); }
}

export async function schoolLogin(request, env, path, readSession, tokenHash) {
  if (request.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
  let body;
  try { body = await request.json(); } catch { return reply({ error: 'invalid_request' }, 400); }

  let code, payload;
  const issue = path === '/api/auth/schools/authorize';
  if (issue) {
    if (!validToken(body?.challenge)) return reply({ error: 'invalid_request' }, 400);
    if (request.headers.get('origin') !== 'https://pdd-drive.app') return reply({ error: 'forbidden' }, 403);
    const session = await readSession(request, env);
    const user = session?.user;
    if (!providers.has(user?.provider) || !user.id.startsWith(user.provider + '_')) {
      return reply({ error: 'authentication_required' }, 401);
    }
    code = Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, '0')).join('');
    payload = {
      challenge: body.challenge,
      identity: { provider: user.provider, uid: user.id.slice(user.provider.length + 1), name: user.name || '', email: user.email || '' },
    };
  } else {
    if (!validToken(body?.code) || !validToken(body?.verifier)) return reply({ error: 'invalid_request' }, 400);
    code = body.code;
    payload = { challenge: await tokenHash(body.verifier) };
  }
  const store = env.SCHOOL_GRANTS.get(env.SCHOOL_GRANTS.idFromName(code));
  const response = await store.fetch('https://school-grant/', { method: 'POST', body: JSON.stringify(payload) });
  return issue && response.ok ? reply({ code }) : response;
}
