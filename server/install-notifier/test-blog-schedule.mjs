import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { handlePublicBlogSchedule, publicBlogSchedule } from './blog_schedule.js';

const article = {slug: 'example', datePublished: '2026-10-23', published: true, title: 'Private draft title', bodyHtml: 'Private draft content'};
const request = () => new Request('https://w.test/api/blog/schedule');

test('public schedule exposes only versioned publication fields and never caches drafts', async () => {
  const response = await handlePublicBlogSchedule(request(), {INSTALLS: {get: async () => JSON.stringify([article])}});
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('x-robots-tag'), 'noindex');
  assert.deepEqual(await response.json(), {schema: 1, complete: true, count: 1, articles: [{slug: 'example', datePublished: '2026-10-23', published: true}]});
});

test('missing or invalid KV schedule stops builds instead of returning fallback dates', async () => {
  for (const value of [null, 'not json', '{}', JSON.stringify([{...article, datePublished: '2026-02-30'}]), JSON.stringify([article, article])]) {
    const response = await handlePublicBlogSchedule(request(), {INSTALLS: {get: async () => value}});
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), {error: 'blog schedule unavailable'});
  }
  assert.deepEqual(publicBlogSchedule([]), {schema: 1, complete: true, count: 0, articles: []});
});

test('worker route reflects authenticated admin reschedules and deletions without exposing metadata', async () => {
  const {default: worker} = await import('./worker.js');
  const store = new Map([['blog_articles', JSON.stringify([article])]]);
  const password = randomUUID();
  const env = {ADMIN_PASSWORD: password, INSTALLS: {get: async key => store.get(key) ?? null, put: async (key, value) => store.set(key, value)}};
  const edit = (method, body) => new Request('https://w.test/api/admin/blog/example', {
    method, headers: {'Authorization': 'Bearer ' + password, 'Content-Type': 'application/json'},
    ...(body ? {body: JSON.stringify(body)} : {}),
  });
  assert.equal((await worker.fetch(edit('PUT', {datePublished: '2026-10-29'}), env)).status, 200);
  let schedule = await (await worker.fetch(request(), env)).json();
  assert.equal(schedule.articles[0].datePublished, '2026-10-29');
  assert.equal(schedule.articles[0].title, undefined);
  assert.equal((await worker.fetch(edit('DELETE'), env)).status, 200);
  schedule = await (await worker.fetch(request(), env)).json();
  assert.deepEqual(schedule.articles, []);
});
