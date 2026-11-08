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

const ref=(v)=>({t:'marking',id:'m',v,point:true});
const line=()=>App.S.markings.find(m=>m.id==='m');
function marking(points){load(simple());App.S.markings.push({id:'m',type:'dashed',points:clone(points)});App.state.savedJson=JSON.stringify(App.S);App.state.undo=[];App.select({t:'marking',id:'m'});}
(async()=>{
const dense=Array.from({length:101},(_,i)=>[0,i]);marking(dense);const old=JSON.stringify(App.S);
App.simplifyMarkings();assert.deepEqual(clone(line().points),[[0,0],[0,50],[0,100]]);assert.equal(App.state.undo.length,1);
App.undo();assert.equal(JSON.stringify(App.S),old);App.redo();
assert.deepEqual(clone(App.simplifyMarkingPoints([[0,0],[0,2],[0,5],[4,5],[7,5]])),[[0,0],[0,5],[7,5]]);
assert.deepEqual(clone(App.simplifyMarkingPoints([[0,0],[0,5],[0,0]])),[[0,0],[0,5],[0,0]],'reversal retained');
marking([[0,0],[0,10],[0,20],[0,30],[0,40]]);
App.select(ref(1));App.toggle(ref(2));assert.equal(App.state.sel.length,2);
App.toggle(ref(2));assert.equal(App.state.sel.length,1);App.toggle(ref(2));
App.select([...App.state.sel,{t:'street',id:'s'}]);assert(App.state.sel.every(App.isMarkingVertex),'vertex mode cannot accidentally delete a whole object from a mixed selection');
assert(!App.canCopy(ref(1))&&!App.canRotate(ref(1)),'point selection never copies or rotates entire lines');
let before=JSON.stringify(App.S);hit=ref(1);
point('down',.1,10.1);point('move',4.1,13.1);point('up',4.1,13.1);
assert.deepEqual(clone(line().points),[[0,0],[4,13],[4,23],[0,30],[0,40]]);assert.equal(App.state.undo.length,1);
App.undo();assert.equal(JSON.stringify(App.S),before);App.redo();
App.nudge(1,0);assert.deepEqual(clone(line().points[1]),[5,13]);assert.deepEqual(clone(line().points[2]),[5,23]);assert.deepEqual(clone(line().points[0]),[0,0]);
await App.remove();assert.equal(App.S.markings.some(m=>m.id==='m'),true);assert.deepEqual(clone(line().points),[[0,0],[0,30],[0,40]]);
App.undo();assert.equal(line().points.length,5);
App.select([ref(0),ref(1),ref(2),ref(3)]);before=JSON.stringify(App.S);await App.remove();assert.equal(JSON.stringify(App.S),before,'minimum two points, atomic refusal');
App.select([ref(1),ref(2)]);App.state.locked.add('marks');before=JSON.stringify(App.S);App.nudge(5,0);await App.remove();assert.equal(JSON.stringify(App.S),before);App.state.locked.clear();
// Escape rolls the whole group back; pointer jitter leaves no history.
hit=ref(1);before=JSON.stringify(App.S);point('down',5,13);point('move',10,18);Tools.escape();assert.equal(JSON.stringify(App.S),before);
const count=App.state.undo.length;point('down',5,13);point('move',5.1,13.1);point('up',5.1,13.1);assert.equal(JSON.stringify(App.S),before);assert.equal(App.state.undo.length,count);
console.log('Marking points: simplification, reversals, selection identity, group drag, nudge, delete, history, minimum length, locks and cancel PASS');
})().catch(e=>{console.error(e);process.exitCode=1;});
