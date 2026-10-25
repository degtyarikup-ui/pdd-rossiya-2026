// Referral attribution and conversion goals without a browser/network.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const script = fs.readFileSync(path.join(__dirname, '../../web_landing/ru/assets/tracker.js'), 'utf8');

function run(referrer, search = '', saved, options = {}) {
  const events = [], goals = [], handlers = {}, requests = [], redirects = [];
  const storage = new Map(saved ? [['pdd_attr_v1', JSON.stringify(saved)]] : []);
  const local = options.local || new Map();
  const links = options.links || [];
  const document = {
    referrer, readyState: 'loading', documentElement: {},
    querySelectorAll() { return links; },
    addEventListener(name, callback) { handlers[name] = callback; }
  };
  const location = {search, pathname: options.pathname || '/blog/example/', hostname: 'pdd-drive.ru',
    replace(url) { redirects.push(url); }};
  location.href = 'https://' + location.hostname + location.pathname + search;
  const window = {location, ym(...args) { goals.push(args); }};
  const navigator = {userAgent: 'Test browser', sendBeacon(endpoint, body) {
    if (options.beaconThrows) throw new Error('unavailable');
    if (options.beaconRejected) return false;
    events.push(JSON.parse(body));
    return true;
  }};
  const sessionStorage = {getItem: key => storage.get(key) || null, setItem: (key, value) => storage.set(key, value)};
  const localStorage = {getItem: key => local.get(key) || null, setItem: (key, value) => local.set(key, value)};
  let mutation;
  class MutationObserver {
    constructor(callback) { mutation = callback; }
    observe() {}
  }
  const fetch = (url, options) => { requests.push({url, ...options}); return Promise.resolve({}); };
  vm.runInNewContext(script, {window, document, navigator, sessionStorage, localStorage, URL, URLSearchParams, setTimeout, fetch, MutationObserver});
  return {events, goals, handlers, storage, local, requests, redirects, links, mutation};
}

function anchor(href, attributes = {}) {
  return {tagName: 'A', href, getAttribute(name) { return attributes[name] || null; }};
}

test('search and AI referrers remain distinct; lookalike domains are not trusted', () => {
  for (const [referrer, source, medium] of [
    ['https://chatgpt.com/c/123', 'chatgpt', 'ai'],
    ['https://chat.openai.com/', 'chatgpt', 'ai'],
    ['https://www.perplexity.ai/search/123', 'perplexity', 'ai'],
    ['https://copilot.microsoft.com/', 'copilot', 'ai'],
    ['https://gemini.google.com/app', 'gemini', 'ai'],
    ['https://claude.ai/chat/123', 'claude', 'ai'],
    ['https://www.bing.com/search?q=pdd', 'bing', 'organic'],
    ['https://www.google.com/search?q=pdd', 'google', 'organic'],
    ['https://www.google.com.au/search?q=pdd', 'google', 'organic'],
    ['https://www.google.co.in/search?q=pdd', 'google', 'organic'],
    ['https://yandex.ru/search/?text=pdd', 'yandex', 'organic'],
    ['https://google.com.attacker.example/', 'other', 'referral'],
    ['https://not.me/', 'other', 'referral']
  ]) {
    const {events} = run(referrer);
    assert.equal(events[0].source, source, referrer);
    assert.equal(events[0].medium, medium, referrer);
  }
});

test('explicit campaign wins and internal navigation preserves the original source', () => {
  const fromQuery = run('https://google.com/', '?utm_source=chatgpt.com&utm_medium=ai&utm_campaign=exam');
  assert.equal(fromQuery.events[0].source, 'chatgpt');
  assert.equal(fromQuery.events[0].campaign, 'exam');
  const internal = run('https://pdd-drive.ru/blog/', '', {source: 'bing', campaign: 'referrer', medium: 'organic'});
  assert.equal(internal.events[0].source, 'bing');
  assert.equal(internal.events[0].medium, 'organic');
});

