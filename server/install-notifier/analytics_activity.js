// 90 календарных дней МСК: один бит на аккаунт/платформу/день.
export const ACTIVITY_FROM = '2026-10-07';
const DAY = 86400000;
const MASK = (1n << 90n) - 1n;
const PLATFORMS = ['android', 'ios', 'web', 'unknown'];
export const activityDay = time => new Date(time + 3 * 3600000).toISOString().slice(0, 10);
const ordinal = date => Date.parse(date + 'T00:00:00Z') / DAY;
function bits(value) { return /^[0-9a-f]{1,23}$/.test(value || '') ? BigInt('0x' + value) : 0n; }
export function recordActivity(user, now = Date.now()) {
  const seen = Date.parse(user.lastSeenAt || '');
  // Запись профиля администратором/миграцией не означает использование.
  if (!Number.isFinite(seen) || activityDay(seen) !== activityDay(now)) return;
  const date = activityDay(now), old = user.activity || {};
  const shift = old.date ? ordinal(date) - ordinal(old.date) : 90;
  if (!Number.isFinite(shift) || shift < 0) return;
  const platform = PLATFORMS.includes(String(user.platform).toLowerCase()) ? String(user.platform).toLowerCase() : 'unknown';
  const activity = { date };
  for (const key of PLATFORMS) {
    const previous = shift >= 90 ? 0n : (bits(old[key]) << BigInt(shift)) & MASK;
    const value = previous | (key === platform ? 1n : 0n);
    if (value) activity[key] = value.toString(16);
  }
  user.activity = activity;
}
export function activitySnapshot(users, dates, now = Date.now()) {
  const earliest = activityDay(now - 89 * DAY);
  const from = earliest > ACTIVITY_FROM ? earliest : ACTIVITY_FROM;
  // Последнее обращение достоверно подтверждает только сегодняшний день.
  users = users.map(user => { const copy = { ...user }; recordActivity(copy, now); return copy; });
  return { from, days: dates.map(date => {
    if (date < from) return { date, total: null, android: null, ios: null, web: null, unknown: null };
    const row = { date, total: 0, android: 0, ios: 0, web: 0, unknown: 0 };
    for (const user of users) {
      const history = user.activity;
      if (!history?.date) continue;
      const offset = ordinal(history.date) - ordinal(date);
      if (!Number.isFinite(offset) || offset < 0 || offset >= 90) continue;
      const bit = 1n << BigInt(offset);
      let active = false;
      for (const key of PLATFORMS) if (bits(history[key]) & bit) { row[key]++; active = true; }
      if (active) row.total++;
    }
    return row;
  }) };
}
