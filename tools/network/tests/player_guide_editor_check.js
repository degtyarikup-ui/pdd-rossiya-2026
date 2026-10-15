// Exercise actual Scene3D route rendering/picking and App.select without a GPU or browser draft.
// Vendored THREE performs the geometry, projection and ray calculations. The only test hook
// bootstraps an in-memory scene/camera in a copy of the module, bypassing WebGL mounting.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const THREE = require('../editor/vendor/three.min.js');

const editor = path.join(__dirname, '../editor');
const context = vm.createContext({THREE, console, document: {querySelector: () => null}});
for (const name of ['GLTFLoader', 'LineSegmentsGeometry', 'LineGeometry', 'LineMaterial', 'LineSegments2', 'Line2']) {
  vm.runInContext(fs.readFileSync(path.join(editor, `vendor/${name}.js`), 'utf8'), context);
}
vm.runInContext(fs.readFileSync(path.join(editor, 'app.js'), 'utf8'), context);

const source = fs.readFileSync(path.join(editor, 'scene3d.js'), 'utf8');
const marker = '  return {\n    mount, load, refresh';
assert.ok(source.includes(marker), 'Scene3D public API location is explicit');
const bootstrap = `  return {
    __test: {
      configure(value) {
        model = value; build = null; mode = 'plan'; width = height = 800; pxPerM = 8;
        scene = new THREE.Scene(); groups = {anchors:new THREE.Group()}; scene.add(groups.anchors);
        camera = new THREE.OrthographicCamera(-50,50,50,-50,0.1,200);
        camera.position.set(0,100,0); camera.up.set(0,0,1); camera.lookAt(0,0,0);
        camera.updateProjectionMatrix(); camera.updateMatrixWorld();
        sel = []; hover = null; labels = []; handles = []; hidden = new Set();
        simMode = false; planHandles = false;
        App.state.S = value; App.state.id = value.id; App.state.sel = [];
      },
      redraw() { rebuildRoutes(); rebuildSelection(); },
      group(name) { return groups[name]; },
      labels() { return labels; },
      sim(on) { simMode = on; },
    },
    mount, load, refresh`;
vm.runInContext(source.replace(marker, bootstrap), context);
const api = vm.runInContext('({Scene3D,App})', context);
const view = api.Scene3D, app = api.App, test = view.__test;

function fixture(id = 'player-guide-fixture') {
  return {id, question:{maneuver:'left'}, stop:{x:20,z:-20,yaw:0},
    routes:[
      {id:'approach',kind:'approach',auto:true,points:[[0,-45],[0,-25]]},
      {id:'manoeuvre_left',kind:'manoeuvre',exit:'left',auto:true,points:[[20,-20],[20,0],[20,25]]},
      {id:'choice_А',kind:'choice',label:'А',arrowhead:false,points:[[-20,-20],[-20,25]],labelPosition:[-20,25]},
      {id:'choice_Б',kind:'choice',label:'Б',points:[[-35,-20],[-35,25]],labelPosition:[-35,25]},
    ], actors:[],lights:[],decor:[],roads:[],markings:[],lawns:[],tracks:[]};
}
const guide = {t:'route',id:'manoeuvre_left'};
function pick(x,z) {
  const screen = view.screenOf(x,z);
  return view.hitAt(screen.x,screen.y);
}
function colours(group) {
  const result = [];
  group.traverse(node => {
    if (node.material?.color) result.push(node.material.color.getHex());
  });
  return result;
}
function choiceSnapshot() {
  const opacity = [];
  test.group('routes').traverse(node => {
    if ([0xe0533d,0x8b5cf6].includes(node.material?.color?.getHex())) opacity.push(node.material.opacity);
  });
  return {
    colours:colours(test.group('routes')).filter(c => c === 0xe0533d || c === 0x8b5cf6),
    labels:Array.from(test.labels()).filter(l => l.cls === 'letter').map(l => [l.text,l.colour]),
    opacity,
  };
}

const model = fixture();
test.configure(model);
app.select(guide); // Same entry point used by a route row in the layers panel.
assert.ok(colours(test.group('routes')).includes(0x0574f8), 'default/current route keeps its blue guide');
assert.ok(test.group('selection').children.length > 0, 'visible selected guide retains its editable supports');
assert.equal(pick(20,10)?.id,guide.id, 'visible guide is pickable');
view.setSelection([]);
const choices = choiceSnapshot();
assert.equal(choices.colours.length,3,'both answer ribbons survive, including the choice without an arrowhead');
assert.deepEqual(choices.labels.map(l => l[0]),['А','Б']);
const paths = JSON.stringify(model.routes);

model.question.showPlayerGuide = false;
app.select({...guide,v:1}); // Hiding can leave a previously selected vertex in App.state.
assert.equal(app.state.sel[0].id,guide.id, 'hidden path remains selectable from the layers/inspector');
assert.equal(test.group('selection').children.length,0,'hidden selected route has no blue outline or support handles');
assert.ok(!colours(test.group('routes')).includes(0x0574f8),'hidden selected route has no blue ribbon/arrow');
assert.ok(colours(test.group('routes')).includes(0x16a34a),'hiding blue maneuver does not hide the green approach');
assert.equal(pick(20,0),null,'stale selected support does not remain pickable');
assert.equal(pick(20,10),null,'hidden route cannot be picked or reappear on hover');
assert.deepEqual(choiceSnapshot(),choices,'hidden selected route does not dim, recolour or remove answer choices/letters');
for (const [x,id] of [[-20,'choice_А'],[-35,'choice_Б']]) {
  assert.equal(pick(x,10)?.id,id,'answer choice remains pickable');
}
view.setSelection([]);
view.setHover(guide); // Defensive check for a stale hover while visibility changes.
assert.equal(test.group('selection').children.length,0,'hidden stale hover does not draw an outline');
assert.deepEqual(choiceSnapshot(),choices,'hidden hover cannot dim visible answer choices');
test.sim(true); test.redraw();
assert.ok(!colours(test.group('routes')).includes(0x0574f8),'test-drive mode does not resurrect the hidden guide');
test.sim(false);

// The route row still selects the unchanged gameplay path, so its inspector can restore visibility.
app.select(guide);
model.question.showPlayerGuide = true;
app.select(guide);
assert.ok(colours(test.group('routes')).includes(0x0574f8),'restoring through the selected route returns its guide');
assert.ok(test.group('selection').children.length > 0,'restoring returns editable supports');
assert.equal(pick(20,10)?.id,guide.id,'restored guide is pickable again');
assert.equal(JSON.stringify(model.routes),paths,'visibility never changes or deletes gameplay/answer points');

const regulator = fixture('mini_regulator');
regulator.question.showPlayerGuide = false;
test.configure(regulator); app.select(guide);
assert.ok(colours(test.group('routes')).includes(0x0574f8),'city guide flag does not hide regulator maneuvers');
assert.ok(test.group('selection').children.length > 0,'regulator route editing remains available');

console.log('Player guide editor: actual render/picking, hidden selection/hover/supports, choices, layer restore and regulator PASS');
