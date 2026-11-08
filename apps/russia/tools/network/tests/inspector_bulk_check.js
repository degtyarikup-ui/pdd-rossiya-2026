// Exercise rendered controls against the real selection, layout and undo stack. No authored files.
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
for (const file of ['catalog.js','actor_signals.js','app.js','direction_marking.js','actor_appearance.js','driver_signal.js','inspector.js']) vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
const App = vm.runInContext('App',context), state = App.state;
App.renderPanels = () => App.renderInspector();
const scene = {schema:1,id:'bulk-test',crop:90,layout:Layout.template('cross',90),question:{maneuver:'straight',yieldTo:[]},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],decor:[],signs:[]};
scene.layout.streets.forEach((st,i) => Object.assign(st,{kind:i === 0 ? 'street' : 'avenue',surface:'asphalt',centre:i === 0 ? 'dashed' : 'solid',walk:i !== 0,edge:i === 0}));
scene.decor = [{id:'tree1',prop:'trees/pine_0',pos:[28,28],yaw:0,scale:[.8,1.2,.8]}, {id:'tree2',prop:'trees/round_0',pos:[34,28],yaw:1,scale:[1,1,1]}];
scene.actors = [{id:'car1',type:'car',pos:[-2,-60],yaw:0,maxSpeed:5,behaviour:{staysPut:true}}, {id:'pedestrian',type:'pedestrian',pos:[22,22],yaw:0,maxSpeed:10,behaviour:{staysPut:true}}];
Layout.apply(scene);
state.S = scene; state.id = scene.id; state.savedJson = JSON.stringify(scene); state.undo = []; state.redo = []; state.catalog = {props:[],actorTypes:{car:{},pedestrian:{}}};
const ids = scene.layout.streets.map(st => st.id), ref = id => ({t:'street',id});
const street = id => state.S.layout.streets.find(st => st.id === id);
const chip = (name,value) => listeners.click({target:{closest:selector => selector === '[data-chip]' ? {dataset:{chip:name,value:String(value)}} : null}});
const act = name => listeners.click({target:{closest:selector => selector === '[data-act]' ? {dataset:{act:name}} : null}});
const dragSlider = (name,value,done) => listeners[done ? 'change' : 'input']({target:{closest:selector => selector === '[data-slider]' ? {dataset:{slider:name},value:String(value)} : null}});
const select = refs => App.select(refs);

select(ids.slice(0,2).map(ref));
assert.match(pane.innerHTML,/Дороги · 2/);
assert.match(pane.innerHTML,/mixed-badge/,'mixed roads show an explicit state');
assert.match(pane.innerHTML,/data-chip="bulk-road-kind"/);
assert.match(pane.innerHTML,/road-profile/,'road profiles are illustrated');
assert.match(pane.innerHTML,/aria-label="Асфальт" aria-pressed="true"/,'quick choices expose their current value accessibly');
assert.equal(state.undo.length,0,'opening the inspector never edits');
const original = clone(state.S.layout.streets), unrelated = clone(state.S.decor), history = state.undo.length;
chip('bulk-road-kind','yard');
assert.equal(state.undo.length,history+1,'one field change across two roads creates one undo step');
assert.deepEqual(state.S.layout.streets.map(st => st.kind),['yard','yard',original[2].kind,original[3].kind]);
assert.deepEqual(clone(state.S.decor),unrelated);
for (const id of ids.slice(0,2)) {
  const previous = original.find(st => st.id === id);
  assert.deepEqual(clone({...street(id),kind:previous.kind}),previous,'changing width preserves every other authored property');
}
App.undo();
assert.deepEqual(clone(state.S.layout.streets),original,'undo restores both roads together');
App.redo();
assert.equal(street(ids[0]).kind,'yard'); assert.equal(street(ids[1]).kind,'yard');
for (const [field,value] of [['centre','double'],['walk',false],['edge',false],['surface','sand']]) {
  const previous = clone(state.S.layout.streets), count = state.undo.length;
  chip('bulk-road-'+field,value);
  assert.equal(state.undo.length,count+1);
  for (const id of ids.slice(0,2)) {
    assert.equal(street(id)[field],value);
    const old = previous.find(st => st.id === id);
    assert.deepEqual(clone({...street(id),[field]:old[field]}),old,'each quick action changes only its field');
  }
  assert.deepEqual(clone(street(ids[2])),previous[2]);
}
for (const id of ids.slice(0,2)) {
  const road = state.S.roads.find(road => road.id === 'road_'+id);
  assert.equal(road.surface,'sand'); assert.equal(road.walk,false); assert.equal(road.edge,false);
}

