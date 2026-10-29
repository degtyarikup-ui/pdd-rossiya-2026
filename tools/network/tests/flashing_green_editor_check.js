// Real light inspector/history and the actual Three.js blink update.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const listeners={};
const pane={innerHTML:'',addEventListener:(name,fn)=>listeners[name]=fn,querySelectorAll:()=>[],querySelector:()=>null};
const node={addEventListener(){},dataset:{},classList:{toggle(){}},textContent:''};
const context=vm.createContext({document:{querySelector:key=>key==='#inspector'?pane:node},
  Scene3D:{refresh(){},setSelection(){}},Thumbs:{fillAll(){},img:()=>''},setTimeout:()=>0,clearTimeout(){}});
for(const file of ['catalog.js','app.js','inspector.js'])vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
const App=vm.runInContext('App',context),state=App.state;
App.renderPanels=()=>App.renderInspector();state.catalog={signs:[]};
state.S={id:'flashing-green-fixture',question:{redWait:5},roads:[],routes:[],markings:[],lawns:[],actors:[],decor:[],
  lights:[{id:'light1',state:'red',pos:[4,0],yaw:0,scale:1},{id:'light2',state:'red',pos:[-4,0],yaw:Math.PI,scale:1}]};
state.id=state.S.id;state.savedJson=JSON.stringify(state.S);
App.select({t:'light',id:'light1'});
const chip=value=>listeners.click({target:{closest:sel=>sel==='[data-chip]'?{dataset:{chip:'state',value}}:null}});
assert.match(pane.innerHTML,/aria-label="Мигает зелёный"/);
chip('flashing_green');assert(state.S.lights.every(l=>l.state==='flashing_green'));assert.equal(state.S.question.redWait,null);
assert.match(pane.innerHTML,/После ответа/);assert.match(pane.innerHTML,/Жёлтый · 3 с/);assert.match(pane.innerHTML,/До ответа зелёный продолжает мигать/);
assert(state.dirty);const saved=JSON.stringify(state.S);assert(JSON.parse(saved).lights.every(l=>l.state==='flashing_green'));
App.undo();assert(state.S.lights.every(l=>l.state==='red'));assert.equal(state.S.question.redWait,5);
App.redo();assert.equal(JSON.stringify(state.S),saved);
state.locked.add('lights');chip('green');assert(state.S.lights.every(l=>l.state==='flashing_green'));state.locked.clear();
chip('invalid');assert(state.S.lights.every(l=>l.state==='flashing_green'));
chip('flashing_yellow');assert(state.S.lights.every(l=>l.state==='flashing_yellow'));assert.doesNotMatch(pane.innerHTML,/Жёлтый · 3 с/);

const THREE=require('../editor/vendor/three.min.js');
const render=vm.createContext({THREE,document:{querySelector:()=>null}});
vm.runInContext(fs.readFileSync(require.resolve('../editor/vendor/GLTFLoader.js'),'utf8'),render);
let source=fs.readFileSync(require.resolve('../editor/scene3d.js'),'utf8');
const marker='  return {\n    mount, load, refresh';assert(source.includes(marker));
source=source.replace(marker,`  return {
    __test:{configure(value,groups){model=value;anchors.clear();for(const light of value.lights)anchors.set('light:'+light.id,{group:groups[light.id]});},cycle:updateSignalCycles},
    mount, load, refresh`);
vm.runInContext(source,render);const test=vm.runInContext('Scene3D.__test',render);
function light(){const group=new THREE.Group();for(const color of ['red','yellow','green']){const lamp=new THREE.Mesh(new THREE.PlaneGeometry(1,1),new THREE.MeshBasicMaterial({color:0x111111}));lamp.name='lamp_'+color;group.add(lamp);}return group;}
const green=light(),yellow=light(),steady=light();
test.configure({lights:[{id:'green',state:'flashing_green'},{id:'yellow',state:'flashing_yellow'},{id:'steady',state:'green'}]}, {green,yellow,steady});
const colour=(group,name)=>group.getObjectByName('lamp_'+name).material.color.getHex();
test.cycle(0);assert.equal(colour(green,'green'),0x36ff88);assert.equal(colour(yellow,'yellow'),0xffd52a);
test.cycle(501);assert.equal(colour(green,'green'),0x123126);assert.equal(colour(yellow,'yellow'),0x352d14);
test.cycle(1001);assert.equal(colour(green,'green'),0x36ff88);assert.equal(colour(steady,'green'),0x111111,'steady states are not cycled by the blink updater');
test.cycle(100000);assert.equal(colour(green,'yellow'),0x111111,'the editor never advances the pre-answer signal to yellow');
console.log('Flashing green editor: named state controls, all lights, conflicts, save/undo/redo/locks and actual green/yellow blink updates PASS');
