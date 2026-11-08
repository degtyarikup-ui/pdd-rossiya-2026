// Real scenery, real Layout roads/builds, and the actual App + Tools pointer/history integration.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const Brush = require('../editor/environment_brush.js');
const Layout = require('../editor/layout.js');
const root = path.resolve(__dirname, '../../..');
const scenery = JSON.parse(fs.readFileSync(path.join(root, 'game_godot/scenery/index.json')));
const catalog = {props: Object.entries(scenery.props).map(([id, prop]) => ({id, size: prop.size})), actorTypes: {}};
const blank = () => ({id:'ticket_1_2',crop:90,roads:[],decor:[],actors:[],signs:[],lights:[],officers:[],markings:[],lawns:[],routes:[],stop:{x:-70,z:-70,yaw:0},question:{}});
const config = brushMode => ({brushMode,brushScale:1,brushYaw:0,brushSpacing:1,brushVariation:0,prop:'trees/round_0'});
const clone = object => JSON.parse(JSON.stringify(object));

for (const mode of Brush.MODES) {
  const planned = Brush.plan(blank(), null, catalog, config(mode.id), [0,0]);
  assert.ok(planned.accepted.length, `${mode.title} produces visible objects from the real library`);
  for (const object of planned.accepted) {
    assert.ok(scenery.props[object.prop], `${object.prop} has a real GLB in the scenery catalog`);
    assert.ok(fs.existsSync(path.join(root, 'game_godot/scenery', `${object.prop}.glb`)), `${object.prop} model exists`);
    assert.equal(object.pos.length,2); assert.equal(object.scale.length,3);
  }
  for (let i=0; i<planned.accepted.length; i++) for (let j=i+1; j<planned.accepted.length; j++) {
    assert.ok(!Brush.overlaps(planned.accepted[i].polygon,planned.accepted[j].polygon), `${mode.title} keeps its own objects apart`);
  }
  assert.deepEqual(planned,Brush.plan(blank(),null,catalog,config(mode.id),[0,0]), 'preview and click are deterministic');
  if (mode.compound) assert.ok(planned.accepted.length>=12, `${mode.title} places an entire location in one click`);
}
const village = Brush.plan(blank(),null,catalog,config('village'),[0,0]);
assert.equal(village.accepted.filter(o=>o.prop.startsWith('buildings/')).length,2);
assert.equal(village.accepted.filter(o=>o.prop.startsWith('street/fence_')).length,6);
assert.equal(village.rejected.length,0,'a clear private sector is a complete coherent stamp');
const quarter = Brush.plan(blank(),null,catalog,config('quarter'),[0,0]);
assert.equal(quarter.accepted.filter(o=>o.prop.startsWith('buildings/block')).length,4);
assert.equal(quarter.rejected.length,0,'no internal intersections in a complete city quarter');
const rotated = Brush.plan(blank(),null,catalog,{...config('village'),brushYaw:Math.PI/2,brushScale:1.35},[25,20]);
const firstHouse = rotated.accepted.find(o=>o.prop==='buildings/home_0');
assert.equal(firstHouse.pos[0],25); assert.equal(firstHouse.pos[1],31.475);
assert.equal(firstHouse.scale[0],1.35,'stamp scale affects model and spacing together');
assert.notDeepEqual(Brush.candidates(config('forest'),catalog,0),Brush.candidates(config('forest'),catalog,1),'another variant changes tree arrangement');

// Safety uses the generated polygons immediately, even before a new server build arrives.
const roadScene = blank(); roadScene.layout = Layout.template('cross',90); Layout.apply(roadScene);
for (const p of [[0,30],[9,30]]) {
  assert.equal(Brush.plan(roadScene,null,catalog,config('houses'),p).accepted.length,0,'roads and their pavement stay clear before asynchronous rebuild');
}
assert.equal(Brush.plan(roadScene,null,catalog,config('houses'),[16,30]).accepted.length,1,'free roadside land remains paintable');

