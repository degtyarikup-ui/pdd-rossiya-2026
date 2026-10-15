// Run the actual inspector's event handlers against copied/generated scenes.
// No editor server, browser draft, network file or save API is involved.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const Layout = require('../editor/layout.js');
const clone = value => JSON.parse(JSON.stringify(value));
const listeners = {};
const pane = {innerHTML:'', addEventListener:(kind,fn) => {listeners[kind] = fn;}, querySelectorAll:() => []};
const state = {S:null, id:'inspector-fixture', sel:[], ltab:'scene', texSel:null};
let undo = [], removeCalls = 0, compactSelection;
const App = {
  state, esc:String, ic:() => '', r3:n => Math.round(n * 1000) / 1000,
  objectOf:ref => state.S?.routes.find(r => r.id === ref.id),
  select:ref => {state.sel = Array.isArray(ref) ? ref : [ref]; App.renderInspector();},
  edit:fn => {
    undo.push(clone(state.S));
    fn(state.S);
    Layout.apply(state.S);
    App.renderInspector();
  },
  remove:() => {
    removeCalls++;
    const ref = state.sel[0];
    App.edit(sc => {
      const route = sc.routes.find(r => r.id === ref.id);
      Layout.editPlayerRoute(sc,route);
      route.points.splice(ref.v,1);
    });
    App.select({t:'route',id:ref.id});
  },
};
const wrappedLayout = {...Layout, compactPlayerRoute:(scene,route) => {
  compactSelection = clone(state.sel[0]);
  return Layout.compactPlayerRoute(scene,route);
}};
const context = vm.createContext({
  App, Layout:wrappedLayout, Catalog:{EXITS:{left:{title:'Налево',icon:'left'},straight:{title:'Прямо',icon:'straight'},right:{title:'Направо',icon:'right'},uturn:{title:'Разворот',icon:'uturn'}}},
  document:{querySelector:selector => selector === '#inspector' ? pane : {addEventListener:() => {}}},
  Thumbs:{fillAll:() => {}}, setTimeout,
});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../editor/inspector.js'),'utf8'),context);
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
  const route = scene.routes.find(r => r.kind === kind && (kind === 'approach' || r.exit === 'left'));
  App.select({t:'route',id:route.id});
  undo = []; removeCalls = 0;
  return () => state.S.routes.find(r => r.id === route.id);
}
function selectedIndex(index) {change('routeIndex',index + 1);}
function undoLast() {state.S = undo.pop(); App.select({t:'route',id:state.sel[0].id});}
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
  assert.deepEqual(route().points[0],originalFirst,'pinned first point cannot be changed numerically');
  assert.equal(removeCalls,0,'pinned point never reaches delete handler');
  const beforeAdd = clone(route().points);
  click('route-add-point');
  assert.equal(route().points.length,beforeAdd.length+1,'insert adds one support after the chosen point');
  assert.equal(state.sel[0].v,1);
  assert.deepEqual(route().points[1],beforeAdd[0].map((n,axis) => App.r3((n+beforeAdd[1][axis])/2)));
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
    assert.deepEqual(route().points.at(-1),end,'approach end remains pinned at the player');
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
  assert.deepEqual(route().points[0],dense[0]);
  assert.deepEqual(route().points.at(-1),dense.at(-1),'compact preserves the authored endpoint');
  undoLast();
  assert.deepEqual(route().points,dense,'compact is one reversible edit');
  selectedIndex(dense.length-2);
  click('auto-path');
  assert.equal(state.sel[0].v,undefined,'reset also clears old support index');
  assert.ok(route().auto && !route().manual);
  assert.doesNotMatch(pane.innerHTML,/data-text="routeX"/);
}
// Real traced routes have neither auto nor manual flags. Opening/inspecting
// them must expose their authored supports without rewriting the source file.
for (const id of ['ticket_10_15','ticket_13_15','ticket_9_14']) {
  const file = path.join(__dirname, '../../../game_godot/network', `${id}.json`);
  const diskBefore = fs.readFileSync(file,'utf8');
  state.S = JSON.parse(diskBefore);
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
  assert.equal(fs.readFileSync(file,'utf8'),diskBefore,'legacy source stays byte-for-byte unchanged');
}
{
  const file = path.join(__dirname,'../../../game_godot/network/ticket_10_15.json');
  const diskBefore = fs.readFileSync(file,'utf8');
  state.S = JSON.parse(diskBefore);
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
  assert.equal(fs.readFileSync(file,'utf8'),diskBefore);
}
console.log('Player route inspector: generated/legacy/manual, anchors, numeric edits, add/delete, compact/reset selection and undo PASS');
