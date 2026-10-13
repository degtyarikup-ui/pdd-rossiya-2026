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
const saved = {id:'pole-1',pos:[12,-8],yaw:0.6,code:'5.7.1',mount:'cantilever',reach:4.5,
  secondSign:{code:'2.4',plate:'100 м'},laneDirections:[['straight']]};
const before = structuredClone(saved);
assert.deepEqual(SignMount.faces(saved).map(f => f.code), ['5.7.1','2.4']);
SignMount.swapFaces(saved);
assert.equal(saved.code,'2.4'); assert.equal(saved.plate,'100 м');
assert.equal(saved.secondSign.code,'5.7.1'); assert.deepEqual(saved.secondSign.laneDirections,[['straight']]);
assert.deepEqual(saved.pos,before.pos); assert.equal(saved.yaw,before.yaw); assert.equal(saved.reach,before.reach);
SignMount.swapFaces(saved); assert.deepEqual(saved,before);
const stack = SignMount.layout({},4.36,1.2);
assert.ok(Math.abs(stack.postHeight-5.96)<1e-9); // The shared support reaches the upper face, not the stack midpoint.
assert.deepEqual(SignMount.faces(JSON.parse(JSON.stringify(saved))).map(SignMount.faceCopy),
  SignMount.faces(before).map(SignMount.faceCopy));
console.log('Single/shared roadside pole, overhead geometry and persisted settings: PASS');
