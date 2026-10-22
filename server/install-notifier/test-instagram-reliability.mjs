import test from 'node:test';
import assert from 'node:assert/strict';
import { setImmediate } from 'node:timers';
import { handleSocialAdmin, publishPost, runAutoPost } from './social.js';

function fixture(t, statuses, overrides = {}) {
  const post = {
    id: 'fixture-post', accountId: 'fixture-account', fileName: 'fixture.mp4',
    status: 'processing', targets: ['instagram', 'youtube'],
    instagramStatus: 'processing', instagramContainerId: 'fixture-container',
    instagramMediaId: '17890000000000001', instagramPermalink: 'https://instagram.com/reel/existing/',
    youtubeStatus: 'published', youtubeVideoId: 'existing-youtube',
    youtubePermalink: 'https://youtube.com/shorts/existing',
    scheduledAt: '2026-10-22T16:00:00.000Z', caption: 'Existing caption',
    ...overrides,
  };
  const account = {
    id: post.accountId, name: 'Fixture', active: true,
    instagramAccountId: 'fixture-account', instagramToken: 'fixture-token',
    instagramTokenUpdatedAt: new Date().toISOString(), targets: ['instagram', 'youtube'],
  };
  const data = new Map([
    ['social:posts', JSON.stringify([post])],
    ['social:accounts', JSON.stringify([account])],
    ['social:settings', JSON.stringify({ workerOrigin: 'https://fixture.invalid' })],
  ]);
  const env = { INSTALLS: {
    get: async key => data.get(key) ?? null,
    put: async (key, value) => { data.set(key, value); },
  } };
  const calls = [];
  const controls = { onStatus: null, mediaResponses: [] };
  const responses = statuses.slice();
  t.mock.method(globalThis, 'fetch', async (input, options = {}) => {
    const url = new URL(input);
    const method = options.method || 'GET';
    calls.push({ method, path: url.pathname, signal: options.signal, form: options.body ? new URLSearchParams(options.body) : null });
    if (options.signal?.aborted) throw options.signal.reason;
    if (method === 'GET' && url.pathname.endsWith('/fixture-container')) {
      if (controls.onStatus) await controls.onStatus();
      const response = responses.length > 1 ? responses.shift() : responses[0];
      return typeof response === 'function' ? response() : Response.json(response);
    }
    if (method === 'GET' && /^\/[0-9]{1,32}$/.test(url.pathname.replace('/v21.0', ''))) {
      const response = controls.mediaResponses.length > 1 ? controls.mediaResponses.shift() : controls.mediaResponses[0];
      if (response) return response();
      return Response.json({ id: url.pathname.split('/').pop(), permalink: 'https://www.instagram.com/reel/existing/' });
    }
    if (method === 'POST' && url.pathname.endsWith('/media_publish')) return Response.json({ id: 'new-media' });
    if (method === 'GET' && url.pathname.endsWith('/new-media')) return Response.json({ permalink: 'https://instagram.com/reel/new/' });
    throw new Error('Unexpected fixture request');
  });
  return {
    post, env, calls, controls,
    current: () => JSON.parse(data.get('social:posts'))[0],
    update: patch => { data.set('social:posts', JSON.stringify([{ ...JSON.parse(data.get('social:posts'))[0], ...patch }])); },
    log: () => JSON.parse(data.get('social:log') || '[]'),
  };
}

async function publishWithClock(t, f, operation = () => publishPost(f.env, f.post.id, 'https://fixture.invalid')) {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let done = false;
  const pending = operation().finally(() => { done = true; });
  for (let i = 0; i < 42 && !done; i += 1) {
    await new Promise(setImmediate);
    t.mock.timers.tick(5000);
  }
  await new Promise(setImmediate);
  assert.equal(done, true, 'publication must finish within the existing polling budget');
  return pending;
}

  test('PUBLISHED reconciles only verified existing media and makes no POST', async t => {
    const f = fixture(t, [{ status_code: 'PUBLISHED' }]);
    assert.equal((await publishWithClock(t, f)).status, 'ok');
    assert.deepEqual(f.calls.map(call => call.method), ['GET', 'GET']);
    const post = f.current();
    assert.equal(post.status, 'published');
    assert.equal(post.instagramStatus, 'published');
    assert.equal(post.instagramContainerId, f.post.instagramContainerId);
    assert.equal(post.instagramMediaId, f.post.instagramMediaId);
    assert.equal(post.instagramPermalink, f.post.instagramPermalink);
    assert.equal(post.youtubeStatus, 'published');
    assert.equal(post.youtubeVideoId, f.post.youtubeVideoId);
    assert.equal(post.youtubePermalink, f.post.youtubePermalink);
    assert.equal(post.scheduledAt, f.post.scheduledAt);
    assert.equal(post.caption, f.post.caption);
    assert.equal(post.error, null);
    assert.ok(post.publishedAt);
    assert.equal(post.instagramNeedsReview, false);
    assert.ok(f.calls[1].signal instanceof AbortSignal);
    assert.match(f.log()[0].message, /подтверждена прежняя публикация/);
    assert.equal(f.log()[0].url, undefined);
  });

