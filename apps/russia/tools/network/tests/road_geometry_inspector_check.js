// Exact road geometry fields use the real inspector, generated roads, and undo history.
// Everything is an in-memory fixture; authored scenes are never loaded or saved.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = value => JSON.parse(JSON.stringify(value));
const listeners = {}, messages = [];
const pane = {innerHTML:'',addEventListener:(name,fn) => {listeners[name] = fn;},querySelectorAll:() => [],querySelector:() => null};
const node = {addEventListener:() => {},dataset:{},classList:{toggle:() => {}},textContent:''};
const context = vm.createContext({Layout,
  document:{querySelector:selector => selector === '#inspector' ? pane : node},
  Scene3D:{refresh:() => {},setSelection:() => {}},Tracks:{apply:() => {}},
  Thumbs:{fillAll:() => {},img:() => ''},setTimeout:() => 0,clearTimeout:() => {},
});
for (const file of ['catalog.js','actor_signals.js','app.js','direction_marking.js','actor_appearance.js','driver_signal.js','inspector.js']) {
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
}
const App = vm.runInContext('App',context), state = App.state;
App.renderPanels = () => App.renderInspector();
App.toast = message => messages.push(message);
const scene = {schema:1,id:'road-properties',crop:90,
  layout:{nodes:[{id:'a',x:-30,z:-30},{id:'b',x:-30,z:30},{id:'c',x:15,z:45}],streets:[
    {id:'main',a:'a',b:'b',kind:'street',bend:[0,0],ends:{b:{stop:true}}},
    {id:'neighbor',a:'b',b:'c',kind:'yard',bend:[0,35],surface:'sand'},
  ],player:{street:'main',toward:'b'}},
  question:{maneuver:'straight',yieldTo:[]},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],decor:[],signs:[]};
scene.signs.push({id:'sign',pos:[40,40],yaw:0,code:'2.4'});
scene.routes.push({id:'authored',kind:'choice',manual:true,points:[[5,5],[12,12],[15,6]],label:'A'});
Layout.apply(scene);
state.S = scene; state.id = scene.id; state.savedJson = JSON.stringify(scene); state.undo = []; state.redo = [];
state.catalog = {props:[],actorTypes:{}};
const street = () => Layout.streetOf(state.S.layout,'main');
const roadNode = id => Layout.nodeOf(state.S.layout,id);
const arcLength = () => Layout.polyLen(Layout.centreline(state.S.layout,street()));
const text = (key,value) => listeners.change({target:{closest:selector => selector === '[data-text]' ? {dataset:{text:key},value:String(value)} : null}});
const act = name => listeners.click({target:{closest:selector => selector === '[data-act]' ? {dataset:{act:name}} : null}});
const immutable = () => clone({signs:state.S.signs,route:state.S.routes.find(r=>r.id==='authored')});
const authors = immutable();
const original = JSON.stringify(state.S);
App.select({t:'street',id:'main'});
assert.match(pane.innerHTML,/data-text="road-length"/);
assert.match(pane.innerHTML,/data-text="road-heading"/);
assert.match(pane.innerHTML,/A → B/);
assert.doesNotMatch(pane.innerHTML,/<details|<summary/);
assert.equal(JSON.stringify(state.S),original,'opening road geometry never regenerates a scene');

text('road-heading',90);
assert.equal(state.undo.length,1);
assert.deepEqual(clone(roadNode('a')),{id:'a',x:-30,z:-30},'A stays fixed while direction changes');
assert.deepEqual(clone(roadNode('b')),{id:'b',x:30,z:-30},'heading moves B');
assert.deepEqual(clone(street().bend),[0,-60],'curve rotates with the road');
assert.deepEqual(immutable(),authors,'manual paths and independent objects stay intact');
const rotated = JSON.stringify(state.S);
App.undo(); assert.equal(JSON.stringify(state.S),original);
App.redo(); assert.equal(JSON.stringify(state.S),rotated);

const oldLength = arcLength(), originalBend = clone(street().bend);
text('road-length',oldLength/2);
assert.equal(state.undo.length,2);
assert(Math.abs(arcLength()-oldLength/2)<.01,'length field measures the curved road, not the chord');
assert.deepEqual(clone(roadNode('a')),{id:'a',x:-30,z:-30});
assert.deepEqual(clone(street().bend),[(-30+originalBend[0])/2,(-30+originalBend[1])/2]);
assert.deepEqual(immutable(),authors);

const beforeInvalid = JSON.stringify(state.S), invalidHistory = state.undo.length;
for (const [key,value] of [['road-length',''],['road-length','NaN'],['road-length',0],['road-heading','Infinity'],['road-heading',720]]) text(key,value);
assert.equal(JSON.stringify(state.S),beforeInvalid);
assert.equal(state.undo.length,invalidHistory,'invalid numeric values create no undo step');
text('road-length',350);
assert.equal(JSON.stringify(state.S),beforeInvalid,'a road outside the scene is rejected atomically');
assert.equal(state.undo.length,invalidHistory);
assert(messages.length>0);
messages.length=0;
text('road-heading',-270);
assert.equal(JSON.stringify(state.S),beforeInvalid,'equivalent angle is a no-op');
assert.equal(messages.length,0,'equivalent angle is not reported as an error');

const beforeStraight = JSON.stringify(state.S);
act('straighten');
assert.equal(street().bend,undefined);
assert.equal(state.undo.length,invalidHistory+1);
assert.match(pane.innerHTML,/data-act="straighten" disabled/);
assert.deepEqual(immutable(),authors);
App.undo(); assert.equal(JSON.stringify(state.S),beforeStraight);

App.select({t:'node',id:'a'});
assert.match(pane.innerHTML,/data-text="node-x"/);
const beforeNode = JSON.stringify(state.S), nodeHistory = state.undo.length;
text('node-x',-29.987);
assert.equal(roadNode('a').x,-29.987,'typed coordinates do not snap');
assert.equal(state.undo.length,nodeHistory+1);
App.undo(); assert.equal(JSON.stringify(state.S),beforeNode);
text('node-z',120);
assert.equal(JSON.stringify(state.S),beforeNode,'outside coordinates are rejected');
text('node-z','');
assert.equal(JSON.stringify(state.S),beforeNode,'empty coordinates cannot become zero');
state.locked.add('roads');
text('node-x',10);
assert.equal(JSON.stringify(state.S),beforeNode,'road lock also protects exact coordinates');
App.select({t:'street',id:'main'});
text('road-heading',45); act('straighten');
assert.equal(JSON.stringify(state.S),beforeNode,'locked road ignores geometric actions');
assert.deepEqual(immutable(),authors);
console.log('Road geometry inspector: exact heading/arc length, fixed A, shape preservation, node coordinates, rejection, locks and undo PASS');