test('article CTA emits a click goal and keeps attribution on the web app link', () => {
  const result = run('https://chatgpt.com/');
  const link = {
    tagName: 'A', href: 'https://pdd-drive.ru/app/',
    getAttribute(name) { return {'data-cta': 'article-practice', 'data-context': 'example'}[name]; }
  };
  result.handlers.click({target: link});
  assert.equal(result.goals[0][2], 'article_practice_click');
  assert.equal(result.goals[0][3].article, 'example');
  assert.equal(result.events[1].type, 'click');
  assert.equal(result.events[1].target, 'web');
  assert.equal(result.events[1].source, 'chatgpt');
  assert.equal(new URL(link.href).searchParams.get('utm_source'), 'chatgpt');
  assert.equal(new URL(link.href).searchParams.get('utm_medium'), 'ai');
});


test('first acquisition and article entry survive later external visits and campaigns', () => {
  const first = run('https://yandex.ru/search/?text=private+query', '', undefined, {pathname: '/blog/entry/'});
  const later = run('https://instagram.com/', '?utm_source=instagram&utm_campaign=later', undefined,
    {local: first.local, pathname: '/blog/second/'});
  const link = anchor('/app/?mode=exam#training');
  later.handlers.click({target: link});
  const destination = new URL(link.href);
  assert.equal(later.events[0].source, 'yandex');
  assert.equal(later.events[1].path, '/blog/second/');
  assert.equal(later.events[1].landingPage, '/blog/entry/');
  assert.equal(destination.searchParams.get('utm_source'), 'yandex');
  assert.equal(destination.searchParams.get('utm_medium'), 'organic');
  assert.equal(destination.searchParams.get('landing_page'), '/blog/entry/');
  assert.equal(destination.searchParams.get('referrer_host'), 'yandex.ru');
  assert.equal(destination.searchParams.get('mode'), 'exam');
  assert.equal(destination.hash, '#training');
  assert.ok(!JSON.stringify([...first.local.values(), later.events]).includes('private'));
});

test('direct first visit stays direct after a tagged return', () => {
  const first = run('');
  const later = run('https://google.com/', '?utm_source=threads', undefined, {local: first.local});
  assert.equal(first.events[0].source, 'direct');
  assert.equal(later.events[0].source, 'direct');
  const link = anchor('https://play.google.com/store/apps/details?id=ru.pdd.pdd_app');
  later.handlers.click({target: link});
  const tags = new URLSearchParams(new URL(link.href).searchParams.get('referrer'));
  assert.equal(tags.get('utm_source'), 'direct');
  assert.equal(tags.get('landing_page'), '/blog/example/');
});

test('campaign/content and entry context cross Google Play without losing app ID', () => {
  const result = run('', '?utm_source=ig&utm_medium=paid_social&utm_campaign=fall&utm_content=hero&landing_page=%2Fblog%2Fentry%2F&referrer_host=instagram.com');
  const link = anchor('https://play.google.com/store/apps/details?id=ru.pdd.pdd_app&hl=ru');
  result.handlers.click({target: link});
  const destination = new URL(link.href), tags = new URLSearchParams(destination.searchParams.get('referrer'));
  assert.equal(destination.searchParams.get('id'), 'ru.pdd.pdd_app');
  assert.equal(destination.searchParams.get('hl'), 'ru');
  assert.equal(tags.get('utm_source'), 'instagram');
  assert.equal(tags.get('utm_medium'), 'paid_social');
  assert.equal(tags.get('utm_campaign'), 'fall');
  assert.equal(tags.get('utm_content'), 'hero');
  assert.equal(tags.get('landing_page'), '/blog/entry/');
  assert.equal(tags.get('referrer_host'), 'instagram.com');
  assert.equal(result.events[1].content, 'hero');
});

test('all redirect pages use the same first-touch tagging as article links', () => {
  for (const pathname of ['/go/web/', '/go/gplay/', '/go/appstore/', '/go/rustore/', '/go/web/index.html']) {
    const result = run('', '?ref=threads_launch', undefined, {pathname});
    assert.equal(result.redirects.length, 1, pathname);
    assert.equal(result.events[1].type, 'click');
    assert.equal(result.events[1].source, 'threads');
    const destination = new URL(result.redirects[0]);
    if (pathname.includes('web')) assert.equal(destination.searchParams.get('utm_source'), 'threads');
    if (pathname.includes('gplay')) assert.equal(new URLSearchParams(destination.searchParams.get('referrer')).get('utm_campaign'), 'launch');
    if (pathname.includes('appstore')) assert.equal(destination.searchParams.get('ct'), 'launch');
    if (pathname.includes('rustore')) assert.equal(new URLSearchParams(destination.searchParams.get('referrerId')).get('utm_source'), 'threads');
  }
});

