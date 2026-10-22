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
  const writes = [];
  const env = { INSTALLS: {
    get: async key => data.get(key) ?? null,
    put: async (key, value) => { writes.push(key); data.set(key, value); },
  } };
  const calls = [];
  const controls = { onStatus: null, mediaResponses: [], other: null };
  const responses = statuses.slice();
  t.mock.method(globalThis, 'fetch', async (input, options = {}) => {
    const url = new URL(input);
    const method = options.method || 'GET';
    calls.push({ method, path: url.pathname, signal: options.signal, form: options.body ? new URLSearchParams(options.body) : null });
    if (options.signal?.aborted) throw options.signal.reason;
    if (controls.other) {
      const response = await controls.other(url, options);
      if (response) return response;
    }
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
    post, env, calls, controls, writes,
    set: (key, value) => data.set(key, JSON.stringify(value)),
    get: key => JSON.parse(data.get(key) || 'null'),
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
    let now = Date.now();
    t.mock.method(Date, 'now', () => now);
    f.controls.mediaResponses = [transient[1], () => Response.json({ id: f.post.instagramMediaId, permalink: f.post.instagramPermalink })];
    await publishWithClock(t, f, async () => {
      assert.equal((await publishPost(f.env, f.post.id, 'https://fixture.invalid')).status, 'error');
      assert.notEqual(f.current().instagramNeedsReview, true);
      assert.doesNotMatch(f.current().error, /200 секунд|private/);
      if (transient[0] === 'HTTP 429') now += 3600001;
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

const cooldownKey = 'social:instagram_cooldown';
const quota = (status = 403, retryAfter) => Response.json({ error: {
  code: 4, error_subcode: 1349210, message: 'private upstream quota text',
} }, { status, headers: retryAfter ? { 'retry-after': retryAfter } : {} });

for (const stage of ['create', 'status', 'publish', 'verify']) {
  test(`code 4 in ${stage} starts one global cooldown, prevents fallback/repeated calls and notifies once`, async t => {
    const f = fixture(t, [stage === 'status' ? () => quota() : { status_code: stage === 'verify' ? 'PUBLISHED' : 'FINISHED' }],
      stage === 'create' ? { instagramContainerId: null, instagramMediaId: null } : {});
    if (stage === 'verify') f.controls.mediaResponses = [() => quota()];
    if (stage === 'create' || stage === 'publish') f.controls.other = url =>
      url.pathname.endsWith(stage === 'create' ? '/media' : '/media_publish') ? quota() : null;
    let notifications = 0;
    const notify = async () => { notifications++; };
    await publishWithClock(t, f, async () => {
      assert.equal((await publishPost(f.env, f.post.id, 'https://fixture.invalid', notify)).status, 'error');
      const cooldown = f.get(cooldownKey);
      assert.equal(cooldown.reason, 'rate_limit');
      assert.ok(cooldown.until >= Date.now() + 3599000 && cooldown.until <= Date.now() + 3600000);
      assert.notEqual(f.current().instagramNeedsReview, true);
      assert.equal(f.current().instagramContainerId, f.post.instagramContainerId);
      assert.equal(f.current().instagramMediaId, f.post.instagramMediaId);
      assert.equal(f.current().instagramPermalink, f.post.instagramPermalink);
      assert.equal(f.current().youtubeVideoId, f.post.youtubeVideoId);
      const calls = f.calls.length, postWrites = f.writes.filter(key => key === 'social:posts').length;
      assert.equal((await publishPost(f.env, f.post.id, 'https://fixture.invalid', notify)).status, 'pending');
      assert.deepEqual(await runAutoPost(f.env, 'https://fixture.invalid', notify), []);
      assert.equal(f.calls.length, calls);
      assert.equal(f.writes.filter(key => key === 'social:posts').length, postWrites);
      assert.equal(notifications, 1);
      assert.equal(f.writes.filter(key => key === cooldownKey).length, 1);
      assert.doesNotMatch(f.current().error, /private/);
    });
    assert.ok(f.calls.every(call => !call.path.includes('/me/')));
    assert.equal(f.calls.filter(call => call.method === 'POST').length, ['create', 'publish'].includes(stage) ? 1 : 0);
  });
}

for (const [header, expectedHours] of [['7200', 2], ['999999999', 24], ['invalid', 1], ['-2', 1]]) {
  test(`Retry-After ${header} is bounded to ${expectedHours} hours`, async t => {
    const now = Date.now();
    t.mock.method(Date, 'now', () => now);
    const f = fixture(t, [() => quota(429, header)]);
    await publishWithClock(t, f);
    assert.equal(f.get(cooldownKey).until, now + expectedHours * 3600000);
  });
}

test('HTTP-date Retry-After can extend the default one-hour cooldown', async t => {
  const now = Math.floor(Date.now() / 1000) * 1000;
  t.mock.method(Date, 'now', () => now);
  const f = fixture(t, [() => quota(429, new Date(now + 3 * 3600000).toUTCString())]);
  await publishWithClock(t, f);
  assert.equal(f.get(cooldownKey).until, now + 3 * 3600000);
});

test('HTTP 429 without an API code activates the default cooldown', async t => {
  const f = fixture(t, [() => Response.json({}, { status: 429 })]);
  await publishWithClock(t, f);
  assert.equal(f.get(cooldownKey).reason, 'rate_limit');
  assert.notEqual(f.current().instagramNeedsReview, true);
});

for (const kind of ['expired', 'too-far-future', 'string', 'wrong-reason', 'malformed']) {
  test(`${kind} cooldown cannot block Instagram forever`, async t => {
    const f = fixture(t, [{ status_code: 'PUBLISHED' }]);
    f.set(cooldownKey, { reason: kind === 'wrong-reason' ? 'unknown' : 'rate_limit',
      until: kind === 'expired' ? Date.now() - 1 : kind === 'too-far-future' ? Date.now() + 25 * 3600000
        : kind === 'string' ? String(Date.now() + 3600000) : kind === 'malformed' ? null : Date.now() + 3600000 });
    assert.equal((await publishWithClock(t, f)).status, 'ok');
    assert.equal(f.calls.length, 2);
  });
}

test('ordinary code 190/403 is not mistaken for the app rate limit', async t => {
  const f = fixture(t, [() => Response.json({ error: { code: 190 } }, { status: 403 })]);
  await publishWithClock(t, f);
  assert.equal(f.get(cooldownKey), null);
  assert.notEqual(f.current().instagramNeedsReview, true);
});

test('manual Instagram retry reports the cooldown without changing quarantine or scheduling background work', async t => {
  const f = fixture(t, [], { status: 'failed', instagramStatus: 'failed', instagramNeedsReview: true });
  f.set(cooldownKey, { reason: 'rate_limit', until: Date.now() + 3600000 });
  const before = f.current(), tasks = [];
  const request = new Request('https://fixture.invalid/api/admin/social/posts/publish-platform', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ id: f.post.id, platform: 'instagram' }),
  });
  const response = await handleSocialAdmin(request, f.env, { waitUntil: task => tasks.push(task) }, new URL(request.url), {
    jsonResponse: (body, status = 200) => Response.json(body, { status }),
  });
  const body = await response.json();
  assert.equal(body.ok, false); assert.equal(body.status, 'pending'); assert.ok(body.retryAt);
  assert.match(body.message, /паузе/);
  assert.deepEqual(f.current(), before);
  assert.equal(tasks.length, 0); assert.equal(f.writes.length, 0); assert.equal(f.calls.length, 0);
});

test('cooldown blocks stale processing/resume, due work, and old-token refresh without post writes', async t => {
  const f = fixture(t, [], { status: 'processing', processingSince: '2026-10-20T16:00:00.000Z' });
  f.set(cooldownKey, { reason: 'rate_limit', until: Date.now() + 3600000 });
  f.set('social:accounts', [{ ...f.get('social:accounts')[0], instagramTokenUpdatedAt: '2020-01-01T00:00:00.000Z' }]);
  const before = f.current();
  assert.deepEqual(await runAutoPost(f.env, 'https://fixture.invalid'), []);
  assert.deepEqual(f.current(), before);
  assert.equal(f.calls.length, 0);
  assert.equal(f.writes.filter(key => key === 'social:posts').length, 0);
});

test('a cold refresh rate limit stops later accounts and due Instagram publication in the same cron', async t => {
  const f = fixture(t, [], { status: 'failed' });
  const account = { ...f.get('social:accounts')[0], instagramTokenUpdatedAt: '2020-01-01T00:00:00.000Z' };
  f.set('social:accounts', [account, { ...account, id: 'second-account' }]);
  f.controls.other = url => url.pathname === '/refresh_access_token' ? quota() : null;
  await runAutoPost(f.env, 'https://fixture.invalid');
  assert.equal(f.calls.length, 1);
  assert.equal(f.get(cooldownKey).reason, 'rate_limit');
  assert.notEqual(f.current().instagramNeedsReview, true);
});

test('optional permalink rate limit preserves the successfully published media ID', async t => {
  const f = fixture(t, [{ status_code: 'FINISHED' }]);
  f.controls.other = url => url.pathname.endsWith('/new-media') ? quota() : null;
  assert.equal((await publishWithClock(t, f)).status, 'ok');
  assert.equal(f.current().instagramMediaId, 'new-media');
  assert.equal(f.current().instagramStatus, 'published');
  assert.equal(f.current().instagramPermalink, null);
  assert.equal(f.get(cooldownKey).reason, 'rate_limit');
  assert.equal(f.calls.filter(call => call.method === 'POST').length, 1);
});

test('cooldown keeps YouTube independent and changes a paused Instagram processing status to queued without erasing history', async t => {
  const f = fixture(t, [], { status: 'failed', instagramStatus: 'processing', youtubeStatus: 'queued', driveFileId: 'fixture-video',
    instagramPreviousAttempts: [{ containerId: 'old-fixture-container', mediaId: 'old-fixture-media' }] });
  f.set(cooldownKey, { reason: 'rate_limit', until: Date.now() + 3600000 });
  f.set('social:settings', { workerOrigin: 'https://fixture.invalid', googleClientId: 'fixture', googleClientSecret: 'fixture', googleRefreshToken: 'fixture-refresh' });
  f.controls.other = (url, options) => {
    if (url.hostname === 'oauth2.googleapis.com') return Response.json({ access_token: crypto.randomUUID(), expires_in: 3600 });
    if (url.pathname.includes('/drive/v3/files/')) return new Response(new Uint8Array(2000), { headers: { 'content-type': 'video/mp4' } });
    if (url.pathname.includes('/upload/youtube/')) return new Response('', { headers: { location: 'https://upload.fixture.invalid/video' } });
    if (url.hostname === 'upload.fixture.invalid' && options.method === 'PUT') return Response.json({ id: 'new-youtube' });
    return null;
  };
  let notifications = 0;
  const result = await publishPost(f.env, f.post.id, 'https://fixture.invalid', async () => { notifications++; });
  assert.equal(result.status, 'error');
  assert.equal(f.current().youtubeStatus, 'published');
  assert.equal(f.current().youtubeVideoId, 'new-youtube');
  assert.equal(f.current().instagramStatus, 'queued');
  for (const key of ['instagramContainerId', 'instagramMediaId', 'instagramPermalink', 'instagramPreviousAttempts']) {
    assert.deepEqual(f.current()[key], f.post[key]);
  }
  assert.equal(f.calls.some(call => call.path.includes('/v21.0/')), false);
  assert.equal(notifications, 0);
});

test('real YouTube failures still notify while Instagram is cooling down', async t => {
  const f = fixture(t, [], { youtubeStatus: 'queued' });
  f.set(cooldownKey, { reason: 'rate_limit', until: Date.now() + 3600000 });
  let notifications = 0;
  await publishPost(f.env, f.post.id, 'https://fixture.invalid', async () => { notifications++; });
  assert.equal(notifications, 1);
  assert.equal(f.calls.length, 0);
  assert.match(f.current().error, /YouTube/);
});

test('cooldown KV write failures keep a local bounded hold without failing publication handling', async t => {
  const f = fixture(t, [() => quota()]);
  const originalPut = f.env.INSTALLS.put;
  f.env.INSTALLS.put = async (key, value) => {
    if (key === cooldownKey) throw new Error('private storage details');
    return originalPut(key, value);
  };
  t.mock.method(console, 'warn', () => {});
  await publishWithClock(t, f, async () => {
    assert.equal((await publishPost(f.env, f.post.id, 'https://fixture.invalid')).status, 'error');
    const calls = f.calls.length;
    assert.equal((await publishPost(f.env, f.post.id, 'https://fixture.invalid')).status, 'pending');
    assert.equal(f.calls.length, calls);
    assert.equal(f.current().youtubeStatus, 'published');
    assert.notEqual(f.current().instagramNeedsReview, true);
  });
});

test('an unavailable cooldown read holds Instagram safely and still attempts independent YouTube work', async t => {
  const f = fixture(t, [], { youtubeStatus: 'queued' });
  const originalGet = f.env.INSTALLS.get;
  f.env.INSTALLS.get = async key => {
    if (key === cooldownKey) throw new Error('private storage details');
    return originalGet(key);
  };
  let notifications = 0;
  assert.equal((await publishPost(f.env, f.post.id, 'https://fixture.invalid', async () => { notifications++; })).status, 'error');
  assert.equal(f.calls.length, 0);
  assert.equal(f.current().youtubeStatus, 'failed', 'the independent YouTube branch ran and reported its absent fixture credentials');
  assert.equal(notifications, 1);
  assert.notEqual(f.current().instagramNeedsReview, true);
});

test('manual publish and a mixed batch leave held Instagram posts untouched while allowing other work', async t => {
  const f = fixture(t, [], { status: 'failed' });
  const youtube = { ...f.current(), id: 'youtube-only', targets: ['youtube'], youtubeStatus: 'queued' };
  f.set('social:posts', [f.current(), youtube]);
  f.set(cooldownKey, { reason: 'rate_limit', until: Date.now() + 3600000 });
  const before = f.current(), tasks = [];
  const call = async (path, body) => {
    const request = new Request('https://fixture.invalid/api/admin/social/posts/' + path, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
    });
    return handleSocialAdmin(request, f.env, { waitUntil: task => tasks.push(task) }, new URL(request.url), {
      jsonResponse: (payload, status = 200) => Response.json(payload, { status }),
    });
  };
  assert.equal((await (await call('publish', { id: f.post.id })).json()).status, 'pending');
  assert.equal(tasks.length, 0);
  assert.deepEqual(f.current(), before);
  const batch = await (await call('publish-now', { ids: [f.post.id, youtube.id] })).json();
  assert.equal(batch.started, 1); assert.equal(batch.held, 1);
  await Promise.all(tasks);
  assert.deepEqual(f.current(), before);
  assert.equal(f.calls.length, 0);
});
