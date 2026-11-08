import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import worker from './worker.js';
import { SocialPublisher } from './social_guard.js';
import { readSocialPosts, saveSocialPosts } from './social_queue.js';
import { SOCIAL_CLIENT_JS } from './social_ui.js';

class Storage {
  data = new Map(); alarm = null;
  async get(key) { return structuredClone(this.data.get(key)); }
  async put(key, value) { this.data.set(key, structuredClone(value)); }
  async delete(key) { this.data.delete(key); }
  async list({ prefix = '' }) {
    return new Map([...this.data].filter(([key]) => key.startsWith(prefix)).map(([key, value]) => [key, structuredClone(value)]));
  }
  async getAlarm() { return this.alarm; }
  async setAlarm(value) { this.alarm = value; }
  async transaction(run) {
    const saved = structuredClone(this.data), alarm = this.alarm;
    try { return await run(this); }
    catch (error) { this.data = saved; this.alarm = alarm; throw error; }
  }
}

function fixture(t) {
  const posts = [
    { id: 'one', accountId: 'fixture', fileName: 'one.mp4', driveFileId: 'drive-one', status: 'failed', caption: 'old',
      instagramStatus: 'failed', youtubeStatus: 'published', youtubeVideoId: 'existing-youtube', targets: ['instagram', 'youtube'] },
    { id: 'two', accountId: 'fixture', fileName: 'two.mp4', driveFileId: 'drive-two', status: 'failed', caption: 'old',
      instagramStatus: 'failed', youtubeStatus: 'published', youtubeVideoId: 'existing-two', targets: ['instagram', 'youtube'] },
  ];
  const data = new Map([['social:posts', JSON.stringify(posts)],
    ['social:settings', JSON.stringify({ workerOrigin: 'https://fixture.invalid' })]]);
  const storage = new Storage(), tasks = [], upstream = [];
  const env = { ADMIN_PASSWORD: 'fixture', SOCIAL_QUEUE_REQUIRED: 'true',
    INSTALLS: { get: async key => data.get(key) ?? null, put: async (key, value) => data.set(key, value) } };
  const object = new SocialPublisher({ storage }, env);
  let beforeChange = null, forceStatus = null, queueCalls = 0;
  env.SOCIAL_PUBLISHER = { idFromName: value => value, get: () => ({ fetch: async (url, options) => {
    queueCalls++;
    if (String(url).endsWith('/change') && beforeChange) {
      const run = beforeChange; beforeChange = null; await run();
    }
    const response = forceStatus ? new Response('PRIVATE_PROVIDER_BODY', { status: forceStatus })
      : await object.fetch(new Request(url, options));
    upstream.push({ operation: new URL(url).pathname, status: response.status });
    return response;
  } }) };
  t.mock.method(globalThis, 'fetch', async () => { assert.fail('the fixture must not contact external services'); });
  const logs = [];
  t.mock.method(console, 'error', (...args) => logs.push(args));
  const call = async (body, { authorized = true } = {}) => {
    const response = await worker.fetch(new Request('https://fixture.invalid/api/admin/social/posts/bulk', {
      method: 'POST', headers: { 'content-type': 'application/json', ...(authorized ? { authorization: 'Bearer fixture' } : {}) },
      body: JSON.stringify(body),
    }), env, { waitUntil: promise => tasks.push(promise) });
    await Promise.all(tasks);
    return response;
  };
  return { posts, env, upstream, logs, call, read: () => readSocialPosts(env),
    beforeChange: run => { beforeChange = run; }, forceStatus: status => { forceStatus = status; },
    queueCalls: () => queueCalls };
}

