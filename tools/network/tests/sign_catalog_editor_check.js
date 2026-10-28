// Full catalogue names, real sign inspector, searchable grid and plate edits with undo.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const info = require('../../../game_godot/signs/catalog.json');
const options = Object.entries(info).map(([code,item]) => ({dataset:{signOption:`${code} · ${item.title}`},hidden:false}));
const listeners = {};
const pane = {innerHTML:'',addEventListener:(name,fn) => {listeners[name] = fn;},
  querySelectorAll:selector => selector === '[data-sign-option]' ? options : [],querySelector:() => null};
const node = {addEventListener:() => {},dataset:{},classList:{toggle:() => {}},textContent:''};
const context = vm.createContext({Layout,
  document:{querySelector:selector => selector === '#inspector' ? pane : node},
  Scene3D:{refresh:() => {},setSelection:() => {}},Tracks:{apply:() => {}},
  Thumbs:{fillAll:() => {},img:() => ''},setTimeout:() => 0,clearTimeout:() => {},
});
for (const file of ['catalog.js','sign_mount.js','lane_sign.js','actor_signals.js','app.js','direction_marking.js','inspector.js'])
  vm.runInContext(fs.readFileSync(require.resolve('../editor/'+file),'utf8'),context);
const {App,Catalog} = vm.runInContext('({App,Catalog})',context), state = App.state;
Catalog.setSignCatalog(info);
App.renderPanels = () => App.renderInspector();
state.catalog = {signs:Object.keys(info),signInfo:info};
state.S = {id:'sign-fixture',question:{},roads:[],routes:[],markings:[],lawns:[],actors:[],lights:[],decor:[],
  signs:[{id:'sign1',code:'2.4',pos:[-6,-10],yaw:0}]};
state.id = state.S.id;
state.savedJson = JSON.stringify(state.S);
App.select({t:'sign',id:'sign1'});
assert.match(pane.innerHTML,/aria-label="3.28 · Стоянка запрещена"/);
assert.match(pane.innerHTML,/value="8.2.2"/,'all plates are available under the selected sign');
listeners.input({target:{closest:s => s === '[data-sign-search]' ? {value:'3.28'} : null}});
assert.equal(options.filter(o => !o.hidden).length,1,'inspector search filters without replacing the focused input');
const chip = (name,value) => listeners.click({target:{closest:s => s === '[data-chip]' ? {dataset:{chip:name,value}} : null}});
const change = (name,value) => listeners.change({target:{closest:s => s === '[data-text]' ? {dataset:{text:name},value} : null}});
chip('code','3.28');
const sign = () => state.S.signs[0];
assert.equal(sign().code,'3.28');
change('plateSign','8.2.2'); assert.equal(sign().plateSign,'8.2.2');
const saved = JSON.stringify(state.S);
assert.equal(JSON.parse(saved).signs[0].plateSign,'8.2.2');
App.undo(); assert.equal(sign().plateSign,undefined);
App.redo(); assert.equal(sign().plateSign,'8.2.2');
state.locked.add('signs'); change('plateSign','8.2.3');
assert.equal(sign().plateSign,'8.2.2','a locked sign retains its plate'); state.locked.clear();
change('plateSign',''); assert.equal(sign().plateSign,undefined,'plate can be removed');
assert.equal(Catalog.signName('8.2.2'),'Зона действия');
console.log('Sign catalogue inspector: complete named grid, search, sign/plate selection, persistence, undo and locks PASS');
