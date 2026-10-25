import test from 'node:test';
import assert from 'node:assert/strict';
import worker, { sanitizeAnalyticsEvent } from './worker.js';
import { acquisitionFields, mergeAcquisition, attributedDestination } from './attribution.js';
import { userSummary, listUserSummaries } from './user_store.js';
import { accountRead, accountRpc } from './account_state.js';
import { fixture, identity, session, request } from './fixture-account.mjs';

const acquisition = { marketingSource: 'yandex', marketingMedium: 'organic', marketingCampaign: 'exam',
  marketingContent: 'article_cta', landingPage: '/blog/bilety-temy-ili-ekzamen-pdd/',
  referrerHost: 'yandex.ru', attributionMethod: 'web_referrer' };

test('attribution snapshots are sanitized together and first known/direct sources stay immutable', () => {
  assert.deepEqual(mergeAcquisition(acquisition, { marketingSource: 'instagram', landingPage: '/links/' }), acquisition);
  assert.equal(mergeAcquisition({ marketingSource: 'direct' }, acquisition).marketingSource, 'direct');
  assert.deepEqual(mergeAcquisition({ marketingSource: '__proto__' }, acquisition), acquisition);
  const clean = acquisitionFields({ marketingSource: '__proto__', marketingCampaign: 'toString',
    marketingContent: '<script>', marketingMedium: 'constructor', landingPage: '//evil.test/path', referrerHost: 'user:pass@host', attributionMethod: 'guessed' });
  assert.equal(clean.marketingSource, 'unknown');
  for (const [key, value] of Object.entries(clean)) if (key !== 'marketingSource') assert.equal(value, '');
  assert.equal(acquisitionFields({ landingPage: '/blog/article/?email=secret#token' }).landingPage, '/blog/article/');
});

test('server redirects keep article/search tags through real /app, Play and RuStore destinations', async () => {
  for (const target of ['web', 'gplay', 'rustore']) {
    const url = new URL('https://fixture.invalid/go/' + target);
    for (const [key, value] of Object.entries({ utm_source: 'yandex', utm_medium: 'organic', utm_campaign: 'exam', landing_page: acquisition.landingPage, referrer_host: 'yandex.ru' })) url.searchParams.set(key, value);
    const response = await worker.fetch(new Request(url, { headers: { 'user-agent': 'Googlebot' } }), {});
    assert.equal(response.status, 302);
    const destination = new URL(response.headers.get('location'));
    const tags = target === 'web' ? destination.searchParams : new URLSearchParams(destination.searchParams.get(target === 'rustore' ? 'referrerId' : 'referrer'));
    assert.equal(tags.get('utm_source'), 'yandex'); assert.equal(tags.get('utm_medium'), 'organic');
    assert.equal(tags.get('landing_page'), acquisition.landingPage);
    if (target === 'web') assert.equal(destination.origin + destination.pathname, 'https://pdd-drive.ru/app/');
  }
  assert.equal(new URL(attributedDestination('https://pdd-drive.ru/app/', 'google_play_organic', '')).searchParams.get('utm_source'), 'google_play_organic');
  assert.equal(new URL(attributedDestination('https://pdd-drive.ru/app/', 'google', '')).searchParams.get('utm_medium'), 'referral', 'a Google link tag alone does not prove search');
  assert.equal(new URL(attributedDestination('https://pdd-drive.ru/app/', 'chatgpt', '')).searchParams.get('utm_medium'), 'ai');
  const noGuess = acquisitionFields({ installStore: 'App Store' });
  assert.equal(noGuess.marketingSource, 'unknown');
});

test('source survives durable sync, stale KV, another device and restart, and reaches authoritative summary', async () => {
  const { env, restart } = fixture(); const token = await session(env);
  assert.equal((await worker.fetch(request('/api/user/sync', { ...identity(), platform: 'web', ...acquisition }, token), env)).status, 200);
  await env.INSTALLS.put('user:google_123', JSON.stringify({ ...identity(), marketingSource: 'instagram' }), { metadata: { ...identity(), v: 4 } });
  restart('google_123');
  assert.equal((await worker.fetch(request('/api/user/sync', { id: 'google_123', platform: 'ios', marketingSource: 'instagram', landingPage: '/links/', hasPaidPurchase: true, purchaseEvidenceKnown: true }, token), env)).status, 200);
  const saved = JSON.parse(await accountRead(env, 'google_123', 'user:google_123'));
  assert.deepEqual(acquisitionFields(saved), acquisition);
  assert.equal(userSummary(saved).hasPaidPurchase, false, 'client cannot forge buyer evidence');
  const summary = (await (await accountRpc(env, 'google_123', '/_account/metadata')).json()).summary;
  assert.deepEqual(acquisitionFields(summary), acquisition);
  // List enrichment must use authoritative DO fields, not an old KV profile.
  const listed = await listUserSummaries(env);
  assert.equal(listed[0].marketingSource, 'yandex');
});

test('KV summary budget preserves source and buyer proof; event sanitization keeps context without secrets', () => {
  const full = { ...identity('apple_' + '1'.repeat(200)), ...acquisition, name: 'Ю'.repeat(60), email: 'ю'.repeat(80),
    avatarUrl: 'https://example.com/' + 'a'.repeat(260), ipCity: 'К'.repeat(100), ipRegion: 'К'.repeat(100),
    verifiedPurchase: { store: 'appstore', evidenceVersion: 1, environment: 'Production', paid: true } };
  const summary = userSummary(full);
  assert.ok(Buffer.byteLength(JSON.stringify(summary)) <= 1024);
  assert.equal(summary.marketingSource, 'yandex'); assert.equal(summary.hasPaidPurchase, true);
  const event = sanitizeAnalyticsEvent({ ...acquisition, type: 'click', source: 'yandex', path: '/blog/article/', referrer: 'https://yandex.ru/?private=value', purchaseToken: 'secret' });
  assert.equal(event.landingPage, acquisition.landingPage); assert.equal(event.referrerHost, 'yandex.ru');
  assert.equal(event.purchaseToken, undefined); assert.equal(event.referrer, undefined);
});