assert.doesNotMatch(pane.innerHTML,/data-chip="bulk-road-centre"|data-toggle="bulk-road-(?:walk|edge)"/, "a dirt road only shows applicable settings");
// A mixed selection exposes separate sections; applying road options leaves scenery untouched.
select([ref(ids[0]),ref(ids[1]),{t:'decor',id:'tree1'},{t:'actor',id:'car1'}]);
assert.match(pane.innerHTML,/Окружение · 1/); assert.match(pane.innerHTML,/Участники · 1/);
const others = clone({decor:state.S.decor,actors:state.S.actors});
chip('bulk-road-surface','asphalt');
assert.deepEqual(clone({decor:state.S.decor,actors:state.S.actors}),others);

// Locks are checked when the action runs, not only when the selection was made.
const beforeLocked = clone(state.S.layout.streets), lockedHistory = state.undo.length;
state.locked.add('roads');
chip('bulk-road-kind','highway');
assert.deepEqual(clone(state.S.layout.streets),beforeLocked);
assert.equal(state.undo.length,lockedHistory);
App.renderInspector(); assert.match(pane.innerHTML,/Заблокировано: 2/);
chip('tint','#3e7c42');
assert.equal(state.S.decor[0].tint,'#3e7c42');
assert.deepEqual(clone(state.S.layout.streets),beforeLocked,'editing unlocked scenery preserves locked roads');
state.locked.clear();

// Explicit group values and per-actor compatibility retain unrelated behaviour flags.
select([{t:'decor',id:'tree1'},{t:'decor',id:'tree2'},{t:'actor',id:'car1'},{t:'actor',id:'pedestrian'}]);
chip('bulk-scale',1.25);
assert.ok(state.S.decor.every(d => d.scale.every(value => value === 1.25)));
const scaleHistory = state.undo.length;
dragSlider('scale',1.1,false); dragSlider('scale',1.3,true);
assert.equal(state.undo.length,scaleHistory+1,'a whole slider gesture has one undo step');
assert.ok(state.S.decor.every(d => d.scale.every(value => value === 1.625)));
App.undo(); assert.ok(state.S.decor.every(d => d.scale.every(value => value === 1.25)));
dragSlider('scale',.8,true);
assert.ok(state.S.decor.every(d => d.scale.every(value => value === 1)),'slider is rebound to restored objects after undo');
const speedHistory = state.undo.length;
chip('bulk-speed','fast');
assert.equal(state.undo.length,speedHistory+1); assert.ok(state.S.actors.every(actor => actor.maxSpeed === 15));
chip('bulk-signal','left');
assert.equal(state.S.actors[0].behaviour.turnSignal,'left');
assert.equal(state.S.actors[0].behaviour.staysPut,true);
assert.equal(state.S.actors[1].behaviour.turnSignal,undefined,'pedestrians do not receive vehicle signals');
App.undo(); assert.equal(state.S.actors[0].behaviour.turnSignal,undefined);

