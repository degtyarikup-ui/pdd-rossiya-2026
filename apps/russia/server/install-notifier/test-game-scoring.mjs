import { test } from 'node:test';
import assert from 'node:assert/strict';
import { awardGameScore, gameDayKey, gameDailySummary, GAME_TRACKED_RUNS } from './game_scoring.js';

const morning = Date.parse('2026-10-10T07:00:00Z');

test('cumulative reports are incremental and idempotent through mistakes and retries', () => {
  let entry;
  const report = score => {
    const result = awardGameScore(entry, { runId: 'city-one', runScore: score, newRun: true }, morning);
    entry = result.entry;
    return result;
  };
  assert.equal(report(80).credited, 80);
  assert.equal(report(80).credited, 0, 'lost response retry');
  assert.equal(report(40).credited, 0, 'stale report cannot lower the high-water mark');
  assert.equal(report(70).credited, 0);
  assert.equal(report(120).credited, 40);
  assert.equal(entry.score, 120);
  assert.equal(entry.runs, 1);
  assert.equal(entry.best, 120);
});

test('all new runs contribute without a daily budget; retries remain idempotent', () => {
  let entry = awardGameScore(null, { runId: 'signs-one', score: 600 }, morning).entry;
  const clipped = awardGameScore(entry, { runId: 'regulator-one', score: 1000 }, morning);
  assert.equal(clipped.credited, 1000);
  assert.equal(clipped.dailyEarned, 1600);
  assert.equal(clipped.limitReached, false);
  entry = clipped.entry;
  const retry = awardGameScore(entry, { runId: 'regulator-one', score: 1000 }, morning + 86400000);
  assert.equal(retry.credited, 0);
  assert.equal(retry.dailyEarned, 0);
  const increase = awardGameScore(retry.entry, { runId: 'regulator-one', runScore: 1400 }, morning + 86400000);
  assert.equal(increase.credited, 400, 'only newly earned cumulative points count');
  assert.equal(increase.entry.runs, 2);
});

test('a live run crossing into a fresh weekly board credits only its new delta', () => {
  const first = awardGameScore(null, { runId: 'sunday-run', runScore: 1100, delta: 100, newRun: false }, morning);
  assert.equal(first.credited, 100);
  assert.equal(first.entry.runs, 0, 'continuing a counted run does not count another run');
  const retry = awardGameScore(first.entry, { runId: 'sunday-run', runScore: 1100, delta: 100, newRun: false }, morning);
  assert.equal(retry.credited, 0);
  const next = awardGameScore(retry.entry, { runId: 'sunday-run', runScore: 1200, delta: 100, newRun: false }, morning);
  assert.equal(next.credited, 100);
  const capped = awardGameScore(null, { runId: 'old-capped-run', runScore: 2000, delta: 100, newRun: false }, morning);
  assert.equal(capped.credited, 0, 'old per-run excess does not reopen in a new week');
});

test('per-run bounds preserve existing points without a weekly ceiling', () => {
  let entry = { score: 50000, best: 5000, runs: 40 };
  for (let day = 0; day < 8; day++) {
    const result = awardGameScore(entry, { runId: 'city-' + day, runScore: 99999999 }, morning + day * 86400000);
    assert.equal(result.credited, 1500);
    entry = result.entry;
  }
  assert.equal(entry.score, 62000, 'old earned points are never reset');
  assert.equal(entry.best, 5000, 'old personal record is preserved');
  assert.equal(Object.keys(entry._ranking.days).length, 7);
  const replay = awardGameScore(entry, { runId: 'city-0', runScore: 99999999 }, morning + 8 * 86400000);
  assert.equal(replay.credited, 0);
});

