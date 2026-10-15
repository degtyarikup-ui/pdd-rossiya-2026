// Run the actual inspector's event handlers against copied/generated scenes.
// No editor server, browser draft, network file or save API is involved.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = value => JSON.parse(JSON.stringify(value));
const deepEqual = (actual,expected,label) => assert.deepEqual(clone(actual),clone(expected),label);
const listeners = {};
const pane = {innerHTML:'', addEventListener:(kind,fn) => {listeners[kind] = fn;}, querySelectorAll:() => []};
let state, removeCalls = 0, compactSelection;
const wrappedLayout = {...Layout, compactPlayerRoute:(scene,route) => {
  compactSelection = clone(state.sel[0]);
  return Layout.compactPlayerRoute(scene,route);
}};
const context = vm.createContext({
  Layout:wrappedLayout, Catalog:{EXITS:{left:{title:'Налево',icon:'left'},straight:{title:'Прямо',icon:'straight'},right:{title:'Направо',icon:'right'},uturn:{title:'Разворот',icon:'uturn'}}},
  document:{querySelector:selector => selector === '#inspector' ? pane : {addEventListener:() => {},dataset:{},classList:{toggle:() => {}}}},
  Scene3D:{refresh:() => {},setSelection:() => {}},Tracks:{apply:() => {}},
  Thumbs:{fillAll:() => {},img:() => ''},setTimeout:() => 0,clearTimeout:() => {},
});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../editor/app.js'),'utf8')+'\nglobalThis.testApp = App;',context);
const App = context.testApp;
state = App.state;
const actualRemove = App.remove;
App.remove = (...args) => {removeCalls++; return actualRemove(...args);};
vm.runInContext(fs.readFileSync(path.join(__dirname,'../editor/inspector.js'),'utf8'),context);
App.renderPanels = () => App.renderInspector();
function click(act) {
  return listeners.click({target:{closest:selector => selector === '[data-act]' ? {dataset:{act}} : null}});
}
function change(key,value) {
  return listeners.change({target:{closest:selector => selector === '[data-text]' ? {dataset:{text:key},value:String(value)} : null}});
}
function setup(kind,free=false) {
  const scene = {schema:1,id:'inspector-fixture',crop:90,layout:Layout.template('cross',90),question:{maneuver:'left',correct:0,text:{ru:{options:['Да']}}},roads:[],routes:[],markings:[],lawns:[],actors:[],lights:[]};
  Layout.apply(scene);
  if (free) {Layout.setPlayerMode(scene,'free'); Layout.apply(scene);}
  state.S = scene;
  state.id = scene.id;
  state.savedJson = JSON.stringify(scene);
  state.undo = []; state.redo = [];
  const route = scene.routes.find(r => r.kind === kind && (kind === 'approach' || r.exit === 'left'));
  App.select({t:'route',id:route.id});
  removeCalls = 0;
  return () => state.S.routes.find(r => r.id === route.id);
}
function selectedIndex(index) {change('routeIndex',index + 1);}
function undoLast() {App.undo(); App.select({t:'route',id:state.sel[0].id});}
for (const free of [false,true]) for (const kind of ['approach','manoeuvre']) {
  const route = setup(kind,free);
  assert.match(pane.innerHTML,new RegExp(`Опорных точек: ${route().points.length}`));
  assert.match(pane.innerHTML,/строится по дорогам/);
  assert.doesNotMatch(pane.innerHTML,/data-text="routeX"/,'automatic points are not silently editable');
  click('own-path');
  assert.ok(route().manual && !route().auto,'explicit manual mode uses Layout helper');
  assert.match(pane.innerHTML,/data-text="routeX"/);
  assert.match(pane.innerHTML,/data-text="routeX"[^>]*disabled/,'origin is pinned at the entry/player');
  const originalFirst = clone(route().points[0]);
  change('routeX',9876);
  click('route-delete-point');
  deepEqual(route().points[0],originalFirst,'pinned first point cannot be changed numerically');
  assert.equal(removeCalls,0,'pinned point never reaches delete handler');
  const beforeAdd = clone(route().points);
  click('route-add-point');
  assert.equal(route().points.length,beforeAdd.length+1,'insert adds one support after the chosen point');
  assert.equal(state.sel[0].v,1);
  deepEqual(route().points[1],beforeAdd[0].map((n,axis) => App.r3((n+beforeAdd[1][axis])/2)));
  change('routeX',route().points[1][0]+0.15);
  const x = route().points[1][0];
  assert.equal(state.sel[0].v,1,'regeneration retains the selected support index');
  change('routeX',''); change('routeX','not-a-number'); change('routeZ','Infinity');
  assert.equal(route().points[1][0],x,'invalid coordinates are ignored');
  const n = route().points.length;
  click('route-delete-point');
  assert.equal(route().points.length,n-1,'delete removes exactly the selected interior support');
  assert.equal(state.sel[0].v,undefined);
  if (kind === 'approach') {
    selectedIndex(route().points.length-1);
    const end = clone(route().points.at(-1));
    change('routeZ',5432); click('route-delete-point');
    deepEqual(route().points.at(-1),end,'approach end remains pinned at the player');
    assert.doesNotMatch(pane.innerHTML,/data-act="route-add-point"/,'no insertion beyond approach endpoint');
  }
  // The old selected index must be dropped before compact/reset rerenders a shorter path.
  App.edit(sc => {
    const r = sc.routes.find(r => r.id === route().id);
    Layout.editPlayerRoute(sc,r);
    r.points = r.points.flatMap((a,i,points) => i === points.length-1 ? [a] : Array.from({length:4},(_,j) => a.map((n,axis) => App.r3(n+(points[i+1][axis]-n)*j/4))));
  });
  const dense = clone(route().points);
  selectedIndex(dense.length-2);
  assert.match(pane.innerHTML,/Упростить точки/);
  click('route-compact');
  assert.equal(compactSelection.v,undefined,'stale vertex cleared before simplification');
  assert.equal(state.sel[0].v,undefined);
  assert.ok(route().points.length <= dense.length);
  deepEqual(route().points[0],dense[0]);
  deepEqual(route().points.at(-1),dense.at(-1),'compact preserves the authored endpoint');
  undoLast();
  deepEqual(route().points,dense,'compact is one reversible edit');
  selectedIndex(dense.length-2);
  click('auto-path');
  assert.equal(state.sel[0].v,undefined,'reset also clears old support index');
  assert.ok(route().auto && !route().manual);
  assert.doesNotMatch(pane.innerHTML,/data-text="routeX"/);
}
// Editable author scenes can be converted to the constructor at any time.
// Keep the legacy representation explicit instead of depending on their current disk state.
function legacyFixture(id) {
  const sc={schema:1,id,crop:90,layout:Layout.template('cross',90),question:{maneuver:'left',correct:0,text:{ru:{options:['Да']}}},roads:[],routes:[],markings:[],lawns:[],actors:[],lights:[],decor:[]};
  Layout.apply(sc);
  delete sc.layout;
  for(const route of sc.routes){delete route.auto;delete route.manual;}
  return sc;
}
// Real traced routes have neither auto nor manual flags. Opening/inspecting
// them must expose their authored supports without rewriting the source file.
for (const id of ['ticket_10_15','ticket_13_15','ticket_9_14']) {
  state.S = legacyFixture(id);
  state.id = id;
  assert.ok(!state.S.layout,'legacy fixture has no road constructor');
  const authored = state.S.routes.find(r => r.kind === 'manoeuvre' && !r.auto && !r.manual && r.points.length > 2);
  assert.ok(authored,`${id} has a route without either mode flag`);
  const route = () => state.S.routes.find(r => r.id === authored.id);
  App.select({t:'route',id:authored.id,v:1});
  assert.match(pane.innerHTML,/ручной путь/);
  assert.match(pane.innerHTML,/data-text="routeX"/,'legacy controls are immediately available');
  const oldPoint = clone(route().points[1]);
  change('routeX',oldPoint[0]+0.125);
  assert.equal(route().points[1][0],App.r3(oldPoint[0]+0.125));
  assert.equal(route().points[1][1],oldPoint[1]);
  assert.ok(route().manual && !route().auto,'first legacy numeric edit records explicit manual intent');
  assert.doesNotMatch(pane.innerHTML,/data-act="auto-path"/,'traced manual manoeuvre cannot be regenerated by a missing constructor');
  const n = route().points.length;
  click('route-add-point');
  assert.equal(route().points.length,n+1);
  click('route-delete-point');
  assert.equal(route().points.length,n,'legacy supports can also be inserted/deleted');

}
{
  state.S = legacyFixture('legacy-approach');
  state.id = state.S.id;
  const route = () => state.S.routes.find(r => r.kind === 'approach');
  App.select({t:'route',id:route().id,v:route().points.length-1});
  assert.match(pane.innerHTML,/ручной путь/,'legacy approach uses the same inferred mode');
  assert.match(pane.innerHTML,/data-text="routeZ"/);
  assert.doesNotMatch(pane.innerHTML,/data-act="auto-path"/,'traced road has no constructor to regenerate an approach');
  const newZ = App.r3(route().points.at(-1)[1]+0.25);
  change('routeZ',newZ);
  assert.equal(route().points.at(-1)[1],newZ);
  assert.equal(state.S.stop.z,newZ,'legacy approach numeric endpoint matches mouse-drag player anchoring');
  assert.ok(route().manual);

}
// Exercise the real App.remove / edit / undo paths, including automatic and
// traced routes. Timers are disabled above, so no preview/save request is sent.
function resetHistory() {
  state.undo=[]; state.redo=[]; state.savedJson=JSON.stringify(state.S); state.dirty=false;
}
for (const mode of ['auto','manual','traced','А/Б']) {
  let route;
  if (mode === 'traced' || mode === 'А/Б') {
    state.S=legacyFixture(mode);
    state.id=state.S.id;
    route=() => state.S.routes.find(r => r.id === 'manoeuvre_left');
    App.select({t:'route',id:route().id});
  } else {
    route=setup('manoeuvre');
    if (mode === 'manual') click('own-path');
  }
  const before=clone(state.S.routes);
  resetHistory();
  const selection=clone(state.sel);
  App.remove();
  assert.equal(state.S.question.showPlayerGuide,false,`${mode}: whole-route Delete hides its visual`);
  deepEqual(state.S.routes,before,`${mode}: Delete preserves every route and point`);
  assert.ok(state.dirty,`${mode}: hide marks an unsaved change`);
  assert.equal(state.undo.length,1,`${mode}: hide is one undo step`);
  assert.match(pane.innerHTML,/Скрыта в этой сцене/);
  assert.match(pane.innerHTML,/Вернуть синюю стрелку/);
  assert.doesNotMatch(pane.innerHTML,/data-text="routeX"/,'hidden guide has no invisible point-edit controls');
  assert.doesNotMatch(pane.innerHTML,/data-act="own-path"/);
  App.undo();
  assert.equal(Object.hasOwn(state.S.question,'showPlayerGuide'),false);
  deepEqual(state.S.routes,before);
  assert.equal(state.dirty,false,'undo restores the saved scene');
  App.redo();
  assert.equal(state.S.question.showPlayerGuide,false);
  click('player-guide');
  assert.equal(Object.hasOwn(state.S.question,'showPlayerGuide'),false,'restore deletes the false-only flag');
  deepEqual(state.S.routes,before);
  // Direct hide with an individual vertex selected clears its old index first.
  App.select({...selection[0],v:1});
  App.setPlayerGuideVisible(false);
  assert.equal(state.sel[0].v,undefined);
  assert.equal(state.S.question.showPlayerGuide,false);
  App.setPlayerGuideVisible(true);
  assert.equal(Object.hasOwn(state.S.question,'showPlayerGuide'),false);
  // The common scene inspector can restore the flag without a route selection.
  App.setPlayerGuideVisible(false);
  App.select([]);
  assert.match(pane.innerHTML,/Вернуть синюю стрелку/);
  click('player-guide');
  assert.equal(Object.hasOwn(state.S.question,'showPlayerGuide'),false);
  deepEqual(state.S.routes,before);
  if (mode === 'manual') {
    resetHistory();
    App.select({t:'route',id:route().id,v:1});
    const n=route().points.length;
    App.remove();
    assert.equal(route().points.length,n-1,'Delete on a point still removes one point');
    assert.equal(Object.hasOwn(state.S.question,'showPlayerGuide'),false,'point Delete does not hide the guide');
    App.undo();
    deepEqual(state.S.routes,before,'point Delete remains undoable');
  }
}
{
  const route=setup('manoeuvre');
  state.S.routes.push({id:'choice_А',kind:'choice',label:'А',points:[[1,1],[2,2]]});
  const before=clone(state.S.routes);
  resetHistory();
  // Mixed Delete hides the manoeuvre and still deletes the other selected item.
  state.sel=[{t:'route',id:route().id},{t:'route',id:'choice_А'}];
  App.remove();
  assert.equal(state.S.question.showPlayerGuide,false);
  deepEqual(state.S.routes,before.filter(r => r.id !== 'choice_А'));
  assert.equal(state.undo.length,1,'mixed Delete is one edit');
  App.undo();
  deepEqual(state.S.routes,before);
  assert.equal(Object.hasOwn(state.S.question,'showPlayerGuide'),false);
}
{
  state.S=JSON.parse(fs.readFileSync(path.join(__dirname,'../../../game_godot/network/mini_regulator.json'),'utf8'));
  state.id='mini_regulator';
  resetHistory();
  const before=clone(state.S);
  const route=state.S.routes.find(r => r.kind === 'manoeuvre');
  App.select({t:'route',id:route.id});
  assert.doesNotMatch(pane.innerHTML,/data-act="player-guide"/,'mini-game inspector has no city-only toggle');
  App.remove();
  App.setPlayerGuideVisible(false);
  deepEqual(state.S,before,'mini-game whole-route Delete remains protected');
  assert.equal(state.undo.length,0,'mini-game guide protection creates no edit');
  App.select([]);
  assert.doesNotMatch(pane.innerHTML,/data-act="player-guide"/,'mini-game general inspector also has no toggle');
}
console.log('Player route inspector: generated/legacy/manual, anchors, point edits, compact, guide visibility, actual Delete/undo/dirty and mini-game protection PASS');
