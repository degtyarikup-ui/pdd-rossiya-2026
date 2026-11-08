// Actual pointer handlers, route rebuilds/history and Three.js actor/ghost support.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const SurfaceSupport = require('../editor/surface_support.js');
const THREE = require('../editor/vendor/three.min.js');
const clone = value => JSON.parse(JSON.stringify(value));
const elements = new Map(), pointer = {};
const element = () => ({hidden:false, innerHTML:'', dataset:{}, style:{}, classList:{add(){},remove(){},toggle(){}},
  addEventListener(){},querySelector:()=>null,querySelectorAll:()=>[]});
let hit, ghost;
const context = vm.createContext({Layout, SurfaceSupport, THREE, console, setTimeout:()=>0, clearTimeout(){},
  document:{querySelector:key=>{if(!elements.has(key))elements.set(key,element());return elements.get(key);},querySelectorAll:()=>[]},
  Scene3D:{on:(key,fn)=>pointer[key]=fn,refresh(){},setSelection(){},setDraft(){},setGhost:g=>ghost=g,setHover(){},
    setPanTool(){},setPlanHandles(){},onRoad:x=>Math.abs(x)<4.2,hitAt:()=>hit},
  Thumbs:{fillAll(){},fill(){},img:()=>''}, Tracks:{apply(){},nearest:()=>null},
});
for (const name of ['catalog.js','actor_signals.js','app.js','tools.js'])
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+name),'utf8'),context);
const {App,Tools} = vm.runInContext('({App,Tools})',context);
App.renderPanels=()=>{};
App.state.catalog={actorTypes:{car:{asset:'template/actor_0.glb'}}};
App.state.S={id:'free-actors',crop:90,layout:Layout.template('cross',90),question:{maneuver:'straight'},
  roads:[],routes:[],actors:[],lights:[],decor:[],markings:[],lawns:[]};
Layout.apply(App.state.S);
App.state.id=App.state.S.id;
Tools.init();
const point=(type,x,z)=>pointer.pointer({type,world:{x,z},sx:0,sy:0});
Tools.set('actor');
point('move',-6.125,-30.275);
assert.equal(ghost.x,-6.125,'preview keeps the exact click even within the old five-metre lane magnet');
assert.equal(ghost.z,-30.275);
point('down',-6.125,-30.275);point('up',-6.125,-30.275);
let car=App.state.S.actors[0];
assert.deepEqual(clone(car.pos),[-6.125,-30.275]);
assert.equal(car.behaviour.staysPut,true,'a new car on the pavement is parked by default');
car.way='straight'; // Legacy stationary cars can still carry an automatic way.
Layout.apply(App.state.S);
assert.deepEqual(clone(car.pos),[-6.125,-30.275],'unrelated rebuild preserves a parked car with an old way');
Tools.set('select');
hit={t:'actor',id:car.id};App.select(hit);
const before=clone(car.pos), yaw=car.yaw;
point('down',...before);point('move',-5.875,-22.125);point('up',-5.875,-22.125);
assert.deepEqual(clone(App.state.S.actors[0].pos),[-5.875,-22.125],'release never moves the car back to a lane');
assert.equal(App.state.S.actors[0].yaw,yaw,'release does not change the authored direction');
App.undo();assert.deepEqual(clone(App.state.S.actors[0].pos),before);
App.redo();assert.deepEqual(clone(App.state.S.actors[0].pos),[-5.875,-22.125]);
car=App.state.S.actors[0];car.behaviour.staysPut=false;
car.pos=[-2.375,-32.125];Layout.apply(App.state.S);
let route=App.state.S.routes.find(r=>r.id===car.route);
assert.deepEqual(clone(car.pos),[-2.375,-32.125],'automatic route building cannot move an active car either');
assert.deepEqual(clone(route.points[0]),clone(car.pos),'the driving route starts at its actual location');
route.manual=true;
const oldRoute=clone(route.points);
App.moveRef(App.state.S,{t:'actor',id:car.id},-3,2);Layout.apply(App.state.S);
assert.deepEqual(clone(route.points),oldRoute.map(p=>[p[0]-3,p[1]+2]),'manual path moves with the car');
delete route.manual;car.pos=[-25,-30];Layout.apply(App.state.S);
assert.equal(car.route,null,'moving beyond the road plan clears a stale automatic start');
assert.deepEqual(clone(car.pos),[-25,-30]);

// Drive the real rendering helpers, using actual Three.js transforms without a GPU.
THREE.GLTFLoader=class {load(_url,done){done(null);}};
const viewContext=vm.createContext({THREE,SurfaceSupport,console});
const source=fs.readFileSync(require.resolve('../editor/scene3d.js'),'utf8');
const marker='  return {\n    mount, load, refresh';
assert(source.includes(marker));
vm.runInContext(source.replace(marker,`  return {
    __test: {configure(b) {build=b;scene=new THREE.Scene();}, placeAnchor,
      pose(g) {anchors.set('actor:test',{group:g});}, ghost() {return ghostObj;}},
    mount, load, refresh`),viewContext);
const view=vm.runInContext('Scene3D',viewContext);
if (process.argv[2]) {
  for (const fixture of JSON.parse(fs.readFileSync(process.argv[2],'utf8'))) {
    for (const sample of fixture.samples) {
      const {x,z,y}=sample;
      assert.equal(SurfaceSupport.at(fixture.build,x,z).y,y,fixture.name+': '+sample.name);
      view.__test.configure(fixture.build);
      const actor=new THREE.Group();
      view.__test.placeAnchor(actor,'actor',{pos:[x,z],yaw:.3});
      assert.equal(actor.position.y,y,'actual actor stands on '+sample.name);
      view.__test.pose(actor);view.setPose('actor:test',x,z,.3);
      assert.equal(actor.position.y,y,'test-drive pose stands on '+sample.name);
      view.setGhost({url:null,kind:'actor',x,z,half:[2,.9],yaw:0});
      assert.equal(view.__test.ghost().position.y,y,'preview stands on '+sample.name);
    }
  }
}
console.log('Free actors: exact placement/drag/rebuild, parked defaults, undo/redo, manual paths, stale-route removal and rendered support PASS');
