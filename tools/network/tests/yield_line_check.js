// Real inspector controls, undo and generated markings; authored scenes are never written.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = value => JSON.parse(JSON.stringify(value));
const listeners = {};
const pane = {innerHTML:'',addEventListener:(name,fn) => {listeners[name] = fn;},querySelectorAll:() => [],querySelector:() => null};
const node = {addEventListener:() => {},dataset:{},classList:{toggle:() => {}},textContent:''};
const context = vm.createContext({Layout,
  document:{querySelector:selector => selector === '#inspector' ? pane : node},
  Scene3D:{refresh:() => {},setSelection:() => {}},Tracks:{apply:() => {}},
  Thumbs:{fillAll:() => {},img:() => ''},setTimeout:() => 0,clearTimeout:() => {},
});
for (const file of ['catalog.js','actor_signals.js','app.js','direction_marking.js','inspector.js']) vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
const App = vm.runInContext('App',context), state = App.state;
App.renderPanels = () => App.renderInspector();
function fixture(kind = 'street', angle = 0) {
  const scene = {schema:1,id:'yield-line-test',crop:90,layout:Layout.template('cross',90),
    question:{maneuver:'straight',correct:0,text:{ru:{options:['Да']}}},
    roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],decor:[],signs:[]};
  for (const n of scene.layout.nodes) {
    const x = n.x, z = n.z;
    n.x = x * Math.cos(angle) - z * Math.sin(angle);
    n.z = x * Math.sin(angle) + z * Math.cos(angle);
    const edge = Math.max(Math.abs(n.x),Math.abs(n.z));
    if (edge > 0) { n.x *= 90 / edge; n.z *= 90 / edge; }
  }
  for (const st of scene.layout.streets) {
    st.kind = kind;
    st.ends = {a:{stop:true},b:{stop:true}};
  }
  Layout.apply(scene);
  return scene;
}
state.S = fixture(); state.id = state.S.id; state.savedJson = JSON.stringify(state.S);
state.catalog = {props:[],actorTypes:{}};
const stId = state.S.layout.streets[0].id;
const street = () => Layout.streetOf(state.S.layout,stId);
const ref = {t:'street',id:stId};
const chip = (name,value) => listeners.click({target:{closest:selector => selector === '[data-chip]' ? {dataset:{chip:name,value}} : null}});
const act = dataset => listeners.click({target:{closest:selector => selector === '[data-act]' ? {dataset} : null}});
App.select(ref);
const before = clone(state.S), end = ['a','b'].find(e => Layout.nodeKind(state.S.layout,Layout.nodeOf(state.S.layout,street()[e]),90) === 'junction');
assert.match(pane.innerHTML,new RegExp(`data-chip="stop-style-${end}"`));
const depth = state.undo.length;
chip(`stop-style-${end}`,'yield');
assert.equal(state.undo.length,depth + 1);
assert.equal(street().ends[end].stopStyle,'yield');
assert.equal(state.S.markings.find(m => m.type === 'stop' && m.street === stId).stopStyle,'yield');
assert.deepEqual(clone(state.S.routes),before.routes,'changing paint preserves player routes');
assert.deepEqual(clone(state.S.roads),before.roads,'changing paint preserves the roads');
App.undo(); assert.deepEqual(clone(state.S),before);
App.redo(); assert.equal(street().ends[end].stopStyle,'yield');
const withYield = clone(state.S);
state.locked.add('roads');
chip(`stop-style-${end}`,'solid');
assert.deepEqual(clone(state.S),withYield,'locked roads cannot change style');
state.locked.clear();
chip(`stop-style-${end}`,'bad'); assert.deepEqual(clone(state.S),withYield);
chip(`stop-style-${end}`,'solid'); assert.equal(street().ends[end].stopStyle,undefined);
chip(`stop-style-${end}`,'yield');
act({act:'end',end,what:'stop'}); assert.equal(street().ends[end].stop,false);
assert.ok(!state.S.markings.some(m => m.street === stId && m.type === 'stop'));
act({act:'end',end,what:'stop'});
assert.equal(state.S.markings.find(m => m.street === stId && m.type === 'stop').stopStyle,'yield','off/on remembers style');

state.S.markings.push({id:'manual-stop',type:'stop',points:[[0,-35],[-4,-35]],colour:'yellow'});
App.select({t:'marking',id:'manual-stop'});
chip('stop-style','yield');
const manual = () => state.S.markings.find(m => m.id === 'manual-stop');
assert.equal(manual().stopStyle,'yield'); assert.equal(manual().colour,'yellow');
assert.match(pane.innerHTML,/Развернуть треугольники/);
act({act:'yield-flip'}); assert.deepEqual(clone(manual().points),[[-4,-35],[0,-35]]);
App.undo(); assert.deepEqual(clone(manual().points),[[0,-35],[-4,-35]]);
chip('type','zebra'); assert.equal(manual().stopStyle,undefined,'switching marking kind clears stop style');

const fixtures = [];
for (const kind of ['yard','street','avenue','highway']) for (const angle of [0,Math.PI/4]) {
  const scene = fixture(kind,angle), original = clone(scene);
  for (const st of scene.layout.streets) for (const e of ['a','b']) st.ends[e].stopStyle = 'yield';
  Layout.apply(scene);
  const marks = scene.markings.filter(m => m.type === 'stop');
  assert.equal(marks.length,4); assert.ok(marks.every(m => m.stopStyle === 'yield'));
  assert.deepEqual(clone(scene.stop),original.stop);
  const saved = clone(scene); Layout.apply(saved); assert.deepEqual(clone(saved),clone(scene),'save/reload is stable');
  fixtures.push(scene);
}
if (process.argv[2]) fs.writeFileSync(process.argv[2],JSON.stringify(fixtures));
console.log('Yield line: inspector, undo, locks, manual lines, direction, widths and save/reload PASS');
