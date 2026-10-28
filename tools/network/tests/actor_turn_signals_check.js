// Actual inspector handlers, save/reload and preview sides; never touches live scene files.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const ActorSignals = require('../editor/actor_signals.js');
const clone = value => JSON.parse(JSON.stringify(value));
const listeners = {}, cases = [];
const pane = {innerHTML:'',addEventListener:(kind,fn) => {listeners[kind] = fn;},querySelectorAll:() => [],querySelector:() => null};
const context = vm.createContext({
  Layout,ActorSignals,document:{querySelector:s => s === '#inspector' ? pane : {addEventListener:() => {},dataset:{},classList:{toggle:() => {}}}},
  Scene3D:{refresh:() => {},setSelection:() => {}},Tracks:{apply:() => {}},
  Thumbs:{fillAll:() => {},img:() => ''},setTimeout:() => 0,clearTimeout:() => {},
});
for (const name of ['catalog','driver_signal','app','inspector']) vm.runInContext(fs.readFileSync(require.resolve('../editor/'+name+'.js'),'utf8'),context);
const App = vm.runInContext('App',context), state = App.state;
App.renderPanels = () => App.renderInspector();
state.catalog = {actorTypes:{bus:{asset:'template/actor_0.glb'}}};
state.S = {schema:1,id:'fixture',crop:90,layout:Layout.template('cross',90),question:{maneuver:'straight'},roads:[],markings:[],lawns:[],routes:[],lights:[],actors:[{
  id:'bus',type:'bus',name:'Автобус',pos:[-1.75,-35],yaw:0,scale:[1,1,1],halfLength:3,halfWidth:1,way:'straight',maxSpeed:10,
  behaviour:{waitsForPlayer:true,staysPut:false,signalPlan:[{from:0,to:18,side:'right'}]},
}]};
Layout.apply(state.S);
state.id = state.S.id; state.savedJson = JSON.stringify(state.S); state.undo = []; state.redo = [];
const actor = () => state.S.actors[0];
const select = () => App.select({t:'actor',id:'bus'});
const chip = (key,value) => listeners.click({target:{closest:s => s === '[data-chip]' ? {dataset:{chip:key,value}} : null}});
const change = value => listeners.change({target:{closest:s => s === '[data-text]' ? {dataset:{text:'turnSignal'},value} : null}});
const fixture = (name,side) => cases.push({name,side,scene:clone(state.S)});
select();
assert.match(pane.innerHTML,/<select data-text="turnSignal">/);
assert.match(pane.innerHTML,/<option value="auto" selected>/);
for (const [way,side] of [['left','L'],['right','R'],['uturn','L'],['straight','']]) {
  chip('way',way);
  assert.equal(ActorSignals.side(actor(),state.S),side,'chosen manoeuvre beats the legacy signal side');
  fixture('automatic '+way,side);
}
// A difficult/manual path is deliberately independent of the lamp choice.
state.S.routes.find(r => r.id === actor().route).manual = true;
const original = clone(state.S), motion = clone(actor()); delete motion.behaviour;
for (const [setting,side] of [['left','L'],['right','R'],['off','']]) {
  change(setting);
  assert.equal(ActorSignals.mode(actor()),setting);
  assert.equal(ActorSignals.side(actor(),state.S),side);
  assert.deepEqual(clone(state.S.routes),original.routes,'lamp choice cannot regenerate the manual path');
  assert.deepEqual(clone(state.S.roads),original.roads);
  const actual = clone(actor()); delete actual.behaviour;
  assert.deepEqual(actual,motion,'pose, movement intention, size and speed stay intact');
  assert.equal(actor().behaviour.waitsForPlayer,true);
  assert.deepEqual(clone(actor().behaviour.signalPlan),original.actors[0].behaviour.signalPlan);
  const reloaded = clone(state.S); Layout.apply(reloaded);
  assert.equal(ActorSignals.mode(reloaded.actors[0]),setting,'save/reload retains manual lamp');
  fixture('manual '+setting,side);
  const lit = ActorSignals.litSides(actor(),state.S,0);
  assert.deepEqual(lit,{left:side === 'L',right:side === 'R'});
  assert.deepEqual(ActorSignals.litSides(actor(),state.S,.4),{left:false,right:false});
}
App.undo(); select(); assert.equal(ActorSignals.mode(actor()),'right');
App.redo(); select(); assert.equal(ActorSignals.mode(actor()),'off');
change('auto'); assert.equal(Object.hasOwn(actor().behaviour,'turnSignal'),false);
chip('way','left'); assert.equal(ActorSignals.side(actor(),state.S),'L');
fixture('return to automatic','L');
change('right');
ActorSignals.setHazards(actor(),true);
assert.deepEqual(ActorSignals.litSides(actor(),state.S,0),{left:true,right:true},'hazards take precedence');
ActorSignals.setHazards(actor(),false);
assert.deepEqual(ActorSignals.litSides(actor(),state.S,0),{left:false,right:true},'turn selection survives hazards');
fixture('manual right after hazards','R');
actor().behaviour.staysPut = true; actor().route = null;
fixture('stationary manual right','R');
assert.equal(ActorSignals.side(actor(),state.S),'R','stationary vehicle needs no recognised route');
for (const type of ['car','truck','bus','van','special','tanker','motorcycle','tram','tractor']) {
  assert.equal(ActorSignals.side({type,way:'straight',behaviour:{turnSignal:'left'}}),'L');
}
for (const type of ['pedestrian','cyclist','cart','train']) {
  assert.equal(ActorSignals.side({type,behaviour:{turnSignal:'left'}}),'');
}
const pathScene = {routes:[{id:'own',points:[[0,0],[0,10],[10,10],[20,10]]}]};
assert.equal(ActorSignals.side({type:'car',route:'own'},pathScene),'L','manual path can still be inferred in automatic mode');
const beforeInvalid = clone(actor()); change('invalid'); ActorSignals.setTurn(actor(),'invalid');
assert.deepEqual(clone(actor()),beforeInvalid);
if (process.argv[2]) fs.writeFileSync(process.argv[2],JSON.stringify(cases));
console.log('Actor turn signals: automatic manoeuvres, manual/auto/off, actual inspector, unchanged paths, preview, undo/reload PASS');
