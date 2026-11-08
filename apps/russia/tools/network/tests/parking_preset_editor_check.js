// A complete inserted site transforms together; individual objects remain independent.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const Presets=require('../editor/parking_presets.js');
const elements=new Map(),element=()=>({hidden:true,dataset:{},classList:{toggle(){},add(){},remove(){}},addEventListener(){}});
const context=vm.createContext({document:{querySelector:key=>{if(!elements.has(key))elements.set(key,element());return elements.get(key);}},
 Scene3D:{refresh(){},setSelection(){}},setTimeout:()=>0,clearTimeout(){},console});
vm.runInContext(fs.readFileSync(require.resolve('../editor/app.js'),'utf8'),context);
const App=vm.runInContext('App',context),clone=o=>JSON.parse(JSON.stringify(o));
const preset={id:'fuel',decor:[
 {prop:'parking/fuel_pump',pos:[2,3],yaw:0,scale:[1,1,1]},
 {prop:'parking/fuel_canopy',pos:[0,1],yaw:0,scale:[1,1,1]},
 {prop:'parking/fuel_roof',pos:[0,1],yaw:0,scale:[1,1,1]}],
 roads:[{name:'Apron',exact:true,outer:[[-10,-10],[10,-10],[10,10],[-10,10]],holes:[]}],
 markings:[{type:'solid',points:[[-1,-4],[1,-4]]}]};
const scene={id:'preset-editor-fixture',question:{},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],decor:[]};
App.state.S=scene;App.state.id=scene.id;App.renderPanels=()=>{};
const refs=Presets.place(scene,preset,[20,30],0);
// The production placement adds this grouping metadata; keep the fixture explicit.
for(const key of ['decor','roads','markings'])for(const o of scene[key])o.presetInstance='fuel_1';
App.state.savedJson=JSON.stringify(scene);App.select(refs);
assert(refs.every(App.canCopy),'the entire site includes its authored apron in copies');
const before=JSON.stringify(scene);
App.rotate(90);
assert.deepEqual(clone(scene.decor[0].pos),[17,32],'pump offset rotates around the site centre');
assert.deepEqual(clone(scene.decor[1].pos),[19,30]);assert.deepEqual(clone(scene.decor[2].pos),[19,30],'roof remains aligned with its columns');
assert.deepEqual(clone(scene.roads[0].outer[0]),[30,20],'apron rotates around the same centre');
assert.deepEqual(clone(scene.markings[0].points),[[24,29],[24,31]]);
assert.equal(scene.decor[0].yaw,-1.571);
App.undo();assert.equal(JSON.stringify(App.state.S),before);App.redo();
const original=clone(App.state.S),count=refs.length;
App.duplicate(25);
assert.equal(App.state.sel.length,count,'whole-site duplicate contains props, apron and markings');
assert.equal(App.state.S.roads.length,2);
const copied=App.state.sel.map(App.objectOf),instance=copied[0].presetInstance;
assert(instance && instance!=='fuel_1');assert(copied.every(o=>o.presetInstance===instance));
const all=()=>['decor','roads','markings'].flatMap(key=>App.state.S[key]);
const originalMembers=()=>all().filter(o=>o.presetInstance==='fuel_1');
const originalSnapshot=JSON.stringify(originalMembers()),copyBefore=JSON.stringify(copied);
App.rotate(45);
assert.equal(JSON.stringify(originalMembers()),originalSnapshot,'rotating a copied assembly never moves the original');
const canopy=all().find(o=>o.presetInstance===instance&&o.prop==='parking/fuel_canopy');
const roof=all().find(o=>o.presetInstance===instance&&o.prop==='parking/fuel_roof');
assert.deepEqual(clone(canopy.pos),clone(roof.pos));assert.equal(canopy.yaw,roof.yaw);
App.undo();assert.equal(JSON.stringify(App.state.sel.map(App.objectOf)),copyBefore);
const pump=App.state.S.decor.find(o=>o.presetInstance==='fuel_1'&&o.prop==='parking/fuel_pump');
App.select({t:'decor',id:pump.id});const position=clone(pump.pos),sibling=JSON.stringify(App.state.S.decor.find(o=>o.presetInstance==='fuel_1'&&o.prop==='parking/fuel_canopy'));
App.rotate(15);assert.deepEqual(clone(pump.pos),position,'an individually selected part rotates around itself');
assert.equal(JSON.stringify(App.state.S.decor.find(o=>o.presetInstance==='fuel_1'&&o.prop==='parking/fuel_canopy')),sibling);
App.duplicate();const loose=App.objectOf(App.state.sel[0]);assert.equal(loose.presetInstance,undefined,'individual copies detach from the source assembly');
App.select({t:'road',id:App.state.S.roads[0].id});assert(!App.canCopy(App.state.sel[0]),'unrelated raw-road copy semantics remain unchanged');
console.log('PASS complete preset rotation, aligned roof/columns/apron, history, complete duplicate isolation and independent part editing');
