// Exercise actual Scene3D route rendering/picking and App.select without a GPU or browser draft.
// Vendored THREE performs the geometry, projection and ray calculations. The only test hook
// bootstraps an in-memory scene/camera in a copy of the module, bypassing WebGL mounting.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const THREE = require('../editor/vendor/three.min.js');

const editor = path.join(__dirname, '../editor');
const context = vm.createContext({THREE, Tracks:require('../editor/tracks.js'), console, document: {querySelector: () => null}});
for (const name of ['GLTFLoader', 'LineSegmentsGeometry', 'LineGeometry', 'LineMaterial', 'LineSegments2', 'Line2']) {
  vm.runInContext(fs.readFileSync(path.join(editor, `vendor/${name}.js`), 'utf8'), context);
}
vm.runInContext(fs.readFileSync(path.join(editor, 'app.js'), 'utf8'), context);
vm.runInContext(fs.readFileSync(path.join(editor, 'annotation_line.js'), 'utf8'), context);
vm.runInContext(fs.readFileSync(path.join(editor, 'bus_stop_marking.js'), 'utf8'), context);

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
      filterBaked,
      redraw() { rebuildRoutes(); rebuildSelection(); },
      group(name) { return groups[name]; },
      labels() { return labels; },
      sim(on) { simMode = on; },
      frame(on) { phone = on ? {} : null; rebuildRoutes(); rebuildSelection(); },
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

const preview = fixture();
test.configure(preview); test.frame(true);
assert.ok(!colours(test.group('routes')).includes(0x16a34a),'phone hides the approach editing line');
assert.deepEqual(choiceSnapshot().labels.map(l => l[0]),['А','Б'],'phone preserves the actual answer choices');
assert.ok(!colours(test.group('routes')).includes(0x0574f8),'choices replace the fallback player guide in the phone');
preview.routes = preview.routes.filter(r => r.kind !== 'choice');
test.redraw();
assert.ok(colours(test.group('routes')).includes(0x0574f8),'phone shows the actual player guide when there are no choice routes');
preview.question.showPlayerGuide = false; test.redraw();
assert.ok(!colours(test.group('routes')).includes(0x0574f8),'phone respects the hidden player guide');
test.frame(false);

const short = fixture();
short.routes = short.routes.filter(r => r.kind !== 'choice');
short.routes.push({id:'player_guide',kind:'guide',manual:true,points:[[20,-20],[20,-16],[20,-12]]});
test.configure(short); app.select({t:'route',id:'player_guide',v:2});
assert.equal(pick(20,-14)?.id,'player_guide','the short arrow is pickable instead of the underlying full drive route');
assert.equal(pick(20,10),null,'the invisible long driving route cannot intercept guide edits');
let bounds = new THREE.Box3().setFromObject(test.group('routes'));
assert.ok(bounds.max.z < -10,'editor draws only the nearby custom guide');
test.frame(true);
bounds = new THREE.Box3().setFromObject(test.group('routes'));
assert.ok(bounds.max.z < -10,'phone preview uses the short guide instead of the complete drive path');
short.question.showPlayerGuide = false; test.redraw();
assert.ok(!colours(test.group('routes')).includes(0x0574f8),'hidden short guide is not drawn in preview');
assert.equal(test.group('selection').children.length,0,'hidden short guide has no editable handles');
test.frame(false);

const annotations=fixture();
annotations.question.showPlayerGuide=false;
annotations.routes.push({id:'annotation_1',kind:'annotation',style:'both',colour:'#20242b',points:[[10,10],[30,10]]});
test.configure(annotations);test.redraw();
assert.equal(test.group('routes').children.filter(node=>node.userData.annotation==='annotation_1').length,2,'outlined annotation has no letter mesh');
assert.equal(pick(15,10)?.id,'annotation_1','annotations are pickable independently of the player guide');
assert.deepEqual(choiceSnapshot().labels.map(l=>l[0]),['А','Б'],'annotations add no answer letters');
test.frame(true);
assert.ok(colours(test.group('routes')).includes(0x20242b),'phone framing retains annotations when player guide is hidden');
annotations.routes=annotations.routes.filter(r=>r.kind!=='choice');annotations.question.showPlayerGuide=true;test.redraw();
assert.ok(colours(test.group('routes')).includes(0x0574f8),'annotations do not replace the player guide');
test.frame(false);
console.log('Player guide editor: actual render/picking, hidden selection/hover/supports, choices, annotations, layer restore and regulator PASS');

