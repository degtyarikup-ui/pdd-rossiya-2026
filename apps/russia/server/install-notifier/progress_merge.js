// Driving game: counters only grow, the garage is a union of cars, the
// chosen car is whatever the device reports last.
function mergeGame(existing, incoming) {
  const ex = existing || {}, inc = incoming || {};
  const seen = new Set(), cars = [];
  for (const car of [...(Array.isArray(ex.garageCars) ? ex.garageCars : []), ...(Array.isArray(inc.garageCars) ? inc.garageCars : [])]) {
    if (!car || typeof car.id !== 'string' || typeof car.paint !== 'string') continue;
    const key = car.id + ':' + car.paint;
    if (!seen.has(key)) { seen.add(key); cars.push({ id: car.id, paint: car.paint }); }
  }
  const num = v => (typeof v === 'number' && isFinite(v) ? v : 0);
  return {
    bestScore: Math.max(num(ex.bestScore), num(inc.bestScore)),
    garageCars: cars,
    garageCorrect: Math.max(num(ex.garageCorrect), num(inc.garageCorrect)),
    garageUnlocks: Math.max(num(ex.garageUnlocks), num(inc.garageUnlocks)),
    vehicle: inc.vehicle || ex.vehicle || null,
    vehiclePaint: inc.vehiclePaint || ex.vehiclePaint || null,
  };
}


const object = value => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const strings = value => Array.isArray(value) ? value.filter(x => typeof x === 'string') : [];
const time = value => typeof value === 'number' && Number.isFinite(value)
  ? Math.max(0, Math.min(Number.MAX_SAFE_INTEGER, Math.trunc(value)))
  : typeof value === 'string' ? Math.max(0, Date.parse(value) || 0) : 0;

// Same merge contract as progress_snapshot.dart: the last answer wins;
// explicit removals and resets survive delayed replies and older devices.
export function mergeProgress(existing, incoming) {
  const ex = object(existing), inc = object(incoming);
  const reset = Math.max(time(ex.resetAt), time(inc.resetAt));
  const records = (field, favorite = false) => {
    const result = {};
    for (const source of [ex, inc]) for (const [id, raw] of Object.entries(object(source[field]))) {
      const value = object(raw);
      if (raw !== value || ['__proto__','constructor','prototype'].includes(id)) continue;
      const stamp = time(value[favorite ? 'updatedAt' : 'answeredAt']);
      if (reset && stamp <= reset) continue;
      const old = result[id];
      const oldStamp = time(old?.[favorite ? 'updatedAt' : 'answeredAt']);
      if (!old || stamp > oldStamp || (stamp === oldStamp &&
          (favorite ? value.present === false : time(value.attemptsCount) >= time(old.attemptsCount)))) {
        result[id] = value;
      }
    }
    return result;
  };
  const out = {resetAt: reset};
  for (const suffix of ['Ab','Cd']) {
    for (const prefix of ['questionProgress','ticketProgress']) out[prefix+suffix] = records(prefix+suffix);
    const states = records('favoriteStates'+suffix, true);
    const favorites = new Set(reset ? [] : [...strings(ex['favorites'+suffix]), ...strings(inc['favorites'+suffix])]);
    for (const [id, state] of Object.entries(states)) {
      if (state.present === true) favorites.add(id);
      else if (state.present === false) favorites.delete(id);
    }
    out['favorites'+suffix] = [...favorites];
    out['favoriteStates'+suffix] = states;
    const exams = new Set();
    for (const raw of [...(Array.isArray(ex['examResults'+suffix]) ? ex['examResults'+suffix] : []), ...(Array.isArray(inc['examResults'+suffix]) ? inc['examResults'+suffix] : [])]) {
      const entry = typeof raw === 'string' ? raw : JSON.stringify(raw);
      try {
        const exam = JSON.parse(entry);
        if (exam && typeof exam === 'object' && (!reset || time(exam.completedAt ?? exam.date) > reset)) exams.add(entry);
      } catch { /* Invalid history entry. */ }
    }
    out['examResults'+suffix] = [...exams];
  }
  const a = time(ex.resetAt) < reset ? {} : object(ex.streak);
  const b = time(inc.resetAt) < reset ? {} : object(inc.streak);
  const days = [...new Set([...strings(a.activeDays), ...strings(b.activeDays)])].sort();
  const latest = time(a.lastActiveDate) > time(b.lastActiveDate) ? a : b;
  out.streak = {
    current: Math.max(time(a.current), time(b.current)), longest: Math.max(time(a.longest), time(b.longest)),
    lastActiveDate: latest.lastActiveDate ?? null, startDate: latest.startDate ?? null, activeDays: days.slice(-60),
  };
  out.settings = {...object(ex.settings), ...object(inc.settings)};
  out.game = mergeGame(ex.game, inc.game);
  out.miniGames = mergeMiniGames(ex.miniGames, inc.miniGames);
  out.achievementStats = mergeAchievementStats(
    time(ex.resetAt) < reset ? {} : ex.achievementStats,
    time(inc.resetAt) < reset ? {} : inc.achievementStats);
  out.updatedAt = new Date().toISOString();
  return out;
}

// Numeric mini-game fields, all merged by maximum. Same list as
// miniGameCounters in lib/data/models/progress_snapshot.dart.
const swipeGame = ['bestScore','maxCombo','totalSolved','totalSwiped','trainingCount'];
export const MINI_GAME_COUNTERS = {
  regulator: swipeGame, signs: swipeGame, crossroads: swipeGame,
  // level1…level25: stars of the «Парковка» levels (0–3), the best result of each.
  parking: ['bestScore','maxCombo','totalSolved','trainingCount',
    ...Array.from({ length: 25 }, (_, i) => `level${i + 1}`)],
  violator: ['bestScore','maxCombo','totalViolatorsCaught','totalSolved','gamesPlayed'],
  roadSigns: ['bestScore','maxCombo','totalAnswered','totalCorrect'],
};
const MAX_SIGNS_VIEWED = 1000;

export function mergeMiniGames(a, b) {
  const out = {};
  for (const [game, keys] of Object.entries(MINI_GAME_COUNTERS)) {
    out[game] = {};
    for (const key of keys) {
      out[game][key] = Math.max(time(object(object(a)[game])[key]), time(object(object(b)[game])[key]));
    }
  }
  return out;
}

// Achievement counters: numbers only grow, viewed signs are a union and the
// last early/night day is the later date. A reset clears them like the streak.
export function mergeAchievementStats(a, b) {
  const x = object(a), y = object(b);
  const later = key => {
    const p = typeof x[key] === 'string' ? x[key] : null;
    const q = typeof y[key] === 'string' ? y[key] : null;
    return p === null ? q : q === null ? p : (p >= q ? p : q);
  };
  const out = {};
  for (const key of ['marathonBest','earlyDays','nightDays','comebacks']) out[key] = Math.max(time(x[key]), time(y[key]));
  out.earlyLast = later('earlyLast');
  out.nightLast = later('nightLast');
  out.signsViewed = [...new Set([...strings(x.signsViewed), ...strings(y.signsViewed)])].sort().slice(0, MAX_SIGNS_VIEWED);
  return out;
}
