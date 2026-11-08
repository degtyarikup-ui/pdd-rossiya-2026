const assert = require('node:assert/strict');
const TexGen = require('../editor/texgen.js');
const fs = require('node:fs');
const index = JSON.parse(fs.readFileSync('game_godot/scenery/index.json', 'utf8'));
const config = index.textures.find(t => t.kind === 'dirt');
assert(config && config.period === 4.8 && index.textures.length <= 24);
const a = TexGen.build('dirt', 'earth'), b = TexGen.build('dirt', 'earth');
assert.equal(a, b, 'repeated preview uses cached texture');
assert.equal(a.w, 256); assert.equal(a.h, 256);
for (const channel of [a.r, a.g, a.b]) {
  const average = channel.reduce((sum, x) => sum+x, 0)/channel.length;
  assert(Math.abs(average-0.5)<0.004, 'neutral map preserves the soil base tone');
  assert(Math.max(...channel)-Math.min(...channel)>0.25, 'visible earth detail');
  let edge=0,interior=0;
  for(let y=0;y<256;y++) {edge+=Math.abs(channel[y*256]-channel[y*256+255]);interior+=Math.abs(channel[y*256+128]-channel[y*256+127]);}
  assert(edge<interior*3, 'periodic seam is no stronger than internal grain');
}
console.log('Compact, repeatable soil detail and seamless edges: PASS');
