// Inspect and edit a copy of the real 139-vertex turning area without converting it.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = value => JSON.parse(JSON.stringify(value));
const listeners = {};
const pane = {innerHTML:'',addEventListener:(name,fn)=>{listeners[name]=fn;},querySelectorAll:()=>[],querySelector:()=>null};
const node = {addEventListener:()=>{},dataset:{},classList:{toggle:()=>{}},textContent:''};
const context = vm.createContext({Layout,
  document:{querySelector:selector=>selector==='#inspector'?pane:node},
  Scene3D:{refresh:()=>{},setSelection:()=>{}},Tracks:{apply:()=>{throw new Error('native edit rebuilt tracks');}},
  Thumbs:{fillAll:()=>{},img:()=>''},setTimeout:()=>0,clearTimeout:()=>{},
});
for(const file of ['catalog.js','actor_signals.js','app.js','direction_marking.js','actor_appearance.js','driver_signal.js','inspector.js']) {
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
}
const App=vm.runInContext('App',context),state=App.state;
App.renderPanels=()=>App.renderInspector();App.toast=()=>{};
const original=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../../../game_godot/network/ticket_9_14.json'),'utf8'));
state.S=clone(original);state.id=original.id;state.savedJson=JSON.stringify(original);state.undo=[];state.redo=[];
state.catalog={props:[],actorTypes:{}};
state.plan=Layout.template('cross',90);
const ref={t:'road',id:'road_0',part:-1};
const select=(extra={})=>App.select({...ref,...extra});
const text=(key,value)=>listeners.change({target:{closest:selector=>selector==='[data-text]'?{dataset:{text:key},value:String(value)}:null}});
const toggle=(key,value)=>listeners.change({target:{closest:selector=>selector==='[data-toggle]'?{dataset:{toggle:key},checked:value}:null}});
const chip=(key,value)=>listeners.click({target:{closest:selector=>selector==='[data-chip]'?{dataset:{chip:key,value}}:null}});
const act=key=>listeners.click({target:{closest:selector=>selector==='[data-act]'?{dataset:{act:key}}:null}});
const road=()=>state.S.roads.find(r=>r.id==='road_0');
const expectOnlyRoad=(expected,message)=>{
  const source=clone(original);source.roads[source.roads.findIndex(r=>r.id==='road_0')]=expected;
  assert.deepEqual(clone(state.S),source,message);
};
const restore=()=>{App.undo();assert.deepEqual(clone(state.S),original);};

assert.equal(road().outer.length,139);
select();
assert.match(pane.innerHTML,/data-text="shape-center-x"/);
assert.match(pane.innerHTML,/data-text="shape-point-z"/);
assert.match(pane.innerHTML,/\/ 139/);
assert.doesNotMatch(pane.innerHTML,/convert|конструктор|<details|<summary/);
assert.deepEqual(clone(state.S),original,'browsing preserves every original vertex and scene field');
assert.equal(state.undo.length,0);

for(const [key,value] of [['shape-surface','sand'],['shape-surface','asphalt']]) {
  chip(key,value);
  const expected=clone(original.roads[0]);expected.surface=value;
  expectOnlyRoad(expected,'a surface edit never detects/replaces the road or regenerates participants');
  restore();
}
toggle('shape-edge',false);
expectOnlyRoad({...clone(original.roads[0]),edge:false});restore();
toggle('shape-walk',false);
expectOnlyRoad({...clone(original.roads[0]),walk:false});restore();
toggle('shape-shoulder',true);
expectOnlyRoad({...clone(original.roads[0]),shoulder:2.5,walk:false});
toggle('shape-walk',true);
expectOnlyRoad({...clone(original.roads[0]),walk:true});
App.undo();restore();

