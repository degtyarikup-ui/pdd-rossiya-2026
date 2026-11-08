// Exercise the native-road UI and real history on a copy of ticket 9·14.
// Its 139-point outline contains an interior dead end that exit detection cannot reconstruct.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = value => JSON.parse(JSON.stringify(value));
const source = JSON.parse(fs.readFileSync(path.join(__dirname,'../../../game_godot/network/ticket_9_14.json'),'utf8'));
const elements = new Map(), events = {};
const element = () => ({hidden:false,innerHTML:'',dataset:{},style:{},classList:{add(){},remove(){},toggle(){}},
  addEventListener(){},querySelector:()=>null,querySelectorAll:()=>[]});
let hit, preview, inspectorOpened = 0, actorRebuilds = 0;
const context = vm.createContext({Layout:{...Layout,applyActors(...args){actorRebuilds++;return Layout.applyActors(...args);}},
  console,setTimeout:()=>0,clearTimeout(){},
  document:{querySelector:key=>{if(!elements.has(key))elements.set(key,element());return elements.get(key);},querySelectorAll:()=>[]},
  Scene3D:{on:(key,fn)=>events[key]=fn,refresh(){},setSelection(){},setDraft:d=>preview=d,setGhost(){},setHover(){},
    setPanTool(){},setPlanHandles(){},screenOf:(x,z)=>({x:x*5,y:z*5}),hitAt:(_x,_y,skip)=>hit && !skip(hit)?hit:null},
  Thumbs:{fillAll(){},fill(){},img:()=>''},Tracks:{apply(){},nearest:()=>null},
});
for (const name of ['catalog.js','app.js','tools.js'])
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+name),'utf8'),context);
const {App,Tools} = vm.runInContext('({App,Tools})',context);
App.renderPanels=()=>{};App.showInspector=()=>inspectorOpened++;
App.api=()=>{throw new Error('Native editing must not reconstruct roads using a detector');};
App.confirm=()=>{throw new Error('Adding a road must not ask to replace authored roads');};
Tools.init();
function load() {
  App.state.S=clone(source);App.state.id=source.id;App.state.plan=null;
  App.state.undo=[];App.state.redo=[];App.state.sel=[];App.state.locked.clear();
  App.state.savedJson=JSON.stringify(App.S);Tools.set('select');
  return JSON.stringify(App.S);
}
const point=(type,x,z,extra={})=>events.pointer({type,world:{x,z},sx:x*5,sy:z*5,...extra});
const original=load();
assert.equal(source.roads[0].outer.length,139);
Tools.convertScene();
assert.equal(JSON.stringify(App.S),original,'the old conversion action only selects native geometry');
assert.deepEqual(clone(App.state.sel),[{t:'road',id:'road_0'}]);
assert.equal(inspectorOpened,1);assert.equal(App.state.undo.length,0);
App.state.locked.add('roads');App.select([]);Tools.editRoads();
assert.equal(App.state.sel.length,0);App.state.locked.clear();

// The body moves immediately, carrying every original vertex and hole without resampling.
// Even with an inferred actor plan cached, a geometry-only edit must not regenerate actor paths.
App.state.plan=Layout.template('cross',90);actorRebuilds=0;hit={t:'road',id:'road_0'};
point('down',0,-20);point('move',2,-17);point('up',2,-17);
const moved=clone(App.S.roads[0]);
assert.deepEqual(moved.outer,source.roads[0].outer.map(([x,z])=>[App.r3(x+2),App.r3(z+3)]));
assert.deepEqual(moved.holes,source.roads[0].holes.map(r=>r.map(([x,z])=>[App.r3(x+2),App.r3(z+3)])));
assert.equal(actorRebuilds,0,'editing a native surface must not rebuild cached actor routes');
for(const key of Object.keys(source).filter(k=>k!=='roads')) assert.deepEqual(clone(App.S[key]),source[key],key);
assert.equal(App.state.undo.length,1);App.undo();assert.equal(JSON.stringify(App.S),original);
App.state.plan=null;

