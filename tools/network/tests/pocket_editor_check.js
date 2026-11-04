// Real tool/inspector/history operations on disposable scenes; no authored files are saved.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const Layout=require('../editor/layout.js'),RoadPocket=require('../editor/road_pocket.js');
const elements=new Map(),pointer={};let hit=null,draft=null;
const element=()=>({hidden:false,innerHTML:'',dataset:{},style:{},listeners:{},classList:{add(){},remove(){},toggle(){}},
  addEventListener(name,fn){this.listeners[name]=fn;},querySelector(){return null;},querySelectorAll(){return [];}});
const context=vm.createContext({Layout,RoadPocket,console,setTimeout:()=>0,clearTimeout(){},
 document:{querySelector:key=>{if(!elements.has(key))elements.set(key,element());return elements.get(key);},querySelectorAll:()=>[]},
 Scene3D:{on:(name,fn)=>pointer[name]=fn,refresh(){},setSelection(){},setDraft:value=>draft=value,setGhost(){},setHover(){},setPanTool(){},setPlanHandles(){},hitAt:()=>hit},
 Thumbs:{fillAll(){},img(){return '';},fill(){}},Tracks:{apply(){}},
});
for(const file of ['catalog.js','app.js','tools.js','inspector.js'])vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
const {App,Tools}=vm.runInContext('({App,Tools})',context);
const clone=v=>JSON.parse(JSON.stringify(v));
const roads=[{id:'road',outer:[[-4,-50],[4,-50],[4,50],[-4,50]],holes:[],walk:true}];
const scene={id:'pocket-fixture',question:{},roads,markings:[],routes:[],lawns:[],actors:[],decor:[],lights:[]};
App.state.S=scene;App.state.id=scene.id;App.state.savedJson=JSON.stringify(scene);
App.renderPanels=()=>{App.renderInspector();Tools.renderBar();};Tools.init();
const pane=elements.get('#inspector');
const point=(type,x,z,extra={})=>pointer.pointer({type,world:{x,z},sx:x*10,sy:z*10,...extra});
const current=()=>App.state.S.pockets?.[0];
const field=(key,value)=>pane.listeners.change({target:{closest:s=>s==='[data-text]'?{dataset:{text:'pocket-'+key},value:String(value)}:null}});
Tools.set('pocket');point('move',5,0);assert.equal(draft.kind,'pocket');
point('down',5,0);point('up',5,0);
assert.equal(Tools.current(),'select');assert.equal(App.state.sel[0].t,'pocket');
assert.deepEqual(clone(current().pos),[4,0],'pocket mouth aligns with the authored road boundary');
assert(RoadPocket.outline(current()).every(p=>p[0]>=4-1e-6),'pocket expands outward, never across existing lanes');
assert.equal(App.state.undo.length,1);assert.match(pane.innerHTML,/Плавный заезд/);assert.match(pane.innerHTML,/Плавный выезд/);
field('width',5.5);field('entryLength',14);field('exitLength',4);field('length',20);
assert.equal(current().width,5.5);assert.equal(current().entryLength,14);assert.equal(current().exitLength,4);
const edited=JSON.stringify(current());App.undo();assert.equal(current().length,16);App.redo();assert.equal(JSON.stringify(current()),edited);
for(const bad of ['',0,'NaN',2000])field('width',bad);assert.equal(current().width,5.5,'invalid dimensions leave saved geometry unchanged');
field('x',6);field('z',10);assert.deepEqual(clone(current().pos),[6,10]);
hit={t:'pocket',id:current().id};point('down',6,10);point('move',9,14);point('up',9,14);
assert.deepEqual(clone(current().pos),[9,14],'dragging moves the mouth with the original pointer offset');
const beforeRotate=current().yaw;App.rotate(90);assert(Math.abs(current().yaw-beforeRotate)>.5);
App.undo();assert.equal(current().yaw,beforeRotate);
App.duplicate();assert.equal(App.state.S.pockets.length,2);assert.notEqual(App.state.S.pockets[0].id,App.state.S.pockets[1].id);
App.remove();assert.equal(App.state.S.pockets.length,1);App.undo();assert.equal(App.state.S.pockets.length,2);
App.select({t:'pocket',id:current().id});App.state.locked.add('roads');const locked=JSON.stringify(App.state.S);
field('width',8);App.nudge(4,5);App.rotate(45);App.duplicate();App.remove();Tools.set('pocket');point('down',30,30,{alt:true});point('up',30,30,{alt:true});
assert.equal(JSON.stringify(App.state.S),locked,'all editing and placement respect road layer locks');
App.state.locked.clear();Tools.set('pocket');point('down',30,30,{alt:true});point('move',40,30,{alt:true});point('up',40,30,{alt:true});
const free=App.state.S.pockets.at(-1);assert.deepEqual(clone(free.pos),[30,30]);assert(Math.abs(free.yaw-Math.PI/2)<1e-8);
assert.equal(JSON.stringify(App.state.S.roads),JSON.stringify(roads),'source road outlines survive all pocket edits');
const roundtrip=JSON.parse(JSON.stringify(App.state.S));assert.equal(roundtrip.pockets[0].entryLength,14);assert.equal(roundtrip.pockets[0].exitLength,4);
// Boundary winding and heading do not change which side of a road is outside.
for(const ring of [roads[0].outer,[...roads[0].outer].reverse()]) for(const x of [-5,5]){
 const placed=RoadPocket.placement({roads:[{outer:ring}]},[x,0]);
 assert(RoadPocket.outline(placed).every(p=>x<0?p[0]<=-4+1e-6:p[0]>=4-1e-6));
}
const offRoad=RoadPocket.placement({roads:[{surface:'pavement',outer:roads[0].outer}]},[5,0]);
assert.deepEqual(offRoad.pos,[5,0],'sidewalk platforms are not carriageway snapping targets');
console.log('Pocket editor: boundary snap, free placement and heading, dimensions, drag, history, copy/delete, locks and source preservation PASS');