test('published media verification has a ten-second deadline and timeout remains transient', async t => {
  const f = fixture(t, [{ status_code: 'PUBLISHED' }]);
  const timeout = AbortSignal.abort(new DOMException('private timeout details', 'TimeoutError'));
  const budgets = [];
  t.mock.method(AbortSignal, 'timeout', budget => { budgets.push(budget); return timeout; });
  assert.equal((await publishWithClock(t, f)).status, 'error');
  assert.deepEqual(budgets, [10000]);
  assert.equal(f.calls[1].signal, timeout);
  assert.notEqual(f.current().instagramNeedsReview, true);
  assert.match(f.current().error, /временно не дал проверить/);
  assert.doesNotMatch(f.current().error, /private|200 секунд/);
  assert.ok(f.calls.every(call => call.method === 'GET'));
});

for (const name of ['AbortError', 'TimeoutError', 'TypeError']) {
  test(`published media response body ${name} stays transient instead of requiring review`, async t => {
    const f = fixture(t, [{ status_code: 'PUBLISHED' }]);
    f.controls.mediaResponses = [() => ({
      ok: true, status: 200,
      json: async () => { throw Object.assign(new Error('private body I/O details'), { name }); },
    })];
    assert.equal((await publishWithClock(t, f)).status, 'error');
    assert.ok(f.calls[1].signal instanceof AbortSignal);
    assert.notEqual(f.current().instagramNeedsReview, true);
    assert.match(f.current().error, /временно не дал проверить/);
    assert.doesNotMatch(f.current().error, /private|200 секунд/);
    assert.ok(f.calls.every(call => call.method === 'GET'));
  });
}

test('PUBLISHED without a known valid media ID needs review and never invents an identity', async t => {
  const f = fixture(t, [{ status_code: 'PUBLISHED' }], { instagramMediaId: null, instagramPermalink: null });
  assert.equal((await publishWithClock(t, f)).status, 'error');
  assert.deepEqual(f.calls.map(call => call.method), ['GET']);
  assert.equal(f.current().instagramMediaId, null);
  assert.equal(f.current().instagramPermalink, null);
  assert.equal(f.current().instagramNeedsReview, true);
  assert.equal(f.current().status, 'failed');
  assert.match(f.current().error, /доступность ролика не подтверждена/);
});

test('PUBLISHED reads fresh metadata committed during the status GET and preserves it', async t => {
  const f = fixture(t, [{ status_code: 'PUBLISHED' }], { instagramMediaId: null, instagramPermalink: null });
  const concurrent = { instagramMediaId: '17890000000000002', instagramPermalink: 'https://www.instagram.com/reel/concurrent/' };
  f.controls.onStatus = () => f.update(concurrent);
  assert.equal((await publishWithClock(t, f)).status, 'ok');
  assert.ok(f.calls[1].path.endsWith('/' + concurrent.instagramMediaId));
  assert.equal(f.current().instagramMediaId, concurrent.instagramMediaId);
  assert.equal(f.current().instagramPermalink, concurrent.instagramPermalink);
  assert.equal(f.current().youtubeVideoId, f.post.youtubeVideoId);
  assert.equal(f.current().scheduledAt, f.post.scheduledAt);
  assert.ok(f.calls.every(call => call.method === 'GET'));
});

