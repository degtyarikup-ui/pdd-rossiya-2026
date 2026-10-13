// The roadside anchor stays fixed when the overhead board's reach or side changes.
const assert = require('node:assert/strict');
const SignMount = require('../editor/sign_mount.js');
for (const height of [1.8, 3, 6]) {
  const plain = SignMount.layout({}, height);
  assert.equal(plain.x, 0); assert.equal(plain.bottom, 2.2);
  for (const reach of [0.5, 4.5, 15]) for (const armSide of ['left', 'right']) {
    const saved = JSON.parse(JSON.stringify({mount:'cantilever',reach,armSide,clearance:5.5,pos:[-8,10],yaw:Math.PI}));
    const model = SignMount.layout(saved, height);
    assert.equal(model.x, reach * (armSide === 'left' ? 1 : -1));
    assert.equal(model.bottom, 5.5);
    assert.ok(model.postHeight >= model.bottom + height);
    assert.ok(model.armLength > Math.abs(model.x));
    assert.deepEqual(saved.pos, [-8,10]);
  }
}
assert.equal(SignMount.layout({mount:'cantilever',reach:-10,clearance:2}).reach, 0.5);
assert.equal(SignMount.layout({mount:'cantilever',reach:100,clearance:20}).bottom, 8);
console.log('Overhead sign geometry and persisted settings: PASS');
