// Actual scene panels: implemented scenes are separate from the new exam-question backlog.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.resolve(__dirname, '../editor/panels.js'), 'utf8');
const scenes = [
  { id: 'ticket_10_14', playable: true, reviewGroup: 'unmarked-2026-10-15', questionText: 'Поворот налево', errors: 0 },
  { id: 'ticket_11_2', playable: false, reviewGroup: 'unmarked-2026-10-15', questionText: 'Знак', errors: 2 },
  { id: 'ticket_12_5', playable: false, questionText: 'Разворот', errors: 0 },
  { id: 'ticket_1_5', playable: false, questionText: 'Поворот', errors: 0, assistantReview: { author: 'codex', status: 'pending' } },
  { id: 'ticket_2_5', playable: true, questionText: 'Полосы', errors: 0, assistantReview: { author: 'codex', status: 'approved' } },
  { id: 'mini_regulator', playable: false, questionText: '', errors: 0 },
];
const questions = [{ id: 'ticket_1_1' }, { id: 'ticket_cd_1_2' }];
const storage = new Map();
function mount(search = '') {
  const listeners = {};
  const element = () => ({ innerHTML: '', hidden: true, addEventListener() {}, querySelector() { return null; }, querySelectorAll() { return []; }, focus() {}, setSelectionRange() {}, value: '' });
  const elements = Object.fromEntries(['#left-body', '#home-screen', '#home-q'].map(id => [id, element()]));
  const document = { querySelector: selector => elements[selector], querySelectorAll: () => [], addEventListener(type, callback) { (listeners[type] ??= []).push(callback); } };
  const opened = [], reviewed = [];
  const QuestionReview = { open: async id => reviewed.push(id || 'first-pending'), close() {}, setQuery() {},
    sidebarHtml: () => questions.map(question => `<button data-question="${question.id}">question photo</button>`).join(''),
    homeHtml: () => '<div>question cards</div>', visibleCount: () => questions.length };
  const App = { state: { scenes: structuredClone(scenes), questions, section: 'city' }, esc: value => String(value ?? ''), ic: () => '', thumbRev: {},
    sceneTitle: id => id.replace(/^ticket_/, '').replace('_', ' '), openScene: async id => opened.push(id) };
  vm.runInNewContext(source, { App, QuestionReview, document, URLSearchParams, location: { search }, Thumbs: { fillAll() {} }, Tools: { renderBar() {} },
    localStorage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value) } });
  const dispatch = (type, target) => listeners[type].forEach(callback => callback({ target }));
  const click = (attribute, value) => dispatch('click', { closest: selector => selector === `[${attribute}]` ? { dataset: { [attribute.replace('data-', '').replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())]: value } } : null });
  const rows = html => Array.from(html.matchAll(/data-scene="([^"]+)"/g), match => match[1]);
  return { App, elements, opened, reviewed, click, dispatch, rows,
    left: () => { App.renderPanels(); return elements['#left-body'].innerHTML; },
    home: () => { App.renderHome(); return elements['#home-screen'].innerHTML; } };
}
let ui = mount();
const ordinary = ['ticket_2_5', 'ticket_10_14', 'ticket_11_2', 'ticket_12_5'];
assert.deepEqual(ui.rows(ui.left()), ordinary);
assert.match(ui.left(), /Все созданные сцены/);
assert.doesNotMatch(ui.left(), /На просмотр|на просмотр/);
assert.doesNotMatch(ui.home(), /На просмотр|на просмотр/);
assert.deepEqual(Array.from(ui.left().matchAll(/data-scene-section="([^"]+)"/g), match => match[1]), ['scenes', 'assistant', 'questions']);
assert.doesNotMatch(ui.left(), /data-filter=|class="chips"/, 'primary sections never mix with old flat filter chips');
ui.dispatch('change', { matches: selector => selector === '[data-scene-status]', value: 'game' });
assert.deepEqual(ui.rows(ui.left()), ['ticket_2_5', 'ticket_10_14']);
ui.dispatch('change', { matches: selector => selector === '[data-scene-status]', value: 'err' });
assert.deepEqual(ui.rows(ui.left()), ['ticket_11_2']);
ui.click('data-scene', 'ticket_11_2');
assert.deepEqual(ui.opened, ['ticket_11_2']);
ui.click('data-scene-section', 'assistant');
assert.equal(ui.App.approvalFilter(), 'pending');
assert.deepEqual(ui.rows(ui.left()), ['ticket_1_5'], 'review queue initially shows pending scenes only');
assert.match(ui.left(), /На одобрение<\/span><em>1/);
assert.match(ui.left(), /Статус одобрения/);
assert.match(ui.home(), /Сцены Codex/);
ui.dispatch('change', { matches: selector => selector === '[data-scene-status]', value: 'approved' });
assert.deepEqual(ui.rows(ui.left()), ['ticket_2_5'], 'approved scenes remain in their original Codex section');
ui.dispatch('change', { matches: selector => selector === '[data-scene-status]', value: 'all' });
assert.deepEqual(ui.rows(ui.left()), ['ticket_1_5', 'ticket_2_5']);
ui.click('data-scene-section', 'scenes');
assert.equal(ui.App.sceneFilter(), 'err', 'switching section remembers the last game-scene subfilter');
ui.click('data-scene-section', 'questions');
assert.deepEqual(ui.rows(ui.left()), [], 'candidate drafts cannot appear as implemented scenes');
assert.match(ui.left(), /data-question="ticket_1_1"/);
assert.match(ui.left(), /План вопросов<\/span><em>2/);
assert.match(ui.home(), /question cards/);
assert.deepEqual(ui.reviewed, ['first-pending']);
ui = mount();
assert.equal(ui.App.sceneFilter(), 'questions', 'new questions tab preference survives reopening');
ui.App.showQuestions('ticket_cd_1_2');
assert.deepEqual(ui.reviewed, ['ticket_cd_1_2']);
ui = mount('?filter=review');
assert.equal(ui.App.sceneFilter(), 'all', 'obsolete review deep links fall back to all scenes');
assert.deepEqual(ui.rows(ui.left()), ordinary);
ui.dispatch('input', { id: 'scene-q', value: '10 14' });
assert.deepEqual(ui.rows(ui.left()), ['ticket_10_14']);
ui.App.state.section = 'regulator';
assert.deepEqual(ui.rows(ui.left()), ['mini_regulator'], 'city filters leave separate mini-game reachable');
ui = mount();
ui.App.state.scenes = ['ticket_19_1', 'ticket_23_5', 'ticket_2_12', 'ticket_2_1', 'ticket_3_1'].map(id => ({ id, errors: 0 }));
const sourceOrder = ui.App.state.scenes.map(scene => scene.id);
ui.App.setSceneFilter('all');
const numericOrder = ['ticket_2_1', 'ticket_2_12', 'ticket_3_1', 'ticket_19_1', 'ticket_23_5'];
assert.deepEqual(ui.rows(ui.left()), numericOrder, 'sort ticket and question numbers numerically');
assert.deepEqual(ui.rows(ui.home()), numericOrder);
assert.deepEqual(ui.App.state.scenes.map(scene => scene.id), sourceOrder, 'sorting never changes the source scene list');
ui.App.state.scenes.forEach(scene => { scene.assistantReview = { author: 'codex', status: 'pending' }; });
ui.App.setSceneFilter('assistant');
assert.deepEqual(ui.rows(ui.left()), numericOrder, 'approval queue uses the same numeric order');
console.log('Scene panels: three explicit sections, contextual filters, pending/approved Codex, search and restart PASS');
