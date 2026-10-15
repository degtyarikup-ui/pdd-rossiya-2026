// Render the actual scene panels with a tiny DOM; no server, browser or author writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const editor = path.resolve(__dirname, '../editor');
const network = path.resolve(__dirname, '../../../game_godot/network');
const source = fs.readFileSync(path.join(editor, 'panels.js'), 'utf8');
const scenes = fs.readdirSync(network).filter(file => file.endsWith('.json')).sort().map(file => {
  const scene = JSON.parse(fs.readFileSync(path.join(network, file), 'utf8'));
  return { id: scene.id, playable: scene.id !== 'mini_regulator' && scene.reviewed === true,
    reviewGroup: scene.reviewGroup, questionText: '', errors: 0 };
});
const expected = scenes.filter(scene => scene.reviewGroup === 'unmarked-2026-10-15').map(scene => scene.id);
assert.equal(expected.length, 23);
const storage = new Map();

function mount(search = '') {
  const listeners = {};
  const element = () => ({ innerHTML: '', hidden: true, addEventListener() {},
    querySelector() { return null; }, querySelectorAll() { return []; },
    focus() {}, setSelectionRange() {}, value: '' });
  const elements = Object.fromEntries(['#left-body', '#home-screen', '#home-q'].map(id => [id, element()]));
  const document = { querySelector: selector => elements[selector], querySelectorAll: () => [],
    addEventListener(type, callback) { (listeners[type] ??= []).push(callback); } };
  const opened = [];
  const App = { state: { scenes: structuredClone(scenes), section: 'city' },
    esc: value => String(value ?? ''), ic: () => '', thumbRev: {},
    sceneTitle: id => id.replace(/^ticket_/, '').replace('_', ' '),
    openScene: async id => opened.push(id) };
  vm.runInNewContext(source, { App, document, URLSearchParams, location: { search }, Thumbs: { fillAll() {} }, Tools: { renderBar() {} },
    localStorage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value) } });
  const dispatch = (type, target) => listeners[type].forEach(callback => callback({ target }));
  const click = (attribute, value) => dispatch('click', {
    closest: selector => selector === `[${attribute}]` ? { dataset: { [attribute.replace('data-', '')]: value } } : null,
  });
  const rows = html => Array.from(html.matchAll(/data-scene="([^"]+)"/g), match => match[1]);
  return { App, elements, opened, click, dispatch, rows,
    left: () => { App.renderPanels(); return elements['#left-body'].innerHTML; },
    home: () => { App.renderHome(); return elements['#home-screen'].innerHTML; } };
}

let ui = mount();
assert.equal(ui.rows(ui.left()).length, scenes.length - 1, 'all city scenes exclude the separate mini-game');
ui.click('data-filter', 'review');
assert.deepEqual(ui.rows(ui.left()), expected, 'left pane isolates exactly the original 23');
assert.deepEqual(ui.rows(ui.home()), expected, 'home cards use the same review group');
assert.match(ui.left(), /На просмотр <em>23<\/em>/);
assert.match(ui.home(), /Список сохраняется после включения/);
ui.click('data-scene', expected[0]);
assert.deepEqual(ui.opened, [expected[0]], 'an excluded scene remains openable in the editor');
ui.App.state.scenes.find(scene => scene.id === expected[0]).playable = true;
assert.deepEqual(ui.rows(ui.left()), expected, 'manual inclusion keeps the scene in the review list');
assert.match(ui.left(), /в игре/);
ui = mount();
assert.deepEqual(ui.rows(ui.left()), expected, 'review filter survives a fresh editor instance');
ui.dispatch('input', { id: 'scene-q', value: '10 14' });
assert.deepEqual(ui.rows(ui.left()), ['ticket_10_14'], 'search works inside the review group');
ui.dispatch('input', { id: 'scene-q', value: '' });
ui.click('data-filter', 'game');
assert.deepEqual(ui.rows(ui.left()), scenes.filter(scene => scene.playable).map(scene => scene.id));
ui = mount('?filter=review');
assert.deepEqual(ui.rows(ui.left()), expected, 'direct review link overrides the previous saved filter');
ui = mount();
assert.deepEqual(ui.rows(ui.left()), expected, 'direct review link also saves the filter for reopening');
ui.App.state.section = 'regulator';
assert.deepEqual(ui.rows(ui.left()), ['mini_regulator'], 'city filters do not hide the mini-game tab');
console.log('Scene review panels: exact 23, left/home/search, manual inclusion and restart PASS');
