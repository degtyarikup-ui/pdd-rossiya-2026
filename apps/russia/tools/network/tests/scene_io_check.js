// Deliberately complete HTTP and thumbnail callbacks out of order in the real editor.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const elements = new Map(), requests = [], thumbnails = [], thumbnailWrites = [];
const tick = () => new Promise(resolve => setImmediate(resolve));
const document = {
  querySelector(key) {
    if (!elements.has(key)) elements.set(key, { hidden:true, dataset:{}, classList:{toggle(){}} });
    return elements.get(key);
  },
  querySelectorAll: () => [], addEventListener(){}, removeEventListener(){},
};
const response = data => ({ ok:true, json:async () => data });
const context = vm.createContext({
  document, history:{replaceState(){}}, setTimeout:()=>0, clearTimeout(){},
  Layout:{refreshPlayerRoutes(){}}, Tools:{set(){}},
  Scene3D:{load(){},refresh(){},setSelection(){},capture:()=>({toBlob:callback=>thumbnails.push(callback)})},
  fetch(path, opts={}) {
    if (path === '/api/scenes') return Promise.resolve(response([]));
    if (path.startsWith('/api/thumb/')) { thumbnailWrites.push(path); return Promise.resolve(response({})); }
    return new Promise((resolve,reject) => requests.push({path, body:opts.body && JSON.parse(opts.body), resolve:data=>resolve(response(data)),reject}));
  },
});
vm.runInContext(fs.readFileSync(require.resolve('../editor/app.js'),'utf8'),context);
const App = vm.runInContext('App',context);
function next(path) {
  const request = requests.shift();
  assert.equal(request?.path,path);
  return request;
}
function scene(id) { return {scene:{id,value:0,layout:{streets:[]},markings:[],lawns:[]},findings:[]}; }
const edit = value => App.edit(s=>{s.value=value;},{rebuild:false});
(async()=>{
  const first = App.openScene('ticket_1_1'), stale = next('/api/scene/ticket_1_1');
  const second = App.openScene('ticket_2_2');
  next('/api/scene/ticket_2_2').resolve(scene('ticket_2_2')); await second;
  stale.resolve(scene('ticket_1_1')); await first;
  assert.equal(App.state.id,'ticket_2_2','a slower earlier click never replaces the chosen scene');

  edit(1);
  const save = App.save(), duplicate = App.save();
  const one = next('/api/scene/ticket_2_2'); assert.equal(one.body.value,1);
  edit(2);
  const two = App.save(); edit(3);
  assert.equal(requests.length,0,'writes to one file are serialized and duplicate requests coalesced');
  one.resolve({findings:[]}); await Promise.all([save,duplicate]); await tick();
  const queued = next('/api/scene/ticket_2_2'); assert.equal(queued.body.value,2);
  queued.resolve({findings:[]}); await two;
  assert.equal(JSON.parse(App.state.savedJson).value,2);
  assert.equal(App.state.S.value,3); assert.equal(App.state.dirty,true,'later edits remain unsaved');
  assert.equal(thumbnails.length,0,'do not publish pictures of an unsaved edit');

  const run = App.runInGame();
  const three = next('/api/scene/ticket_2_2');
  const leave = App.openScene('ticket_3_3');
  next('/api/scene/ticket_3_3').resolve(scene('ticket_3_3')); await tick();
  assert.equal(App.state.id,'ticket_2_2','leaving waits for the requested save');
  three.resolve({findings:[]}); await Promise.all([run,leave]);
  assert.equal(App.state.id,'ticket_3_3');
  assert.equal(requests.length,0,'a pending test run cannot launch the new scene');
  thumbnails.shift()({}); await tick();
  assert.deepEqual(thumbnailWrites,['/api/thumb/ticket_2_2']);

  const pending = App.openScene('ticket_4_4');
  edit(42);
  next('/api/scene/ticket_4_4').resolve(scene('ticket_4_4')); await tick();
  const dialog = document.querySelector('#confirm'); assert.equal(dialog.hidden,false);
  dialog.onclick({target:{closest:()=>({dataset:{answer:'no'}})}}); await pending;
  assert.equal(App.state.id,'ticket_3_3'); assert.equal(App.state.S.value,42,'edits made during a scene load are protected');

  const clean = App.save(); next('/api/scene/ticket_3_3').resolve({findings:[]}); await clean;
  const include = App.setPlayable(true), approval = next('/api/game/include/ticket_3_3');
  edit(43);
  const duringInclude = App.save(); edit(44);
  assert.equal(requests.length,0);
  approval.resolve({playable:true,count:1}); await include; await tick();
  const approvedSave = next('/api/scene/ticket_3_3');
  assert.equal(approvedSave.body.reviewed,true,'a queued geometry save carries forward the published status');
  assert.equal(approvedSave.body.value,43); approvedSave.resolve({findings:[]}); await duringInclude;
  assert.equal(App.state.dirty,true); assert.equal(App.state.S.value,44);

  async function choose(sid,answer) {
    const result = App.openScene(sid);
    next('/api/scene/'+sid).resolve(scene(sid)); await tick();
    assert.equal(dialog.hidden,false);
    assert.equal(document.querySelector('#confirm-discard').hidden,false);
    dialog.onclick({target:{closest:()=>({dataset:{answer}})}}); await tick();
    return {result};
  }
  App.showHome(true);
  const failed = await choose('ticket_4_4','yes');
  assert.equal(App.isSaving,true); assert.equal(document.querySelector('#home-screen').hidden,true);
  next('/api/scene/ticket_3_3').reject(new Error('offline')); await failed.result;
  assert.equal(App.state.id,'ticket_3_3'); assert.equal(App.state.dirty,true); assert.equal(App.isSaving,false);

  const changed = await choose('ticket_4_4','yes');
  const oldSnapshot = next('/api/scene/ticket_3_3'); edit(45);
  oldSnapshot.resolve({findings:[]}); await changed.result;
  assert.equal(App.state.id,'ticket_3_3'); assert.equal(App.state.S.value,45);
  assert.equal(App.state.dirty,true,'a newer edit stays open after saving the earlier snapshot');
  const success = await choose('ticket_4_4','yes');
  const latest = next('/api/scene/ticket_3_3'); assert.equal(latest.body.value,45);
  latest.resolve({findings:[]}); await success.result;
  assert.equal(App.state.id,'ticket_4_4'); assert.equal(App.state.dirty,false);

  edit(1);
  const discard = await choose('ticket_5_5','discard');
  await discard.result; assert.equal(App.state.id,'ticket_5_5'); assert.equal(requests.length,0);
  const slow = App.openScene('ticket_6_6'), slowGet = next('/api/scene/ticket_6_6');
  App.showHome(true); slowGet.resolve(scene('ticket_6_6')); await slow;
  assert.equal(App.state.id,'ticket_5_5'); assert.equal(document.querySelector('#home-screen').hidden,false);
  console.log('Scene I/O: ordered opens, save/discard/cancel, failed save and new edits, library navigation, promotion and play targeting PASS');
})().catch(error=>{console.error(error);process.exitCode=1});