// A vertex edit changes that vertex only; no contour is simplified or inferred.
const v=25,p=source.roads[0].outer[v];hit={t:'road',id:'road_0',v,point:true};
point('down',...p);point('move',p[0]+1.123,p[1]+2.234,{alt:true});point('up',p[0]+1.123,p[1]+2.234,{alt:true});
assert.equal(App.S.roads[0].outer.length,139);
assert.deepEqual(clone(App.S.roads[0].outer[v]),[App.r3(p[0]+1.123),App.r3(p[1]+2.234)]);
source.roads[0].outer.forEach((p,i)=>{if(i!==v)assert.deepEqual(clone(App.S.roads[0].outer[i]),p);});
App.undo();assert.equal(JSON.stringify(App.S),original);

// New graph roads coexist with the source, including its paint, player and all six routes.
Tools.set('road');hit=null;point('down',40,30);assert.equal(JSON.stringify(App.S),original);
point('down',40,55);
assert.equal(App.S.layout.preserveSource,true);
assert.equal(App.S.layout.streets.length,1);assert.ok(App.S.roads.some(r=>r.planGenerated));
for(const key of Object.keys(source)) {
  if(['roads','markings','lawns'].includes(key)) assert.deepEqual(clone(App.S[key].filter(x=>!x.planGenerated)),source[key],key);
  else assert.deepEqual(clone(App.S[key]),source[key],key);
}
assert.equal(App.S.roads.find(r=>r.id==='road_0').outer.length,139);
const added=JSON.stringify(App.S);assert.equal(App.state.undo.length,1);
Tools.escape();App.undo();assert.equal(JSON.stringify(App.S),original);
App.redo();assert.equal(JSON.stringify(App.S),added);

// Native start/approach controls remain editable after an additive road is introduced.
Tools.set('select');hit={t:'stop'};const oldStop=clone(App.S.stop);
point('down',oldStop.x,oldStop.z);point('move',oldStop.x+2,oldStop.z+3);point('up',oldStop.x+2,oldStop.z+3);
assert.equal(App.S.stop.x,App.r3(oldStop.x+2));assert.equal(App.S.stop.z,App.r3(oldStop.z+3));
assert.equal(App.S.stop.yaw,oldStop.yaw);App.undo();assert.equal(JSON.stringify(App.S),added);
const ap=App.S.routes.find(r=>r.kind==='approach'), pv=0, at=ap.points[pv];
hit={t:'route',id:ap.id,v:pv,point:true};
point('down',...at);point('move',at[0]+2,at[1]+1,{alt:true});point('up',at[0]+2,at[1]+1,{alt:true});
assert.deepEqual(clone(App.S.routes.find(r=>r.id===ap.id).points[pv]),[App.r3(at[0]+2),App.r3(at[1]+1)]);
App.undo();assert.equal(JSON.stringify(App.S),added);
assert.equal(preview,null);
// Added streets still offer working automatic actor paths, without rebuilding
// the authored question routes or a different participant's path.
const nativeRoutes=clone(App.S.routes);
App.edit(sc=>sc.actors.push(
  {id:'added_car',type:'car',pos:[38.2,30],yaw:0,way:'straight',behaviour:{}},
  {id:'other_car',type:'car',pos:[38.2,40],yaw:0,way:'straight',behaviour:{}}
));
const routeOf=id=>App.S.routes.find(r=>r.id===`actor_${id}`);
assert.deepEqual(clone(routeOf('added_car').points[0]),[38.2,30]);
const otherRoute=clone(routeOf('other_car'));
App.edit(sc=>{sc.actors.find(a=>a.id==='added_car').pos=[38.2,35];});
assert.deepEqual(clone(routeOf('added_car').points[0]),[38.2,35]);
assert.deepEqual(clone(routeOf('other_car')),otherRoute);
for(const route of nativeRoutes) assert.deepEqual(clone(App.S.routes.find(r=>r.id===route.id)),route);
const beforePaint=clone(App.S.routes);
App.edit(sc=>{sc.actors.find(a=>a.id==='added_car').paint='#ffffff';});
assert.deepEqual(clone(App.S.routes),beforePaint,'cosmetic participant edits cannot replace authored routes');
console.log('Native road tools: 139-point dead end, direct move/vertex edits, safe legacy action, additive street, source data, player/path editing and history PASS');
