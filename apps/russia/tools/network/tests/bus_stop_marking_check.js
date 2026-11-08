// Real tool placement and inspector/history on disposable in-memory editor scenes.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const Layout=require('../editor/layout.js');
const elements=new Map(),pointer={};
const element=()=>({innerHTML:'',hidden:false,dataset:{},style:{},listeners:{},classList:{toggle(){},add(){},remove(){}},
  addEventListener(name,fn){this.listeners[name]=fn;},querySelector:()=>null,querySelectorAll:()=>[]});
let preview;
const context=vm.createContext({Layout,console,setTimeout:()=>0,clearTimeout(){},Tracks:{apply(){}},Thumbs:{fillAll(){}},
  document:{querySelector:key=>{if(!elements.has(key))elements.set(key,element());return elements.get(key);},querySelectorAll:()=>[]},
  Scene3D:{on:(key,fn)=>pointer[key]=fn,refresh(){},setSelection(){},setGhost(){},setHover(){},setDraft:value=>preview=value,setPanTool(){},setPlanHandles(){}},
});
for(const file of ['catalog.js','direction_marking.js','bus_stop_marking.js','app.js','tools.js','inspector.js'])
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
const {App,Tools,BusStopMark:Bus}=vm.runInContext('({App,Tools,BusStopMark})',context);
const clone=x=>JSON.parse(JSON.stringify(x));
const s=App.state;
s.S={id:'bus-stop-fixture',question:{},roads:[{id:'road',outer:[[-4,-40],[4,-40],[4,40],[-4,40]],holes:[]}],routes:[],markings:[],actors:[],lights:[],decor:[],lawns:[]};
s.id=s.S.id;s.savedJson=JSON.stringify(s.S);
App.renderPanels=()=>{App.renderInspector();Tools.renderBar();};
Tools.init();Tools.set('marking');
const pane=elements.get('#inspector'),pop=elements.get('#popover');
const click=(el,selector,dataset)=>el.listeners.click({target:{closest:key=>key===selector?{dataset}:null}});
const chip=(name,value)=>click(pane,'[data-chip]',{chip:name,value});
const text=(key,value)=>pane.listeners.change({target:{closest:sel=>sel==='[data-text]'?{dataset:{text:'bus-'+key},value:String(value)}:null}});
const slider=(key,value)=>pane.listeners.change({target:{closest:sel=>sel==='[data-slider]'?{dataset:{slider:'bus-'+key},value}:null}});
const act=name=>click(pane,'[data-act]',{act:name});
const point=(type,x,z)=>pointer.pointer({type,world:{x,z},sx:0,sy:0});
click(pop,'button',{mark:'bus_stop'});
assert.match(pop.innerHTML,/data-mark="bus_stop"/);
point('down',-3.5,-20);point('move',-3.5,0);
assert.equal(preview.kind,'bus_stop');assert.equal(preview.side,-1,'preview faces inward from the kerb');
point('down',-3.5,0);
const current=()=>s.S.markings[0];
assert.equal(Tools.current(),'select','new stop is immediately ready to move and resize');
assert.equal(s.undo.length,1);assert.equal(current().colour,'yellow');assert.equal(current().side,-1);
assert.equal(current().depth,1.2);assert.equal(current().step,1.5);assert.equal(current().width,.12);
assert.match(pane.innerHTML,/Глубина зубцов/);assert.match(pane.innerHTML,/Толщина линии/);
const original=JSON.stringify(current());App.undo();assert.equal(s.S.markings.length,0);App.redo();assert.equal(JSON.stringify(current()),original);App.select({t:'marking',id:current().id});
for(const [key,value] of [['length',24],['depth',1.6],['step',1.2],['width',.18]])text(key,value);
assert.equal(Bus.length(current()),24);assert.equal(current().depth,1.6);assert.equal(current().step,1.2);assert.equal(current().width,.18);
slider('depth',1.1);assert.equal(current().depth,1.1);App.undo();assert.equal(current().depth,1.6);
for(const bad of ['',0,100,'NaN']){text('depth',bad);assert.equal(current().depth,1.6);}
act('bus-side');assert.equal(current().side,1);App.undo();assert.equal(current().side,-1);
s.locked.add('marks');text('depth',2);act('bus-side');chip('type','solid');assert.equal(current().type,'bus_stop');assert.equal(current().depth,1.6);assert.equal(current().side,-1);s.locked.clear();
App.nudge(1,2);assert.deepEqual(clone(current().points[0]),[-2.5,-18]);App.undo();
const shape=clone(Bus.polygons(current()));App.rotate(90);assert.equal(Bus.count(current()),20);App.undo();assert.deepEqual(clone(Bus.polygons(current())),shape);
App.duplicate();assert.equal(s.S.markings.length,2);App.remove();assert.equal(s.S.markings.length,1);
App.select({t:'marking',id:current().id});chip('type','solid');assert.equal(current().depth,undefined);chip('type','bus_stop');assert.equal(current().depth,1.2);assert.equal(current().colour,'yellow');
const fixtures=[];
for(const length of [2,7.3,20,60])for(const depth of [.4,1.2,3])for(const step of [.6,1.5,4])for(const side of [-1,1])for(const angle of [0,.63,Math.PI/2]) {
  const mark={type:'bus_stop',points:[[7,4],[7+Math.cos(angle)*length,4+Math.sin(angle)*length]],depth,step,width:.12,side,colour:'yellow'};
  fixtures.push({mark,polygons:clone(Bus.polygons(mark)),line:clone(Bus.line(mark))});
}
assert.equal(Bus.label({points:[[0,0],[2,0]],step:4}),'1 зубец');
if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(fixtures));
console.log('Bus stops: real two-click tool/preview, inward side, size controls, validation, locks, copy/move/rotate/delete and undo/redo PASS');
