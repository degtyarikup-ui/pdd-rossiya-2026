// Real pointer handlers and history. Disposable road plans only; no authored scene is saved.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = value => JSON.parse(JSON.stringify(value));
const elements = new Map(), pointer = {};
const element = () => ({hidden:false,innerHTML:'',dataset:{},style:{},classList:{add(){},remove(){},toggle(){}},
  addEventListener(){},querySelector:()=>null,querySelectorAll:()=>[]});
let hit, preview;
const context = vm.createContext({Layout,console,setTimeout:()=>0,clearTimeout(){},
  document:{querySelector:key=>{if(!elements.has(key))elements.set(key,element());return elements.get(key);},querySelectorAll:()=>[]},
  Scene3D:{on:(key,fn)=>pointer[key]=fn,refresh(){},setSelection(){},setDraft:d=>preview=d,setGhost(){},setHover(){},
    setPanTool(){},setPlanHandles(){},screenOf:(x,z)=>({x:x*5,y:z*5}),hitAt:(_x,_y,skip)=>hit && !skip(hit)?hit:null},
  Thumbs:{fillAll(){},fill(){},img:()=>''},Tracks:{apply(){},nearest:()=>null},
});
for (const name of ['catalog.js','app.js','tools.js'])
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+name),'utf8'),context);
const {App,Tools} = vm.runInContext('({App,Tools})',context);
App.renderPanels=()=>{};
Tools.init();
function load(layout) {
  App.state.S={id:'road-drag',crop:90,layout,question:{maneuver:'straight'},
    roads:[],routes:[],actors:[],lights:[],signs:[],decor:[],markings:[],lawns:[]};
  Layout.apply(App.S); App.state.id=App.S.id; App.state.undo=[];App.state.redo=[];App.state.sel=[];
  App.state.savedJson=JSON.stringify(App.S);App.state.locked.clear(); Tools.set('select');
  return JSON.stringify(App.S);
}
const node=(id,x,z)=>({id,x,z});
const street=(id,a,b,bend)=>({id,a,b,kind:'street',ends:{},...(bend?{bend}: {})});
const simple=()=>({nodes:[node('a',0,-30),node('b',0,30)],streets:[street('s','a','b')]});
const point=(type,x,z,mod={})=>pointer.pointer({type,world:{x,z},sx:x*5,sy:z*5,...mod});
const getNode=id=>clone(Layout.nodeOf(App.S.layout,id));
const getStreet=id=>clone(Layout.streetOf(App.S.layout,id));

// A click/jitter on the bend handle must never create a bend or history entry.
let original=load(simple());hit={t:'bend',id:'s'};App.select({t:'street',id:'s'});
point('down',.3,0);point('move',.6,0);point('up',.6,0);
assert.equal(JSON.stringify(App.S),original);assert.equal(App.state.undo.length,0);
// A grab near the diamond preserves its pointer offset; the midpoint follows it exactly.
point('down',.3,0);point('move',10.3,0);point('up',10.3,0);
assert.deepEqual(getStreet('s').bend,[20,0]);assert.equal(App.state.undo.length,1);
assert.equal(preview,null);App.undo();assert.equal(JSON.stringify(App.S),original);
App.redo();assert.deepEqual(getStreet('s').bend,[20,0]);
// Bringing the midpoint back to its straight position removes the bend in one gesture.
point('down',10.3,0);point('move',.3,0);point('up',.3,0);
assert.equal(getStreet('s').bend,null);App.undo();assert.deepEqual(getStreet('s').bend,[20,0]);
point('down',10,0);point('move',20,5);Tools.escape();assert.deepEqual(getStreet('s').bend,[20,0]);assert.equal(preview,null);

// Endpoints can leave the old road instead of being magnetized to its own centreline.
original=load(simple());hit={t:'node',id:'b'};
point('down',.2,29.8);point('move',10.2,29.8);point('up',10.2,29.8);
assert.deepEqual(getNode('b'),node('b',10,30));assert.equal(App.state.undo.length,1);
App.undo();assert.equal(JSON.stringify(App.S),original);
// Shift constrains the direction; Alt is available from the beginning of the drag.
point('down',0,30);point('move',11,25,{shift:true,alt:true});point('up',11,25,{shift:true,alt:true});
let b=getNode('b');const heading=Math.atan2(b.x,b.z+30)*180/Math.PI;
assert.ok(Math.abs(heading-15)<.002);App.undo();
point('down',0,30,{alt:true});point('move',10.123,31.456,{alt:true});point('up',10.123,31.456,{alt:true});
assert.deepEqual(getNode('b'),node('b',10.123,31.456));App.undo();

