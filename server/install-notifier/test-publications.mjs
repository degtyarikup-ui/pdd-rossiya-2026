import test from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizePublications, filterPublications, summarizePublications,
  publicationDay, publicationTime, publicationMskToIso, PUBLICATIONS_DATA_CLIENT_JS,
} from './publications_data.js';

const now = Date.parse('2026-10-07T09:00:00Z');

test('Moscow dates and datetime-local conversions work across UTC midnight', () => {
  assert.equal(publicationDay('2026-10-07T20:59:59Z'), '2026-10-07');
  assert.equal(publicationDay('2026-10-07T21:00:00Z'), '2026-10-08');
  assert.equal(publicationTime('2026-10-07T21:00:00Z'), '00:00');
  assert.equal(publicationMskToIso('2026-10-08T00:15'), '2026-10-07T21:15:00.000Z');
  assert.equal(publicationDay('2026-10-08'), '2026-10-08');
  assert.equal(publicationMskToIso('2026-02-30T10:00'), null);
  assert.equal(publicationMskToIso('2026-10-08T24:00'), null);
  assert.equal(publicationDay('2026-02-30T10:00:00Z'), null);
  assert.equal(publicationDay('bad date'), null);
});

test('blog past dates are plan metadata, not verified releases or failed posts', () => {
  const items = normalizePublications({ blog: [
    { slug: 'yesterday', title: 'Вчера', datePublished: '2026-10-06', published: true, cover: 'cover.jpg' },
    { slug: 'today', datePublished: '2026-10-07', published: true },
    { slug: 'future', datePublished: '2026-10-08', published: true },
    { slug: 'draft', datePublished: '2026-10-09', published: false },
    { slug: 'invalid', datePublished: '2026-02-30' },
  ] }, { now });
  assert.deepEqual(items.map(item => item.status), ['dated', 'scheduled', 'scheduled', 'draft', 'draft']);
  assert.ok(items.every(item => item.publicationVerified === false));
  assert.ok(items.every(item => item.time === null));
  assert.equal(items[0].thumbnail, 'https://pdd-drive.ru/blog/yesterday/cover.jpg');
  assert.equal(items[0].publishedAt, null);
  const summary = summarizePublications(items, { now });
  assert.equal(summary.today, 1, 'today is still part of the blog plan');
  assert.equal(summary.next7Days, 2, 'the seven-day window includes today');
  assert.equal(summary.counts.published, 0);
});

test('blog plan changes from scheduled to dated at Moscow midnight and preserves drafts', () => {
  const source = { blog: [
    { slug: 'today', datePublished: '2026-10-08', published: true },
    { slug: 'draft', datePublished: '2026-10-08', published: false },
  ] };
  const before = normalizePublications(source, { now: '2026-10-08T20:59:59Z' });
  const after = normalizePublications(source, { now: '2026-10-08T21:00:00Z' });
  assert.deepEqual(before.map(item => item.status), ['scheduled', 'draft']);
  assert.deepEqual(after.map(item => item.status), ['dated', 'draft']);
});

test('legacy sent-to-Telegram posts are not reported as published in Threads', () => {
  const [item] = normalizePublications({ threads: { posts: [
    { id: 'legacy', text: 'Отправлен для ручного постинга', status: 'sent_to_tg', scheduledDate: '2026-10-08' },
  ] } }, { now });
  assert.equal(item.status, 'queued');
  assert.equal(item.publishedAt, null);
  assert.equal(item.legacyDate, '2026-10-08');
  assert.equal(item.scheduleMode, 'none');
});

