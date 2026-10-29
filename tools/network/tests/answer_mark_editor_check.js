// Exercise real placement, inspector, dragging and history on disposable in-memory scenes.
const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const Layout = require('../editor/layout.js');
const elements = new Map(), pointer = {};
const element = () => ({hidden:false, innerHTML:'', dataset:{}, style:{}, listeners:{}, classList:{add(){},remove(){},toggle(){}},
  addEventListener(name,fn){this.listeners[name]=fn;},querySelector:()=>null,querySelectorAll:()=>[]});
let draft, hit;
const context = vm.createContext({Layout, console, setTimeout:()=>0, clearTimeout(){},
  document:{querySelector:key=>{if(!elements.has(key))elements.set(key,element());return elements.get(key);},querySelectorAll:()=>[]},
  Scene3D:{on:(key,fn)=>pointer[key]=fn,refresh(){},setSelection(){},setDraft:d=>draft=d,setGhost(){},setHover(){},setPanTool(){},setPlanHandles(){},hitAt:()=>hit},
  Thumbs:{fillAll(){}}, Tracks:{apply(){}},
});
for(const name of ['catalog.js','actor_signals.js','annotation_line.js','answer_mark.js','app.js','tools.js','inspector.js'])
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+name),'utf8'),context);
const {App,Tools,AnswerMark} = vm.runInContext('({App,Tools,AnswerMark})',context);
const clone = x=>JSON.parse(JSON.stringify(x));
const scene = {id:'letter-fixture',question:{},roads:[],routes:[],actors:[],lights:[],decor:[],markings:[],lawns:[]};
App.state.S=scene; App.state.id=scene.id; App.state.savedJson=JSON.stringify(scene);
App.renderPanels=()=>{App.renderInspector();Tools.renderBar();};
Tools.init();
const pane=elements.get('#inspector'), pop=elements.get('#popover');
const button=(dataset,disabled=false)=>({dataset,disabled});
const click=(el,selector,data)=>el.listeners.click({target:{closest:s=>s===selector?button(data):null}});
const mode=value=>click(pop,'button',{answerMode:value});
const chip=(name,value)=>click(pane,'[data-chip]',{chip:name,value});
const point=(type,x,z)=>pointer.pointer({type,world:{x,z},sx:0,sy:0});
const choices=()=>App.state.S.routes.filter(r=>r.kind==='choice');
Tools.set('answer'); mode('letter');
assert(!Tools.list().some(t=>t.id==='annotation'),'only one toolbar entry');
point('move',30,40);assert.equal(draft.label,'А');
point('down',30,40);assert.equal(choices().length,1);assert.equal(choices()[0].display,'letter');
assert.deepEqual(clone(choices()[0].points),[]);assert.deepEqual(clone(choices()[0].labelPosition),[30,40]);
assert.equal(Tools.opts.answerLetter,'Б','advance to next free letter');
assert.match(pane.innerHTML,/отдельная буква в кружке/);assert.doesNotMatch(pane.innerHTML,/data-act="mid"/);
const before = JSON.stringify(App.state.S);
App.undo();assert.equal(choices().length,0);App.redo();assert.equal(JSON.stringify(App.state.S),before);
point('down',40,40);point('down',50,40);point('down',60,40);assert.equal(choices().length,4);
const count=App.state.undo.length;point('down',70,40);assert.equal(choices().length,4);assert.equal(App.state.undo.length,count);
App.select({t:'route',id:'choice_А'});chip('label','Б');assert.equal(choices()[0].label,'А','occupied letter cannot be reused');
Tools.set('select');hit={t:'letter',id:'choice_А'};point('down',31,41);point('move',36,46);point('up',36,46);
assert.deepEqual(clone(choices()[0].labelPosition),[35,45],'drag retains initial grab offset');
App.undo();assert.deepEqual(clone(choices()[0].labelPosition),[30,40]);
App.state.locked.add('routes');chip('answer-display','arrow');assert.equal(Tools.current(),'select');App.state.locked.clear();
App.select({t:'route',id:'choice_А'});chip('answer-display','line');
point('down',35,40);Tools.enter();
assert.equal(Tools.current(),'select');assert.equal(choices()[0].display,undefined);assert.equal(choices()[0].arrowhead,false);
const path=JSON.stringify(choices()[0].points);chip('answer-display','letter');assert.equal(choices()[0].display,'letter');
assert.deepEqual(clone(App.pointsOfRef({t:'route',id:'choice_А'})),[],'hidden remembered path has no edit handles');
chip('answer-display','arrow');assert.equal(choices()[0].display,undefined);assert.equal(JSON.stringify(choices()[0].points),path);
assert.equal(choices()[0].arrowhead,undefined,'restoring arrow restores old path');
Tools.set('annotation');assert.equal(Tools.current(),'answer');assert.equal(Tools.opts.answerMode,'annotation');
point('down',0,0);point('down',5,0);Tools.enter();assert.equal(App.state.S.routes.filter(r=>r.kind==='annotation').length,1);
Tools.set('answer');mode('letter');App.state.locked.add('routes');App.select({t:'route',id:'choice_Г'});App.remove();
assert.equal(choices().length,4,'locked letters cannot be deleted');App.state.locked.clear();App.remove();
assert.equal(choices().length,3);assert.equal(Tools.opts.answerLetter,'Г','delete frees the letter');
point('down',70,40);assert.equal(choices().length,4);
// Participant paths must work even when the remembered answer mode is letter-only.
App.renderPanels=()=>Tools.renderBar();
App.state.S.actors.push({id:'car_1',type:'car',pos:[0,0],behaviour:{staysPut:true}});
Tools.drawPathFor('car_1');point('down',2,0);point('down',4,0);Tools.enter();
assert(App.state.S.routes.some(r=>r.kind==='actor'&&r.manual));assert.equal(choices().length,4);
console.log('Answer marks: unified tool, free placement, letters, drag offset, limits, locks, history, hide/restore/draw line, annotations and actor paths PASS');
