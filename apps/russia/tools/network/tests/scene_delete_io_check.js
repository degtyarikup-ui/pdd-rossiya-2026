// Deletion shares the real editor's write queue and cannot discard an unrelated draft.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const elements = new Map(), requests = [], shown = [];
const tick = () => new Promise(resolve => setImmediate(resolve));
const document = {querySelector(key) {
  if (!elements.has(key)) elements.set(key,{hidden:true,dataset:{},classList:{toggle(){}}});
  return elements.get(key);
},querySelectorAll:()=>[],addEventListener(){},removeEventListener(){}};
const response = data => ({ok:true,json:async()=>data});
const context = vm.createContext({document,history:{replaceState(){}},setTimeout:()=>0,clearTimeout(){},
  Tools:{set(){}},Layout:{refreshPlayerRoutes(){}},
  Scene3D:{load(){},refresh(){},setSelection(){},setBuild:b=>shown.push(b),capture:()=>({toBlob(){}})},
  fetch(path,opts={}) {
    if(path==='/api/scenes')return Promise.resolve(response([]));
    return new Promise((resolve,reject)=>requests.push({path,body:opts.body&&JSON.parse(opts.body),
      resolve:data=>resolve(response(data)),reject}));
  },
});
vm.runInContext(fs.readFileSync(require.resolve('../editor/app.js'),'utf8'),context);
const App=vm.runInContext('App',context);
const next=path=>{const r=requests.shift();assert.equal(r?.path,path);return r;};
const scene=id=>({scene:{id,layout:{streets:[]},roads:[],actors:[],routes:[],markings:[],lawns:[]},findings:[]});
const info=id=>({id,ids:[id],hasScene:true,revision:'r1'});
const answer=yes=>document.querySelector('#confirm').onclick({target:{closest:()=>({dataset:{answer:yes?'yes':'no'}})}});
const set=async id=>{const opened=App.openScene(id);next('/api/scene/'+id).resolve(scene(id));await opened;};
(async()=>{
 await set('ticket_9_14');App.edit(s=>s.note='my draft',{rebuild:false});
 const before=JSON.stringify(App.S),history=JSON.stringify(App.state.undo);
 let pending=App.deleteScene('ticket_9_14');next('/api/scene/ticket_9_14/deletion').resolve(info('ticket_9_14'));await tick();
 assert.match(document.querySelector('#confirm-text').textContent,/Несохранённые изменения/);
 answer(false);assert.equal(await pending,false);assert.equal(JSON.stringify(App.S),before);assert.equal(requests.length,0);

 // Deleting another row never saves/discards the open scene or its undo history.
 pending=App.deleteScene('ticket_40_13');next('/api/scene/ticket_40_13/deletion').resolve(info('ticket_40_13'));await tick();answer(true);await tick();
 let deletion=next('/api/scene/ticket_40_13/delete');assert.equal(deletion.body.revision,'r1');
 assert.equal(await App.deleteScene('ticket_40_13'),false);
 deletion.resolve({ids:['ticket_40_13']});assert.equal(await pending,true);
 assert.equal(JSON.stringify(App.S),before);assert.equal(JSON.stringify(App.state.undo),history);assert.equal(App.state.dirty,true);

 pending=App.deleteScene('ticket_9_14');next('/api/scene/ticket_9_14/deletion').resolve(info('ticket_9_14'));await tick();answer(true);await tick();
 next('/api/scene/ticket_9_14/delete').reject(new Error('changed since confirmation'));
 assert.equal(await pending,false);assert.equal(JSON.stringify(App.S),before);assert.equal(App.state.dirty,true);

 // A save already running finishes before deletion is described; no later save
 // or publication can queue behind deletion and recreate the removed scene.
 const save=App.save(),writing=next('/api/scene/ticket_9_14');
 pending=App.deleteScene('ticket_9_14');assert.equal(requests.length,0);
 assert.equal(App.save(),false);await App.setPlayable(true);assert.equal(requests.length,0);
 writing.resolve({findings:[]});await save;await tick();
 next('/api/scene/ticket_9_14/deletion').resolve(info('ticket_9_14'));await tick();answer(true);await tick();
 deletion=next('/api/scene/ticket_9_14/delete');assert.equal(App.save(),false);
 deletion.resolve({ids:['ticket_9_14']});assert.equal(await pending,true);
 assert.equal(App.S,null);assert.equal(App.state.id,null);assert.equal(App.state.dirty,false);
 assert.equal(App.state.undo.length,0);App.undo();assert.equal(App.S,null);
 assert.equal(document.querySelector('#home-screen').hidden,false);

 // Changing the selected scene while metadata is loading cancels deletion.
 await set('ticket_2_2');pending=App.deleteScene('ticket_3_3');const late=next('/api/scene/ticket_3_3/deletion');
 await set('ticket_4_4');late.resolve(info('ticket_3_3'));assert.equal(await pending,false);
 assert.equal(App.state.id,'ticket_4_4');assert.equal(requests.length,0);
 assert.equal(await App.deleteScene('mini_regulator'),false);assert.equal(requests.length,0);
 console.log('Scene deletion I/O: cancel, failures, unrelated drafts, write queue, stale navigation, clearing history and protected mini-game PASS');
})().catch(e=>{console.error(e);process.exitCode=1});
