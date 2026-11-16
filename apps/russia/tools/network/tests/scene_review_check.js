// Shared visible filters exercise the real question module and scene-panel handlers.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const read = name => fs.readFileSync(require.resolve('../editor/' + name), 'utf8');
const records = [
  {id:'ticket_10_14',ticket:10,number:14,status:'game',hasScene:true,question:'Поворот налево'},
  {id:'ticket_11_2',ticket:11,number:2,status:'plan',hasScene:true,question:'Знак'},
  {id:'ticket_12_5',ticket:12,number:5,status:'plan',hasScene:false,decision:'yes',question:'Разворот'},
  {id:'ticket_1_5',ticket:1,number:5,status:'ai',hasScene:true,question:'Поворот'},
  {id:'ticket_2_5',ticket:2,number:5,status:'game',hasScene:true,question:'Полосы'},
  {id:'ticket_3_5',ticket:3,number:5,status:'game',hasScene:false,question:'Дорожный вопрос'},
  {id:'ticket_3_6',ticket:3,number:6,status:'plan',hasScene:false,question:'Не выбран'},
  {id:'ticket_3_7',ticket:3,number:7,status:'game',hasScene:true,decision:'no',question:'Удалён'},
];
const storage = new Map();
function mount(search='') {
  const listeners={}, opened=[];
  const element=()=>({innerHTML:'',hidden:true,querySelector:()=>null,querySelectorAll:()=>[],addEventListener(){}});
  const elements=Object.fromEntries(['#left-body','#home-screen'].map(key=>[key,element()]));
  const document={querySelector:key=>elements[key],querySelectorAll:()=>[],addEventListener(type,callback){(listeners[type]??=[]).push(callback);}};
  const App={state:{scenes:[{id:'mini_regulator'}],section:'city',questions:structuredClone(records)},esc:String,ic:()=>'',thumbRev:{},sceneTitle:id=>id,openScene:async id=>{opened.push(id);App.state.id=id;}};
  const context=vm.createContext({App,document,URLSearchParams,location:{search},window:{history:{replaceState(){}}},localStorage:{getItem:key=>storage.get(key),setItem:(key,value)=>storage.set(key,value)},Thumbs:{fillAll(){}},Tools:{renderBar(){}}});
  vm.runInContext(read('question_plan.js')+'\nglobalThis.QuestionPlan=QuestionPlan;',context);
  vm.runInContext(read('panels.js'),context);
  App.state.questionsLoaded=true;
  const left=()=>{App.renderPanels({only:['left']});return elements['#left-body'].innerHTML;};
  const home=()=>{App.renderHome();return elements['#home-screen'].innerHTML;};
  const ids=html=>Array.from(html.matchAll(/data-plan-question="([^"]+)"/g),m=>m[1]);
  const dispatch=(type,target)=>listeners[type].forEach(fn=>fn({target}));
  const click=value=>dispatch('click',{closest:selector=>selector==='[data-scene-filter]'?{dataset:{sceneFilter:value}}:null});
  return {App,plan:context.QuestionPlan,opened,ids,left,home,dispatch,click};
}
let ui=mount();
const all=['ticket_10_14','ticket_11_2','ticket_12_5','ticket_1_5','ticket_2_5','ticket_3_5'];
assert.deepEqual(ui.ids(ui.left()),all);
assert.deepEqual(Array.from(ui.left().matchAll(/data-scene-filter="([^"]+)"/g),m=>m[1]),['all','game','assistant','plan']);
assert.doesNotMatch(ui.left()+ui.home(),/<select|data-toggle-scene-filters|data-scene-section|План вопросов|Игровые сцены/);
assert.equal(ui.plan.count('all'),6);assert.equal(ui.plan.count('game'),3);assert.equal(ui.plan.count('ai'),1);assert.equal(ui.plan.count('plan'),2);
ui.click('assistant');assert.deepEqual(ui.ids(ui.left()),['ticket_1_5']);assert.match(ui.left(),/На одобрении/);
ui.click('game');assert.deepEqual(ui.ids(ui.left()),['ticket_10_14','ticket_2_5','ticket_3_5']);
assert.match(ui.left(),/data-plan-question="ticket_3_5"[^>]*disabled/,'procedural road questions cannot create duplicate scenes');
ui.click('plan');assert.deepEqual(ui.ids(ui.left()),['ticket_11_2','ticket_12_5']);
ui.click('all');
ui.dispatch('input',{id:'scene-q',value:'Билет №10 вопрос 14'});assert.deepEqual(ui.ids(ui.left()),['ticket_10_14']);
ui.dispatch('input',{id:'scene-q',value:'Билет 1'});assert.deepEqual(ui.ids(ui.left()),['ticket_1_5']);
ui.dispatch('input',{id:'scene-q',value:'разворот'});assert.deepEqual(ui.ids(ui.home()),['ticket_12_5']);
ui=mount('?filter=assistant');assert.equal(ui.App.sceneFilter(),'assistant');
ui=mount('?filter=questions');assert.equal(ui.App.sceneFilter(),'plan');
ui=mount('?filter=review');assert.equal(ui.App.sceneFilter(),'all');
ui.App.setSceneFilter('assistant');ui.App.state.questions.find(q=>q.id==='ticket_1_5').status='game';
assert.deepEqual(ui.ids(ui.left()),[],'approved scenes leave the pending queue');
ui.click('game');assert(ui.ids(ui.left()).includes('ticket_1_5'));
ui.App.state.section='regulator';assert.match(ui.left(),/data-scene="mini_regulator"/);assert.doesNotMatch(ui.left(),/scene-tabs/);
console.log('Scene filters: unified four visible tabs, counts, pending-only approval, search, old links, road protection and regulator PASS');