const center=clone(App.shapeCenter(ref));
text('shape-center-x',center[0]+3);
const translated=clone(original.roads[0]);translated.outer=translated.outer.map(([x,z])=>[App.r3(x+3),App.r3(z)]);
expectOnlyRoad(translated,'moving the dense outline preserves its vertex sequence and all other scene data');
assert.deepEqual(clone(App.shapeCenter(ref)),[center[0]+3,center[1]]);
restore();
act('rot90');
const rotated=clone(original.roads[0]);rotated.outer=rotated.outer.map(([x,z])=>[App.r3(center[0]-(z-center[1])),App.r3(center[1]+(x-center[0]))]);
for (let i=0;i<rotated.outer.length;i++) for (let axis=0;axis<2;axis++) assert(Math.abs(road().outer[i][axis]-rotated.outer[i][axis])<.0011,'rotation uses a stable bounds center, independent of vertex density');
expectOnlyRoad({...clone(original.roads[0]),outer:clone(road().outer)},'rotation preserves all unrelated authored data');
restore();

text('shape-index',139);
assert.equal(state.sel[0].v,138);
assert.equal(state.undo.length,0,'choosing a vertex is not an edit');
act('shape-insert');
const inserted=clone(original.roads[0]);const first=inserted.outer[0],last=inserted.outer.at(-1);
inserted.outer.push([(first[0]+last[0])/2,(first[1]+last[1])/2]);
expectOnlyRoad(inserted,'inserting at the final segment preserves all 139 existing vertices');
assert.equal(state.sel[0].v,139);
act('shape-remove-point');
assert.deepEqual(clone(state.S),original,'removing only the inserted vertex restores the exact trace');
App.undo();App.undo();assert.deepEqual(clone(state.S),original);
select({v:7});
const coordinate=original.roads[0].outer[7][0]+.12345;
text('shape-point-x',coordinate);
const movedPoint=clone(original.roads[0]);movedPoint.outer[7][0]=coordinate;
expectOnlyRoad(movedPoint,'exact vertex edits touch one coordinate only');
restore();
const history=state.undo.length;
for(const [key,value] of [['shape-center-x',''],['shape-center-z','Infinity'],['shape-point-x','NaN'],['shape-index',0],['shape-index',140]])text(key,value);
assert.deepEqual(clone(state.S),original);assert.equal(state.undo.length,history);
state.locked.add('roads');
text('shape-center-x',4);text('shape-point-z',8);toggle('shape-shoulder',true);chip('shape-surface','sand');act('shape-insert');act('shape-remove-point');act('shape-delete');act('rot90');
assert.deepEqual(clone(state.S),original,'all native shape actions honour the road layer lock');
state.locked.clear();

// Interior rings move/rotate/edit independently; whole-road transforms keep rings together.
state.S=clone(original);road().holes=[[[10,10],[13,10],[13,14],[10,14]]];state.undo=[];state.redo=[];
const withHole=clone(state.S);select();
assert.match(pane.innerHTML,/data-text="shape-contour"/);
text('shape-contour',0);assert.equal(state.sel[0].part,0);
assert.doesNotMatch(pane.innerHTML,/data-chip="shape-surface"/,'island properties do not pretend to change the road surface');
text('shape-center-x',12.5);
assert.deepEqual(clone(road().outer),original.roads[0].outer);
assert.deepEqual(clone(road().holes[0]),[[11,10],[14,10],[14,14],[11,14]]);
App.undo();assert.deepEqual(clone(state.S),withHole);
select({part:0,v:1});act('shape-remove-point');assert.equal(road().holes[0].length,3);
const triangle=JSON.stringify(state.S);act('shape-remove-point');assert.equal(JSON.stringify(state.S),triangle,'an island keeps at least three vertices');
act('shape-delete');assert.equal(road().holes.length,0);assert.equal(road().outer.length,139);
assert.equal(state.sel[0].part,-1);
App.undo();assert.equal(road().holes[0].length,3);
select({v:1});act('shape-delete');
assert.equal(state.S.roads.length,0,'Delete road removes the road, even when a vertex is selected');
App.undo();assert.equal(road().outer.length,139);

console.log('Native shape inspector: real 139-point trace unchanged on view, native flags/position/rotation, exact vertex edits, islands, locks, no regeneration and undo PASS');
