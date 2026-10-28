// Real inspector, editor history and shared arrow polygons; no author files are written.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const clone = value => JSON.parse(JSON.stringify(value));
const shapes = require('../editor/direction_arrows.json');
const listeners = {};
const pane = {innerHTML:'',addEventListener:(name,fn)=>{listeners[name]=fn;},querySelectorAll:()=>[],querySelector:()=>null};
const element = {addEventListener(){},dataset:{},classList:{toggle(){}},textContent:''};
const context = vm.createContext({
  document:{querySelector:key=>key==='#inspector'?pane:element},
  Scene3D:{refresh(){},setSelection(){}}, Thumbs:{fillAll(){}},
  setTimeout:()=>0,clearTimeout(){},
  fetch:async()=>({ok:true,json:async()=>clone(shapes)}),
});
for (const file of ['catalog.js','direction_marking.js','app.js','inspector.js'])
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
const App = vm.runInContext('App',context), marks = vm.runInContext('DirectionMark',context);
const chip = (name,value)=>listeners.click({target:{closest:s=>s==='[data-chip]'?{dataset:{chip:name,value}}:null}});
const slider = (name,value)=>listeners.change({target:{closest:s=>s==='[data-slider]'?{dataset:{slider:name},value}:null}});
(async()=>{
  await marks.load();
  App.renderPanels=()=>App.renderInspector();
  const state=App.state;
  state.S={schema:1,id:'arrow-test',crop:90,roads:[],routes:[],actors:[],lights:[],decor:[],markings:[{id:'arrow',type:'arrow',points:[[0,0],[0,6]],direction:'straight',width:2.6}]};
  state.id=state.S.id;state.savedJson=JSON.stringify(state.S);
  const ref={t:'marking',id:'arrow'};
  const current=()=>state.S.markings.find(m=>m.id==='arrow');
  App.select(ref);
  assert.match(pane.innerHTML,/data-chip="mark-direction"/);
  assert.match(pane.innerHTML,/data-slider="mark-length"/);
  chip('mark-direction','straight_right');
  assert.equal(current().direction,'straight_right');
  App.undo();assert.equal(current().direction,'straight');
  App.redo();assert.equal(current().direction,'straight_right');
  slider('mark-length',8); assert.equal(Math.hypot(...current().points[1]),8);
  slider('mark-width',3); assert.equal(current().width,3);
  const original=clone(current());
  App.rotate(180);
  assert(Math.abs(current().points[1][1]-original.points[0][1])<.001,'rotation reverses the arrow');
  App.undo();assert.deepEqual(clone(current()),original);
  App.nudge(2,3);assert.deepEqual(clone(current().points),[[2,3],[2,11]]);
  App.undo();assert.deepEqual(clone(current()),original);
  state.locked.add('marks');chip('mark-direction','left');
  assert.equal(current().direction,'straight_right','locked markings retain their direction');
  state.locked.clear();
  App.duplicate();assert.equal(state.S.markings.length,2);
  await App.remove();assert.equal(state.S.markings.length,1);
  App.select(ref);
  chip('type','solid');assert.equal(current().direction,undefined);
  chip('type','arrow');assert.equal(current().direction,'straight');
  const fixtures=[];
  for(const [direction] of marks.variants) for(const angle of [0,.63,Math.PI/2,Math.PI]) {
    const mark={id:'test',type:'arrow',direction,points:[[5,10],[5+Math.sin(angle)*6,10+Math.cos(angle)*6]],width:2.6};
    fixtures.push({mark,polygons:clone(marks.polygons(mark))});
    assert.match(marks.svg(direction),/<polygon points=/);
  }
  if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(fixtures));
  console.log('Direction arrows: inspector variants/size, rotation, move, copy/delete, lock, undo/redo and shared polygons PASS');
})().catch(e=>{console.error(e);process.exitCode=1});
