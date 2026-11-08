import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  finalizeGameWeek, bestGameRank, deleteGameBest, closeFinishedGameWeeks,
  GAME_MIN_PLAYERS, GAME_BEST_TOP,
} from './game_weeks.js';

class KV {
  data = new Map(); writes = [];
  async get(k) { return this.data.get(k) ?? null; }
  async put(k, v) { this.writes.push(k); this.data.set(k, v); }
  async delete(k) { this.data.delete(k); }
}
const board = n => Array.from({ length: n }, (_, i) => ({ userId: 'u' + (i + 1), score: 1000 - i }));

test('неделя закрывается один раз и запоминает лучшие места', async () => {
  const env = { INSTALLS: new KV() };
  assert.equal(await finalizeGameWeek(env, '2026-W40', board(30)), true);
  assert.equal(await bestGameRank(env, 'u1'), 1);
  assert.equal(await bestGameRank(env, 'u30'), 30);
  assert.equal(await bestGameRank(env, 'nobody'), null);

  const writes = env.INSTALLS.writes.length;
  assert.equal(await finalizeGameWeek(env, '2026-W40', board(30)), false);
  assert.equal(env.INSTALLS.writes.length, writes, 'повторное закрытие ничего не пишет');
});

test('лучшее место за всё время не ухудшается', async () => {
  const env = { INSTALLS: new KV() };
  await finalizeGameWeek(env, 'W1', board(20));            // u5 → 5 место
  const worse = board(20); [worse[4], worse[9]] = [worse[9], worse[4]];
  await finalizeGameWeek(env, 'W2', worse);                // u5 → 10 место
  assert.equal(await bestGameRank(env, 'u5'), 5);
  const better = board(20); [better[4], better[0]] = [better[0], better[4]];
  await finalizeGameWeek(env, 'W3', better);               // u5 → 1 место
  assert.equal(await bestGameRank(env, 'u5'), 1);
});

test('в историю попадает только топ и только игроки с очками', async () => {
  const env = { INSTALLS: new KV() };
  const ranked = board(GAME_BEST_TOP + 20);
  ranked[0].score = 0; // нулевой счёт не считается участием
  await finalizeGameWeek(env, 'W1', ranked);
  assert.equal(await bestGameRank(env, 'u1'), null);
  assert.equal(await bestGameRank(env, 'u2'), 1);
  assert.equal(await bestGameRank(env, 'u' + (GAME_BEST_TOP + 1)), GAME_BEST_TOP);
  assert.equal(await bestGameRank(env, 'u' + (GAME_BEST_TOP + 2)), null);
});

test('неделя с малым числом игроков не засчитывается, но закрывается', async () => {
  const env = { INSTALLS: new KV() };
  assert.equal(await finalizeGameWeek(env, 'W1', board(GAME_MIN_PLAYERS - 1)), true);
  assert.equal(await bestGameRank(env, 'u1'), null);
  assert.equal(await finalizeGameWeek(env, 'W1', board(50)), false, 'закрытая неделя не открывается заново');
});

test('удаление аккаунта убирает место из истории', async () => {
  const env = { INSTALLS: new KV() };
  await finalizeGameWeek(env, 'W1', board(20));
  await deleteGameBest(env, 'u3');
  assert.equal(await bestGameRank(env, 'u3'), null);
  assert.equal(await bestGameRank(env, 'u4'), 4);
});

test('закрытые недели не читаются заново: только незакрытые', async () => {
  const env = { INSTALLS: new KV() };
  const reads = [];
  const weekKeyAt = d => 'W' + Math.floor(d.getTime() / (7 * 86400000));
  const readBoard = async (_e, week) => { reads.push(week); return {}; };
  const rank = () => board(15);
  await closeFinishedGameWeeks(env, weekKeyAt, readBoard, rank);
  assert.equal(reads.length, 4, 'первый запуск закрывает 4 недели');
  assert.equal(await bestGameRank(env, 'u1'), 1);
  await closeFinishedGameWeeks(env, weekKeyAt, readBoard, rank);
  assert.equal(reads.length, 4, 'повторный запуск таблиц не читает');
});