// Use the actual checked-in road surfaces, not a mocked point-in-road implementation.
const build = JSON.parse(fs.readFileSync(path.join(root,'game_godot/network/build/ticket_16_15.json')));
for (const id of ['asphalt','pavement']) {
  const surface = build.surfaces.find(s=>s.id===id);
  assert.ok(surface?.idx.length, `real ${id} triangles exist`);
  let tri;
  for(let i=0;i<surface.idx.length;i+=3){
    const candidate=surface.idx.slice(i,i+3).map(n=>[surface.verts[n*2],surface.verts[n*2+1]]);
    if(candidate.every(p=>Math.abs(p[0])<60 && Math.abs(p[1])<60)){tri=candidate;break;}
  }
  assert.ok(tri,`real ${id} includes an interior triangle`);
  const center = tri.reduce((s,p)=>[s[0]+p[0]/3,s[1]+p[1]/3],[0,0]);
  const result = Brush.plan(blank(),build,catalog,config('houses'),center);
  assert.equal(result.accepted.length,0,`house cannot cover real ${id} triangles`);
  assert.equal(result.rejected[0].reason,'road');
}
// A thin road can cross a house while all four house corners fall outside the road.
const thin = {surfaces:[{id:'asphalt',verts:[-20,-.1,20,-.1,20,.1,-20,.1],idx:[0,1,2,0,2,3]}]};
assert.equal(Brush.plan(blank(),thin,catalog,config('houses'),[0,0]).accepted.length,0,'intersection edges, not just object center/corners, protect the whole footprint');
const atEdge = Brush.plan(blank(),null,catalog,config('quarter'),[86,86]);
assert.ok(atEdge.rejected.some(d=>d.reason==='edge'));
assert.ok(atEdge.accepted.every(o=>o.polygon.every(p=>Math.abs(p[0])<=90 && Math.abs(p[1])<=90)),'whole footprints respect scene crop');

for (const type of ['decor','actors','signs','lights','officers','stop']) {
  const scene = blank();
  if(type==='stop') scene.stop = {x:25,z:25,yaw:0};
  else scene[type].push(type==='decor' ? {id:'existing',prop:'buildings/home_0',pos:[25,25],yaw:0,scale:[1,1,1]} : {id:'existing',pos:[25,25],halfLength:2,halfWidth:1});
  assert.equal(Brush.plan(scene,null,catalog,config('houses'),[25,25]).accepted.length,0,`${type} is protected from brush objects`);
}
const occupiedLot = blank();
occupiedLot.decor.push({id:'existing_house',prop:'buildings/home_0',pos:[-8.5,0],yaw:0,scale:[1,1,1]});
const partial = Brush.plan(occupiedLot,null,catalog,config('village'),[0,0]);
assert.equal(partial.rejected.length,7,'a blocked house skips its entire lot including its fence/garden');
assert.equal(partial.accepted.length,7,'the other complete lot can still be placed');
assert.ok(partial.accepted.every(o=>o.group==='lot_1'));
const ids = Brush.append(occupiedLot,partial);
assert.equal(new Set(occupiedLot.decor.map(d=>d.id)).size,occupiedLot.decor.length,'ordinary decor IDs remain unique');
assert.ok(occupiedLot.decor.filter(d=>ids.includes(d.id)).every(d=>Object.keys(d).sort().join(',')==='id,pos,prop,scale,tint,yaw'),'saved objects use the existing runtime format, with no editor-only metadata');

const erasing = blank();
Brush.append(erasing,village);
erasing.decor.push({id:'central_tree',prop:'trees/round_0',pos:[0,0],scale:[1,1,1],yaw:0});
const houseCount=erasing.decor.filter(d=>d.prop.startsWith('buildings/')).length;
assert.ok(Brush.erase(erasing,catalog,config('forest'),[0,0])>0);
assert.equal(erasing.decor.filter(d=>d.prop.startsWith('buildings/')).length,houseCount,'forest eraser leaves houses and fences intact');
Brush.erase(erasing,catalog,config('village'),[0,0]);
assert.equal(erasing.decor.length,0,'location eraser removes all of that local environment');

