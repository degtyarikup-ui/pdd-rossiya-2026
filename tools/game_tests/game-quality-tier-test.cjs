// Classification of the device GPU into quality tiers (assets/game/quality-tier.js).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
global.window = {};
global.document = {};
new Function(fs.readFileSync(path.join(__dirname, '../../assets/game/quality-tier.js'), 'utf8')).call(global);
const { classifyGpu } = window.PDD_QUALITY;
const cases = {
  'ANGLE (Qualcomm, Adreno (TM) 610, OpenGL ES 3.2)': 'low',      // Honor X7b (Snapdragon 680)
  'Adreno (TM) 619': 'low', 'Adreno (TM) 506': 'low', 'Adreno (TM) 612': 'low',
  'Adreno (TM) 642L': 'mid', 'Adreno (TM) 630': 'mid', 'Adreno (TM) 720': 'mid',
  'Adreno (TM) 660': 'high', 'Adreno (TM) 740': 'high', 'Adreno (TM) 750': 'high',
  'Mali-G52 MC2': 'low', 'Mali-G57 MC2': 'low', 'Mali-G31': 'low', 'Mali-T830': 'low',
  'Mali-G68': 'mid', 'Mali-G78 MP14': 'mid', 'Mali-G76 MC4': 'mid',
  'Mali-G715': 'high', 'Immortalis-G720': 'high', 'ANGLE (ARM, Mali-G715-Immortalis MC11, OpenGL ES 3.2)': 'high', // Pixel 9 Pro XL
  'Apple GPU': 'high', 'Samsung Xclipse 920': 'high', 'PowerVR Rogue GE8320': 'low',
  'ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (LLVM 10.0.0)))': null, '': null, 'Unknown GPU': null,
};
for (const [name, tier] of Object.entries(cases)) assert.equal(classifyGpu(name), tier, name);
console.log('PASS: GPU -> quality tier classification');