test('Threads legacy dates do not invent an executable schedule', () => {
  const items = normalizePublications({ threads: { posts: [
    { id: 'legacy', text: 'Старая дата', scheduledDate: '2026-10-09' },
    { id: 'new', text: 'План', scheduledAt: '2026-10-08T07:00:00Z' },
    { id: 'old', text: 'Просрочено', scheduledAt: '2026-10-07T07:00:00Z' },
    { id: 'done', status: 'published', scheduledAt: '2026-10-08T07:00:00Z', publishedAt: '2026-10-07T08:00:00Z' },
  ] } }, { now });
  assert.equal(items[0].status, 'queued');
  assert.equal(items[0].date, null);
  assert.equal(items[0].legacyDate, '2026-10-09');
  assert.equal(items[0].scheduleMode, 'none');
  assert.equal(items[1].time, '10:00');
  assert.equal(items[2].overdue, true);
  assert.equal(items[3].date, '2026-10-07');
  assert.equal(items[3].overdue, false);
});

test('undated videos remain automatic and partial failures preserve destination state', () => {
  const sources = { social: {
    accounts: [{ id: 'active', name: 'Россия', active: true, postTime: '19:00', targets: ['instagram', 'youtube'] },
      { id: 'paused', active: false, postTime: '14:00' }],
    posts: [
      { id: 'automatic', accountId: 'active', title: 'Без даты', streamToken: 'safe_token', status: 'queued' },
      { id: 'partial', accountId: 'active', targets: ['instagram', 'youtube'], status: 'failed', instagramStatus: 'published', youtubeStatus: 'failed', error: 'Сбой YouTube' },
      { id: 'paused', accountId: 'paused', scheduledAt: '2026-10-06T07:00:00Z', status: 'queued' },
      { id: 'missing', accountId: 'removed', status: 'queued' },
    ],
  } };
  const before = structuredClone(sources);
  const items = normalizePublications(sources, { now });
  assert.deepEqual(sources, before, 'normalization must not change the publishing queues');
  assert.equal(items[0].status, 'queued');
  assert.equal(items[0].scheduleMode, 'automatic');
  assert.equal(items[0].date, null);
  assert.equal(items[0].autoTime, '19:00');
  assert.equal(items[0].thumbnail, '/s/t/safe_token');
  assert.equal(items[1].status, 'failed');
  assert.equal(items[1].partialPublished, true);
  assert.deepEqual(items[1].channelStatuses, { instagram: 'published', youtube: 'failed' });
  assert.equal(items[2].paused, true);
  assert.equal(items[2].overdue, false);
  assert.equal(items[3].error, 'Аккаунт удалён');
});

test('channel, status, text and inclusive date filters combine without losing destinations', () => {
  const items = normalizePublications({ blog: [{ slug: 'b', title: 'Статья', datePublished: '2026-10-08' }],
    threads: { posts: [{ id: 't', text: 'Вопрос про знаки', scheduledAt: '2026-10-07T21:00:00Z' }, { id: 'u', text: 'Без даты' }] },
    social: { accounts: [{ id: 'a', active: true, name: 'ПДД Россия' }], posts: [
      { id: 's', accountId: 'a', title: 'Знаки', targets: ['youtube', 'instagram', 'youtube'], scheduledAt: '2026-10-08T08:00:00Z' },
      { id: 'f', accountId: 'a', status: 'failed' },
    ] },
  }, { now });
  const options = { channel: 'youtube', status: 'scheduled', query: 'РОССИЯ', dateFrom: '2026-10-08', dateTo: '2026-10-08' };
  assert.deepEqual(filterPublications(items, options).map(item => item.id), ['social:s']);
  assert.deepEqual(filterPublications(items, { dateFrom: '2026-10-08', dateTo: '2026-10-08' }).map(item => item.id), ['blog:b', 'threads:t', 'social:s']);
  assert.equal(filterPublications(items, { dateFrom: '2026-10-08', includeUndated: true }).length, 5);
  assert.equal(filterPublications(items, { status: 'failed' }).length, 1);
  assert.equal(filterPublications(items, { query: 'Несуществующая строка' }).length, 0);
  const summary = summarizePublications(items, { now });
  assert.equal(summary.total, 5);
  assert.equal(summary.channels.youtube, 2);
  assert.equal(summary.next7Days, 3);
  assert.equal(summary.undated, 2);
  assert.equal(summary.attention, 1);
});

