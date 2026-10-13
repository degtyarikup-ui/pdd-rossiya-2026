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
  out.updatedAt = new Date().toISOString();
  return out;
}

export function mergeMiniGames(a, b) {
  const out = {};
  for (const game of ['regulator','signs','crossroads']) {
    out[game] = {};
    for (const key of ['bestScore','maxCombo','totalSolved','totalSwiped','trainingCount']) {
      out[game][key] = Math.max(time(object(object(a)[game])[key]), time(object(object(b)[game])[key]));
    }
  }
  return out;
}