const tokens=fixture();
tokens.routes=tokens.routes.filter(r=>r.kind!=='choice');
tokens.routes.push({id:'choice_В',kind:'choice',label:'В',display:'letter',points:[[-30,-20],[-30,20]],labelPosition:[10,10]});
test.configure(tokens);app.select({t:'route',id:'choice_В'});
assert.equal(test.group('selection').children.length,0,'a hidden remembered line has no outline or supports');
assert.equal(pick(-30,0),null,'a hidden remembered line is not pickable');
assert.equal(pick(10,10)?.t,'letter','standalone letter can be dragged');
assert.equal(choiceSnapshot().labels[0][0],'В','standalone letter is rendered');
test.frame(true);
assert.equal(test.group('routes').children.length,0,'letter-only phone has neither a hidden answer line nor fallback guide');
assert.equal(choiceSnapshot().labels[0][0],'В','phone retains standalone letter');
tokens.routes.find(r=>r.kind==='choice').points=[];test.redraw();
assert.equal(choiceSnapshot().labels[0][0],'В','a new letter needs no points');
test.frame(false);
view.setHidden(new Set(['routes']));
assert.equal(choiceSnapshot().labels.length,0,'hiding routes hides standalone letters too');
view.setHidden(new Set());
assert.equal(choiceSnapshot().labels[0][0],'В','restoring routes restores the letter');
console.log('Standalone letters: actual render, picking, hidden path, selection and phone preview PASS');

// The old ticket mesh contains blue reference bands, independent of answer routes.
const baked = new THREE.Group(), geometry = new THREE.BufferGeometry();
const positions=[], vertexColours=[];
for (const [y,colour] of [[.038,[5/255,116/255,248/255]],[.038,[1,1,1]],[.12,[5/255,116/255,248/255]]]) {
  positions.push(-3,y,-12,0,y,-12,0,y,-11.9);
  for(let i=0;i<3;i++)vertexColours.push(...colour);
}
geometry.setAttribute('position',new THREE.Float32BufferAttribute(positions,3));
geometry.setAttribute('color',new THREE.Float32BufferAttribute(vertexColours,3));
const oldGround=new THREE.Mesh(geometry,new THREE.MeshBasicMaterial());oldGround.name='static';baked.add(oldGround);
test.filterBaked(baked,{surfaces:[]});
assert.deepEqual(Array.from(oldGround.geometry.index.array),[3,4,5,6,7,8],
  'remove only legacy blue reference bands; preserve white markings and actual raised blue guides');
console.log('Legacy blue reference bars: hidden without removing authored markings or guides PASS');

const stops=fixture();stops.routes=[];
const stopMark={id:'bus',type:'bus_stop',colour:'yellow',points:[[-3.5,-20],[-3.5,0]],side:-1,depth:1.2,step:1.5,width:.12};
stops.markings=[stopMark];test.configure(stops);test.redraw();
const Bus=vm.runInContext('BusStopMark',context),tip=Bus.line(stopMark)[1];
assert.equal(pick(...tip)?.id,'bus','pointed tips are pickable away from the kerb axis');
view.setHidden(new Set(['marks']));assert.equal(pick(...tip),null,'hidden zigzags do not intercept selection');view.setHidden(new Set());
view.setDraft({kind:'bus_stop',points:[[-3.5,-20]],cursor:[-3.5,0],side:-1});
assert.ok(test.group('draft').children.some(node=>node.material?.color?.getHex()===0xf5b025),'preview draws actual yellow triangles');
view.setDraft(null);
console.log('Bus stop renderer: actual pointed-tip picking, layer visibility and yellow geometry preview PASS');