const unconfirmed = [
  ['missing media', () => Response.json({ error: { code: 100, error_subcode: 33, message: 'private-message' } }, { status: 400 }), 'media_unavailable'],
  ['unauthorized media', () => Response.json({ error: { code: 190 } }, { status: 401 }), 'media_unconfirmed'],
  ['forbidden media', () => Response.json({}, { status: 403 }), 'media_unconfirmed'],
  ['mismatching identity', () => Response.json({ id: '17890000000000003', permalink: 'https://www.instagram.com/reel/existing/' }), 'media_unconfirmed'],
  ['missing permalink', () => Response.json({ id: '17890000000000001' }), 'media_unconfirmed'],
  ['noncanonical permalink', () => Response.json({ id: '17890000000000001', permalink: 'https://instagram.com.attacker.invalid/reel/existing/' }), 'media_unconfirmed'],
  ['invalid media JSON', () => new Response('{invalid'), 'media_unconfirmed'],
];
for (const [name, response, reason] of unconfirmed) {
  test(`PUBLISHED ${name} needs manual review and leaves identity/history intact`, async t => {
    const f = fixture(t, [{ status_code: 'PUBLISHED' }]);
    f.controls.mediaResponses = [response];
    assert.equal((await publishWithClock(t, f)).status, 'error');
    const post = f.current();
    assert.equal(post.status, 'failed');
    assert.equal(post.instagramNeedsReview, true);
    assert.equal(post.instagramReviewReason, reason);
    assert.equal(post.instagramContainerId, f.post.instagramContainerId);
    assert.equal(post.instagramMediaId, f.post.instagramMediaId);
    assert.equal(post.instagramPermalink, f.post.instagramPermalink);
    assert.equal(post.youtubeStatus, 'published');
    assert.equal(post.scheduledAt, f.post.scheduledAt);
    assert.match(post.error, /Нужна проверка перед новой публикацией/);
    assert.doesNotMatch(post.error, /200 секунд|private/);
    assert.ok(f.calls.every(call => call.method === 'GET'));
  });
}

for (const status of ['failed', 'queued', 'processing']) {
  test(`cron skips needs-review ${status} posts without blind status/publish retries`, async t => {
    const f = fixture(t, [{ status_code: 'PUBLISHED' }], { status, instagramNeedsReview: true, processingSince: '2026-10-21T16:00:00.000Z' });
    const before = f.current();
    assert.deepEqual(await runAutoPost(f.env, 'https://fixture.invalid'), []);
    assert.equal(f.calls.length, 0);
    assert.deepEqual(f.current(), before);
  });
}

for (const transient of [
  ['network', () => { throw new Error('private-network-details'); }],
  ['HTTP 429', () => Response.json({}, { status: 429 })],
  ['HTTP 500', () => Response.json({}, { status: 500 })],
]) {
  test(`PUBLISHED media check ${transient[0]} stays retryable and can recover with read-only verification`, async t => {
    const f = fixture(t, [{ status_code: 'PUBLISHED' }]);
    f.controls.mediaResponses = [transient[1], () => Response.json({ id: f.post.instagramMediaId, permalink: f.post.instagramPermalink })];
    await publishWithClock(t, f, async () => {
      assert.equal((await publishPost(f.env, f.post.id, 'https://fixture.invalid')).status, 'error');
      assert.notEqual(f.current().instagramNeedsReview, true);
      assert.doesNotMatch(f.current().error, /200 секунд|private/);
      assert.equal((await publishPost(f.env, f.post.id, 'https://fixture.invalid')).status, 'ok');
    });
    assert.equal(f.current().status, 'published');
    assert.ok(f.calls.every(call => call.method === 'GET'));
  });
}

test('an explicit manual retry rechecks the same container without reuploading YouTube', async t => {
  const f = fixture(t, [{ status_code: 'PUBLISHED' }], { status: 'failed', instagramStatus: 'failed', instagramNeedsReview: true });
  const request = new Request('https://fixture.invalid/api/admin/social/posts/publish-platform', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ id: f.post.id, platform: 'instagram' }),
  });
  const tasks = [];
  await publishWithClock(t, f, async () => {
    const response = await handleSocialAdmin(request, f.env, { waitUntil: task => tasks.push(task) }, new URL(request.url), { jsonResponse: (body, status = 200) => Response.json(body, { status }) });
    assert.equal(response.status, 200);
    await Promise.all(tasks);
  });
  assert.equal(f.current().status, 'published');
  assert.equal(f.current().instagramNeedsReview, false);
  assert.equal(f.current().instagramContainerId, f.post.instagramContainerId);
  assert.equal(f.current().youtubeVideoId, f.post.youtubeVideoId);
  assert.ok(f.calls.every(call => call.method === 'GET'));
});