// Selecting all roads and clearing use the actual selection API and honour hidden/locked layers.
select(ref(ids[0]));
assert.match(pane.innerHTML,/data-chip="surface"/); assert.doesNotMatch(pane.innerHTML,/<details|<summary|по ней едет игрок/);
assert.match(pane.innerHTML,/data-text="player-end"/);
chip('edge',true); assert.equal(street(ids[0]).edge,true);
act('select-roads'); assert.deepEqual(clone(state.sel),ids.map(ref));
act('clear-selection'); assert.equal(state.sel.length,0);
assert.match(pane.innerHTML,/data-act="select-roads"/);
state.hidden.add('roads'); act('select-roads'); assert.equal(state.sel.length,0);
state.hidden.clear(); state.locked.add('roads'); act('select-roads'); assert.equal(state.sel.length,0);
state.locked.clear(); act('select-roads'); assert.equal(state.sel.length,4);
const invalidHistory = state.undo.length;
chip('bulk-road-kind','invalid'); chip('bulk-road-centre','invalid'); chip('bulk-road-walk','invalid');
assert.equal(state.undo.length,invalidHistory,'invalid quick-action values cannot corrupt the plan');

// Suppressed markings remain explicit; returning to automatic lines never deletes authored lines.
street(ids[0]).surface = 'sand'; street(ids[0]).manualMarks = true;
street(ids[1]).kind = 'avenue'; street(ids[1]).median = 3; street(ids[2]).manualMarks = true;
const authored = {id:'authored-marking',type:'solid',colour:'yellow',points:[[25,28],[31,37]]};
state.S.markings.push(clone(authored));
select(ids.slice(0,2).map(ref));
assert.doesNotMatch(pane.innerHTML,/data-chip="bulk-road-centre"/, "manual, unpaved and divided streets have no automatic centre line to set");
const oldCentres = ids.slice(0,2).map(id => street(id).centre);
assert.match(pane.innerHTML,/Вернуть авторазметку/);
chip('bulk-road-centre','solid');
assert.deepEqual(ids.slice(0,2).map(id => street(id).centre),oldCentres, 'an inapplicable bulk control leaves stored preferences intact');
assert.equal(street(ids[0]).manualMarks,true,'ordinary centre choices do not silently discard manual mode');
const beforeAuto = clone(state.S.layout.streets), autoHistory = state.undo.length;
act('bulk-road-marks-auto');
assert.equal(state.undo.length,autoHistory+1,'explicit bulk auto mode is one undo step');
assert.equal(street(ids[0]).manualMarks,undefined); assert.equal(street(ids[2]).manualMarks,true);
assert.deepEqual(clone({...street(ids[0]),manualMarks:true}),beforeAuto[0],'returning to auto only changes the selected manualMarks flag');
assert.deepEqual(clone(state.S.markings.find(mark => mark.id === authored.id)),authored,'author markings remain intact');
App.undo(); assert.equal(street(ids[0]).manualMarks,true); assert.equal(street(ids[2]).manualMarks,true);
state.locked.add('roads');
const lockedAutoHistory = state.undo.length;
act('bulk-road-marks-auto');
assert.equal(street(ids[0]).manualMarks,true); assert.equal(state.undo.length,lockedAutoHistory);
state.locked.clear(); select(ref(ids[0])); act('marks-auto');
assert.equal(street(ids[0]).manualMarks,undefined,'the same explicit action works for a single road');
assert.deepEqual(clone(state.S.markings.find(mark => mark.id === authored.id)),authored);
state.locked.add('actors');
select({t:'actor',id:'car1'}); // A related-object link can open a locked object.
assert.match(pane.innerHTML,/Слой заблокирован/);
const beforePaint = JSON.stringify(state.S), beforeSteps = state.undo.length;
chip('paint','#C0392B');
assert.equal(JSON.stringify(state.S),beforePaint);
assert.equal(state.undo.length,beforeSteps,'inspecting a locked actor cannot create a history entry');
// A through-highway offers the four possible end combinations in one control.
state.locked.clear();
state.S.layout = {
  nodes:[{id:"west",x:-90,z:0},{id:"east",x:90,z:0}],
  streets:[{id:"through",a:"west",b:"east",kind:"highway",ends:{}}],
  player:{street:"through",toward:"west",lane:1,questionAt:48},
};
Layout.apply(state.S);
select(ref("through"));
const choose = (key,value) => listeners.change({target:{closest:s => s === "[data-text]" ? {dataset:{text:key},value} : null}});
assert.match(pane.innerHTML, /data-text="highway-preset"/);
assert.doesNotMatch(pane.innerHTML, /data-chip="port-/);
const originalPlayer = clone(state.S.layout.player), beforeDirection = state.undo.length;
choose("player-end","west");
assert.deepEqual(clone(state.S.layout.player),originalPlayer,"choosing the current direction preserves authored lane and distance");
assert.equal(state.undo.length,beforeDirection);
for (const [preset,a,b] of [["entry","highway","avenue"],["both","avenue","avenue"],["exit","avenue","highway"],["through","highway","highway"]]) {
  choose("highway-preset",preset);
  assert.equal(Layout.highwayPort(street("through"),"a"),a);
  assert.equal(Layout.highwayPort(street("through"),"b"),b);
  assert.match(pane.innerHTML,new RegExp(`value="${preset}" selected`));
}
console.log('Inspector bulk editing: real handlers, mixed selection, locks, generated geometry and undo passed');

// Explicit zero survives regeneration and a single road has the same median choices.
chip('median','0');
assert.equal(Layout.medianOf(street('through')),0);
assert.equal(street('through').median,0);
assert.equal(state.S.roads.find(r=>r.id==='road_through').holes.length,0);
App.undo();assert.equal(Layout.medianOf(street('through')),3);
App.redo();assert.equal(Layout.medianOf(street('through')),0);

state.S.layout=Layout.template('cross',90);
for(const st of state.S.layout.streets) st.kind='highway';
Layout.apply(state.S);
const group=state.S.layout.streets.slice(0,2).map(st=>st.id);
select(group.map(ref));
for(const key of ['median','port','stop-style','ends']) assert.match(pane.innerHTML,new RegExp(`data-chip="bulk-road-${key}"`));
for(const key of ['length','heading','approach']) assert.match(pane.innerHTML,new RegExp(`data-text="bulk-road-${key}"`));
const flag=(name,checked)=>listeners.change({target:{closest:s=>s==='[data-toggle]'?{dataset:{toggle:name},checked}:null}});
const beforeMedian=clone(state.S.layout), countMedian=state.undo.length;
chip('bulk-road-median',0);
assert.equal(state.undo.length,countMedian+1);
for(const id of group) { assert.equal(Layout.medianOf(street(id)),0);assert.equal(state.S.roads.find(r=>r.id==='road_'+id).holes.length,0); }
assert.equal(Layout.medianOf(state.S.layout.streets[2]),3);
App.undo();assert.deepEqual(clone(state.S.layout),beforeMedian);
App.redo();assert(group.every(id=>street(id).median===0));
const beforeEnds=clone(state.S.layout), countEnds=state.undo.length;
flag('bulk-road-end-stop',true);
assert.equal(state.undo.length,countEnds+1);
for(const id of group) for(const end of ['a','b']) {
  const st=street(id), kind=Layout.nodeKind(state.S.layout,Layout.nodeOf(state.S.layout,st[end]),90);
  assert.equal(!!st.ends?.[end]?.stop,kind==='junction');
}
App.undo();assert.deepEqual(clone(state.S.layout),beforeEnds);App.redo();
flag('bulk-road-end-zebra',true);
chip('bulk-road-stop-style','yield');
for(const id of group) assert(state.S.markings.some(m=>m.street===id&&m.stopStyle==='yield'));
choose('bulk-road-approach','4');
for(const id of group) {
  const st=street(id), nid=[st.a,st.b].find(n=>Layout.nodeKind(state.S.layout,Layout.nodeOf(state.S.layout,n),90)==='junction');
  assert.equal(Layout.endOffset(state.S.layout,st,nid,90),4);
}
act('bulk-road-approach-reset');
for(const id of group) assert(Object.values(street(id).ends).every(e=>!e.approachOffset));
chip('bulk-road-port','avenue');
for(const id of group) for(const end of ['a','b']) {
  const st=street(id), border=Layout.nodeKind(state.S.layout,Layout.nodeOf(state.S.layout,st[end]),90)==='border';
  assert.equal(Layout.highwayPort(st,end),border?'avenue':'highway');
}
chip('bulk-road-ends','a');
const scopedBefore=clone(state.S.layout);
flag('bulk-road-end-stop',false);
for(const id of group) assert.deepEqual(clone(street(id).ends?.b),scopedBefore.streets.find(st=>st.id===id).ends?.b);
chip('bulk-road-ends','both');
const autoLines=state.S.markings.filter(m=>m.auto&&group.includes(m.street)&&['solid','dashed'].includes(m.type)).length;
const manualBefore=state.S.markings.filter(m=>!m.auto).length;
act('bulk-road-marks-own');
assert.equal(state.S.markings.filter(m=>!m.auto).length,manualBefore+autoLines);
assert(group.every(id=>street(id).manualMarks));
App.undo();assert(group.every(id=>!street(id).manualMarks));
chip('bulk-road-kind','street');chip('bulk-road-surface','sand');
assert.match(pane.innerHTML,/data-text="bulk-road-paved"/);
choose('bulk-road-paved','12');
assert(group.every(id=>Object.values(street(id).ends).some(e=>e.paved===12)));
const lockedPlan=JSON.stringify(state.S.layout), lockedCount=state.undo.length;
state.locked.add('roads');
chip('bulk-road-median',5);chip('bulk-road-port','highway');flag('bulk-road-end-stop',true);choose('bulk-road-paved','5');choose('bulk-road-length','30');act('bulk-road-marks-own');
assert.equal(JSON.stringify(state.S.layout),lockedPlan);assert.equal(state.undo.length,lockedCount);
state.locked.clear();

// Independent roads can receive exact geometry together, with one undo record.
state.S.layout={preserveSource:true,nodes:[{id:'a',x:-30,z:-30},{id:'b',x:-30,z:10},{id:'c',x:30,z:-30},{id:'d',x:30,z:30}],streets:[{id:'one',a:'a',b:'b',kind:'street'},{id:'two',a:'c',b:'d',kind:'street'}]};
Layout.apply(state.S);select(['one','two'].map(ref));
const geomBefore=clone(state.S.layout),geomCount=state.undo.length;
choose('bulk-road-length','25');
assert.equal(state.undo.length,geomCount+1);
for(const st of state.S.layout.streets) assert(Math.abs(Layout.polyLen(Layout.centreline(state.S.layout,st))-25)<.01);
App.undo();assert.deepEqual(clone(state.S.layout),geomBefore);App.redo();
choose('bulk-road-heading','45');
for(const st of state.S.layout.streets) {const a=Layout.nodeOf(state.S.layout,st.a),b=Layout.nodeOf(state.S.layout,st.b);assert(Math.abs(b.x-a.x-(b.z-a.z))<.01);}
console.log('Expanded road controls: zero median, ends, ports, markings, geometry, eligibility, locks and undo PASS');
const validGeometry=JSON.stringify(state.S.layout),validSteps=state.undo.length;
App.toast=()=>{};
choose('bulk-road-length','360');
assert.equal(JSON.stringify(state.S.layout),validGeometry,'out-of-bounds group dimensions are rejected without partial edits');
assert.equal(state.undo.length,validSteps);
for(const invalid of ['', 'NaN', '-1']) choose('bulk-road-length',invalid);
assert.equal(JSON.stringify(state.S.layout),validGeometry);
assert.equal(state.undo.length,validSteps);
