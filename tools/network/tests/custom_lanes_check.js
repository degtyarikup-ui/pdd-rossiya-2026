// Custom cross-sections are additive: authored presets keep their original geometry.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const L = require('../editor/layout.js');
const clone = x => JSON.parse(JSON.stringify(x));
const near = (a,b,why,tolerance=.002) => assert.ok(Math.abs(a-b)<=tolerance,`${why}: ${a} vs ${b}`);
const fixtures=[];
function scene(template='straight',crop=90) {
  return {schema:1,id:'custom-lanes-test',crop,layout:L.template(template,crop),question:{maneuver:'straight',correct:0,text:{ru:{options:['Да']}}},
    roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],compliance:{status:'ok'}};
}
function config(st,a={left:2,right:3},b=a,width=3.5,taper=40) {L.setLaneConfig(st,{a,b,width,taper});}
function inside(p,polygon) {
  let yes=false;
  for(let i=0,j=polygon.length-1;i<polygon.length;j=i++) {
    const a=polygon[i],b=polygon[j];
    if ((a[1]>p[1])!==(b[1]>p[1]) && p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]) yes=!yes;
  }
  return yes;
}
function onRoad(s,p) {return s.roads.some(r=>inside(p,r.outer)&&!(r.holes||[]).some(h=>inside(p,h)));}
function routeSupported(s,route) {
  for(let i=0;i<route.points.length;i++) {
    const p=route.points[i];
    if(Math.max(Math.abs(p[0]),Math.abs(p[1]))>s.crop-.1) continue;
    assert.ok(onRoad(s,p),`${s.testCase}/${route.id}: route leaves asphalt at ${p}`);
  }
}
function retain(s,name) {
  L.apply(s);s.testCase=name;
  for(const r of s.routes) routeSupported(s,r);
  const saved=JSON.stringify(s), again=clone(s);L.apply(again);
  assert.equal(JSON.stringify(again),saved,`${name}: save/reload regenerates identical output`);
  fixtures.push(s);return s;
}
const original={kind:'street',ends:{a:{stop:true}}},before=clone(original);
assert.deepEqual(L.laneConfig(original),{a:{left:1,right:1},b:{left:1,right:1},width:4.2,taper:40});
assert.deepEqual(original,before,'reading defaults does not migrate a scene');
for(const kind of ['yard','street','avenue','highway']) {
  const s=scene(),st=s.layout.streets[0];st.kind=kind;
  config(st);retain(s,`asymmetric-${kind}`);
  const profile=L.streetProfile(s.layout,st,90,90);
  near(profile.leftWidth,7+L.medianOf(st)/2,`${kind}: two left lanes`);
  near(profile.rightWidth,10.5+L.medianOf(st)/2,`${kind}: three right lanes`);
  assert.equal(L.laneOffsets(st,st.a).length,2);assert.equal(L.laneOffsets(st,st.b).length,3);
  for(const toward of [st.a,st.b]) {
    for(let index=0;index<L.laneOffsets(st,toward).length;index++) {
      s.layout.player={street:st.id,toward,lane:index};L.apply(s);
      const plan=L.playerPlan(s),hit=L.nearestLane(s,plan.stop,Math.atan2(plan.tin[0],plan.tin[1]));
      assert.equal(hit.toward,toward);near(hit.d,0,'player occupies an actual directional lane');
      for(const r of s.routes)routeSupported(s,r);
    }
  }
}
for(const crop of [45,90])for(const bend of [false,true])for(const reverse of [false,true]) {
  const s=scene('straight',crop),st=s.layout.streets[0];
  config(st,{left:2,right:reverse?1:3},{left:2,right:reverse?3:1},3.5,40);
  if(bend)st.bend=[16,0];
  s.layout.player={street:st.id,toward:st.b,lane:2};
  retain(s,`merge-${crop}-${bend}-${reverse}`);
  const total=L.polyLen(L.centreline(s.layout,st));
  for(const d of [0,24,34]) {
    near(L.streetProfile(s.layout,st,d,crop).rightLanes,reverse?1:3,'A stable runtime collar');
    near(L.streetProfile(s.layout,st,total-d,crop).rightLanes,reverse?3:1,'B stable runtime collar');
  }
  const lane=L.laneAway(s.layout,st,st.a,L.laneOffsets(st,st.b)[2],crop);
  for(const p of lane)if(Math.max(Math.abs(p[0]),Math.abs(p[1]))<crop-.1)assert.ok(onRoad(s,p),'outer lane remains on asphalt through merge');
  for(let i=1;i<lane.length;i++)assert.ok(Math.hypot(lane[i][0]-lane[i-1][0],lane[i][1]-lane[i-1][1])<2,'merge has no discontinuity');
  near(Math.hypot(lane.at(-1)[0]-L.nodeOf(s.layout,st.b).x,lane.at(-1)[1]-L.nodeOf(s.layout,st.b).z),reverse?8.75:1.75,'outer lane reaches adjacent remaining lane',.3);
}
for(const maneuver of ['straight','left','right','uturn']) {
  const s=scene('cross');s.question.maneuver=maneuver;
  for(const st of s.layout.streets)config(st,{left:2,right:3},{left:1,right:2});
  retain(s,`junction-${maneuver}`);
}
// Selection and picking share the rendered asymmetric/tapered bounds.
{
  const s=scene(),st=s.layout.streets[0];config(st,{left:2,right:3},{left:1,right:1});L.apply(s);
  const outline=L.streetOutline(s.layout,st,s.crop);
  assert.ok(inside([-10, -70],outline),'selection includes the outer third lane');
  assert.ok(!inside([10,-70],outline),'selection does not invent a third opposite lane');
  assert.ok(Number.isFinite(L.streetHitDistance(s.layout,st,[-10,-70],90)));
  assert.equal(L.streetHitDistance(s.layout,st,[10,-70],90),Infinity);
  assert.equal(L.streetHitDistance(s.layout,st,[-10,70],90),Infinity,'narrow end cannot capture empty ground');
  assert.ok(Number.isFinite(L.streetHitDistance(s.layout,st,[-3,70],90)));
}
// The end cap follows the real asymmetric section, not a large centred disc.
{
  const s=scene(),st=s.layout.streets[0];L.nodeOf(s.layout,st.b).z=30;config(st,{left:1,right:3});L.apply(s);
  const cap=s.roads.find(r=>r.id===`road_${st.b}`);
  near(Math.max(...cap.outer.map(p=>p[0])),3.5,'dead-end narrow side');
  near(Math.min(...cap.outer.map(p=>p[0])),-10.5,'dead-end wide side');
}
// Splitting a taper keeps the original longitudinal profile, including after persistence.
{
  const s=scene(),st=s.layout.streets[0];config(st,{left:2,right:3},{left:1,right:1});
  L.apply(s);const originalStop=clone(s.stop), originalRoutes=clone(s.routes), originalRoads=clone(s.roads);
  const total=L.polyLen(L.centreline(s.layout,st)),expected=Array.from({length:181},(_,d)=>L.streetProfile(s.layout,st,d,s.crop));
  const split=130,nid=L.splitStreet(s.layout,st.id,split,s.crop),other=s.layout.streets.find(x=>x.a===nid);
  for(let d=0;d<=total;d++) {
    const actual=L.streetProfile(s.layout,d<=split?st:other,d<=split?d:d-split,s.crop);
    near(actual.leftWidth,expected[d].leftWidth,'split preserves left edge');
    near(actual.rightWidth,expected[d].rightWidth,'split preserves right edge');
  }
  s.testSplitBefore={roads:originalRoads,routes:originalRoutes};
  retain(s,'split-taper');
  assert.deepEqual(s.stop,originalStop,'splitting keeps the question at the same world position');
  for(const route of s.routes) {
    const previous=originalRoutes.find(r=>r.id===route.id);
    assert.deepEqual(route.points[0],previous.points[0],'split retains the route entrance');
    assert.deepEqual(route.points.at(-1),previous.points.at(-1),'split retains the route destination');
  }
  assert.ok(st.lanes.profile);L.setLaneConfig(st,L.laneConfig(st));assert.ok(!st.lanes.profile,'explicit edit replaces inherited span');
}
// Full-chassis fixtures: all six lanes, short pavement tapers, narrow lane widths,
// both traffic directions and both the compact and standard carriageway sides.
for(const both of [false,true])for(const width of [2.5,3.5,4.5])for(const taper of [5,40])for(const reverse of [false,true]) {
  for(const direction of both ? ['a','b'] : ['b'])for(let lane=0;lane<6;lane++) {
    const s=scene('straight',45),st=s.layout.streets[0];
    const wide={left:both?6:1,right:6}, narrow={left:1,right:1};
    config(st,reverse?narrow:wide,reverse?wide:narrow,width,taper);
    s.layout.player={street:st.id,toward:st[direction],lane};
    L.apply(s);s.testCase=`extreme-${both}-${width}-${taper}-${reverse}-${direction}-${lane}`;
    s.testFullBody=true;fixtures.push(s);
    for(const route of s.routes)routeSupported(s,route);
  }
}
if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(fixtures));
console.log(`Custom lanes: ${fixtures.length} asymmetric, merging, curved, compact, junction and split fixtures PASS`);
