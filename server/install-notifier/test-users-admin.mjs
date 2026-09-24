// Раздел «Пользователи» админки: Premium на срок, заметки, история, удаление.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { computePremiumExpiry, summarizeProgress } from './users_admin.js';

class KV {
  data = new Map();
  async get(k) { return this.data.get(k) ?? null; }
  async put(k, v) { this.data.set(k, String(v)); }
  async delete(k) { this.data.delete(k); }
  async list({ prefix }) { return { keys: [...this.data.keys()].filter(k => k.startsWith(prefix)).map(name => ({ name })) }; }
}
const DAY = 86400000;
function setup() {
  const env = { INSTALLS: new KV(), ADMIN_PASSWORD: 'pw' };
  env.INSTALLS.data.set('user:u1', JSON.stringify({ id: 'u1', name: 'Анна', email: 'a@x.ru', isPremium: false, pushToken: 'secret-push' }));
  env.INSTALLS.data.set('user_email:a@x.ru', 'u1');
  env.INSTALLS.data.set('users_list', JSON.stringify(['u1']));
  env.INSTALLS.data.set('user_progress:u1', JSON.stringify({
    questionProgressAb: { 1: { isCorrect: true }, 2: { isCorrect: false } },
    examResultsAb: [JSON.stringify({ ticketNumber: 3, correctAnswers: 19, wrongAnswers: 1, passed: true, completedAt: '2026-09-01T10:00:00Z' })],
    streak: { current: 2, longest: 5 },
  }));
  return env;
}
const call = (env, path, body, auth = 'pw') => worker.fetch(new Request('https://w.test' + path, {
  method: body === undefined ? 'GET' : 'POST',
  headers: { 'content-type': 'application/json', ...(auth ? { authorization: 'Bearer ' + auth } : {}) },
  ...(body === undefined ? {} : { body: JSON.stringify(body) }),
}), env).then(async r => ({ status: r.status, data: await r.json() }));

test('без пароля API пользователей закрыто', async () => {
  const env = setup();
  assert.equal((await call(env, '/api/admin/users', undefined, null)).status, 401);
  assert.equal((await call(env, '/api/admin/users/grant-premium', { userId: 'u1', days: 7 }, 'wrong')).status, 401);
});

test('срок Premium: продление, отсчёт с сегодня, дата, навсегда', () => {
  const now = Date.parse('2026-09-24T00:00:00Z');
  const active = { isPremium: true, premiumExpiresAt: new Date(now + 10 * DAY).toISOString() };
  assert.equal(computePremiumExpiry(active, { days: 30 }, now).expiresAt, new Date(now + 40 * DAY).toISOString());
  assert.equal(computePremiumExpiry(active, { days: 30, mode: 'set' }, now).expiresAt, new Date(now + 30 * DAY).toISOString());
  assert.equal(computePremiumExpiry(active, { until: '2026-12-31' }, now).expiresAt, '2026-12-31T23:59:59.000Z');
  assert.equal(computePremiumExpiry(active, { isLifetime: true }, now).expiresAt, null);
  assert.ok(computePremiumExpiry(active, { until: '2026-01-01' }, now).error);
  assert.ok(computePremiumExpiry(active, { days: 0 }, now).error);
  assert.ok(computePremiumExpiry(active, { days: 99999 }, now).error);
});

test('выдача и отзыв пишутся в историю, заметка сохраняется', async () => {
  const env = setup();
  const g = await call(env, '/api/admin/users/grant-premium', { userId: 'u1', days: 14, comment: 'конкурс' });
  assert.equal(g.status, 200);
  assert.equal(g.data.user.premiumActive, true);
  assert.equal(g.data.user.pushToken, undefined);
  const left = Date.parse(g.data.user.premiumExpiresAt) - Date.now();
  assert.ok(left > 13.9 * DAY && left <= 14 * DAY);
  assert.equal((await call(env, '/api/admin/users/grant-premium', { userId: 'u1', until: '2000-01-01' })).status, 400);
  await call(env, '/api/admin/users/note', { userId: 'u1', note: 'VIP' });
  await call(env, '/api/admin/users/revoke-premium', { userId: 'u1' });
  const d = await call(env, '/api/admin/users/detail?id=u1');
  assert.equal(d.data.user.isPremium, false);
  assert.equal(d.data.admin.note, 'VIP');
  assert.deepEqual(d.data.admin.history.map(h => h.action), ['revoke', 'grant']);
  assert.equal(d.data.admin.history[1].comment, 'конкурс');
  assert.equal(d.data.progress.ab.answered, 2);
  assert.equal(d.data.progress.ab.examsPassed, 1);
  assert.equal(d.data.user.hasPushToken, true);
});

test('удаление убирает профиль, прогресс, заметки и сессии', async () => {
  const env = setup();
  await call(env, '/api/admin/users/note', { userId: 'u1', note: 'x' });
  assert.equal((await call(env, '/api/admin/users/delete', { userId: 'u1' })).status, 200);
  for (const key of ['user:u1', 'user_progress:u1', 'user_admin:u1', 'user_email:a@x.ru']) assert.equal(env.INSTALLS.data.has(key), false, key);
  assert.ok(env.INSTALLS.data.has('auth_generation:u1'));
  assert.deepEqual(JSON.parse(env.INSTALLS.data.get('users_list')), []);
  assert.equal((await call(env, '/api/admin/users/detail?id=u1')).status, 404);
});

test('сводка прогресса без данных', () => {
  assert.equal(summarizeProgress(null), null);
  assert.equal(summarizeProgress({}).ab.answered, 0);
});
