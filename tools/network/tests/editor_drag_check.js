// A whole scenery stroke is one ordinary editor edit; locked selections stay unchanged.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const elements = new Map();
let rebuilds = 0;
const element = () => ({hidden:true,classList:{toggle(){},add(){},remove(){}},addEventListener(){},dataset:{}});
const context = vm.createContext({Layout:{...Layout,apply(s){rebuilds++;return Layout.apply(s);}},
  document:{querySelector:key=>{if(!elements.has(key))elements.set(key,element());return elements.get(key);},querySelectorAll:()=>[]},
  Scene3D:{refresh(){},setSelection(){},setHidden(){}},setTimeout:()=>0,clearTimeout(){},console});
vm.runInContext(fs.readFileSync(require.resolve('../editor/app.js'),'utf8'),context);
const App=vm.runInContext('App',context);
App.renderPanels=()=>{};
App.state.S={id:'brush-drag',schema:1,crop:90,layout:Layout.template('cross',90),question:{maneuver:'straight'},roads:[],routes:[],markings:[],lawns:[],actors:[],lights:[],signs:[],decor:[]};
Layout.apply(App.state.S);
App.state.id=App.state.S.id;
App.state.savedJson=JSON.stringify(App.state.S);
const original=App.state.savedJson;
App.beginDrag();
for(let i=0;i<4;i++)App.dragMove(s=>s.decor.push({id:`tree_${i}`,prop:'trees/pine_0',pos:[20+i*4,20],yaw:0,scale:[1,1,1]}),{rebuild:false});
assert.equal(rebuilds,0,'painting must not rebuild road routes every pointer move');
App.endDrag({rebuild:false});
assert.equal(App.state.undo.length,1,'one stroke, one undo step');
assert.equal(App.state.dirty,true);
App.undo();assert.equal(JSON.stringify(App.state.S),original);
App.redo();assert.equal(App.state.S.decor.length,4);
App.beginDrag();App.dragMove(s=>s.decor[0].pos[0]=55,{rebuild:false});App.cancelDrag();
assert.equal(App.state.S.decor[0].pos[0],20,'cancelled stroke restores previous placement');
App.state.sel=[{t:'decor',id:'tree_0'}];App.state.locked.add('decor');
const locked=JSON.stringify(App.state.S);
App.nudge(3,3);App.rotate(15);App.remove();
assert.equal(JSON.stringify(App.state.S),locked,'keyboard edits respect locked layers');
console.log('Editor scenery strokes: no route rebuild, one undo/redo, cancellation and locked edits PASS');
