// Раздел «Пользователи» админки: Premium на срок, заметки, история, удаление.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { computePremiumExpiry, summarizeProgress } from './users_admin.js';

class KV {
  data = new Map();
  meta = new Map();
  ops = 0;
  async get(k) { this.ops++; return this.data.get(k) ?? null; }
  async put(k, v, o) { this.data.set(k, String(v)); if (o?.metadata) this.meta.set(k, o.metadata); else this.meta.delete(k); }
  async delete(k) { this.data.delete(k); this.meta.delete(k); }
  async list({ prefix, cursor }) {
    const all = [...this.data.keys()].filter(k => k.startsWith(prefix)).sort();
    const start = cursor ? Number(cursor) : 0, page = all.slice(start, start + 1000);
    const done = start + 1000 >= all.length;
    return { keys: page.map(name => ({ name, metadata: this.meta.get(name) })), list_complete: done, cursor: done ? undefined : String(start + 1000) };
  }
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

test('события аналитики чистятся: XSS, __proto__, мусор', async () => {
  const env = setup();
  await worker.fetch(new Request('https://w.test/api/track', { method: 'POST', headers: { 'content-type': 'application/json', 'user-agent': 'Mozilla/5.0 (iPhone)', 'cf-ipcountry': 'RU' },
    body: JSON.stringify({ type: 'view', source: '__proto__', campaign: '<img src=x onerror=alert(1)>', path: '/a"><script>' }) }), env, { waitUntil() {} });
  assert.equal({}.views, undefined);
  const all = [...env.INSTALLS.data.values()].join('\n');
  assert.ok(!all.includes('<img') && !all.includes('<script'), 'HTML не должен попасть в KV');
});

test('отчёт и опрос отзывов — только с паролем', async () => {
  const env = setup();
  for (const q of ['?report=daily&send=true', '?reviews=check']) {
    const r = await worker.fetch(new Request('https://w.test/' + q), env, { waitUntil() {} });
    assert.equal(r.status, 401, q);
  }
});

test('импорт Threads требует пароль и чистит id', async () => {
  const env = setup();
  env.SHARED_SECRET = 'app-key';
  const post = (headers) => worker.fetch(new Request('https://w.test/api/threads/import', { method: 'POST', headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify({ posts: [{ id: "x');alert(1)//", text: 'пост' }] }) }), env);
  assert.equal((await post({ 'x-install-secret': 'app-key' })).status, 403);
  assert.equal((await post({ authorization: 'Bearer pw' })).status, 200);
  const r = await call(env, '/api/admin/threads/state');
  assert.ok(!JSON.stringify(r.data).includes('alert'));
});

test('страница админки не встраивается в чужие сайты', async () => {
  const r = await worker.fetch(new Request('https://w.test/admin'), setup());
  assert.equal(r.headers.get('x-frame-options'), 'DENY');
});

test('список из метаданных: 2500 пользователей без чтения профилей', async () => {
  const env = setup();
  for (let i = 0; i < 2500; i++) env.INSTALLS.data.set('user:x' + i, JSON.stringify({ id: 'x' + i, name: 'U' + i }));
  const first = await call(env, '/api/admin/users');
  assert.equal(first.data.users.length, 2501);
  assert.equal(first.data.users.filter(u => u.pending).length, 2501 - 150);
  for (let i = 0; i < 20; i++) await call(env, '/api/admin/users');
  env.INSTALLS.ops = 0;
  const done = await call(env, '/api/admin/users');
  assert.equal(done.data.users.filter(u => u.pending).length, 0);
  assert.equal(env.INSTALLS.ops, 0, 'после дозаписи профили не читаются');
  assert.ok(done.data.users.every(u => u.pushToken === undefined));
});
