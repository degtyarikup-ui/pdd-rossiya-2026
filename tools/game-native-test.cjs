// Native bridge smoke test against tools/game_preview.dart's local VM service.
// Usage: node tools/game-native-test.cjs <vmservice-out-file> <simulator-udid> <screenshots-dir>
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const [vmFile, device, shots] = process.argv.slice(2);
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
  const base = fs.readFileSync(vmFile, 'utf8').trim().replace(/^ws:/, 'http:').replace(/ws$/, '');
  const vm = (await (await fetch(base + 'getVM')).json()).result;
  const isolate = vm.isolates.find(i => i.name === 'main').id;
  async function command(action = 'snapshot', extra = {}) {
    const q = new URLSearchParams({ isolateId: isolate, action, ...extra });
    const data = await (await fetch(base + 'ext.pdd.gamePreview?' + q)).json();
    if (data.error) throw new Error(JSON.stringify(data.error));
    return data.result;
  }
  async function until(phase, timeout = 30000) {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      const state = await command();
      if (state.phase === phase) return state;
      await delay(150);
    }
    throw new Error('Native game did not reach ' + phase);
  }
  function screenshot(name) {
    if (!shots) return;
    fs.mkdirSync(shots, { recursive: true });
    execFileSync('xcrun', ['simctl', 'io', device, 'screenshot', path.join(shots, name + '.png')], { stdio: 'pipe' });
  }
  await until('driving');
  screenshot('native-driving');
  await command('gas');
  const question = await until('situation');
  screenshot('native-question');
  const wrong = (question.situation.correctAnswerIndex + 1) % question.situation.options.length;
  await command('answer', { index: String(wrong) });
  await until('explanation'); screenshot('native-explanation');
  await command('continue');
  await until('resolving');
  await delay(20000); screenshot('native-resolving');
  const waiting = await command();
  assert.equal(waiting.phase, 'resolving', 'Manual driving must wait for the player');
  assert.equal(waiting.distance, question.distance);
  await command('gas');
  const finished = await until('driving');
  await command('release');
  screenshot('native-after-turn');
  assert(finished.distance > question.distance);
  assert(finished.violations >= 0); // Going straight can differ from this random question's maneuver.
  assert.equal(finished.situation, null);
  console.log(JSON.stringify({ passed: true, wrongAnswerRecovered: true, violations: finished.violations,
    distanceAfterTurn: finished.distance }, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
