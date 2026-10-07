import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { BLOG_CLIENT_JS, BLOG_VIEW_HTML } from './blog_ui.js';

function harness(initial) {
  const fixture = structuredClone(initial);
  const requests = [], events = [], toasts = [], nodes = new Map();
  const filters = ['upcoming', 'past', 'all'].map(filter => ({
    dataset: {blogFilter:filter}, classList: {toggle() {}}, setAttribute() {}, addEventListener() {},
  }));
  function node(id) {
    if (!nodes.has(id)) nodes.set(id, {
      id, textContent: '', innerHTML: '', value: '', hidden: true, disabled: false,
      listeners: {}, addEventListener(type, fn) { this.listeners[type] = fn; },
      querySelectorAll() { return filters; },
    });
    return nodes.get(id);
  }
  class FixedDate extends Date {
    constructor(...args) { super(...(args.length ? args : ['2026-10-07T12:00:00.000Z'])); }
  }
  const context = {
    Intl, Date:FixedDate, console,
    document: {getElementById:node, querySelectorAll() { return filters; }, dispatchEvent(event) { events.push(event); }},
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options.detail; } },
    confirm() { return true; },
    adminEsc(value) { return String(value ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); },
    adminToast(message, isError) { toasts.push({message,isError}); },
    async adminFetchJson(url, options = {}) {
      requests.push({url, ...options});
      if (context.failNext && options.method) { context.failNext = false; throw new Error('network failed'); }
      if (!options.method) return structuredClone(fixture);
      if (options.method === 'PUT') {
        const slug = decodeURIComponent(url.split('/').pop());
        Object.assign(fixture.find(a => a.slug === slug), JSON.parse(options.body));
      } else if (url.endsWith('/reorder')) {
        JSON.parse(options.body).changes.forEach(change => Object.assign(fixture.find(a => a.slug === change.slug), change));
      } else if (options.method === 'DELETE') {
        const slug = decodeURIComponent(url.split('/').pop());
        const index = fixture.findIndex(a => a.slug === slug);
        if (index >= 0) fixture.splice(index, 1);
      }
      return {ok:true};
    },
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(BLOG_CLIENT_JS, context);
  return {context, node, requests, events, toasts, fixture};
}

const articles = [
  {slug:'past',title:'Прошедшая статья',datePublished:'2026-10-06',cover:'cover.jpg'},
  {slug:'today',title:'Сегодняшняя статья',datePublished:'2026-10-07',cover:'cover.jpg'},
  {slug:'future',title:'Будущая статья',datePublished:'2026-10-09',cover:'cover.jpg'},
];

test('blog workspace compiles and uses explicit save with accessible controls', () => {
  assert.doesNotThrow(() => new Function(BLOG_CLIENT_JS));
  assert.match(BLOG_VIEW_HTML, /id="blog-view"/);
  assert.match(BLOG_VIEW_HTML, /aria-label="Поиск статей"/);
  assert.match(BLOG_VIEW_HTML, /\.bl-date-actions\[hidden\]/);
});

test('all article data loads once and filters include today in the plan', async () => {
  const h = harness(articles);
  await h.context.loadBlogArticles();
  assert.equal(h.requests[0].url, '/api/admin/blog');
  assert.equal(h.node('blog-upcoming-count').textContent, 2);
  assert.equal(h.node('blog-past-count').textContent, 1);
  assert.deepEqual(Array.from(h.context.blVisibleArticles(), a => a.slug), ['today','future']);
  h.context.blState.filter = 'past';
  assert.deepEqual(Array.from(h.context.blVisibleArticles(), a => a.slug), ['past']);
  h.context.blState.filter = 'all';
  h.context.blState.search = 'будущая';
  assert.deepEqual(Array.from(h.context.blVisibleArticles(), a => a.slug), ['future']);
});

test('article content, URLs and attributes escape values from stored metadata', async () => {
  const h = harness([{slug:'unsafe"<slug>', title:'<script>alert(1)</script>', description:'<img src=x onerror=alert(2)>', cover:'cover".jpg', datePublished:'2026-10-09'}]);
  await h.context.loadBlogArticles();
  const html = h.node('blog-articles-container').innerHTML;
  assert.doesNotMatch(html, /<script>|<img src=x/);
  assert.match(html, /&lt;script&gt;/);
  assert.match(html, /unsafe&quot;&lt;slug&gt;/);
  assert.match(html, /unsafe%22%3Cslug%3E/);
  assert.match(html, /cover%22\.jpg/);
});

test('date save patches one article and notifies the unified calendar', async () => {
  const h = harness(articles);
  await h.context.loadBlogArticles();
  h.node('date-future').value = '2026-10-12';
  h.context.blState.drafts.future = '2026-10-12';
  await h.context.updateArticleDate('future');
  const writes = h.requests.filter(r => r.method);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].method, 'PUT');
  assert.deepEqual(JSON.parse(writes[0].body), {datePublished:'2026-10-12'});
  assert.equal(h.fixture.find(a => a.slug === 'future').datePublished, '2026-10-12');
  assert.equal(h.events.length, 1);
  assert.equal(h.events[0].type, 'pdd:publications-changed');
  assert.equal(h.events[0].detail.channel, 'blog');
  assert.equal(h.context.blState.drafts.future, undefined);
});

test('failed date save retains the original date and draft without success event', async () => {
  const h = harness(articles);
  await h.context.loadBlogArticles();
  h.node('date-future').value = '2026-10-12';
  h.context.blState.drafts.future = '2026-10-12';
  h.context.failNext = true;
  await h.context.updateArticleDate('future');
  assert.equal(h.fixture.find(a => a.slug === 'future').datePublished, '2026-10-09');
  assert.equal(h.context.blState.drafts.future, '2026-10-12');
  assert.equal(h.events.length, 0);
  assert.equal(h.toasts.at(-1).isError, true);
  assert.equal(h.context.blState.busy, false);
});

test('reorder swaps dates through one atomic request', async () => {
  const h = harness(articles);
  await h.context.loadBlogArticles();
  await h.context.swapArticle(1,2);
  const writes = h.requests.filter(r => r.method);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].url, '/api/admin/blog/reorder');
  assert.deepEqual(JSON.parse(writes[0].body), {changes:[{slug:'today',datePublished:'2026-10-09'},{slug:'future',datePublished:'2026-10-07'}]});
  assert.equal(h.fixture.find(a => a.slug === 'future').datePublished, '2026-10-07');
  assert.equal(h.events.length, 1);
});