// A road can be grabbed in one gesture without a preliminary selection click.
original=load(simple());hit={t:'street',id:'s'};
point('down',0,5);point('move',4.1,8.1);point('up',4.1,8.1);
assert.deepEqual(getNode('a'),node('a',4,-27));assert.deepEqual(getNode('b'),node('b',4,33));
assert.equal(App.state.undo.length,1);App.undo();assert.equal(JSON.stringify(App.S),original);

// Road and node multiselections move shared nodes once and carry neighbouring bends correctly.
original=load({nodes:[node('a',-20,-20),node('b',0,0),node('c',20,20),node('d',30,-20)],
  streets:[street('s1','a','b',[-20,0]),street('s2','b','c',[0,20]),street('s3','b','d',[20,-10])]});
hit={t:'street',id:'s1'};App.select([hit,{t:'street',id:'s2'},{t:'node',id:'b'}]);
point('down',-10,-10);point('move',-8.2,-7.2);point('move',-6.7,-5.7);point('up',-6.7,-5.7);
assert.deepEqual(getNode('a'),node('a',-16.5,-15.5));assert.deepEqual(getNode('b'),node('b',3.5,4.5));
assert.deepEqual(getNode('c'),node('c',23.5,24.5));assert.deepEqual(getNode('d'),node('d',30,-20));
assert.deepEqual(getStreet('s1').bend,[-16.5,4.5]);assert.deepEqual(getStreet('s2').bend,[3.5,24.5]);
assert.deepEqual(getStreet('s3').bend,[21.75,-7.75]);assert.equal(App.state.undo.length,1);
App.undo();assert.equal(JSON.stringify(App.S),original);App.redo();assert.deepEqual(getNode('b'),node('b',3.5,4.5));

// Merging is previewed and happens only at the displayed target; Alt bypasses it.
const separate=()=>({nodes:[node('a',0,-30),node('b',0,30),node('c',20,0),node('d',20,30)],
  streets:[street('s1','a','b'),street('s2','c','d')]});
original=load(separate());hit={t:'node',id:'b'};
point('down',0,30);point('move',19.6,.3);assert.deepEqual(clone(preview.snap),[20,0]);
point('up',19.6,.3);assert.equal(App.S.layout.nodes.some(n=>n.id==='b'),false);
assert.equal(getStreet('s1').b,'c');assert.equal(App.state.undo.length,1);App.undo();assert.equal(JSON.stringify(App.S),original);
point('down',0,30,{alt:true});point('move',19.6,.3,{alt:true});assert.equal(preview,null);
point('up',19.6,.3,{alt:true});assert.ok(Layout.nodeOf(App.S.layout,'b'));assert.deepEqual(getNode('b'),node('b',19.6,.3));
App.undo();
// A displayed road target becomes a real T-junction on release, not two overlaid roads.
point('down',0,30);point('move',20.1,15);assert.deepEqual(clone(preview.snap),[20,15]);
point('up',20.1,15);
const junction=App.state.sel[0].id;
assert.equal(Layout.streetsAt(App.S.layout,junction).length,3);
assert.equal(getStreet('s1').b,junction);assert.equal(App.state.undo.length,1);
App.undo();assert.equal(JSON.stringify(App.S),original);

// Switching tools during a drag cancels the whole gesture and clears its snap marker.
point('down',0,30);point('move',19.6,.3);Tools.set('hand');
assert.equal(JSON.stringify(App.S),original);assert.equal(preview,null);

// Keyboard placement uses the same graph transform; shared junctions never move twice.
original=load({nodes:[node('a',-20,0),node('b',0,0),node('c',20,0)],
  streets:[street('s1','a','b',[-10,6]),street('s2','b','c')]});
App.select([{t:'street',id:'s1'},{t:'street',id:'s2'},{t:'node',id:'b'}]);
App.nudge(2,3);
assert.deepEqual(getNode('b'),node('b',2,3));assert.deepEqual(getStreet('s1').bend,[-8,9]);
App.undo();assert.equal(JSON.stringify(App.S),original);
App.select({t:'street',id:'s1'});
const oldLength=Layout.polyLen(Layout.centreline(App.S.layout,App.S.layout.streets[0]));
App.rotate(90);
assert.deepEqual(getNode('a'),node('a',-10,-10));assert.deepEqual(getNode('b'),node('b',-10,10));
assert.deepEqual(getNode('c'),node('c',20,0),'unselected endpoint stays fixed');
assert(Math.abs(Layout.polyLen(Layout.centreline(App.S.layout,App.S.layout.streets[0]))-oldLength)<.001);
App.undo();assert.equal(JSON.stringify(App.S),original);
hit={t:'street',id:'s1'};point('down',-10,0);point('move',-5,5);App.undo();
point('move',0,10);point('up',0,10);
assert.equal(JSON.stringify(App.S),original,'undo while held cancels the gesture and subsequent pointer movement');
console.log('Road drag: no click mutation, offset/grip stability, live snap, Alt/Shift, connected multiselection, one-step history and cancellation PASS');
