// Camera framing contracts: the visible part of the phone, rotated drag geometry, and actual
// authoring controls/save/cancel handlers. No scene files are modified.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Camera = require('../editor/question_camera.js');
const THREE = require('../editor/vendor/three.min.js');
const near = (a, b, message) => assert.ok(Math.abs(a - b) < 1e-7, `${message}: ${a} != ${b}`);
const legacy = {centre: [7, 23], height: 22, card: 342};
const oldFree = 1 - legacy.card / 844, oldSize = legacy.height / oldFree;
const oldLookZ = legacy.centre[1] - (1 - oldFree) * oldSize / 2 / Math.sin(Math.atan2(42, 44));
const oldPose = Camera.pose(legacy);
near(oldPose.size, oldSize, 'legacy size'); near(oldPose.look[0], 7, 'legacy look X');
near(oldPose.look[1], 0, 'legacy elevation'); near(oldPose.look[2], oldLookZ, 'legacy look Z');
near(oldPose.position[0], 7, 'legacy camera X'); near(oldPose.position[1], 42, 'legacy camera height');
near(oldPose.position[2], oldLookZ - 44, 'legacy camera behind target');

function project(q, point, width, height, rect) {
  const p = Camera.pose(q), b = Camera.viewport(q, width, height, rect);
  const camera = new THREE.OrthographicCamera(b.left, b.right, b.top, b.bottom, .1, 5000);
  camera.position.set(...p.position); camera.lookAt(...p.look); camera.updateMatrixWorld();
  const s = new THREE.Vector3(...point).project(camera);
  return [(s.x + 1) / 2 * width, (1 - s.y) / 2 * height];
}
let frames = 0;
for (const yaw of [0, Math.PI / 2, -2.9]) for (const pitch of [Camera.MIN_PITCH, Camera.DEFAULT_PITCH, Camera.MAX_PITCH]) {
  for (const card of [200, 342, 560]) for (const elevation of [0, 3.5, 30]) {
    const q = {centre: [27, -13], height: 8.5, card, yaw, pitch, elevation};
    // The phone can be shifted away from the stage centre to make space for authoring controls.
    const rect = {x: 38, y: 24, w: 390, h: 844}, W = 1050, H = 1000;
    const target = [q.centre[0], q.elevation, q.centre[1]], at = project(q, target, W, H, rect);
    near(at[0], rect.x + rect.w / 2, 'target centred across phone');
    near(at[1], rect.y + rect.h * (1 - card / 844) / 2, 'target centred above card');
    const moved = Camera.pan(q, 19, -11, rect.h), shifted = project(moved, target, W, H, rect);
    near(shifted[0] - at[0], 19, 'rotated horizontal pan follows pointer');
    near(shifted[1] - at[1], -11, 'rotated vertical pan follows pointer');
    frames++;
  }
}
const side = Camera.pose({centre:[10,20],height:4,card:280,yaw:Math.PI/2,pitch:Math.PI/6,elevation:3});
near(side.position[1],3+Camera.DISTANCE/2,'elevation offsets camera and aim together');
near(side.position[2],20,'side view looks along X');
const orbit = Camera.orbit({...legacy,elevation:4},5000,-5000);
assert.deepEqual(orbit.centre,legacy.centre); near(orbit.elevation,4,'orbit keeps target height');
near(orbit.pitch,Camera.MIN_PITCH,'pitch clamp'); assert.ok(Math.abs(orbit.yaw) <= Math.PI);
near(Camera.zoom(legacy,.00001).height,1.5,'sign close-ups allowed');
near(Camera.zoom(legacy,10000).height,140,'zoom out bound');
const malformed = Camera.normalize({height:NaN,yaw:Infinity,pitch:NaN,elevation:NaN,centre:[undefined,Infinity]});
assert.ok(Object.values(Camera.pose(malformed)).flat().every(Number.isFinite),'malformed input cannot poison renderer');

