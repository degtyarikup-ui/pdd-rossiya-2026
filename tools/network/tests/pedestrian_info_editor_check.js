// Real light inspector/history and the actual Three.js blink update.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const listeners={};
const pane={innerHTML:'',addEventListener:(name,fn)=>listeners[name]=fn,querySelectorAll:()=>[],querySelector:()=>null};
const node={addEventListener(){},dataset:{},classList:{toggle(){}},textContent:''};
const context=vm.createContext({document:{querySelector:key=>key==='#inspector'?pane:node},
  Scene3D:{refresh(){},setSelection(){}},Thumbs:{fillAll(){},img:()=>''},setTimeout:()=>0,clearTimeout(){}});
for(const file of ['catalog.js','signal_mount.js','app.js','inspector.js'])vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
const App=vm.runInContext('App',context),state=App.state;
App.renderPanels=()=>App.renderInspector();state.catalog={signs:[]};
state.S={id:'flashing-green-fixture',question:{redWait:5},roads:[],routes:[],markings:[],lawns:[],actors:[],decor:[],
  lights:[{id:'light1',state:'red',pos:[4,0],yaw:0,scale:1},{id:'light2',state:'red',pos:[-4,0],yaw:Math.PI,scale:1}]};
state.id=state.S.id;state.savedJson=JSON.stringify(state.S);
App.select({t:'light',id:'light1'});

const chip=(name,value)=>listeners.click({target:{closest:sel=>sel==='[data-chip]'?{dataset:{chip:name,value}}:null}});
const original=JSON.stringify(state.S);
assert.match(pane.innerHTML,/Нижние секции · пешеходы/);
chip('pedestrian-left','off');chip('pedestrian-right','flashing');
assert.equal(state.S.lights[0].pedestrianSections.left,'off');
assert.equal(state.S.lights[0].pedestrianSections.right,'flashing');
assert.equal(state.S.lights[1].pedestrianSections,undefined,'only the selected light changes');
const saved=JSON.stringify(state.S);App.undo();App.redo();assert.equal(JSON.stringify(state.S),saved);
state.locked.add('lights');chip('pedestrian-left','on');assert.equal(JSON.stringify(state.S),saved);state.locked.clear();
chip('pedestrian-right','bad');assert.equal(JSON.stringify(state.S),saved);
chip('state','green');assert.equal(state.S.lights[0].pedestrianSections.right,'flashing');
chip('pedestrian-left','');chip('pedestrian-right','');assert.equal(state.S.lights[0].pedestrianSections,undefined);
console.log('Pedestrian information inspector: per-light states, main signal independence, undo/redo, locks and removal PASS');
