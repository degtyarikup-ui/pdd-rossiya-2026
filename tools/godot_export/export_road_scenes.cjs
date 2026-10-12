// Road question scenes (straight-road questions: speed zones, overtaking, railway crossings,
// observation, bus stops, detours, emergency lane) -> game_godot/roads/road_scenes.json.
//   node tools/godot_export/export_road_scenes.cjs
// The data is the same the web game reads (assets/game/road-situations.js, verbatim question
// text). The game does not play these scenes yet: scripts/road_scenes.gd is the next step.
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '../..');
const src = fs.readFileSync(path.join(ROOT, 'assets/game/road-situations.js'), 'utf8');
const win = {};
new Function('window', src)(win);
const list = win.PDD_ROAD_SITUATIONS || [];
const scenes = list.map(s => ({
  id: s.id, ticket: s.ticket, sourceQuestionId: s.sourceQuestionId, category: s.category, kind: s.type,
  title: s.title, options: s.options, correctAnswerIndex: s.correctAnswerIndex, explanation: s.explanation,
  pddRule: s.pddRule, legend: s.legend, sourceImage: s.sourceImage, note: s.note || null, scene: s.scene,
}));
const broken = scenes.filter(s => s.correctAnswerIndex == null || s.correctAnswerIndex < 0 || s.correctAnswerIndex >= s.options.length);
if (broken.length) {
  console.error('wrong correct answer index in:', broken.map(s => s.id).join(' '));
  process.exit(1);
}
const out = path.join(ROOT, 'game_godot/roads/road_scenes.json');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify({ schema: 1, count: scenes.length, scenes }, null, 1) + '\n');
const kinds = {};
for (const s of scenes) { const k = s.scene?.kind ?? s.kind; kinds[k] = (kinds[k] || 0) + 1; }
console.log(`exported ${scenes.length} road scenes`, JSON.stringify(kinds));