test('full Worker returns a reviewable 409 for a real stale bulk caption edit, preserving the winner and atomicity', async t => {
  const f = fixture(t);
  f.beforeChange(async () => {
    const winner = await f.read(); winner[0].caption = 'concurrent winner';
    await saveSocialPosts(f.env, winner);
  });
  const response = await f.call({ ids: ['one', 'two'], action: 'caption', caption: 'stale bulk edit' });
  assert.equal(response.status, 409);
  const body = await response.json();
  assert.equal(body.code, 'social_queue_conflict');
  assert.match(body.error, /Обновить.*проверьте статусы/);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), '*');
  const current = await f.read();
  assert.deepEqual(current[0], { ...f.posts[0], caption: 'concurrent winner' });
  assert.deepEqual(current[1], f.posts[1], 'the second row does not partially commit');
  assert.equal(f.upstream.filter(item => item.operation === '/queue/change').length, 2, 'one winning write and one rejected write; no automatic replay');
  assert.ok(f.upstream.some(item => item.status === 409));
  assert.deepEqual(f.logs, [], 'a guarded conflict is not reported as a server failure');
});

for (const action of ['requeue', 'delete']) test(`stale bulk ${action} cannot erase a concurrently completed publication`, async t => {
  const f = fixture(t);
  const winnerPatch = { status: 'published', instagramStatus: 'published', instagramMediaId: 'existing-instagram',
    instagramPermalink: 'https://www.instagram.com/reel/fixture/', publishedAt: '2026-10-27T08:00:00Z' };
  f.beforeChange(async () => {
    const winner = await f.read(); winner[0] = { ...winner[0], ...winnerPatch };
    await saveSocialPosts(f.env, winner);
  });
  const response = await f.call({ ids: ['one', 'two'], action });
  assert.equal(response.status, 409);
  const current = await f.read();
  assert.deepEqual(current[0], { ...f.posts[0], ...winnerPatch });
  assert.deepEqual(current[1], f.posts[1]);
  assert.equal(current[0].youtubeVideoId, 'existing-youtube');
  assert.equal(f.upstream.filter(item => item.operation === '/queue/change').length, 2);
});

test('unknown queue outages remain errors and never expose raw upstream text as a conflict', async t => {
  const f = fixture(t); f.forceStatus(503);
  const response = await f.call({ ids: ['one'], action: 'caption', caption: 'new' });
  assert.ok(response.status >= 500);
  const body = await response.json();
  assert.notEqual(body.code, 'social_queue_conflict');
  assert.doesNotMatch(JSON.stringify(body), /PRIVATE_PROVIDER_BODY|fixture|Bearer/);
});

test('unauthorized admin requests do not reach the queue or disclose conflict details', async t => {
  const f = fixture(t);
  const response = await f.call({ ids: ['one'], action: 'requeue' }, { authorized: false });
  assert.equal(response.status, 401);
  assert.equal(f.queueCalls(), 0);
  assert.deepEqual(await response.json(), { error: 'unauthorized' });
});

test('bulk UI surfaces a conflict, retains selection and waits for manual review instead of replaying', async () => {
  const source = /window\.scBulk = async function \(action\) \{[\s\S]*?\n\};/.exec(SOCIAL_CLIENT_JS)?.[0];
  assert.ok(source);
  const toasts = [], calls = [];
  let reloads = 0, conflict = true;
  const context = { window: {}, scPicked: () => ['one', 'two'], scSelected: { one: true, two: true }, confirm: () => true,
    scApi: async (path, body) => { calls.push({ path, body }); if (conflict) throw Error('Очередь изменилась. Нажмите «Обновить»'); return { ok: true }; },
    scToast: (...args) => toasts.push(args), loadSocial: async () => { reloads++; } };
  vm.runInNewContext(source, context);
  await context.window.scBulk('requeue');
  assert.equal(calls.length, 1);
  assert.deepEqual(context.scSelected, { one: true, two: true });
  assert.equal(reloads, 0);
  assert.match(toasts[0][0], /Действие не выполнено:.*Обновить/);
  assert.equal(toasts[0][1], true);
  conflict = false;
  await context.window.scBulk('requeue');
  assert.equal(calls.length, 2, 'only the explicit second action retries');
  assert.equal(Object.keys(context.scSelected).length, 0);
  assert.equal(reloads, 1);
  assert.equal(toasts.at(-1)[0], 'Готово');
});
