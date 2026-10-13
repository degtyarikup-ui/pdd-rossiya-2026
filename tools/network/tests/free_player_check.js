// Free placement changes the question pose/routes while retaining roads, paint and authored paths.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const Layout = require('../editor/layout.js');
const clone = s => JSON.parse(JSON.stringify(s));
function scene(template) {
  const s = {schema:1,id:'free-player-test',crop:90,layout:Layout.template(template,90),question:{maneuver:'straight',correct:0,text:{ru:{options:['Да']}}},compliance:{status:'ok'},roads:[],routes:[],markings:[],lawns:[],actors:[],lights:[],decor:[]};
  Layout.apply(s);return s;
}
const cases = [];
for(const [template,points] of [
 ['ring',[[-14,0,0],[-12,-6,-0.25],[0,14,Math.PI/2],[14,0,Math.PI],[-14,6,0.4]]],
 ['cross',[[-1.8,-50,0],[-1.8,20,0],[20,1.8,Math.PI/2],[-20,-1.8,-Math.PI/2],[0,0,0.7]]],
 ['avenue',[[40,-5.25,-Math.PI/2],[-35,-1.75,-Math.PI/2]]],
 ['straight',[[-1.8,-55,0],[-1.8,35,0]]],
]) {
 const s=scene(template),original=clone(s),roadPaint=JSON.stringify([s.roads,s.markings,s.lawns]);
 assert.equal(Layout.setPlayerMode(s,'free'),true);
 for(const [x,z,yaw] of points) {
  s.layout.player.pose={x,z,yaw};
  assert.ok(Layout.freePlayerSupported(s,s.layout.player.pose),`${template} ${x},${z}: footprint`);
  Layout.apply(s);
  assert.equal(s.playerRouteErrors,undefined,`${template}: valid pose has complete routes`);
  assert.deepEqual(s.stop,{x,z,yaw:Math.round(yaw*1000)/1000});
  assert.equal(JSON.stringify([s.roads,s.markings,s.lawns]),roadPaint,'roads and paint unchanged');
  const approach=s.routes.find(r=>r.kind==='approach');
  assert.deepEqual(approach.points.at(-1),[x,z]);
  assert.ok(Math.hypot(...approach.points[0])>80,'approach still enters at the border');
  for(const r of s.routes.filter(r=>r.kind==='manoeuvre')) assert.deepEqual(r.points[0],[x,z],`${r.id}: starts at pose`);
  const saved=clone(s);Layout.apply(saved);assert.deepEqual(saved.stop,s.stop,'save/reload retains exact pose');
  assert.deepEqual(saved.routes,s.routes,'routes stable after reload');
  cases.push({template,scene:clone(s)});
 }
 const before=clone(s.layout.player.pose);
 assert.equal(Layout.movePlayer(s,[80,80]),false,'reject lawn');assert.deepEqual(s.layout.player.pose,before);
 Layout.setPlayerMode(s,'street');Layout.apply(s);assert.deepEqual(clone(s.stop),original.stop,'street mode restored');
 assert.equal(JSON.stringify(s.routes),JSON.stringify(original.routes),'street routes restored');
}
const ring=scene('ring');Layout.setPlayerMode(ring,'free');
assert.equal(Layout.movePlayer(ring,[0,0]),false,'island rejected even though approach roads overlap it');
assert.equal(Layout.movePlayer(ring,[-14,0]),true);assert.equal(Layout.rotatePlayer(ring,0.42),true);Layout.apply(ring);
const straight=scene('straight');Layout.setPlayerMode(straight,'free');
assert.equal(Layout.movePlayer(straight,[-3.5,-45]),false,'full footprint prevents kerb overlap');
const ordinary=scene('cross');const custom=ordinary.routes.find(r=>r.exit==='left');custom.manual=true;delete custom.auto;
Layout.apply(ordinary);const own=clone(ordinary.layout.paths);
Layout.setPlayerMode(ordinary,'free');Layout.movePlayer(ordinary,[-1.8,-25]);Layout.apply(ordinary);Layout.apply(ordinary);
assert.deepEqual(ordinary.layout.paths,own,'manual source paths never overwritten by free route copies');
Layout.setPlayerMode(ordinary,'street');Layout.apply(ordinary);assert.deepEqual(ordinary.layout.paths,own);
// Intentional edits of a free-mode arrow have a separate source from its street-mode route.
const freeManual=scene('cross');
const streetLeft=freeManual.routes.find(r=>r.exit==='left');streetLeft.manual=true;delete streetLeft.auto;
Layout.apply(freeManual);const streetSources=clone(freeManual.layout.paths);
const streetStraight=clone(freeManual.routes.find(r=>r.exit==='straight').points);
Layout.setPlayerMode(freeManual,'free');Layout.movePlayer(freeManual,[-1.8,-25]);Layout.apply(freeManual);
let edited=freeManual.routes.find(r=>r.exit==='straight');
Layout.setPlayerRouteManual(freeManual,edited,true);Layout.apply(freeManual);
edited=freeManual.routes.find(r=>r.exit==='straight');
assert.ok(edited.manual&&!edited.auto,'own-path remains manual in free mode');
const vertex=Math.floor(edited.points.length*.4),changedPoint=[edited.points[vertex][0]+.3,edited.points[vertex][1]];
Layout.editPlayerRoute(freeManual,edited);edited.points[vertex]=changedPoint;
Layout.apply(freeManual);
assert.ok(freeManual.layout.freePaths.straight.some(p=>p[0]===changedPoint[0]&&p[1]===changedPoint[1]),'changed arrow vertex is stored');
assert.ok(freeManual.routes.find(r=>r.exit==='straight').points.some(p=>p[0]===changedPoint[0]&&p[1]===changedPoint[1]),'changed arrow vertex remains rendered');
const freeSource=clone(freeManual.layout.freePaths.straight);
const reload=clone(freeManual);Layout.apply(reload);assert.deepEqual(reload.routes,freeManual.routes,'manual free routes stable after save/reload');
Layout.movePlayer(reload,[-1.8,-32]);Layout.apply(reload);Layout.apply(reload);
assert.deepEqual(reload.layout.freePaths.straight,freeSource,'moving pose never rewrites the free author source');
assert.deepEqual(reload.layout.paths,streetSources,'new free edits never rewrite ordinary author source');
assert.deepEqual(reload.routes.find(r=>r.exit==='straight').points[0],[-1.8,-32]);
Layout.setPlayerMode(reload,'street');Layout.apply(reload);
assert.deepEqual(reload.routes.find(r=>r.exit==='straight').points,streetStraight,'street automatic route is retained');
assert.deepEqual(reload.layout.paths,streetSources);
Layout.setPlayerMode(reload,'free');Layout.apply(reload);
Layout.setPlayerRouteManual(reload,reload.routes.find(r=>r.exit==='straight'),false);Layout.apply(reload);
assert.ok(reload.routes.find(r=>r.exit==='straight').auto,'explicit automatic reset is respected');
assert.equal(reload.layout.freePaths.straight,null);
assert.deepEqual(reload.layout.paths,streetSources,'reset free path preserves ordinary manual paths');

