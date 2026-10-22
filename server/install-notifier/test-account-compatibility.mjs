import test from 'node:test';
import assert from 'node:assert/strict';
import { accountReadMany } from './account_state.js';
import { readSession } from './user_auth.js';
import { fixture, session, request } from './fixture-account.mjs';

function legacyBinding(env, reply) {
  const original = env.ACCOUNTS.get.bind(env.ACCOUNTS);
  const calls = [];
  env.ACCOUNTS.get = id => ({ fetch: (input, options) => {
    const path = new URL(typeof input === 'string' ? input : input.url).pathname;
    calls.push(path);
    return path === '/_account/read-many' ? reply() : original(id).fetch(input, options);
  } });
  return calls;
}

test('new session reader stays compatible with an old DO installation-style response or missing RPC', async () => {
  for (const reply of [
    () => Response.json({ ok: true, ignored: true, reason: 'not-a-store-install' }),
    () => new Response('not found', { status: 404 }),
  ]) {
    const { env } = fixture(), token = await session(env);
    const calls = legacyBinding(env, reply);
    assert.equal((await readSession(request('/api/notifications', undefined, token), env)).user.id, 'google_123');
    assert.deepEqual(calls, ['/_account/read-many', '/_account/read', '/_account/read']);
    // The legacy fallback still observes the authoritative generation immediately.
    await env.ACCOUNTS.get('google_123').fetch('https://account.internal/_account/write', {
      method: 'POST', headers: { 'x-account-id': 'google_123' },
      body: JSON.stringify({ key: 'auth_generation:google_123', value: 'revoked' }),
    });
    assert.equal(await readSession(request('/api/notifications', undefined, token), env), null);
  }
});

test('read-many never accepts malformed results or hides an unavailable account store behind fallback', async () => {
  for (const reply of [
    () => Response.json({ ok: true }),
    () => Response.json({ values: [] }),
    () => Response.json({ values: [null, {}] }),
    () => Response.json({ values: [null, null, null] }),
    () => new Response('unavailable', { status: 503 }),
  ]) {
    const { env } = fixture();
    const calls = legacyBinding(env, reply);
    await assert.rejects(accountReadMany(env, 'google_123', ['auth_generation:google_123', 'revoked_session:google_123:fixture']), /account storage unavailable/);
    assert.deepEqual(calls, ['/_account/read-many']);
  }
});
