// Real App integration: virtual template save, editor/review draft safety and failed-save guards.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = value => JSON.parse(JSON.stringify(value));
const elements = new Map(), calls = [];
const element = () => ({hidden:true,classList:{toggle(){},add(){},remove(){}},addEventListener(){},dataset:{}});
let drawn, failSave = false;
const scene = {id:'ticket_cd_1_1',schema:1,crop:90,layout:Layout.template('cross',90),question:{maneuver:'straight'},questionPool:{category:'cd'},roads:[],routes:[],markings:[],lawns:[],actors:[],lights:[],decor:[]};
Layout.apply(scene);
const context = vm.createContext({
  Layout, document:{querySelector:key => {if (!elements.has(key)) elements.set(key,element()); return elements.get(key);},querySelectorAll:()=>[],title:''},
  Scene3D:{load:(s,built)=>{drawn=built;},refresh(){},setSelection(){},capture:()=>({toBlob(){}})},Tools:{set(){}},
  QuestionPlan:{load:async()=>[]},history:{replaceState(){}},
  setTimeout:()=>0,clearTimeout(){},
  fetch:async(path,options={})=>{
    calls.push({path,options});
    let data = path === '/api/scenes' ? [] : path.includes('/include/') ? {playable:true,count:1} : options.method ? {findings:[]} : {scene:clone(scene),build:{surfaces:[]},findings:[],virtual:true};
    const ok = !(failSave && options.method && path.startsWith('/api/scene/'));
    if (!ok) data = {error:'fixture save failure'};
    return {ok,statusText:'fixture',json:async()=>data};
  },
});
vm.runInContext(fs.readFileSync(require.resolve('../editor/app.js'),'utf8'),context);
const App = vm.runInContext('App',context);
App.renderPanels = ()=>{};
(async()=>{
  assert.equal(App.sceneTitle('ticket_cd_1_1'),'Билет 1 · вопрос 1 · C/D');
  await App.openScene(scene.id);
  assert.equal(App.state.virtual,true); assert.equal(App.state.dirty,false,'untouched generated base has no authored edits to discard');
  assert.equal(elements.get('#save').disabled,false,'new base can be saved without an unrelated edit');
  assert.ok(drawn,'virtual template draws the provided road build immediately');
  App.edit(sc => {sc.question.authorDraft = 'kept';},{rebuild:false});
  const before = JSON.stringify(App.state.S), previousCalls = calls.length;
  await App.openScene(scene.id);
  assert.equal(JSON.stringify(App.state.S),before,'reopening the same editor preserves unsaved scene and history');
  assert.equal(calls.length,previousCalls,'same scene is not fetched again');
  failSave = true;
  await App.setPlayable(true); await App.runInGame();
  assert.equal(App.state.dirty,true);
  assert.ok(!calls.some(call=>call.path.includes('/include/') || call.path.includes('/run/')),'failed save cannot enable or run stale data');
  failSave = false;
  await App.save();
  assert.equal(App.state.virtual,false); assert.equal(App.state.dirty,false);
  await App.setPlayable(true);
  assert.equal(App.state.S.reviewed,true);
  assert.equal(App.state.S.questionPool,undefined,'promotion clears the in-memory draft marker');
  console.log('Question pool editor: virtual drawing/save, same-scene draft, failed-save guards and promotion PASS');
})().catch(error=>{console.error(error);process.exitCode=1;});
