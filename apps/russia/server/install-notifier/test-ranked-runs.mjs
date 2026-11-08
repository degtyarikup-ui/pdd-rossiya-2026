import test from 'node:test';
import assert from 'node:assert/strict';
import { RankedRuns } from './ranked_runs.js';
import { MemoryStorage } from './fixture-account.mjs';
const call = (object, path, body) => object.fetch(new Request('https://ranking/' + path, { method: 'POST', body: JSON.stringify(body) }));
test('invented runs earn nothing; registered runs obey one server clock across IDs and retries', async t => {
  let now = Date.now(); t.mock.method(Date, 'now', () => now);
  const object = new RankedRuns({ storage: new MemoryStorage() });
  for (let i = 0; i < 20; i++) {
    const r = await call(object, 'verify', { runId: 'invented-' + i, score: 1500, week: '2026-W45' });
    assert.equal((await r.json()).ranked, false);
  }
  await call(object, 'start', { runId: 'registered-one' });
  await call(object, 'start', { runId: 'registered-two' });
  assert.equal((await call(object, 'verify', { runId: 'registered-one', score: 1500, week: '2026-W45' })).status, 429);
  now += 60000;
  const first = await call(object, 'verify', { runId: 'registered-one', score: 1500, delta: 9999999, week: '2026-W45' });
  assert.equal((await first.json()).score.delta, 1500);
  assert.equal((await call(object, 'verify', { runId: 'registered-two', score: 1500, week: '2026-W45' })).status, 429);
  const retry = await call(object, 'verify', { runId: 'registered-one', score: 1500, week: '2026-W45' });
  assert.equal((await retry.json()).score.delta, 1500);
  const nextWeek = await call(object, 'verify', { runId: 'registered-one', score: 1500, delta: 1500, week: '2026-W46' });
  assert.equal((await nextWeek.json()).score.delta, 0, 'client cannot reopen prior-week points');
});
test('Godot rounds share their session allowance and expired sessions cannot be restored by client timestamps', async t => {
  let now = Date.now(); t.mock.method(Date, 'now', () => now);
  const storage = new MemoryStorage(), object = new RankedRuns({ storage });
  await call(object, 'start', { runId: 'godot-session' });
  now += 30000;
  const first = await call(object, 'verify', { runId: 'godot-session-1', runScore: 500, week: '2026-W45' });
  assert.equal((await first.json()).score.delta, 500);
  const second = await call(object, 'verify', { runId: 'godot-session-2', runScore: 500, week: '2026-W45' });
  assert.equal((await second.json()).score.delta, 500);
  now += 25 * 3600000;
  assert.equal((await (await call(object, 'verify', { runId: 'godot-session-1', runScore: 600, startedAt: now - 100000, week: '2026-W45' })).json()).ranked, false);
});
