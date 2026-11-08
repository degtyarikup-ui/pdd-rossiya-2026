// Exercise the real inspector, undo/redo and generated road metadata without saving a scene.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = value => JSON.parse(JSON.stringify(value));
const listeners = {};
const pane = {innerHTML:'', addEventListener:(kind,fn) => {listeners[kind] = fn;}, querySelectorAll:() => []};
const context = vm.createContext({
  Layout, document:{querySelector:s => s === '#inspector' ? pane : {addEventListener:() => {},dataset:{},classList:{toggle:() => {}}}},
  Scene3D:{refresh:() => {},setSelection:() => {}},Tracks:{apply:() => {}},
  Thumbs:{fillAll:() => {},img:() => ''},setTimeout:() => 0,clearTimeout:() => {},
});
vm.runInContext(fs.readFileSync(require.resolve('../editor/app.js'),'utf8')+'\nglobalThis.testApp = App;',context);
const App = context.testApp, state = App.state;
vm.runInContext(fs.readFileSync(require.resolve('../editor/direction_marking.js'),'utf8'),context);
vm.runInContext(fs.readFileSync(require.resolve('../editor/actor_appearance.js'),'utf8'),context);
vm.runInContext(fs.readFileSync(require.resolve('../editor/driver_signal.js'),'utf8'),context);
vm.runInContext(fs.readFileSync(require.resolve('../editor/inspector.js'),'utf8'),context);
App.renderPanels = () => App.renderInspector();
const scene = {schema:1,id:'ring-test',crop:90,layout:Layout.template('ring',90),question:{maneuver:'straight'},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[]};
scene.layout.streets.forEach(st => {st.edge = false;});
const manual = {id:'own',type:'solid',colour:'yellow',points:[[-5,-40],[-5,-30]]};
scene.markings.push(manual);
Layout.apply(scene);
state.S = scene; state.id = scene.id; state.savedJson = JSON.stringify(scene); state.undo = []; state.redo = [];
const ring = () => state.S.layout.nodes.find(n => n.ring).ring;
const road = () => state.S.roads.find(r => 'outerEdge' in r);
const select = () => App.select({t:'node',id:'c'});
const toggle = (key,on) => listeners.change({target:{closest:s => s === '[data-toggle]' ? {dataset:{toggle:key},checked:on} : null}});
select();
assert.match(pane.innerHTML,/Внешняя сплошная/);
assert.match(pane.innerHTML,/Сплошная вокруг островка/);
assert.equal(road().outerEdge,true); assert.equal(road().innerEdge,true);
toggle('ring-outer-edge',false);
assert.equal(ring().outerEdge,false); assert.equal(road().outerEdge,false); assert.equal(road().innerEdge,true);
App.undo(); select();
assert.equal(ring().outerEdge,undefined); assert.equal(road().outerEdge,true);
App.redo(); select();
assert.equal(road().outerEdge,false);
toggle('ring-inner-edge',false);
listeners.click({target:{closest:s => s === '[data-chip]' ? {dataset:{chip:'size',value:'l'}} : null}});
assert.equal(ring().r,26); assert.equal(ring().outerEdge,false); assert.equal(ring().innerEdge,false);
const saved = clone(state.S);
Layout.apply(saved);
assert.equal(saved.roads.find(r => 'innerEdge' in r).innerEdge,false,'reload keeps ring settings');
assert.deepEqual(clone(state.S.markings.find(m => m.id === 'own')),manual);
assert.ok(state.S.layout.streets.every(st => st.edge === false),'ring toggles leave all arm settings alone');
toggle('ring-outer-edge',true); toggle('ring-inner-edge',true);
assert.equal(ring().outerEdge,undefined); assert.equal(ring().innerEdge,undefined);
assert.equal(road().outerEdge,true); assert.equal(road().innerEdge,true);
console.log('Roundabout inspector: all checks passed');
