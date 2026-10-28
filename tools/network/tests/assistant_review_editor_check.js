// Real App/inspector handlers: edits and test runs remain pending until an explicit approval click.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = value => JSON.parse(JSON.stringify(value));
const read = name => fs.readFileSync(require.resolve('../editor/' + name), 'utf8');
const elements = new Map(), calls = [];
function element() {
  const listeners = {};
  return { hidden: true, innerHTML: '', dataset: {}, listeners, classList: { toggle() {}, add() {}, remove() {} },
    addEventListener(type, callback) { (listeners[type] ??= []).push(callback); }, querySelectorAll: () => [], querySelector: () => null };
}
let stored = { id: 'ticket_1_5', schema: 1, crop: 90, layout: Layout.template('cross', 90),
  question: { maneuver: 'right' }, roads: [], routes: [], markings: [], lawns: [], actors: [], lights: [], decor: [],
  questionPool: { category: 'ab', ticket: 1, number: 5 }, reviewed: false,
  assistantReview: { author: 'codex', batch: '2026-10-16-first-12', status: 'pending' } };
Layout.apply(stored);
let failSave = false;
const context = vm.createContext({ Layout,
  document: { querySelector(key) { if (!elements.has(key)) elements.set(key, element()); return elements.get(key); }, querySelectorAll: () => [], title: '' },
  Scene3D: { load() {}, refresh() {}, setSelection() {}, capture: () => ({ toBlob() {} }) }, Tools: { set() {} },
  Thumbs: { fillAll() {}, img: () => '' }, QuestionPlan: { close() {}, load: async () => [] }, history: { replaceState() {} },
  setTimeout: () => 0, clearTimeout() {},
  async fetch(path, options = {}) {
    const body = options.body && JSON.parse(options.body);
    calls.push({ path, body });
    let data, ok = true;
    if (path === '/api/scenes') data = [];
    else if (!body) data = { scene: clone(stored), build: {}, findings: [], playable: stored.reviewed };
    else if (path.startsWith('/api/scene/')) {
      if (failSave) { ok = false; data = { error: 'fixture save failed' }; }
      else { stored = clone(body); data = { findings: [], reviewed: stored.reviewed, assistantReview: stored.assistantReview, questionPool: stored.questionPool }; }
    } else if (path.includes('/include/')) {
      stored.reviewed = body.playable;
      stored.assistantReview.status = body.playable ? 'approved' : 'pending';
      if (body.playable) delete stored.questionPool;
      data = { playable: stored.reviewed, assistantReview: clone(stored.assistantReview), count: body.playable ? 1 : 0 };
    } else data = { launched: true };
    return { ok, json: async () => data };
  },
});
vm.runInContext(read('app.js'), context);
vm.runInContext(read('catalog.js'), context);
vm.runInContext(read('inspector.js'), context);
const App = vm.runInContext('App', context);
App.state.ltab = 'scenes';
App.renderPanels = () => App.renderInspector();
const inspector = elements.get('#inspector');
const html = () => { App.renderInspector(); return inspector.innerHTML; };
async function click(action) {
  await Promise.all(inspector.listeners.click.map(callback => callback({ target: {
    closest: selector => selector === '[data-act]' ? { dataset: { act: action } } : null,
  } })));
}
(async () => {
  await App.openScene(stored.id);
  assert.match(html(), /Подготовлено Codex/);
  assert.match(html(), /Ожидает вашего одобрения/);
  assert.match(html(), /data-act="approve-scene"/);
  assert.doesNotMatch(html(), /data-toggle="playable"/, 'assistant approval is a deliberate button, never the ordinary toggle');
  const approvalCalls = () => calls.filter(call => call.path.includes('/include/'));
  App.edit(scene => { scene.questionView = { centre: [2, 4], height: 31 }; }, { rebuild: false });
  await App.runInGame();
  assert.equal(approvalCalls().length, 0, 'test run saves the edit without approving');
  assert.equal(stored.assistantReview.status, 'pending');
  assert.deepEqual(stored.questionView, { centre: [2, 4], height: 31 });
  assert.ok(calls.some(call => call.path.includes('/run/')));
  await click('approve-scene');
  assert.equal(approvalCalls().length, 1);
  assert.equal(App.state.S.assistantReview.status, 'approved');
  assert.equal(App.state.S.questionPool, undefined);
  assert.match(html(), /Одобрено вами · сцена в игре/);
  assert.match(html(), /data-act="withdraw-approval"/);
  assert.equal(App.state.dirty, false);
  App.undo();
  assert.equal(App.state.S.assistantReview.status, 'approved', 'geometry undo never revokes an approval');
  assert.equal(App.state.S.questionPool, undefined);
  App.redo();
  assert.equal(App.state.S.questionView.height, 31);
  assert.equal(App.state.S.assistantReview.status, 'approved');
  App.edit(scene => { scene.questionView.height = 29; }, { rebuild: false });
  await click('withdraw-approval');
  assert.equal(stored.reviewed, false);
  assert.equal(App.state.S.assistantReview.status, 'pending');
  assert.equal(stored.questionView.height, 29, 'withdraw first saves manual edits and preserves them');
  assert.equal(stored.assistantReview.batch, '2026-10-16-first-12');
  await click('approve-scene');
  assert.equal(stored.reviewed, true);
  assert.equal(stored.questionView.height, 29);
  await click('withdraw-approval');
  const count = approvalCalls().length;
  App.edit(scene => { scene.questionView.height = 27; }, { rebuild: false });
  failSave = true;
  await click('approve-scene');
  assert.equal(approvalCalls().length, count, 'failed save cannot approve stale geometry');
  assert.equal(App.state.dirty, true);
  assert.equal(App.state.including, false, 'failed-save guard unlocks the button for retry');
  assert.match(html(), /Ожидает вашего одобрения/);
  console.log('Codex editor: pending manual edits/test, explicit approval/withdraw/reapproval and failed-save guard PASS');
})().catch(error => { console.error(error); process.exitCode = 1; });