test('legacy final and delta clients stay bounded without deducting already earned points', () => {
  let result = awardGameScore(null, { score: 100 }, morning);
  result = awardGameScore(result.entry, { delta: 40, runScore: 40, newRun: true }, morning);
  assert.equal(result.entry.score, 140);
  result = awardGameScore(result.entry, { delta: -40, runScore: 0 }, morning);
  assert.equal(result.credited, 0);
  assert.equal(result.entry.score, 140);
  result = awardGameScore(result.entry, { delta: 30, runScore: 30 }, morning);
  assert.equal(result.credited, 0, 'recovering lost local points does not farm weekly awards');
  result = awardGameScore(result.entry, { delta: 500000, runScore: 500000 }, morning);
  assert.equal(result.credited, 1460);
  assert.equal(result.entry.score, 1600);
  assert.equal(awardGameScore(null, { score: 99999999 }, morning).credited, 1500);
});

test('daily boundary follows Moscow midnight rather than UTC midnight', () => {
  assert.equal(gameDayKey(Date.parse('2026-10-10T20:59:59Z')), '2026-10-10');
  assert.equal(gameDayKey(Date.parse('2026-10-10T21:00:00Z')), '2026-10-11');
  const entry = awardGameScore(null, { runId: 'first', score: 1500 }, Date.parse('2026-10-10T20:59:59Z')).entry;
  assert.equal(gameDailySummary(entry, Date.parse('2026-10-10T20:59:59Z')).dailyEarned, 1500);
  assert.equal(gameDailySummary(entry, Date.parse('2026-10-10T21:00:00Z')).dailyEarned, 0);
});

test('tracking remains bounded and retired run IDs cannot reopen after trimming', () => {
  let entry = awardGameScore(null, { runId: 'retired-original', score: 2 }, morning).entry;
  for (let run = 0; run < GAME_TRACKED_RUNS + 40; run++) {
    entry = awardGameScore(entry, { runId: 'signs-' + run, score: 1 }, morning + run + 1).entry;
  }
  assert.equal(Object.keys(entry._ranking.runs).length, GAME_TRACKED_RUNS);
  assert.equal(entry._ranking.runs['retired-original'], undefined);
  assert.ok(entry._ranking.retired.length < 1400);
  const replay = awardGameScore(entry, { runId: 'retired-original', score: 1500 }, morning + 86400000);
  assert.equal(replay.credited, 0);
  assert.equal(replay.entry.runs, entry.runs);
});

test('invalid and extreme inputs cannot corrupt or deduct a score', () => {
  for (const value of [NaN, Infinity, -Infinity, -100, 'not-a-number']) {
    const result = awardGameScore({ score: 10 }, { runId: 'bad-number', runScore: value }, morning);
    assert.equal(result.credited, 0);
    assert.equal(result.entry.score, 10);
  }
  for (const runId of ['', 'x'.repeat(129), '__proto__', 'constructor', {}, null]) {
    assert.throws(() => awardGameScore(null, { runId, runScore: 10 }, morning), /invalid runId/);
  }
});


test('removing budgets preserves a capped production ledger and only credits new runs', () => {
  const previous = { score: 3000, runs: 12, best: 1500, _ranking: {
    days: { '2026-10-12': 1500, '2026-10-13': 1500 }, earned: 3000,
    runs: { 'already-consumed': { score: 1500, at: morning, counted: true } },
    legacyScore: 1500,
  } };
  const now = Date.parse('2026-10-13T12:00:00Z');
  const retry = awardGameScore(previous, { runId: 'already-consumed', score: 1500 }, now);
  assert.equal(retry.entry.score, 3000);
  assert.equal(retry.entry.runs, 12);
  let result = awardGameScore(retry.entry, { runId: 'new-run', score: 1500 }, now);
  assert.equal(result.entry.score, 4500);
  assert.equal(result.entry.runs, 13);
  assert.equal(result.dailyEarned, 3000);
  assert.equal(result.dailyLimit, null);
  assert.equal(result.limitReached, false);
  result = awardGameScore(result.entry, { delta: 200, runScore: 200, newRun: true }, now);
  assert.equal(result.entry.score, 4700, 'installed delta clients can start another run');
  result = awardGameScore(result.entry, { score: 500 }, now);
  assert.equal(result.entry.score, 5200, 'installed final-score clients contribute too');
  assert.equal(previous.score, 3000);
});
