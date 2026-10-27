import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { accountRead } from './account_state.js';
import { fixture, identity, request, session } from './fixture-account.mjs';

const failures = [
  ['retryable reset', () => Object.assign(new Error('fixture reset'), { retryable: true }), 503, '1'],
  ['overload', () => Object.assign(new Error('fixture overload'), { overloaded: true }), 503, '5'],
  ['platform internal', () => new Error('internal error; reference = abcdef0123456789'), 503, '5'],
  ['storage timeout', () => new Error('Durable Object storage operation exceeded timeout which caused object to be reset.'), 503, '1'],
  ['memory exhaustion', () => new Error('SQLITE_NOMEM'), 503, '5'],
  ['application failure', () => new Error('fixture application error'), 500, null],
];

for (const [name, failure, expectedStatus, expectedDelay] of failures) {
  test(`progress ${name}: caller receives backoff guidance without replaying a committed write`, async t => {
    const { env } = fixture();
    const entitlements = { admin_grant: { expiresAt: '2030-01-01T00:00:00.000Z' } };
    await env.INSTALLS.put('user:google_123', JSON.stringify({ ...identity(), entitlements,
      isPremium: true, premiumExpiresAt: entitlements.admin_grant.expiresAt, premiumSource: 'admin_grant' }));
    const token = await session(env), binding = env.ACCOUNTS;
    let writes = 0;
    env.ACCOUNTS = { idFromName: id => binding.idFromName(id), get: id => ({ fetch: async (input, options) => {
      const req = input instanceof Request ? input : new Request(input, options);
      const result = await binding.get(id).fetch(req);
      if (new URL(req.url).pathname === '/api/user/progress/sync') {
        writes++;
        assert.equal(result.status, 200);
        throw failure(); // The primary transaction succeeded, its response was lost.
      }
      return result;
    } }) };
    t.mock.method(console, 'error', () => {});
    t.mock.method(console, 'log', () => {});
    t.mock.method(globalThis, 'fetch', async () => assert.fail('no external side effects'));
    const tasks = [];
    const response = await worker.fetch(request('/api/user/progress/sync', {
      userId: 'google_123', progress: { questionProgressAb: {
        fixture_answer: { answeredAt: Date.now(), correct: true, selectedAnswer: 0 },
      } },
    }, token), env, { waitUntil: task => tasks.push(task) });
    await Promise.all(tasks);
    assert.equal(response.status, expectedStatus);
    assert.equal(response.headers.get('Retry-After'), expectedDelay);
    assert.match(response.headers.get('Access-Control-Expose-Headers'), /Retry-After/);
    assert.deepEqual(await response.json(), { error: 'server unavailable' });
    assert.equal(writes, 1, 'the header must never enable a server-side POST retry');
    const progress = JSON.parse(await accountRead(env, 'google_123', 'user_progress:google_123'));
    assert.equal(progress.questionProgressAb.fixture_answer.correct, true);
    const user = JSON.parse(await accountRead(env, 'google_123', 'user:google_123'));
    assert.deepEqual(user.entitlements, entitlements);
    assert.equal(user.premiumExpiresAt, entitlements.admin_grant.expiresAt);
  });
}

test('payment creation retains its one-attempt contract without a POST Retry-After hint', async t => {
  const { env } = fixture();
  await env.INSTALLS.put('user:google_123', JSON.stringify(identity()));
  const token = await session(env), binding = env.ACCOUNTS;
  let writes = 0;
  env.ACCOUNTS = { idFromName: id => binding.idFromName(id), get: id => ({ fetch: async (input, options) => {
    const req = input instanceof Request ? input : new Request(input, options);
    if (new URL(req.url).pathname === '/api/user/pay-intent') {
      writes++;
      throw Object.assign(new Error('fixture reset'), { retryable: true });
    }
    return binding.get(id).fetch(req);
  } }) };
  t.mock.method(console, 'error', () => {});
  t.mock.method(console, 'log', () => {});
  t.mock.method(globalThis, 'fetch', async () => assert.fail('no payment provider requests'));
  const tasks = [];
  const response = await worker.fetch(request('/api/user/pay-intent', {
    userId: 'google_123', tariff: 'week',
  }, token), env, { waitUntil: task => tasks.push(task) });
  await Promise.all(tasks);
  assert.equal(response.status, 503);
  assert.equal(response.headers.get('Retry-After'), null);
  assert.equal(writes, 1);
});
