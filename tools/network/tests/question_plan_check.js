// Exercise the actual backlog module: selection opens the editor and never writes decisions.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require.resolve('../editor/question_plan.js'), 'utf8');
const copy = value => JSON.parse(JSON.stringify(value));
const fixture = [
  { id: 'ticket_1_1', ticket: 1, number: 1, category: 'ab', question: 'Кому уступить дорогу?', decision: 'yes', status: 'plan', hasScene: false, imageUrl: '/asset/source/ab/1.webp', occurrences: [{ id: 'ticket_40_20', ticket: 40, number: 20 }] },
  { id: 'ticket_1_2', ticket: 1, number: 2, category: 'ab', question: 'Не выбран', decision: null, status: 'plan', hasScene: false },
  { id: 'ticket_1_3', ticket: 1, number: 3, category: 'ab', question: 'Отклонён', decision: 'no', status: 'plan', hasScene: false },
  { id: 'ticket_1_4', ticket: 1, number: 4, category: 'ab', question: 'Готовая сцена', decision: 'yes', status: 'game', hasScene: true },
  { id: 'ticket_1_5', ticket: 1, number: 5, category: 'ab', question: 'Дорожная задача', decision: null, status: 'game', hasScene: false },
  { id: 'ticket_1_6', ticket: 1, number: 6, category: 'ab', question: 'Вариант ИИ', decision: null, status: 'ai', hasScene: true },
  { id: 'ticket_1_7', ticket: 1, number: 7, category: 'ab', question: 'Начатый черновик', decision: null, status: 'plan', hasScene: true },
];
function mount() {
  const listeners = {}, requests = [], opened = [], storage = new Map(), urls = [];
  const home = { hidden: true };
  const App = { state: { id: 'ticket_16_15', S: { unsaved: 'author draft' }, dirty: true },
    ic: () => '', esc: value => String(value ?? '').replaceAll('<', '&lt;').replaceAll('"', '&quot;'),
    renderPanels() {}, renderHome() {}, toast: message => { App.error = message; },
    showHome: on => { home.hidden = !on; },
    async openScene(id) { opened.push(id); if (!App.cancel) { App.state.id = id; home.hidden = true; } },
    async api(url, body) { requests.push({ url, body }); assert.equal(body, undefined); return { questions: copy(fixture) }; } };
  const document = { querySelector: () => home, addEventListener(type, callback) { (listeners[type] ??= []).push(callback); } };
  const context = vm.createContext({ App, document,
    window: { history: { replaceState(_state, _title, url) { urls.push(url); } } },
    localStorage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value) } });
  vm.runInContext(source + '\nglobalThis.plan = QuestionPlan;', context);
  const plan = context.plan;
  App.showQuestions = id => plan.open(id);
  const tick = () => new Promise(resolve => setImmediate(resolve));
  const click = async id => {
    listeners.click.forEach(callback => callback({ target: { closest: selector => selector === '[data-question]' ? { dataset: { question: id } } : null } }));
    await tick();
  };
  return { App, plan, requests, opened, home, urls, listeners, click, tick };
}
(async () => {
  let ui = mount();
  const draft = JSON.stringify(ui.App.state);
  await ui.plan.open();
  assert.equal(ui.home.hidden, false, 'opening the plan shows the normal home screen');
  assert.equal(ui.urls.at(-1), '?filter=questions');
  assert.equal(JSON.stringify(ui.App.state.S), JSON.stringify({ unsaved: 'author draft' }));
  assert.equal(ui.App.state.dirty, true);
  assert.equal(ui.App.state.id, JSON.parse(draft).id);
  assert.deepEqual(Array.from(ui.plan.list(), q => q.id), ['ticket_1_1', 'ticket_1_7'], 'approved questions and started drafts remain');
  assert.equal(ui.plan.visibleCount(), 5);
  assert.equal(ui.plan.count('game'), 2);
  assert.equal(ui.plan.count('ai'), 1);
  assert.match(ui.plan.sidebarHtml(), /data-question="ticket_1_1"/);
  assert.match(ui.plan.sidebarHtml('', { filtersCollapsed: true }), /id="question-filter-options" hidden/);
  assert.doesNotMatch(ui.plan.sidebarHtml() + ui.plan.homeHtml(), /data-qr|Не просмотрен|для отбора|Да —|Нет —|Отменить решение/);
  assert.equal(ui.listeners.keydown, undefined, 'the plan has no decision shortcuts');
  ui.plan.setQuery('40 20');
  assert.equal(ui.plan.list().length, 1, 'search finds all original ticket references');
  ui.plan.setQuery('уступить');
  assert.equal(ui.plan.filterSummary().count, 1);
  ui.plan.setQuery('');
  ui.App.cancel = true;
  await ui.click('ticket_1_1');
  assert.equal(ui.App.state.id, 'ticket_16_15', 'cancelled unsaved-scene confirmation retains the draft');
  assert.equal(ui.home.hidden, false);
  ui.App.cancel = false;
  await ui.click('ticket_1_1');
  assert.equal(ui.App.state.id, 'ticket_1_1', 'one click opens the editor');
  assert.equal(ui.home.hidden, true);
  assert.equal(ui.plan.filterSummary().label, 'Не в игре');
  await ui.plan.open('ticket_1_4');
  assert.equal(ui.App.state.id, 'ticket_1_4', 'legacy question deep links open the scene directly');
  assert.equal(ui.plan.filterSummary().label, 'В игре');
  assert.match(ui.plan.sidebarHtml(), /data-question="ticket_1_5"[^>]*disabled/);
  const beforeRoad = ui.opened.length;
  await ui.plan.open('ticket_1_5');
  assert.equal(ui.opened.length, beforeRoad, 'road questions cannot generate a duplicate scene');
  assert.equal(ui.requests.length, 1, 'navigation neither creates scenes nor changes saved decisions');
  assert.deepEqual(copy(ui.App.state.questions), fixture, 'all source records and decisions remain unchanged');
  let release;
  const waiting = new Promise(resolve => { release = resolve; });
  ui.App.openScene = async id => { ui.opened.push(id); await waiting; ui.App.state.id = id; };
  const inFlight = ui.plan.open('ticket_1_1');
  await ui.tick();
  const beforeSecondClick = ui.opened.length;
  await ui.plan.open('ticket_1_7');
  assert.equal(ui.opened.length, beforeSecondClick, 'rapid clicks cannot race scene navigation');
  release(); await inFlight;
  ui = mount();
  ui.App.api = async () => { throw new Error('Server unavailable'); };
  await ui.plan.open();
  assert.match(ui.plan.homeHtml(), /data-question-retry/);
  assert.equal(ui.App.state.dirty, true, 'failed loading keeps author work');
  ui.App.api = async () => ({ questions: copy(fixture) });
  await ui.plan.load({ refresh: true });
  assert.equal(ui.plan.count('plan'), 2, 'loading can be retried');
  ui = mount();
  let releaseFirst, gets = 0, records = copy(fixture);
  const first = new Promise(resolve => { releaseFirst = resolve; });
  ui.App.api = async () => { const result = { questions: copy(records) }; if (++gets === 1) await first; return result; };
  const earlier = ui.plan.load({ refresh: true });
  records[0].status = 'game'; records[0].hasScene = true;
  const later = ui.plan.load({ refresh: true });
  assert.equal(gets, 1);
  releaseFirst(); await Promise.all([earlier, later]);
  assert.equal(gets, 2);
  assert.equal(ui.plan.count('plan'), 1, 'a promoted question cannot reappear from a stale request');
  assert.equal(ui.plan.count('game'), 3);
  console.log('Question plan: preserved selections/drafts, direct editor, unsaved-work guard, road questions, no decision writes, retry and promotion refresh PASS');
})().catch(error => { console.error(error); process.exitCode = 1; });
