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
for (const [field,value] of [['surface','sand'],['centre','double'],['walk',false],['edge',false]]) {
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
assert.match(pane.innerHTML,/data-chip="surface"/); assert.match(pane.innerHTML,/inspector-more/);
chip('edge',true); assert.equal(street(ids[0]).edge,true);
act('select-roads'); assert.deepEqual(clone(state.sel),ids.map(ref));
act('clear-selection'); assert.equal(state.sel.length,0);
assert.match(pane.innerHTML,/Выбрать все дороги/);
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
assert.match(pane.innerHTML,/Грунт: без разметки и тротуаров/);
assert.match(pane.innerHTML,/По центру — разделитель/);
assert.match(pane.innerHTML,/Ручная разметка/);
assert.match(pane.innerHTML,/Вернуть авторазметку/);
chip('bulk-road-centre','solid');
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
console.log('Inspector bulk editing: real handlers, mixed selection, locks, generated geometry and undo passed');