for (const http of [401, 429, 500]) {
  test(`container HTTP ${http} fails immediately with safe technical details`, async t => {
    const sensitive = 'https://private.invalid/video?access_token=fixture-sensitive';
    const f = fixture(t, [() => Response.json({ error: { code: 190, error_subcode: 463, message: sensitive } }, { status: http })]);
    assert.equal((await publishWithClock(t, f)).status, 'error');
    assert.equal(f.calls.length, 1);
    assert.equal(f.calls[0].method, 'GET');
    assert.match(f.current().error, new RegExp(`HTTP ${http}, code 190, subcode 463`));
    assert.doesNotMatch(f.current().error, /200 секунд|private\.invalid|fixture-sensitive/);
    assert.equal(JSON.stringify(f.log()).includes(sensitive), false);
    assert.equal(f.current().instagramContainerId, f.post.instagramContainerId);
    assert.equal(f.current().youtubeStatus, 'published');
  });
}

const malformed = [
  ['invalid JSON', () => new Response('{invalid', { headers: { 'content-type': 'application/json' } })],
  ['null', () => Response.json(null)],
  ['array', () => Response.json([])],
  ['missing status', () => Response.json({})],
  ['unknown status', () => Response.json({ status_code: 'https://private.invalid/unknown' })],
  ['non-string status', () => Response.json({ status_code: 123 })],
  ['HTTP 200 API error', () => Response.json({ status_code: 'FINISHED', error: { code: 'private-code', error_subcode: { payload: 'private-value' }, message: 'private-message' } })],
];
for (const [name, response] of malformed) {
  test(`${name} is rejected on the first status read without publishing`, async t => {
    const f = fixture(t, [response]);
    assert.equal((await publishWithClock(t, f)).status, 'error');
    assert.deepEqual(f.calls.map(call => call.method), ['GET']);
    assert.equal(f.current().instagramStatus, 'failed');
    assert.equal(f.current().instagramContainerId, f.post.instagramContainerId);
    assert.doesNotMatch(f.current().error, /200 секунд|private|123/);
    assert.doesNotMatch(JSON.stringify(f.log()), /private/);
  });
}

test('IN_PROGRESS followed by FINISHED publishes the existing container exactly once', async t => {
  const f = fixture(t, [{ status_code: 'IN_PROGRESS' }, { status_code: 'FINISHED' }]);
  assert.equal((await publishWithClock(t, f)).status, 'ok');
  const posts = f.calls.filter(call => call.method === 'POST');
  assert.equal(posts.length, 1);
  assert.ok(posts[0].path.endsWith('/media_publish'));
  assert.equal(posts[0].form.get('creation_id'), f.post.instagramContainerId);
  assert.equal(f.current().instagramMediaId, 'new-media');
  assert.equal(f.current().youtubeVideoId, f.post.youtubeVideoId);
  assert.equal(f.current().status, 'published');
});

test('genuine IN_PROGRESS retains the existing bounded polling timeout', async t => {
  const f = fixture(t, [{ status_code: 'IN_PROGRESS' }]);
  assert.equal((await publishWithClock(t, f)).status, 'error');
  assert.equal(f.calls.length, 40);
  assert.ok(f.calls.every(call => call.method === 'GET'));
  assert.match(f.current().error, /200 секунд/);
  assert.equal(f.current().instagramContainerId, f.post.instagramContainerId);
});

for (const status of ['ERROR', 'EXPIRED']) {
  test(`${status} is explicit, terminal for this attempt, and never publishes or recreates`, async t => {
    const f = fixture(t, [{ status_code: status, status: 'private upstream text' }]);
    assert.equal((await publishWithClock(t, f)).status, 'error');
    assert.deepEqual(f.calls.map(call => call.method), ['GET']);
    assert.equal(f.current().instagramContainerId, f.post.instagramContainerId);
    assert.doesNotMatch(f.current().error, /200 секунд|private/);
    assert.match(f.current().error, status === 'ERROR' ? /не смог обработать/ : /истёк/);
    assert.equal(f.current().youtubeStatus, 'published');
  });
}
