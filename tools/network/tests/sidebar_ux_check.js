// Real left-panel controls: compact filters, visual category persistence and safe bulk selection.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = name => fs.readFileSync(path.resolve(__dirname, '../editor', name), 'utf8');
const storage = new Map();
function mount() {
  const listeners = {}, bodyListeners = {};
  const element = () => ({ innerHTML: '', hidden: true, addEventListener(type, callback) { (bodyListeners[type] ??= []).push(callback); }, querySelector() { return null; }, querySelectorAll() { return []; } });
  const elements = Object.fromEntries(['#left-body', '#home-screen'].map(key => [key, element()]));
  const document = { querySelector: key => elements[key], querySelectorAll: () => [], addEventListener(type, callback) { (listeners[type] ??= []).push(callback); } };
  const state = { scenes: [{ id: 'ticket_1_2', playable: true, errors: 0 }], questions: [{ id: 'ticket_2_3' }], section: 'city', id: 'ticket_1_2', sel: [], hidden: new Set(), locked: new Set(),
    catalog: { actorTypes: { car: {}, bus: {} }, signs: ['2.1', '2.4'], props: [{ id: 'trees/pine_0' }, { id: 'buildings/home_0' }, { id: 'street/fence_12' }], lightAsset: 'light.glb' },
    S: { layout: { nodes: [{ id: 'n' }], streets: [{ id: 'a' }, { id: 'b' }] }, roads: [{ id: 'auto', auto: true }, { id: 'manual' }], lawns: [{ id: 'lawn' }], actors: [], officers: [], lights: [], signs: [], routes: [], markings: [], decor: [{ id: 'pine-a', prop: 'trees/pine_0' }, { id: 'pine-b', prop: 'trees/pine_0' }, { id: 'home', prop: 'buildings/home_0' }] } };
  const layerOf = ref => ['street', 'road', 'node', 'lawn'].includes(ref.t) ? 'roads' : ref.t === 'decor' ? 'decor' : ref.t;
  const App = { state, esc: value => String(value ?? '').replaceAll('"', '&quot;'), ic: icon => `<svg data-icon="${icon}"></svg>`, thumbRev: {}, sceneTitle: () => 'Билет 1 · вопрос 2',
    objectOf: ref => ref.t === 'decor' ? state.S.decor.find(item => item.id === ref.id) : {}, sameRef: (a, b) => a.t === b.t && a.id === b.id,
    pickable: ref => !state.hidden.has(layerOf(ref)) && !state.locked.has(layerOf(ref)), nameOf: ref => ref.id,
    select(refs, { add = false } = {}) { state.sel = add ? [...state.sel, ...refs] : refs; }, toast() {} };
  const QuestionReview = { close() {}, sidebarHtml: (_query, options) => `<div id="question-filter-options" ${options.filtersCollapsed ? 'hidden' : ''}>Subfilters</div>`, filterSummary: () => ({ label: 'Реализуем', count: 1 }), visibleCount: () => 1 };
  const context = vm.createContext({ App, document, QuestionReview, URLSearchParams, location: { search: '' }, localStorage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value) },
    Thumbs: { fillAll() {}, img: (kind, id) => `<img class="thumb" data-thumb="${kind}|${id}" alt="">` }, Tools: { renderBar() {}, current: () => 'select', opts: {} }, Layout: { nodeKind: () => 'junction' } });
  vm.runInContext(source('catalog.js') + '\nglobalThis.Catalog = Catalog;', context);
  vm.runInContext(source('panels.js'), context);
  function target(attribute, value, extra = {}) { return { closest: selector => selector === `[${attribute}]` ? { dataset: { [attribute.slice(5).replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase())]: value }, ...extra } : null }; }
  function click(attribute, value, { body = false, shiftKey = false, disabled = false } = {}) {
    const event = { target: target(attribute, value, { disabled }), shiftKey, stopPropagation() {} };
    (body ? bodyListeners.click : listeners.click).forEach(callback => callback(event));
  }
  return { App, state, click, html: () => { App.renderPanels({ only: ['left'] }); return elements['#left-body'].innerHTML; }, input: (id, value) => listeners.input.forEach(callback => callback({ target: { id, value } })) };
}
let ui = mount();
assert.equal(ui.App.sceneFiltersCollapsed(), false);
assert.match(ui.html(), /aria-expanded="true" aria-controls="scene-filters"/);
ui.click('data-toggle-scene-filters', '');
assert.equal(ui.App.sceneFiltersCollapsed(), true);
assert.match(ui.html(), /id="scene-filters" hidden/);
assert.match(ui.html(), /aria-expanded="false"/);
ui.App.setSceneFilter('questions');
assert.match(ui.html(), /План вопросов/);
assert.match(ui.html(), /Реализуем/);
assert.match(ui.html(), /id="question-filter-options" hidden/);
assert.match(ui.html(), /data-scene-section="questions"/, 'hiding status filters never hides the section navigation');
ui = mount();
assert.equal(ui.App.sceneFiltersCollapsed(), true, 'collapsed preference survives reload');
ui.App.setSceneFiltersCollapsed(false);
assert.doesNotMatch(ui.html(), /id="scene-filters" hidden/);
ui.App.setLibraryCategory('signs');
assert.equal(ui.state.ltab, 'library');
assert.match(ui.html(), /data-library-category="signs" aria-pressed="true"/);
assert.match(ui.html(), /data-lib=.*kind.*sign/);
assert.doesNotMatch(ui.html(), /<h4>.*Машины и люди|<h4>.*Деревья и кусты/);
assert.match(ui.html(), /src="\/asset\/sign\/2.1.svg"/, 'category illustrates the actual sign asset');
ui.App.setLibraryCategory('traffic');
assert.match(ui.html(), /Машины и люди/);
assert.match(ui.html(), /Светофоры/);
assert.doesNotMatch(ui.html(), /<h4>.*Знаки|<h4>.*Дома/);
ui.App.setLibraryCategory('decor');
assert.match(ui.html(), /Деревья и кусты/);
assert.match(ui.html(), /Дома/);
ui.input('lib-q', 'ель');
assert.match(ui.html(), /<span>Ель<\/span>/);
assert.doesNotMatch(ui.html(), /<span>Дом 1<\/span>/);
ui.App.setLibraryCategory('signs');
assert.match(ui.html(), /Уступите дорогу/, 'choosing a tool category clears a stale incompatible search');
ui = mount();
assert.equal(ui.App.libraryCategory(), 'signs', 'library category survives reload');
ui.App.setLeftTab('layers');
assert.match(ui.html(), /data-select-layer="roads" aria-label="Выбрать все: Дороги"/);
ui.click('data-select-layer', 'roads', { body: true });
assert.deepEqual(Array.from(ui.state.sel, item => item.id), ['a', 'b', 'manual'], 'bulk road selection excludes generated meshes, islands and junction handles');
ui.state.locked.add('roads');
assert.match(ui.html(), /data-select-layer="roads"[^>]*disabled/);
ui.click('data-select-layer', 'roads', { body: true, disabled: true });
assert.equal(ui.state.sel.length, 3, 'disabled selection cannot clear or modify current selection');
ui.state.locked.clear();
ui.state.hidden.add('roads');
ui.click('data-select-layer', 'roads', { body: true });
assert.equal(ui.state.sel.length, 0, 'hidden refs never enter bulk selection');
ui.state.hidden.clear();
ui.click('data-open', 'decor', { body: true });
assert.match(ui.html(), /data-select-prop="trees\/pine_0" aria-label="Выбрать все: Ель"/);
ui.click('data-select-prop', 'trees/pine_0', { body: true });
assert.deepEqual(Array.from(ui.state.sel, item => item.id), ['pine-a', 'pine-b']);
ui.click('data-select-prop', 'buildings/home_0', { body: true, shiftKey: true });
assert.deepEqual(Array.from(ui.state.sel, item => item.id), ['pine-a', 'pine-b', 'home'], 'Shift adds a group to the existing selection');
ui.state.locked.add('decor');
ui.click('data-select-prop', 'trees/pine_0', { body: true });
assert.equal(ui.state.sel.length, 0, 'locked prop groups cannot be selected');
console.log('Sidebar UX: compact persistent filters, visual library categories, clean question rows and bulk layer selection PASS');
