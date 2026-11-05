// Real inspector events and undo on disposable road plans; no scene files are changed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = v => JSON.parse(JSON.stringify(v));
const listeners = {};
const pane = {innerHTML:'',addEventListener:(name,fn)=>{listeners[name]=fn;},querySelectorAll:()=>[],querySelector:()=>null};
const node = {addEventListener(){},dataset:{},classList:{toggle(){}},textContent:''};
const context = vm.createContext({Layout,
  document:{querySelector:selector=>selector==='#inspector'?pane:node},
  Scene3D:{refresh(){},setSelection(){}},Tracks:{apply(){}},Thumbs:{fillAll(){},img:()=>''},setTimeout:()=>0,clearTimeout(){},
});
for (const file of ['bus_stop_marking.js','catalog.js','actor_signals.js','app.js','direction_marking.js','actor_appearance.js','driver_signal.js','inspector.js']) {
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
}
const App = vm.runInContext('App',context), state = App.state;
App.renderPanels = () => App.renderInspector();
const load = (kind='street',ends={}) => {
  const s = {schema:1,id:'lanes-ui',crop:90,layout:{nodes:[{id:'a',x:0,z:-90},{id:'b',x:0,z:90}],
    streets:[{id:'st',a:'a',b:'b',kind,ends}],player:{street:'st',toward:'b'}},
    question:{maneuver:'straight',yieldTo:[]},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],decor:[],signs:[]};
  Layout.apply(s);
  state.S=s;state.id=s.id;state.savedJson=JSON.stringify(s);state.undo=[];state.redo=[];state.locked.clear();state.catalog={props:[],actorTypes:{}};
  return s;
};
const street = () => state.S.layout.streets[0];
const text = (key,value) => listeners.change({target:{closest:s=>s==='[data-text]'?{dataset:{text:key},value:String(value)}:null}});
const chip = (key,value) => listeners.click({target:{closest:s=>s==='[data-chip]'?{dataset:{chip:key,value}}:null}});
const step = (key,value) => listeners.click({target:{closest:s=>s==='[data-act]'?{dataset:{act:'lane-step',key,step:String(value)}}:null}});

const act=key=>listeners.click({target:{closest:s=>s==='[data-act]'?{dataset:{act:key}}:null}});
load();App.select({t:'street',id:'st'});const original=JSON.stringify(state.S);
act('reversible-five');
assert.deepEqual(clone(street().lanes.a),{left:2,right:3});
assert.equal(street().median,0);
assert.equal(state.S.markings.filter(m=>m.double==='dashed').length,2);
assert.equal(state.S.markings.filter(m=>m.type==='dashed'&&!m.double).length,2);
assert.equal(state.undo.length,1);
const five=JSON.stringify(state.S);App.undo();assert.equal(JSON.stringify(state.S),original);App.redo();assert.equal(JSON.stringify(state.S),five);
for(const key of ['left-1','centre','right-1','right-2'])assert(pane.innerHTML.includes(`data-key="${key}"`));
for(const style of Object.keys(Layout.LINE_STYLES)) {
 text('boundary-right-2',style);assert.equal(street().lineStyles['right-2'],style);
 const m=state.S.markings.filter(m=>m.street==='st');
 assert.equal(m.length,style==='none'?3:4);
 const reloaded=clone(state.S);Layout.apply(reloaded);assert.equal(JSON.stringify(reloaded),JSON.stringify(state.S));
}
text('boundary-all','solid_dashed');assert(state.S.markings.every(m=>m.type==='solid'&&m.double==='dashed'));
const locked=JSON.stringify(state.S);state.locked.add('roads');act('reversible-five');text('boundary-all','none');assert.equal(JSON.stringify(state.S),locked);state.locked.clear();
text('boundary-all','invalid');assert.equal(JSON.stringify(state.S),locked);
act('boundary-reset');assert.equal(street().lineStyles,undefined);assert.equal(street().lanes.a.right,3);
act('marks-own');assert.equal(street().manualMarks,true);const own=clone(state.S.markings.filter(m=>!m.auto));
assert(own.every(m=>m.points.length>=2 && m.points.length<=3),'straight manual conversion keeps only endpoints and optional midpoint');
text('boundary-all','none');assert.deepEqual(clone(state.S.markings.filter(m=>!m.auto)),own);
// New palette styles serialize to existing engine primitives, including manual lines.
for(const style of ['double','double_dashed','solid_dashed','dashed_solid']){
 load();const m={id:'manual',points:[[0,0],[0,15]],type:'solid'};state.S.markings.push(m);App.select({t:'marking',id:'manual'});chip('type',style);
 assert.equal(Layout.markingStyle(m),style);assert(['solid','dashed'].includes(m.type));assert(['solid','dashed'].includes(m.double));
}
// Curved, tapered and divided streets retain the assigned boundary styles.
for(const kind of ['street','avenue','highway'])for(const bend of [null,[18,0]]) {
 const s=load(kind);const st=street();if(bend)st.bend=bend;
 Layout.setLaneConfig(st,{a:{left:2,right:3},b:{left:1,right:2},width:3.5,taper:40});
 st.lineStyles={'left-1':'double_dashed','right-1':'solid_dashed','right-2':'none',centre:'none'};
 Layout.apply(s);assert(s.markings.some(m=>m.double==='dashed'));
 assert(s.markings.every(m=>m.points.every(p=>p.every(Number.isFinite))));
 const copy=clone(s);Layout.apply(copy);assert.deepEqual(copy,s);
}
// Multi-selection edits use one history entry and preserve unrelated markings.
load();const st2=clone(street());st2.id='st2';state.S.layout.streets.push(st2);Layout.apply(state.S);
App.select([{t:'street',id:'st'},{t:'street',id:'st2'}]);act('bulk-road-reversible-five');
assert(state.S.layout.streets.every(st=>st.lineStyles.centre==='double_dashed'));assert.equal(state.undo.length,1);
text('bulk-road-boundary-all','solid');assert(state.S.layout.streets.every(st=>Object.values(st.lineStyles).every(v=>v==='solid')));
load();state.S.markings.push({id:'m1',type:'solid',points:[[0,0],[0,10]]},{id:'m2',type:'dashed',points:[[2,0],[2,10]]});
App.select([{t:'marking',id:'m1'},{t:'marking',id:'m2'}]);const beforeBulk=JSON.stringify(state.S);
chip('bulk-line-style','double_dashed');assert(state.S.markings.filter(m=>m.id.startsWith('m')).every(m=>m.double==='dashed'&&m.type==='dashed'));
assert.equal(state.undo.length,1);App.undo();assert.equal(JSON.stringify(state.S),beforeBulk);
console.log('Boundary markings: five lanes, individual/all styles, reset, undo/redo, locks, manual preservation, curved/tapered/divided roads and reload PASS');
