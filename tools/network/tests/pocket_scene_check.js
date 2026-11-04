// Render/pick the actual Three.js pocket controls without GPU-specific screenshots.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const THREE=require('../editor/vendor/three.min.js'),editor=path.join(__dirname,'../editor');
const context=vm.createContext({THREE,console,document:{querySelector:()=>null},
 RoadPocket:require('../editor/road_pocket.js'),Tracks:require('../editor/tracks.js')});
for(const name of ['GLTFLoader','LineSegmentsGeometry','LineGeometry','LineMaterial','LineSegments2','Line2'])vm.runInContext(fs.readFileSync(path.join(editor,'vendor',name+'.js'),'utf8'),context);
for(const name of ['app.js','annotation_line.js','bus_stop_marking.js'])vm.runInContext(fs.readFileSync(path.join(editor,name),'utf8'),context);
const source=fs.readFileSync(path.join(editor,'scene3d.js'),'utf8'),marker='  return {\n    mount, load, refresh';
assert(source.includes(marker));
vm.runInContext(source.replace(marker,`  return {
 __test:{configure(value,perspective=false){
  model=value;build=null;mode=perspective?'3d':'plan';width=height=800;pxPerM=8;
  scene=new THREE.Scene();groups={anchors:new THREE.Group()};scene.add(groups.anchors);
  camera=perspective?new THREE.PerspectiveCamera(45,1,.1,500):new THREE.OrthographicCamera(-50,50,50,-50,.1,200);
  camera.position.set(perspective?35:0,perspective?60:100,perspective?-45:0);camera.up.set(0,0,1);camera.lookAt(0,0,0);
  camera.updateProjectionMatrix();camera.updateMatrixWorld();
  sel=[];hover=null;labels=[];handles=[];hidden=new Set();simMode=false;planHandles=false;App.state.S=value;App.state.id=value.id;App.state.sel=[];
 },group:name=>groups[name]},
 mount, load, refresh`),context);
const {Scene3D:view,App:app}=vm.runInContext('({Scene3D,App})',context),test=view.__test;
const fixture={id:'pocket-view',question:{},stop:{x:40,z:40,yaw:0},roads:[],markings:[],routes:[],lawns:[],actors:[],lights:[],decor:[],
 pockets:[{id:'pocket',pos:[0,0],yaw:.3,length:16,width:4,entryLength:10,exitLength:6,side:'right'}]};
const RoadPocket=require('../editor/road_pocket.js'),ref={t:'pocket',id:'pocket'};
function pick(point){const screen=view.screenOf(...point);return view.hitAt(screen.x,screen.y);}
for(const perspective of [false,true]){
 test.configure(fixture,perspective);
 const inside=RoadPocket.at(fixture.pockets[0],0,2);
 assert.equal(pick(inside)?.id,'pocket','pocket body remains selectable in '+(perspective?'3D':'2D'));
 const outside=RoadPocket.at(fixture.pockets[0],0,7);assert.equal(pick(outside),null);
 app.select(ref);assert(test.group('selection').children.length>0,'selected pocket has its curved outline');
 assert(view.turnHandle,'pocket exposes the ordinary heading grip');
 const turn=view.turnHandle;assert.equal(view.hitAt(turn.sx,turn.sy).t,'turn');
 view.setDraft({kind:'pocket',points:RoadPocket.outline(fixture.pockets[0]),closed:true,bare:true});
 assert(test.group('draft').children.some(c=>c.isMesh),'placement displays a filled pocket footprint');
 view.setHidden(new Set(['roads']));assert.equal(pick(inside),null,'hidden road layer cannot intercept clicks');
 view.setHidden(new Set());assert.equal(pick(inside)?.id,'pocket');
}
console.log('Pocket Scene3D: filled placement, exact curved selection, rotation grip, 2D/3D picking and hidden-layer behaviour PASS');
