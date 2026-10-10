// Ranked points are earned, never lost. All games share the same Moscow-day
// budget; local game records can keep growing after this budget is exhausted.
export const GAME_DAILY_LIMIT = 1500;
export const GAME_RUN_LIMIT = 1500;
export const GAME_WEEK_LIMIT = GAME_DAILY_LIMIT * 7;
export const GAME_TRACKED_RUNS = 512;
const RETIRED_BITS = 8192;
const RESERVED_IDS = new Set(['__proto__', 'constructor', 'prototype']);

function whole(value, max = Number.MAX_SAFE_INTEGER) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, Math.min(max, Math.trunc(number))) : 0;
}

export function validGameRunId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9._:-]{1,128}$/.test(value) && !RESERVED_IDS.has(value);
}

export function gameDayKey(now = Date.now()) {
  return new Date(Number(now) + 3 * 3600000).toISOString().slice(0, 10);
}

function budget(entry) {
  const saved = entry._ranking;
  const source = saved && typeof saved === 'object' ? saved : {};
  const days = {};
  for (const [day, points] of Object.entries(source.days || {})) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(day)) days[day] = whole(points, GAME_DAILY_LIMIT);
  }
  const runs = {};
  for (const [id, record] of Object.entries(source.runs || {})) {
    if (validGameRunId(id) && record && typeof record === 'object') runs[id] = {
      score: whole(record.score, GAME_RUN_LIMIT), at: whole(record.at), counted: record.counted === true,
    };
  }
  return {
    days, runs, earned: whole(source.earned, GAME_WEEK_LIMIT),
    retired: typeof source.retired === 'string' ? source.retired : '',
    legacyScore: whole(source.legacyScore, GAME_RUN_LIMIT),
  };
}

function retiredBytes(encoded) {
  try {
    const decoded = atob(encoded);
    if (decoded.length === RETIRED_BITS / 8) return Uint8Array.from(decoded, c => c.charCodeAt(0));
  } catch (_) {}
  return new Uint8Array(RETIRED_BITS / 8);
}

function fingerprint(id) {
  // Four independent bit positions. Retired IDs remain rejected after their
  // detailed record is trimmed, so replaying an old run cannot reopen it.
  return [0x811c9dc5, 0x1234567, 0x9e3779b9, 0x85ebca6b].map(seed => {
    let hash = seed;
    for (let i = 0; i < id.length; i++) hash = Math.imul(hash ^ id.charCodeAt(i), 0x01000193);
    return (hash >>> 0) % RETIRED_BITS;
  });
}

function isRetired(bytes, id) {
  return fingerprint(id).every(bit => (bytes[bit >>> 3] & (1 << (bit & 7))) !== 0);
}

function trimRuns(state, bytes) {
  const ids = Object.keys(state.runs).sort((a, b) => state.runs[a].at - state.runs[b].at);
  for (const id of ids.slice(0, Math.max(0, ids.length - GAME_TRACKED_RUNS))) {
    for (const bit of fingerprint(id)) bytes[bit >>> 3] |= 1 << (bit & 7);
    delete state.runs[id];
  }
  state.retired = btoa(String.fromCharCode(...bytes));
}

export function gameDailySummary(entry, now = Date.now()) {
  const state = entry?._ranking;
  const dailyEarned = whole(state?.days?.[gameDayKey(now)], GAME_DAILY_LIMIT);
  return {
    dailyEarned, dailyLimit: GAME_DAILY_LIMIT,
    limitReached: dailyEarned >= GAME_DAILY_LIMIT || whole(state?.earned, GAME_WEEK_LIMIT) >= GAME_WEEK_LIMIT,
  };
}

// Shared by strongly consistent TrafficState and the compatibility KV path.
// Cumulative reports consume their full increase even when the daily budget
// clips the award: retrying tomorrow must not bank yesterday's excess points.
export function awardGameScore(previous, input = {}, now = Date.now()) {
  const entry = previous && typeof previous === 'object' ? { ...previous } : {};
  entry.score = whole(entry.score);
  entry.runs = whole(entry.runs);
  entry.best = whole(entry.best);
  entry.name = String(input.name || entry.name || 'Игрок').slice(0, 40);
  const state = budget(entry), day = gameDayKey(now);
  let requested = 0, runScore = 0, newRun = false;
  if (input.runId !== undefined) {
    if (!validGameRunId(input.runId)) throw new TypeError('invalid runId');
    const bytes = retiredBytes(state.retired);
    const old = state.runs[input.runId];
    const cumulative = whole(input.runScore ?? input.score);
    runScore = Math.min(cumulative, GAME_RUN_LIMIT);
    if (old || !isRetired(bytes, input.runId)) {
      // A live run may cross the weekly boundary into a fresh object. Its
      // delta tells us how much of the cumulative total was already reported
      // in the previous week; clipped old excess also remains clipped.
      const baseline = input.delta !== undefined
        ? whole(cumulative - whole(input.delta), GAME_RUN_LIMIT) : 0;
      const record = old || {
        score: baseline, at: Number(now), counted: input.newRun === false && baseline > 0,
      };
      requested = Math.max(0, runScore - record.score);
      newRun = !record.counted && runScore > 0;
      record.counted ||= newRun;
      record.score = Math.max(record.score, runScore);
      if (requested > 0) record.at = Number(now);
      state.runs[input.runId] = record;
    }
    trimRuns(state, bytes);
  } else if (input.delta !== undefined) {
    // Installed clients have no run identity. Keep their cumulative high-water
    // mark until newRun, and ignore penalties rather than charging them twice.
    if (input.newRun === true) { state.legacyScore = 0; newRun = true; }
    const positiveDelta = whole(input.delta, GAME_RUN_LIMIT);
    if (input.runScore !== undefined) {
      runScore = whole(input.runScore, GAME_RUN_LIMIT);
      requested = positiveDelta > 0 ? Math.max(0, runScore - state.legacyScore) : 0;
      state.legacyScore = Math.max(state.legacyScore, runScore);
    } else {
      requested = Math.min(positiveDelta, GAME_RUN_LIMIT - state.legacyScore);
      state.legacyScore += requested;
      runScore = state.legacyScore;
    }
  } else {
    runScore = whole(input.score, GAME_RUN_LIMIT);
    requested = runScore;
    newRun = runScore > 0;
  }
  const credited = Math.min(requested, GAME_DAILY_LIMIT - (state.days[day] || 0), GAME_WEEK_LIMIT - state.earned);
  state.days[day] = (state.days[day] || 0) + credited;
  // At most seven relevant daily counters in a weekly object.
  for (const oldDay of Object.keys(state.days).sort().slice(0, Math.max(0, Object.keys(state.days).length - 7))) delete state.days[oldDay];
  state.earned += credited;
  entry.score += credited;
  if (newRun) entry.runs += 1;
  entry.best = Math.max(entry.best, runScore);
  if (credited > 0 || !entry.updatedAt) entry.updatedAt = new Date(Number(now)).toISOString();
  entry._ranking = state;
  return { entry, credited, ...gameDailySummary(entry, now) };
}
