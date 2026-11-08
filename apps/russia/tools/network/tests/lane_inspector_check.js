// Real inspector events and undo on disposable road plans; no scene files are changed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = v => JSON.parse(JSON.stringify(v));
const listeners = {};
const pane = {innerHTML:'',addEventListener:(name,fn)=>{listeners[name]=fn;},querySelectorAll:()=>[],querySelector:()=>null};
const node = {addEventListener(){},dataset:{},classList:{toggle(){}},textContent:''};
const context = vm.createContext({Layout,
  document:{querySelector:selector=>selector==='#inspector'?pane:node},
  Scene3D:{refresh(){},setSelection(){}},Tracks:{apply(){}},Thumbs:{fillAll(){},img:()=>''},setTimeout:()=>0,clearTimeout(){},
});
for (const file of ['catalog.js','actor_signals.js','app.js','direction_marking.js','actor_appearance.js','driver_signal.js','inspector.js']) {
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
}
const App = vm.runInContext('App',context), state = App.state;
App.renderPanels = () => App.renderInspector();
const load = (kind='street',ends={}) => {
  const s = {schema:1,id:'lanes-ui',crop:90,layout:{nodes:[{id:'a',x:0,z:-90},{id:'b',x:0,z:90}],
    streets:[{id:'st',a:'a',b:'b',kind,ends}],player:{street:'st',toward:'b'}},
    question:{maneuver:'straight',yieldTo:[]},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],decor:[],signs:[]};
  Layout.apply(s);
  state.S=s;state.id=s.id;state.savedJson=JSON.stringify(s);state.undo=[];state.redo=[];state.locked.clear();state.catalog={props:[],actorTypes:{}};
  return s;
};
const street = () => state.S.layout.streets[0];
const text = (key,value) => listeners.change({target:{closest:s=>s==='[data-text]'?{dataset:{text:key},value:String(value)}:null}});
const chip = (key,value) => listeners.click({target:{closest:s=>s==='[data-chip]'?{dataset:{chip:key,value}}:null}});
const step = (key,value) => listeners.click({target:{closest:s=>s==='[data-act]'?{dataset:{act:'lane-step',key,step:String(value)}}:null}});

load();const original=JSON.stringify(state.S);App.select({t:'street',id:'st'});
assert.equal(JSON.stringify(state.S),original,'inspecting legacy roads preserves serialized scenes');
for (const key of ['a-left','a-right','b-left','b-right','width','taper']) assert(pane.innerHTML.includes(`data-text="lanes-${key}"`));
assert.doesNotMatch(pane.innerHTML,/<details|<summary/);
assert.match(pane.innerHTML,/class="lane-diagram"/);
text('lanes-a-right',1);
assert.equal(street().lanes,undefined,'unchanged legacy values do not create custom geometry');
assert.equal(state.undo.length,0);

text('lanes-a-right',3);
assert.deepEqual(clone(street().lanes),{a:{left:1,right:3},b:{left:1,right:1},width:4.2,taper:40});
assert.equal(state.undo.length,1,'a number change is one undo operation');
assert.match(pane.innerHTML,/Своя ширина/);
assert.doesNotMatch(pane.innerHTML,/data-chip="kind"[^>]+aria-pressed="true"/);
const custom=JSON.stringify(state.S);
App.undo();assert.equal(JSON.stringify(state.S),original);
App.redo();assert.equal(JSON.stringify(state.S),custom);
text('lanes-width',3.5);text('lanes-taper',60);step('b-left',1);
assert.equal(street().lanes.width,3.5);assert.equal(street().lanes.taper,60);assert.equal(street().lanes.b.left,2);
const before=JSON.stringify(state.S), undo=state.undo.length;
for (const [key,value] of [['a-left',''],['a-left',0],['a-left',7],['a-left',1.5],['b-right','NaN'],['width',2],['width',5],['taper',0],['taper',151]]) text('lanes-'+key,value);
assert.equal(JSON.stringify(state.S),before);assert.equal(state.undo.length,undo,'invalid fields never mutate geometry or history');
state.locked.add('roads');text('lanes-a-left',4);step('b-right',1);chip('kind','avenue');
assert.equal(JSON.stringify(state.S),before,'layer lock protects all lane controls and presets');state.locked.clear();
chip('kind','street');
assert.equal(street().lanes,undefined,'same active base preset resets custom lanes');
assert.equal(street().kind,'street');
App.undo();assert.equal(JSON.stringify(state.S),before,'preset reset can be undone exactly');
text('lanes-b-right',6);const maxHistory=state.undo.length;step('b-right',1);
assert.equal(street().lanes.b.right,6);assert.equal(state.undo.length,maxHistory,'stepper stops at its bound');
chip('kind','avenue');assert.equal(street().lanes,undefined);assert.equal(street().kind,'avenue');

load('highway',{a:{port:'avenue'}});const legacy=JSON.stringify(state.S);App.select({t:'street',id:'st'});
assert.equal(JSON.stringify(state.S),legacy);
assert.match(pane.innerHTML,/data-text="highway-preset"/);
assert.equal(Layout.laneConfig(street()).a.left,2,'legacy authored port counts are visible before editing');
text('lanes-width',3.6);
assert.equal(street().lanes.a.left,2,'first edit preserves legacy explicit endpoint counts');
assert.doesNotMatch(pane.innerHTML,/data-text="highway-preset"|data-chip="port-/,'custom lanes have a single source of endpoint counts');
App.undo();assert.equal(JSON.stringify(state.S),legacy);
load('avenue');state.S.crop=45;state.S.layout.nodes[0].z=-45;state.S.layout.nodes[1].z=45;
Layout.setLaneConfig(street(),{a:{left:2,right:3},b:{left:2,right:2},width:3.5,taper:40});
Layout.apply(state.S);const compact=JSON.stringify(state.S);App.select({t:'street',id:'st'});
assert.match(pane.innerHTML,/data-text="lanes-taper"[^>]*min="5" max="22"[^>]*value="22"/);
assert.equal(JSON.stringify(state.S),compact,'showing the effective transition preserves the authored request');
text('lanes-taper',22);text('lanes-taper',23);
assert.equal(JSON.stringify(state.S),compact,'unchanged actual length and over-limit lengths are not written');
text('lanes-taper',12);assert.equal(street().lanes.taper,12);assert.equal(Layout.laneTransition(state.S.layout,street(),45).length,12);
App.undo();assert.equal(JSON.stringify(state.S),compact);
text('road-length',70);
assert.match(pane.innerHTML,/data-text="lanes-taper"[^>]*max="42"[^>]*value="40"/);
assert.equal(street().lanes.taper,40,'changing geometry leaves the requested transition intact');
App.undo();assert.equal(JSON.stringify(state.S),compact);
console.log('Lane inspector: visible endpoint counters, nonmutating legacy display, real changes/undo, invalid bounds, locks, preset reset and highway transition PASS');