test('untrusted URL substrings and lookalike stores never receive tracking tags', () => {
  const result = run('', '?ref=threads');
  for (const href of ['https://evil.example/app/', 'https://play.google.com.evil.example/',
    'https://evil.example/?next=https://play.google.com', 'https://pdd-drive.ru/application/']) {
    const link = anchor(href);
    result.handlers.click({target: link});
    assert.equal(link.href, href);
  }
  assert.equal(result.events.length, 1);
});

test('static, dynamically inserted and middle-clicked app links retain attribution', () => {
  const first = anchor('/app/');
  const result = run('https://duckduckgo.com/?q=pdd', '', undefined, {links: [first]});
  assert.equal(new URL(first.href).searchParams.get('utm_source'), 'duckduckgo');
  const dynamic = anchor('/app/?mode=topics');
  result.links.push(dynamic);
  result.mutation();
  assert.equal(new URL(dynamic.href).searchParams.get('utm_medium'), 'organic');
  result.handlers.auxclick({type: 'auxclick', button: 1, target: dynamic});
  assert.equal(result.events[1].target, 'web');
  result.handlers.auxclick({type: 'auxclick', button: 2, target: dynamic});
  assert.equal(result.events.length, 2);
});

test('rejected or throwing beacons fall back to a navigation-safe fetch', () => {
  for (const options of [{beaconRejected: true}, {beaconThrows: true}]) {
    const result = run('https://google.com/', '', undefined, options);
    assert.equal(result.requests.length, 1);
    assert.equal(result.requests[0].keepalive, true);
    assert.equal(result.requests[0].headers['content-type'], 'text/plain;charset=UTF-8');
    assert.equal(JSON.parse(result.requests[0].body).source, 'google');
  }
});

test('malformed metadata is dropped; explicit Google tags alone do not prove organic search', () => {
  const result = run('', '?utm_source=google&utm_campaign=constructor&utm_content=%3Cscript%3E&landing_page=%2F%2Fevil.example&referrer_host=%3Cbad%3E');
  const event = result.events[0];
  assert.equal(event.source, 'google');
  assert.equal(event.medium, 'referral');
  assert.equal(event.campaign, '');
  assert.equal(event.content, '');
  assert.equal(event.landingPage, '/blog/example/');
  assert.equal(event.referrerHost, '');
});

test('landing and quiz/tariff CTAs load the shared tracker; blog source template includes it', () => {
  const root = path.join(__dirname, '../../web_landing/ru');
  for (const page of ['index.html', 'proverit-znaniya/index.html', 'tarify/index.html',
    'go/web/index.html', 'go/gplay/index.html', 'go/appstore/index.html', 'go/rustore/index.html']) {
    assert.match(fs.readFileSync(path.join(root, page), 'utf8'), /src="\/assets\/tracker\.js"/, page);
  }
  assert.match(fs.readFileSync(path.join(__dirname, 'generator.py'), 'utf8'), /src="\/assets\/tracker\.js"/);
});


test('RuStore SDK referrerId carries article and campaign context', () => {
  const link = anchor('https://www.rustore.ru/catalog/app/ru.pdd.pdd_app');
  const result = run('https://google.com/search?q=pdd', '?utm_source=threads&utm_campaign=launch&utm_content=reel42', undefined, {links: [link]});
  const tags = new URLSearchParams(new URL(link.href).searchParams.get('referrerId'));
  assert.equal(tags.get('utm_source'), 'threads');
  assert.equal(tags.get('utm_campaign'), 'launch');
  assert.equal(tags.get('utm_content'), 'reel42');
  assert.equal(tags.get('landing_page'), '/blog/example/');
  result.handlers.click({target: link});
  assert.equal(result.events[1].target, 'rustore');
});


test('OAuth providers do not masquerade as search acquisitions', () => {
  for (const referrer of ['https://accounts.google.com/', 'https://oauth.yandex.ru/authorize',
    'https://id.yandex.ru/', 'https://appleid.apple.com/auth/authorize']) {
    const result = run(referrer);
    assert.equal(result.events[0].source, 'direct', referrer);
    assert.equal(result.events[0].referrerHost, '', referrer);
  }
});
