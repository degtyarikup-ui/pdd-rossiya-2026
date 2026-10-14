const assert = require('node:assert/strict');
const L = require('../editor/layout.js');
const copy = s => JSON.parse(JSON.stringify(s));
function scene(template='ring') {
  const s={schema:1,id:'approach-test',crop:90,layout:L.template(template,90),question:{maneuver:'straight',correct:0,text:{ru:{options:['Да']}}},roads:[],routes:[],markings:[],lawns:[],actors:[],lights:[]};
  L.apply(s);return s;
}
const route = s => s.routes.find(r=>r.kind==='approach');
const s=scene();L.setPlayerMode(s,'free');s.layout.player.pose={x:-2,z:-12,yaw:-.6};L.apply(s);
assert.ok(L.polyLen(route(s).points)<90,'pose near entry must not force a full lap');
assert.ok(route(s).points.every(p=>Math.abs(p[0])<8),'near-entry approach does not go around opposite side of ring');
for(const angle of [-1.9,-2.4,-3,2.5,1.8,.8,0]) {
  const radius=14.5,x=radius*Math.cos(angle),z=radius*Math.sin(angle);
  s.layout.player.pose={x,z,yaw:Math.atan2(z,-x)};L.apply(s);
  assert.equal(s.playerRouteErrors,undefined);
  const pts=route(s).points;
  for(let i=1;i<pts.length;i++) {
    const [ax,az]=pts[i-1],[bx,bz]=pts[i];
    if(Math.hypot(ax,az)<18 && Math.hypot(bx,bz)<18)
      assert.ok(ax*bz-az*bx<.15,'ring segments follow right-hand circulation');
  }
}
// Manual sources are kept separately for each mode, with pinned entry/car endpoints.
for(const free of [false,true]) {
  const s=scene('cross');if(free){L.setPlayerMode(s,'free');L.movePlayer(s,[-1.8,-25]);L.apply(s);}
  const auto=copy(route(s)),entry=copy(auto.points[0]),stop=copy(auto.points.at(-1));
  L.setPlayerRouteManual(s,route(s),true);L.apply(s);
  assert.ok(route(s).manual&&!route(s).auto);
  const r=route(s);L.editPlayerRoute(s,r);
  r.points=[entry,[-1.6,-45],stop];L.apply(s);
  const key=free?'freeApproachPath':'approachPath';
  assert.deepEqual(s.layout[key],[entry,[-1.6,-45],stop]);
  const reload=copy(s);L.apply(reload);assert.deepEqual(route(reload),route(s),'manual edits survive reload');
  if(free){L.movePlayer(reload,[-1.8,-30]);L.apply(reload);assert.deepEqual(route(reload).points.at(-1),[-1.8,-30]);}
  else {reload.layout.player={...reload.layout.player,questionAt:28};L.apply(reload);}
  assert.deepEqual(reload.layout[key],s.layout[key],'moving car does not overwrite author source');
  assert.deepEqual(route(reload).points[1],[-1.6,-45]);
  L.setPlayerMode(reload,free?'street':'free');L.apply(reload);
  assert.ok(!route(reload).manual,'manual approach does not leak to other mode');
  L.setPlayerMode(reload,free?'free':'street');L.apply(reload);
  assert.ok(route(reload).manual,'switching back restores manual source');
  L.setPlayerRouteManual(reload,route(reload),false);L.apply(reload);
  assert.ok(route(reload).auto&&!route(reload).manual);
  assert.equal(reload.layout[key],undefined);
}
console.log('Approach: near-entry lap/direction/manual-edit/save-load/anchor/mode/reset PASS');