// Exercise the real framing UI handlers and serialized result rather than a duplicate save function.
const elements = new Map(), events = {}, state = {S:{question:{text:{ru:{title:'Вопрос',options:['Первый','Второй']}}},questionView:{...legacy,yaw:2.1,pitch:.35,elevation:3.2}},source:null};
let lastPhone, restores = 0, edits = 0, frameRect = {x:100,y:20,w:390,h:844};
const modes = ['pan','orbit'].map(mode => ({dataset:{cameraGesture:mode},classList:{toggle(){}},setAttribute(){}}));
function element(key) {
  if (!elements.has(key)) elements.set(key,{hidden:false,innerHTML:'',classList:{add(){},remove(){}},
    addEventListener(type,fn){events[key+':'+type]=fn;},querySelector:()=>null,querySelectorAll:()=>modes});
  return elements.get(key);
}
const sceneEvents = {};
const context = vm.createContext({QuestionCamera:Camera,ResizeObserver:class{observe(){}},console,
  document:{querySelector:element,body:{classList:{add(){},remove(){}}},addEventListener:(type,fn)=>{events['document:'+type]=fn;}},
  Tools:{set(){}},App:{state,esc:String,ic:name=>`[${name}]`,r3:v=>Math.round(v*1000)/1000,select(){},setView(){},toast(){},edit(fn,opts){assert.equal(opts.rebuild,false,'framing must not rebuild authored road geometry');edits++;fn(state.S);}},
  Scene3D:{getView:()=>({mode:'plan',x:17,z:42}),setView:v=>{assert.equal(v.mode,'plan');restores++;},setHover(){},setPhone:p=>{lastPhone=p;},setPhoneGesture(){},phoneRect:()=>frameRect,on:(name,fn)=>{sceneEvents[name]=fn;}}});
vm.runInContext(fs.readFileSync(require.resolve('../editor/framing.js'),'utf8')+'\nglobalThis.CameraFraming=Framing;',context);
const Framing = context.CameraFraming;
const click = selectorValues => events['#phone:click']({target:{closest:selector=>selectorValues[selector]||null}});
Framing.start(); near(lastPhone.yaw,2.1,'saved yaw loaded'); near(lastPhone.pitch,.35,'saved pitch loaded'); near(lastPhone.elevation,3.2,'saved elevation loaded');
assert.equal(element('.top').inert,true,'scene navigation is disabled while framing');
assert.match(element('#phone').innerHTML,/data-camera-gesture="orbit"/); assert.match(element('#phone').innerHTML,/data-camera="elevation"/);
frameRect = {x:18,y:20,w:195,h:422}; sceneEvents.resize();
assert.match(element('#phone').innerHTML,/left:18px;top:20px;width:195px;height:422px/,'frame uses canvas-owned dimensions after resizing');
events['#phone:input']({target:{closest:()=>({dataset:{camera:'yaw'},value:'-75'})}});
near(lastPhone.yaw,-75*Math.PI/180,'slider changes camera immediately');
events['document:keydown']({key:'Enter',target:{closest:()=>({tagName:'INPUT'})},preventDefault(){},stopPropagation(){}});
assert.equal(edits,0,'Enter while adjusting a control must not accept the frame');
sceneEvents.phone({...lastPhone,elevation:7.2,pitch:.65});
click({'[data-frame]':{dataset:{frame:'save'}}});
near(state.S.questionView.elevation,7.2,'drag/control changes survive save');
assert.ok(Math.abs(state.S.questionView.yaw+75*Math.PI/180)<.001);
assert.equal(state.S.questionView.card,undefined,'card estimate is not persisted');
assert.equal(lastPhone,null); assert.equal(restores,1);
assert.equal(element('.top').inert,false,'scene navigation is restored after framing');
const saved = JSON.stringify(state.S.questionView);
Framing.start(); click({'[data-camera-preset]':{dataset:{cameraPreset:'top'}}});
near(lastPhone.pitch,Camera.MAX_PITCH,'top preset immediate');
Framing.stop(null); assert.equal(JSON.stringify(state.S.questionView),saved,'Cancel keeps authored camera');
Framing.start(); Framing.stop('auto'); assert.equal(state.S.questionView,undefined,'Automatic framing removes the entire custom pose');
assert.equal(restores,3,'all exits restore normal editor camera');
console.log(`Question camera: legacy pose, ${frames} rotated/elevated card and drag projections, UI roundtrip, cancel and auto PASS`);