// Exercise actual pointer tools with the actual App history, not a duplicate stroke implementation.
const elements = new Map(), pointer = {};
const el = () => ({hidden:false,innerHTML:'',dataset:{},style:{},classList:{add(){},remove(){},toggle(){}},addEventListener(){},querySelectorAll:()=>[]});
let refreshes=0, preview;
const context = vm.createContext({
  EnvironmentBrush:Brush, Layout, Date, console,
  document:{querySelector:key=>{if(!elements.has(key))elements.set(key,el());return elements.get(key);},querySelectorAll:()=>[]},
  Scene3D:{on:(key,fn)=>pointer[key]=fn,refresh:()=>refreshes++,setSelection(){},setGhost(){},setDraft(){},setHover(){},setPanTool(){},setPlanHandles(){},setBrushPreview:p=>preview=p},
  Thumbs:{img:(type,id)=>`<img data-thumb="${id}">`,fill(){}},
  setTimeout:()=>0,clearTimeout(){},Tracks:{apply(){throw new Error('environment stroke must not rebuild tracks');}},
});
for(const script of ['catalog.js','app.js','tools.js'])vm.runInContext(fs.readFileSync(path.join(__dirname,'../editor',script),'utf8'),context);
const App = vm.runInContext('App',context), Tools = vm.runInContext('Tools',context);
App.renderPanels=()=>{}; App.renderSelection=()=>{};
let libraryCategory;
App.setLibraryCategory=category=>libraryCategory=category;
App.state.S=blank(); App.state.id=App.state.S.id; App.state.catalog=catalog; App.state.savedJson=JSON.stringify(App.state.S);
Tools.init(); Tools.set('brush');
assert.equal(libraryCategory,'decor');
const event = (type,x,z,alt=false)=>pointer.pointer({type,world:{x,z},alt,sx:0,sy:0});
event('move',0,0); const beforeClick=clone(preview.accepted);
event('down',0,0); event('move',35,0); event('up',35,0);
assert.equal(App.state.undo.length,1,'a whole stroke is one undo step');
assert.ok(App.state.S.decor.length>beforeClick.length,'dragging paints multiple stamps');
assert.ok(refreshes<=3,'one view refresh per sampled pointer event, with no road/track rebuild per prop');
const painted=JSON.stringify(App.state.S.decor);
App.undo(); assert.equal(App.state.S.decor.length,0); App.redo(); assert.equal(JSON.stringify(App.state.S.decor),painted);
event('down',0,0,true);event('move',35,0,true);event('up',35,0,true);
assert.equal(App.state.undo.length,2,'erase stroke is also one undo step');
App.undo(); assert.equal(JSON.stringify(App.state.S.decor),painted);
Tools.pickProp('street/fence_12');
assert.equal(Tools.current(),'brush');assert.equal(Tools.opts.brushMode,'selected');
assert.equal(Tools.rotateBrush(90),true);assert.equal(Math.round(Tools.opts.brushYaw*180/Math.PI),90);
Tools.set('sign');assert.equal(libraryCategory,'signs');assert.equal(preview,null);
Tools.set('actor');assert.equal(libraryCategory,'traffic');
Tools.set('prop');assert.equal(libraryCategory,'decor');
libraryCategory='all';Tools.pickSign('1.11.2');assert.equal(libraryCategory,'all','library picks preserve the current category/search');
Tools.pickActor('car');assert.equal(libraryCategory,'all');Tools.pickLight(false);assert.equal(libraryCategory,'all');Tools.pickProp('buildings/home_0');assert.equal(libraryCategory,'all');
Tools.set('brush');App.state.locked.add('decor');
const beforeLocked=JSON.stringify(App.state.S.decor), beforeLockedUndo=App.state.undo.length;
event('down',60,60);event('up',60,60);
assert.equal(JSON.stringify(App.state.S.decor),beforeLocked,'a locked environment layer cannot be painted or erased');
assert.equal(App.state.undo.length,beforeLockedUndo);
assert.match(elements.get('#toolbar').innerHTML,/class="tool-label">Дорога/,'toolbar tools have visible short names');
assert.match(elements.get('#toolbar').innerHTML,/aria-label="Знак \(N\)"/,'toolbar actions have accessible names');
console.log('Environment brush: real scenery locations, footprint/crop/road/object safety, complete lots, deterministic preview, library, rotation, stroke undo/redo and erase PASS');
