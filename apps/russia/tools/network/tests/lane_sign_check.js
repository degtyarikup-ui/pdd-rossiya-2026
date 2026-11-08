const assert = require('node:assert/strict');
const fs = require('node:fs');
const LaneSign = require('../editor/lane_sign.js');

const expected = [['left', 'straight'], ['straight'], ['straight', 'right']];
assert.deepEqual(LaneSign.normalize(null), expected);
assert.deepEqual(LaneSign.normalize([]), expected);
assert.deepEqual(LaneSign.normalize([[], ['invalid'], ['right', 'left', 'right'], 'straight']),
  [['straight'], ['straight'], ['left', 'right'], ['straight']]);
const saved = {code:'5.15.1', laneDirections:expected, mount:'cantilever', reach:7, pos:[12,34], yaw:Math.PI};
const before = JSON.stringify(saved);
assert.deepEqual(LaneSign.normalize(JSON.parse(before).laneDirections), expected);
assert.equal(LaneSign.svg(saved.laneDirections), LaneSign.svg(JSON.parse(before).laneDirections));
assert.equal(JSON.stringify(saved), before, 'Rendering must not mutate authored data');
assert.deepEqual(LaneSign.dimensions(expected), {width:3, height:1.875});
const cases = [];
const top = lanes => Math.min(...LaneSign.geometry(lanes).heads.flat().map(p => p[1]));
for (const direction of ['left', 'right']) {
  assert.equal(top([[direction]]), top([['straight']]), 'Single turns reach the straight arrow height');
}
assert.equal(top([['left', 'right']]), 40, 'Two turn branches keep their existing height');
for (let count = 1; count <= 6; count++) {
  for (let mask = 1; mask < 8; mask++) {
    const dirs = LaneSign.DIRECTIONS.filter((_, i) => mask & (1 << i));
    const lanes = Array.from({length:count}, () => [...dirs]);
    const geometry = LaneSign.geometry(lanes), size = LaneSign.dimensions(lanes);
    assert.equal(geometry.paths.length, count * dirs.length);
    assert.equal(geometry.heads.length, count * dirs.length);
    assert.equal(geometry.separators.length, (count - 1) * 5);
    assert.equal(size.height, 1.875);
    assert.ok(size.width >= 1.2 && size.width <= 5.7);
    for (const polygon of geometry.heads) for (const [x,y] of polygon) {
      assert.ok(x > 3 && x < geometry.width - 3 && y > 3 && y < geometry.height - 3, 'Every pointed arrowhead stays inside its face');
    }
    const svg = LaneSign.svg(lanes);
    assert.ok(!/undefined|NaN/.test(svg));
    cases.push({lanes, svg, width:size.width, height:size.height});
  }
}
assert.equal(LaneSign.normalize(Array(20).fill(['straight'])).length, 6);
if (process.argv[2]) fs.writeFileSync(process.argv[2], JSON.stringify(cases));
console.log(`Lane sign constructor: ${cases.length} direction/count combinations, persistence and geometry PASS`);