// A disconnected valid carriageway is placeable, but must fail validation honestly:
// never synthesize a straight line through the lawn to make the question appear reachable.
const isolated=scene('straight');isolated.roads.push({id:'detached-road',outer:[[20,20],[40,20],[40,40],[20,40]],holes:[]});
Layout.setPlayerMode(isolated,'free');assert.equal(Layout.movePlayer(isolated,[30,30]),true);Layout.apply(isolated);
assert.ok(isolated.playerRouteErrors?.length);assert.equal(isolated.routes.some(r=>r.kind==='approach'),false);
const bend=scene('bend-left');const plan=Layout.playerPlan(bend);Layout.setPlayerMode(bend,'free');
const lane=Layout.offsetRight(Layout.lineFrom(bend.layout,plan.st,plan.nid),plan.lo);
const pos=Layout.along(lane,35);bend.layout.player.pose={x:pos.p[0],z:pos.p[1],yaw:Math.atan2(-pos.t[0],-pos.t[1])};
assert.ok(Layout.freePlayerSupported(bend,bend.layout.player.pose));Layout.apply(bend);cases.push({template:'bend-left',scene:bend});
if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(cases));
console.log(`Free player: ${cases.length} placements, roadway/pose/roundabout/save-load/mode/manual-source checks PASS`);