test('client source uses the same normalization and blocks unsafe media URLs', () => {
  const client = new Function(PUBLICATIONS_DATA_CLIENT_JS + '\nreturn {normalizePublications, filterPublications, publicationMskToIso};')();
  const source = { threads: { posts: [{ id: 'unsafe', imageUrl: 'javascript:alert(1)', permalink: '//untrusted.test/x', text: 'Тест' }] } };
  assert.deepEqual(client.normalizePublications(source, { now }), normalizePublications(source, { now }));
  assert.equal(client.normalizePublications(source, { now })[0].thumbnail, null);
  assert.equal(client.normalizePublications(source, { now })[0].permalink, null);
  assert.equal(client.publicationMskToIso('2026-10-07T10:00'), '2026-10-07T07:00:00.000Z');
  assert.deepEqual(normalizePublications({ blog: 'bad', threads: { posts: {} }, social: null }, { now }), []);
});

test('worker renders one publications navigation and all editor workspaces with compiling client', async () => {
  const {default:worker}=await import('./worker.js');
  const response=await worker.fetch(new Request('https://w.test/admin'),{});
  const html=await response.text();
  assert.equal(response.status,200);
  assert.equal((html.match(/data-feature="publications"/g)||[]).length,1);
  assert.doesNotMatch(html,/data-feature="(?:blog|threads|social)"/);
  for(const view of ['publications','blog','threads','social'])assert.equal((html.match(new RegExp('id="'+view+'-view"','g'))||[]).length,1);
  assert.match(html,/id="blog-upcoming-count"/);
  for(const script of html.matchAll(/<script>([\s\S]*?)<\/script>/g))assert.doesNotThrow(()=>new Function(script[1]));
});

test('full blog plan API requires auth and changing a date preserves other article fields', async () => {
  const {default:worker}=await import('./worker.js');
  const original=[{slug:'past',title:'Прошедшая',datePublished:'2026-09-01',published:true},{slug:'future',title:'Будущая',datePublished:'2026-11-01',published:true}];
  const data=new Map([['blog_articles',JSON.stringify(original)]]);
  const env={ADMIN_PASSWORD:'test-password',INSTALLS:{get:async key=>data.get(key)||null,put:async(key,value)=>data.set(key,value)}};
  const req=(path,method='GET',body,auth=true)=>new Request('https://w.test'+path,{method,headers:{...(auth?{authorization:'Bearer test-password'}:{}),'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
  assert.equal((await worker.fetch(req('/api/admin/blog','GET',null,false),env)).status,401);
  assert.deepEqual(await (await worker.fetch(req('/api/admin/blog'),env)).json(),original);
  assert.equal((await worker.fetch(req('/api/admin/blog/future','PUT',{datePublished:'2026-11-03'}),env)).status,200);
  const saved=JSON.parse(data.get('blog_articles'));
  assert.deepEqual(saved[0],original[0]);assert.deepEqual(saved[1],{...original[1],datePublished:'2026-11-03'});
});

test('Threads date editing preserves published status when a planner snapshot is stale', async () => {
  const {default:worker}=await import('./worker.js');
  const data=new Map([['threads_queue',JSON.stringify([{id:'done',text:'Уже вышел',status:'published',publishedAt:'2026-10-07T07:00:00Z'}])]]);
  const env={ADMIN_PASSWORD:'test-password',INSTALLS:{get:async key=>data.get(key)||null,put:async(key,value)=>data.set(key,value)}};
  const request=new Request('https://w.test/api/admin/threads/update',{method:'POST',headers:{authorization:'Bearer test-password','content-type':'application/json'},body:JSON.stringify({id:'done',scheduledAt:'2026-11-01T07:00:00Z'})});
  assert.equal((await worker.fetch(request,env)).status,200);
  assert.equal(JSON.parse(data.get('threads_queue'))[0].status,'published');
});
