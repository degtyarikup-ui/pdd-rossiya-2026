// Exercise the real question-review module: no server, author writes or fake implementation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.resolve(__dirname, '../editor/question_review.js'), 'utf8');
const copy = value => JSON.parse(JSON.stringify(value));
const fixture = [
  { id: 'ticket_1_1', ticket: 1, number: 1, category: 'ab', categories: ['ab', 'cd'], question: 'Кому уступить дорогу?', answers: [{ text: 'Никому', correct: false }, { text: 'Автобусу', correct: true }], imageUrl: '/asset/question/1.webp', comment: 'Пояснение <с текстом>', decision: null },
  { id: 'ticket_1_2', ticket: 1, number: 2, category: 'ab', question: 'Разрешён ли поворот?', answers: [{ text: 'Да', correct: true }], decision: null },
  { id: 'ticket_cd_1_3', ticket: 1, number: 3, category: 'cd', question: 'Грузовой автомобиль', answers: [{ text: 'Нет', correct: true }], decision: 'no' },
];
function mount(records = fixture) {
  const listeners = {}, requests = [], storage = new Map(), classes = new Set(), urls = [];
  const elements = Object.fromEntries(['#question-review', '#home-screen', '#confirm', '#keys'].map(id => [id, { innerHTML: '', hidden: true }]));
  const document = { querySelector: selector => elements[selector], body: { classList: { add: value => classes.add(value), remove: value => classes.delete(value) } },
    addEventListener(type, callback) { (listeners[type] ??= []).push(callback); } };
  const location = { search: '?scene=ticket_16_15' };
  const window = { history: { replaceState(_state, _title, url) { urls.push(url); location.search = url; } } };
  const stored = copy(records);
  const App = { state: { id: 'ticket_16_15', S: { id: 'ticket_16_15', unsaved: { note: 'author draft', arbitrary: [1, 2] } }, dirty: true },
    ic: () => '', esc: value => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;'),
    showHome: on => { elements['#home-screen'].hidden = !on; }, renderPanels() {}, renderHome() {},
    async openScene(id) { App.state.id = id; },
    async api(url, body) {
      requests.push({ url, body });
      if (url === '/api/questions') return { questions: copy(stored) };
      if (App.failure) throw new Error('Server unavailable');
      if (App.pending) await App.pending;
      const id = url.split('/')[3];
      const record = stored.find(question => question.id === id);
      record.decision = body.decision;
      return copy(record);
    } };
  const context = vm.createContext({ App, document, window, location, URLSearchParams,
    localStorage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value) } });
  vm.runInContext(source + '\nglobalThis.testReview = QuestionReview;', context);
  const review = context.testReview;
  App.showQuestions = id => review.open(id);
  const tick = () => new Promise(resolve => setImmediate(resolve));
  const click = async (key, value) => {
    listeners.click.forEach(callback => callback({ target: { closest: selector => selector === `[data-${key}]` ? { dataset: { [key]: value }, disabled: false } : null } }));
    await tick();
  };
  const key = async (value, extra = {}) => {
    const event = { key: value, target: { tagName: 'BODY' }, preventDefault() { this.prevented = true; }, stopImmediatePropagation() {}, ...extra };
    listeners.keydown.forEach(callback => callback(event));
    await tick();
    return event;
  };
  return { App, review, requests, elements, stored, classes, urls, click, key, tick, html: () => elements['#question-review'].innerHTML };
}
(async () => {
  let ui = mount();
  const draft = JSON.stringify(ui.App.state.S);
  await ui.review.open();
  assert.equal(ui.review.currentId(), fixture[0].id);
  assert(ui.review.active());
  assert(ui.classes.has('question-reviewing'));
  assert.equal(ui.requests.length, 1, 'opening review reads without deciding or creating scenes');
  assert.match(ui.html(), /Кому уступить дорогу/);
  assert.match(ui.html(), /Верный ответ/);
  assert.match(ui.html(), /Пояснение &lt;с текстом&gt;/);
  assert.match(ui.html(), /A\/B · C\/D/);
  assert.match(ui.review.sidebarHtml(), /loading="lazy"/);
  assert(!ui.review.sidebarHtml().includes('preview/'), 'question list uses original exam pictures');
  assert.doesNotMatch(ui.review.sidebarHtml(), /<small>|Кому уступить дорогу|A\/B|C\/D/, 'left rows keep only the illustration, reference and decision');
  assert.match(ui.review.sidebarHtml('', { filtersCollapsed: true }), /id="question-filter-options" hidden/);
  assert.doesNotMatch(ui.review.sidebarHtml(), /data-qr="start"|data-qr="editor-mode"|Да \/ Нет/, 'sidebar has no hidden review/editor mode');
  assert.match(ui.review.sidebarHtml(), /select data-question-status aria-label="Решение по вопросу"/);
  assert.match(ui.html(), /data-qr="editor"[^>]*>Открыть в редакторе/);
  assert.equal(ui.review.filterSummary().label, 'Решение ещё не принято');
  assert.equal(ui.review.filterSummary().count, 2);
  assert.equal(ui.urls.at(-1), '?filter=questions&question=ticket_1_1');
  await ui.key('ArrowRight', { repeat: true });
  await ui.key('ArrowLeft', { target: { tagName: 'INPUT' } });
  assert.equal(ui.requests.length, 1, 'key repeat and search typing cannot decide');
  await ui.key('ArrowDown');
  assert.equal(ui.review.currentId(), fixture[1].id, 'skip keeps question undecided');
  await ui.key('ArrowUp');
  assert.equal(ui.review.currentId(), fixture[0].id);
  await ui.click('qr', 'zoom');
  await ui.key('ArrowLeft');
  assert.equal(ui.requests.length, 1, 'zoom cannot accidentally decide');
  await ui.key('Escape');
  assert(ui.review.active(), 'escape first closes enlarged photo');
  await ui.key('ArrowRight');
  assert.deepEqual(copy(ui.requests.at(-1)), { url: '/api/questions/ticket_1_1/decision', body: { decision: 'yes' } });
  assert.equal(ui.review.currentId(), fixture[1].id, 'successful decision advances to next pending');
  assert.equal(ui.review.count('yes'), 1);
  assert.equal(ui.review.count('pending'), 1);
  const visitsBeforeBack = ui.requests.length;
  await ui.key('ArrowUp');
  assert.equal(ui.review.currentId(), fixture[0].id, 'back can revisit an already decided question');
  assert.equal(ui.review.count('yes'), 1, 'back does not undo a stored decision');
  await ui.key('ArrowDown');
  assert.equal(ui.review.currentId(), fixture[1].id);
  assert.equal(ui.requests.length, visitsBeforeBack, 'back and forward do not write decisions');
  assert.equal(JSON.stringify(ui.App.state.S), draft, 'review never alters author scene draft');
  assert.equal(ui.App.state.dirty, true);
  await ui.key('z', { metaKey: true });
  assert.equal(ui.requests.at(-1).body.decision, null);
  assert.equal(ui.review.currentId(), fixture[0].id);
  assert.equal(ui.review.count('pending'), 2);
  assert.match(ui.html(), /Последнее решение отменено/);
  ui.App.failure = true;
  await ui.click('qr', 'no');
  assert.equal(ui.review.currentId(), fixture[0].id, 'failed save never advances');
  assert.equal(ui.review.count('pending'), 2, 'failed save never changes local decision');
  assert.match(ui.html(), /Решение не сохранено/);
  ui.App.failure = false;
  let release;
  ui.App.pending = new Promise(resolve => { release = resolve; });
  const previousRequests = ui.requests.length;
  await ui.click('qr', 'yes');
  await ui.click('qr', 'no');
  assert.equal(ui.requests.length, previousRequests + 1, 'double clicks cannot issue competing decisions');
  assert.match(ui.html(), /Сохраняем решение/);
  release(); await ui.tick(); ui.App.pending = null;
  await ui.click('qr', 'no');
  assert.equal(ui.review.currentId(), null);
  assert.match(ui.html(), /Все вопросы распределены/);
  await ui.click('qfilter', 'yes');
  assert.equal(ui.review.currentId(), fixture[0].id, 'decided questions remain accessible');
  await ui.click('qr', 'no');
  assert.equal(ui.review.count('yes'), 0, 'decisions can be revised');
  await ui.review.open(fixture[2].id);
  assert.equal(ui.review.currentId(), fixture[2].id, 'explicit question opens even outside current group');
  assert.match(ui.html(), /Без иллюстрации/);
  ui.review.setQuery('грузовой c/d');
  assert.equal(ui.review.list().length, 1, 'search includes category and full question text');
  assert.equal(ui.review.filterSummary().count, 1, 'compact status reflects the search and current decision group');
  ui.review.setQuery('1 3');
  assert.equal(ui.review.list().length, 1, 'ticket/question search works');
  ui.App.state.questions.find(question => question.id === fixture[2].id).occurrences = [{id:'ticket_cd_40_20',ticket:40,number:20}];
  ui.review.setQuery('40 20');
  assert.equal(ui.review.list().length, 1, 'merged cards remain searchable by every original ticket position');
  ui.review.setQuery('');
  ui.App.openScene = async () => {}; // Existing dirty-scene confirmation was cancelled.
  await ui.click('qr', 'editor');
  assert(ui.review.active(), 'cancelled editor navigation retains review');
  ui.App.openScene = async id => { ui.App.state.id = id; };
  await ui.click('qr', 'editor');
  assert(!ui.review.active());
  assert.equal(ui.App.state.id, fixture[2].id);
  assert(!ui.classes.has('question-reviewing'));
  assert.equal(ui.review.mode(), 'editor');
  await ui.click('question', fixture[0].id);
  assert.equal(ui.App.state.id, fixture[2].id, 'selecting another plan question leaves the edited scene intact');
  assert(ui.review.active(), 'every plan question opens the same explicit review view');
  assert.equal(ui.review.currentId(), fixture[0].id);
  assert.equal(ui.review.mode(), 'review');
  ui = mount([{ ...fixture[0], decision: 'yes' }, fixture[1], fixture[2]]);
  await ui.review.open();
  assert.equal(ui.review.currentId(), fixture[1].id, 'fresh session resumes first unreviewed question');
  ui.review.close();
  assert.equal(ui.urls.at(-1), '?scene=ticket_16_15', 'closing review returns current scene without touching its draft');
  ui = mount();
  ui.App.state.S = null;
  ui.App.state.id = null;
  let homes = 0;
  ui.App.showHome = on => {
    // Exercise the real integration hook: showHome(true) itself closes review.
    if (on) { homes++; ui.review.close(); }
    ui.elements['#home-screen'].hidden = !on;
  };
  await ui.review.open();
  ui.review.close();
  assert.equal(homes, 1, 'closing a deep-linked review without an editor scene opens home once');
  assert.equal(ui.elements['#home-screen'].hidden, false);
  assert(!ui.review.active());
  assert.equal(ui.urls.at(-1), '?filter=all');
  ui = mount();
  let releaseFirst;
  const firstGet = new Promise(resolve => { releaseFirst = resolve; });
  let serverPool = copy(fixture), gets = 0;
  ui.App.api = async url => {
    assert.equal(url, '/api/questions');
    const response = { questions: copy(serverPool) }; // GET captures server state immediately.
    if (++gets === 1) await firstGet;
    return response;
  };
  const beforePromotion = ui.review.load({ refresh: true });
  serverPool = serverPool.slice(1); // Scene was promoted while the earlier GET is in flight.
  const afterPromotion = ui.review.load({ refresh: true });
  assert.equal(gets, 1, 'overlapping refresh waits for the earlier GET');
  releaseFirst();
  await Promise.all([beforePromotion, afterPromotion]);
  assert.equal(gets, 2, 'refresh after promotion issues a fresh GET instead of reusing old data');
  assert.equal(ui.App.state.questions.length, 2);
  assert(!ui.App.state.questions.some(question => question.id === fixture[0].id), 'promoted question cannot reappear from stale in-flight response');
  console.log('Question review: real module, persisted decisions, retry, guarded saves, undo, filters, navigation, draft preservation PASS');
})().catch(error => { console.error(error); process.exitCode = 1; });
