// The road sign pictures of the web game (assets/game/sign-textures.js, embedded SVG data URLs)
// -> game_godot/signs/<code>.svg, for the Godot game's road signs.
//   node tools/godot_export/export_sign_pictures.cjs
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '../..');
const src = fs.readFileSync(path.join(ROOT, 'assets/game/sign-textures.js'), 'utf8');
const win = {};
new Function('window', src)(win);
const pictures = win.PDD_SIGN_TEXTURES || {};
const out = path.join(ROOT, 'game_godot/signs');
fs.mkdirSync(out, { recursive: true });
let written = 0;
for (const [code, url] of Object.entries(pictures)) {
  const m = /^data:image\/svg\+xml;base64,(.+)$/.exec(url);
  if (!m) continue;   // a picture given as a file is not embedded here
  fs.writeFileSync(path.join(out, `${code}.svg`), Buffer.from(m[1], 'base64'));
  written++;
}
console.log(`wrote ${written} sign pictures of ${Object.keys(pictures).length} codes to game_godot/signs/`);
