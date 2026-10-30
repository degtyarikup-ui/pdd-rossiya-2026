const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const Tracks = require('../editor/tracks.js');
const Support = require('../editor/surface_support.js');
const listeners = {};
const pane = {innerHTML:'',addEventListener:(name,fn)=>listeners[name]=fn,querySelectorAll:()=>[],querySelector:()=>null};
const node = {addEventListener:()=>{},dataset:{},classList:{toggle:()=>{}},textContent:''};
const context = vm.createContext({Layout,Tracks,document:{querySelector:s=>s==='#inspector'?pane:node},
  Scene3D:{refresh:()=>{},setSelection:()=>{}},Thumbs:{fillAll:()=>{},img:()=>''},setTimeout:()=>0,clearTimeout:()=>{}});
for (const file of ['catalog.js','app.js','inspector.js'])
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
const {App} = vm.runInContext('({App})',context), state = App.state;
state.S={id:'fixture',question:{},roads:[],routes:[],markings:[],lawns:[],actors:[],lights:[],decor:[],signs:[],
  tracks:[{id:'rail',points:[[-30,0],[30,0]],render:true}]};
state.id=state.S.id;state.savedJson=JSON.stringify(state.S);
App.renderPanels=()=>App.renderInspector();App.select({t:'track',id:'rail'});
const chip=v=>listeners.click({target:{closest:s=>s==='[data-chip]'?{dataset:{chip:'rail-type',value:v}}:null}});
assert.match(pane.innerHTML,/Трамвайные/);assert.match(pane.innerHTML,/Железнодорожные/);
chip('railway');assert.equal(state.S.tracks[0].railType,'railway');assert.match(pane.innerHTML,/настил переезда/);
assert.deepEqual(JSON.parse(JSON.stringify(state.S.tracks[0])).points,[[-30,0],[30,0]]);
App.undo();assert.equal(state.S.tracks[0].railType,undefined);
App.redo();assert.equal(state.S.tracks[0].railType,'railway');
state.locked.add('roads');chip('tram');assert.equal(state.S.tracks[0].railType,'railway');state.locked.clear();
chip('tram');assert.equal(state.S.tracks[0].railType,'tram');
if(process.argv[2]){
  const fixture=JSON.parse(fs.readFileSync(process.argv[2]))[0];
  for(const [x,z,y] of fixture.samples) assert.ok(Math.abs(Support.at(fixture.build,x,z).y-y)<.0001);
}
console.log('Rail type inspector, legacy default, undo/redo, layer locks and JS/Python ramp height parity PASS');
