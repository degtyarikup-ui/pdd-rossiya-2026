import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {mergeProgress} from './progress_merge.js';
const cases = JSON.parse(readFileSync(new URL('../../test/fixtures/progress_merge.json', import.meta.url)));
for (const row of cases) test(row.name, () => {
  const merged = mergeProgress(row.local,row.remote);
  for (const [key,value] of Object.entries(row.expected)) assert.deepEqual(merged[key],value,key);
});
test('reset never removes earned cars and rejects prototype record IDs', () => {
  const merged = mergeProgress({game:{bestScore:500,garageCars:[{id:'sedan',paint:'red'}]},
    questionProgressAb:JSON.parse('{"__proto__":{"answeredAt":100}}')},{resetAt:20});
  assert.equal(merged.game.bestScore,500);
  assert.equal(merged.game.garageCars.length,1);
  assert.equal(Object.getPrototypeOf(merged.questionProgressAb),Object.prototype);
  assert.equal(Object.hasOwn(merged.questionProgressAb,'__proto__'),false);
});
