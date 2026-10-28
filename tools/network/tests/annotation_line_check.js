// Actual annotation inspector and editor history, plus geometry consumed by the Godot parity test.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const lines=require('../editor/annotation_line.js');
const Layout=require('../editor/layout.js');
const clone=value=>JSON.parse(JSON.stringify(value));
const fixtures=[];
for(const [style] of lines.styles)for(const width of [.08,.16,.6])for(const points of [
  [[0,0],[0,8]],[[2,-3],[2,-3],[5,-3],[5,4]],[[0,0],[.2,.2]],
])for(const border of [0,.04]) {
  const route={style,width,points};
  const geometry=lines.geometry(route,border);
  assert(geometry.length>0 && geometry.length%3===0);
  assert(geometry.flat().every(Number.isFinite));
  fixtures.push({route,border,geometry});
}
const straight=style=>lines.geometry({points:[[0,0],[0,8]],style,width:.16});
assert(straight('line').every(p=>Math.abs(p[0])<=.081));
assert(straight('arrow').some(p=>Math.abs(p[0])>.3&&p[1]>6));
assert(!straight('arrow').some(p=>Math.abs(p[0])>.3&&p[1]<2));
assert(straight('both').some(p=>Math.abs(p[0])>.3&&p[1]<2));
assert.deepEqual(lines.geometry({points:[[0,0],[0,0]]}),[]);
const handlers={};
const pane={innerHTML:'',querySelector:()=>null,querySelectorAll:()=>[],addEventListener:(name,fn)=>{handlers[name]=fn;}};
const node={classList:{toggle(){}},addEventListener(){},dataset:{}};
const context=vm.createContext({Layout,document:{querySelector:key=>key==='#inspector'?pane:node},
  Scene3D:{refresh(){},setSelection(){}},Thumbs:{fillAll(){}},setTimeout:()=>0,clearTimeout(){}});
for(const file of ['annotation_line.js','catalog.js','app.js','inspector.js'])vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
const App=vm.runInContext('App',context),state=App.state;
const chip=(name,value)=>handlers.click({target:{closest:selector=>selector==='[data-chip]'?{dataset:{chip:name,value}}:null}});
const act=name=>handlers.click({target:{closest:selector=>selector==='[data-act]'?{dataset:{act:name}}:null}});
state.S={schema:1,id:'annotation-fixture',crop:90,layout:Layout.template('cross',90),question:{maneuver:'straight'},
  roads:[],markings:[],lawns:[],routes:[{id:'choice_Б',kind:'choice',label:'Б',labelPosition:[3,5],arrowhead:false,points:[[0,5],[3,5]]}],actors:[],lights:[],decor:[],signs:[]};
Layout.apply(state.S);state.id=state.S.id;state.savedJson=JSON.stringify(state.S);
App.renderPanels=()=>App.renderInspector();
App.select({t:'route',id:'choice_Б'});
assert.match(pane.innerHTML,/data-act="as-annotation"/);
const before=clone(state.S);act('as-annotation');
const annotation=()=>state.S.routes.find(r=>r.kind==='annotation');
assert.equal(annotation().style,'line');assert.equal(annotation().colour,'#8b5cf6');
assert.equal(annotation().label,undefined);assert.equal(annotation().labelPosition,undefined);
assert.deepEqual(clone(annotation().points),before.routes.find(r=>r.kind==='choice').points);
assert.match(pane.innerHTML,/без буквы/);assert.doesNotMatch(pane.innerHTML,/data-chip="label"/);
App.undo();assert(state.S.routes.some(r=>r.label==='Б'));App.redo();
App.select({t:'route',id:annotation().id});chip('annotation-style','both');
assert.equal(annotation().style,'both');chip('annotation-colour','#20242b');assert.equal(annotation().colour,'#20242b');
const routesBefore=clone(state.S.routes.filter(r=>r.kind!=='annotation'));
App.nudge(1,2);assert.deepEqual(clone(annotation().points),[[1,7],[4,7]]);
App.undo();App.rotate(90);assert(Math.abs(annotation().points[0][0]-annotation().points[1][0])<.001);
App.undo();App.duplicate();assert.equal(state.S.routes.filter(r=>r.kind==='annotation').length,2);
assert.deepEqual(clone(state.S.routes.filter(r=>r.kind!=='annotation')),routesBefore);
App.undo();App.select({t:'route',id:annotation().id});state.locked.add('routes');
chip('annotation-style','line');assert.equal(annotation().style,'both');
state.locked.clear();
for(let i=0;i<6;i++)state.S.routes.push({id:`annotation_extra_${i}`,kind:'annotation',points:[[0,0],[1,1]],style:'line'});
const saved=clone(state.S.routes.filter(r=>r.kind==='annotation'));Layout.apply(state.S);
assert.deepEqual(clone(state.S.routes.filter(r=>r.kind==='annotation')),saved,'road regeneration preserves unlimited annotations');
if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(fixtures));
console.log('Annotations: three styles, short/duplicate/bent geometry, letter conversion, inspector, copy/rotate/move, locks and history PASS');
