// Real editor format changes and history; fixtures are copies, never saved.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const Layout=require('../editor/layout.js'),clone=v=>JSON.parse(JSON.stringify(v));
const source=JSON.parse(fs.readFileSync(path.join(__dirname,'../../../game_godot/network/ticket_9_14.json'),'utf8'));
const elements=new Map();let fits=0,confirms=0;
const el=()=>({hidden:true,innerHTML:'',dataset:{},style:{},classList:{add(){},remove(){},toggle(){}},addEventListener(){},querySelector:()=>null,querySelectorAll:()=>[]});
const ctx=vm.createContext({Layout,console,setTimeout:()=>0,clearTimeout(){},
 document:{querySelector:k=>{if(!elements.has(k))elements.set(k,el());return elements.get(k)},querySelectorAll:()=>[]},
 Scene3D:{on(){},refresh(){},setSelection(){},setDraft(){},setGhost(){},setHover(){},setPanTool(){},setPlanHandles(){},fit(){fits++}},
 Thumbs:{fillAll(){},fill(){},img:()=>''},Tracks:{apply(){},nearest:()=>null}});
for(const file of ['catalog.js','app.js','tools.js'])vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),ctx);
const {App,Tools}=vm.runInContext('({App,Tools})',ctx);App.renderPanels=()=>{};Tools.init();
function load(){App.state.S=clone(source);App.state.id=source.id;App.state.plan=null;App.state.undo=[];App.state.redo=[];App.state.sel=[];App.state.locked.clear();App.state.savedJson=JSON.stringify(App.S);return JSON.stringify(App.S)}
(async()=>{
 const original=load();assert.equal(App.S.sceneFormat,undefined);
 App.confirm=async()=>{confirms++;return false};await Tools.applySceneFormat('compact');assert.equal(JSON.stringify(App.S),original);assert.equal(App.state.undo.length,0);
 App.confirm=async()=>{confirms++;return true};App.state.locked.add('roads');await Tools.applySceneFormat('compact');assert.equal(confirms,1);App.state.locked.clear();
 await Tools.applySceneFormat('invalid');assert.equal(JSON.stringify(App.S),original);
 let resolve;App.confirm=()=>new Promise(r=>resolve=r);const pending=Tools.applySceneFormat('compact');App.edit(s=>s.question.text='new edit',{rebuild:false});resolve(true);await pending;assert.equal(App.S.crop,source.crop);assert.equal(App.S.question.text,'new edit');
 load();App.confirm=async()=>true;await Tools.applySceneFormat('compact');
 assert.equal(App.S.crop,45);assert.equal(App.S.sceneFormat,'compact');assert.equal(App.S.layout.streets.length,1);
 assert.deepEqual(App.S.layout.nodes.map(n=>Math.abs(n.z)),[45,45]);
 assert(Math.abs(App.S.stop.x)<21&&Math.abs(App.S.stop.z)<21,'question stop remains inside the runtime cut');
 for(const key of ['decor','actors','lights','signs','question'])assert.deepEqual(clone(App.S[key]),source[key],key+' is retained');
 assert.equal(App.state.undo.length,1);assert.equal(fits,1);
 const compact=JSON.stringify(App.S);App.undo();assert.equal(JSON.stringify(App.S),original);App.redo();assert.equal(JSON.stringify(App.S),compact);
 await Tools.applyTemplate('avenue');assert.equal(App.S.crop,45,'templates use the selected size');
 App.undo();assert.equal(JSON.stringify(App.S),compact);
 await Tools.applySceneFormat('standard');assert.equal(App.S.crop,90);assert.equal(App.S.sceneFormat,'standard');assert.equal(App.S.layout.streets.length,4);
 App.undo();assert.equal(JSON.stringify(App.S),compact);
 if(process.argv[2])fs.writeFileSync(process.argv[2],compact);
 console.log('Scene format: explicit compact/standard, cancel/lock/stale protection, preserved objects/text, runtime stop, templates, exact undo/redo PASS');
})().catch(e=>{console.error(e);process.exitCode=1});
