const assert = require('node:assert/strict');
const fs = require('node:fs');
const Presets = require('../editor/parking_presets.js');
const preset = {id:'fuel_station', decor:[{prop:'parking/fuel_pump',pos:[2,3],yaw:.25,scale:[1,1,1]}],
  roads:[{outer:[[0,0],[4,0],[4,5],[0,5]],holes:[[[1,1],[2,1],[2,2],[1,2]]],exact:true}],
  markings:[{type:'solid',points:[[1,2],[3,4]]},{type:'paint',polygons:[{outer:[[0,0],[1,0],[0,1]],holes:[]}]}]};
const before = JSON.stringify(preset), scene = {decor:[{id:'fuel_station_decor_1'}]};
const refs = Presets.place(scene,preset,[10,20],Math.PI/2);
assert.equal(refs.length,4);
assert.equal(scene.decor[1].id,'fuel_station_decor_2');
assert.deepEqual(scene.decor[1].pos,[13,18]);
assert.equal(scene.decor[1].yaw,1.821);
assert.deepEqual(scene.roads[0].outer,[[10,20],[10,16],[15,16],[15,20]]);
assert.deepEqual(scene.roads[0].holes[0],[[11,19],[11,18],[12,18],[12,19]]);
assert.deepEqual(scene.markings[0].points,[[12,19],[14,17]]);
assert.deepEqual(scene.markings[1].polygons[0].outer,[[10,20],[10,19],[11,20]]);
assert.equal(scene.roads[0].exact,true);
assert.equal(JSON.stringify(preset),before,'placement must not alter the reusable source');
Presets.place(scene,preset,[-20,0],0);
assert.notEqual(scene.decor[1].presetInstance,scene.decor[2].presetInstance);
assert.equal(scene.decor[1].presetInstance,scene.roads[0].presetInstance);
for (const key of ['decor','roads','markings']) assert.equal(new Set(scene[key].map(o=>o.id)).size,scene[key].length);
scene.decor[1].pos[0]=999;
assert.deepEqual(scene.decor[2].pos,[-18,3],'parts and repeated instances edit independently');
assert.deepEqual(Presets.place(scene,null,[0,0]),[]);
if (process.argv[2]) {
  const catalog = JSON.parse(fs.readFileSync(process.argv[2]));
  const fixture = JSON.parse(fs.readFileSync(process.argv[3]));
  const source = Presets.get(catalog,'fuel_station');
  assert.ok(source && source.decor.length >= 8);
  const inserted = Presets.place(fixture,source,[25,20],Math.PI/6);
  assert.ok(inserted.some(ref=>ref.t==='road'));
  fs.writeFileSync(process.argv[4],JSON.stringify(fixture));
}
console.log('PASS parking preset rotation, independent parts, repeated placement and stable source');
