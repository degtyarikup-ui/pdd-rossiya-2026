// Exercise preview scheduling with a held pointer and deliberately late HTTP replies.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const timers = new Map(), requests = [], shown = [];
let timerId = 0;
const elements = new Map();
const context = vm.createContext({
  document: {querySelector(key) {
    if (!elements.has(key)) elements.set(key, {hidden:true,dataset:{},classList:{toggle(){}}});
    return elements.get(key);
  },querySelectorAll:()=>[]},
  setTimeout(fn) {timers.set(++timerId,fn);return timerId;},
  clearTimeout(id) {timers.delete(id);},
  Scene3D:{refresh(){},setSelection(){},setBuild(b){shown.push(b);}},
  fetch(path, options) { return new Promise((resolve,reject)=>requests.push({path,
    body:JSON.parse(options.body),reject,
    resolve(build){resolve({ok:true,json:async()=>({build,findings:[],edges:{}})});}})); },
});
vm.runInContext(fs.readFileSync(require.resolve('../editor/app.js'),'utf8'),context);
const App = vm.runInContext('App',context);
App.state.S = {id:'ticket_5_7',roads:[],actors:[],markings:[],routes:[],value:0};
App.state.id = App.S.id;
App.state.savedJson = JSON.stringify(App.S);
const flush = async () => {
  const pending = [...timers.values()]; timers.clear();
  pending.forEach(fn=>fn());
  for(let i=0;i<6;i++) await Promise.resolve();
};
const settled = async () => {for(let i=0;i<8;i++) await Promise.resolve();};
(async()=>{
  App.beginDrag();
  App.dragMove(s=>s.value=1);
  await flush();
  assert.equal(requests.length,1,'road surfaces are requested before pointer release');
  const first=requests.shift();
  for(let i=2;i<=20;i++) App.dragMove(s=>s.value=i);
  await flush();
  assert.equal(requests.length,0,'only one build may be in flight');
  first.resolve('moving-frame'); await settled();
  assert.deepEqual(shown,['moving-frame'],'completed intermediate frames stay visible during a held drag');
  await flush();
  const second=requests.shift();
  assert.equal(second.body.value,20,'queued work coalesces to the newest geometry');
  App.endDrag();
  second.resolve('released-stale'); await settled();
  assert.equal(shown.at(-1),'moving-frame','a pre-release frame cannot overwrite the committed geometry');
  await flush();
  requests.shift().resolve('final'); await settled();
  assert.equal(shown.at(-1),'final');
  assert.equal(App.state.undo.length,1);

  App.beginDrag(); App.dragMove(s=>s.value=30); await flush();
  const cancelled=requests.shift();
  App.cancelDrag();
  cancelled.resolve('cancelled'); await settled();
  assert.equal(shown.at(-1),'final','cancelled shape never arrives after restoration');
  await flush(); requests.shift().resolve('restored'); await settled();
  assert.equal(App.S.value,20);

  App.edit(s=>s.value=40); await flush(); const old=requests.shift();
  App.undo();
  old.resolve('before-undo'); await settled();
  assert.equal(shown.at(-1),'restored','undo invalidates an in-flight preview before the next request starts');
  await flush(); requests.shift().resolve('undo'); await settled();

  App.edit(s=>s.value=50); await flush(); const between=requests.shift();
  App.beginDrag(); App.dragMove(s=>s.value=60);
  between.resolve('previous-edit'); await settled();
  assert.equal(shown.at(-1),'undo','an earlier edit cannot win during a new gesture');
  await flush(); const failed=requests.shift();
  App.dragMove(s=>s.value=70); failed.reject(new Error('temporary')); await settled();
  await flush(); assert.equal(requests[0].body.value,70,'a failed old build does not block the newest geometry');
  requests.shift().resolve('recovered'); await settled();
  App.endDrag(); await flush(); requests.shift().resolve('settled'); await settled();
  App.edit(s=>s.value=80); await flush(); const clicked=requests.shift();
  App.beginDrag(); App.cancelDrag();
  clicked.resolve('after-click'); await settled();
  assert.equal(shown.at(-1),'after-click','a click without a change must not discard the only valid preview');
  App.beginDrag(); App.dragMove(s=>s.value=90); await flush(); const held=requests.shift();
  const historyLength=App.state.undo.length;
  App.undo();
  assert.equal(App.S.value,80,'undo while holding cancels just the current gesture');
  assert.equal(App.state.undo.length,historyLength);
  held.resolve('held-before-undo'); await settled();
  assert.equal(shown.at(-1),'after-click');
  await flush(); requests.shift().resolve('cancelled-by-undo'); await settled();
  console.log('Road preview: live drag, coalescing, release, cancel, undo and late responses PASS');
})().catch(error=>{console.error(error);process.exitCode=1;});
