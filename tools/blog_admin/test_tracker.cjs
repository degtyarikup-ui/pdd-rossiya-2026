// Referral attribution and conversion goals without a browser/network.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const script = fs.readFileSync(path.join(__dirname, '../../web_landing/ru/assets/tracker.js'), 'utf8');

function run(referrer, search = '', saved) {
  const events = [], goals = [], handlers = {};
  const storage = new Map(saved ? [['pdd_attr_v1', JSON.stringify(saved)]] : []);
  const document = {
    referrer, readyState: 'loading',
    addEventListener(name, callback) { handlers[name] = callback; }
  };
  const location = {search, pathname: '/blog/example/', hostname: 'pdd-drive.ru'};
  const window = {location, ym(...args) { goals.push(args); }};
  const navigator = {userAgent: 'Test browser', sendBeacon(endpoint, body) { events.push(JSON.parse(body)); }};
  const sessionStorage = {getItem: key => storage.get(key) || null, setItem: (key, value) => storage.set(key, value)};
  vm.runInNewContext(script, {window, document, navigator, sessionStorage, URL, URLSearchParams, setTimeout});
  return {events, goals, handlers, storage};
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
