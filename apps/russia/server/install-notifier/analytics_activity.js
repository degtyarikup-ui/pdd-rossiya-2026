// 90 календарных дней МСК: один бит на аккаунт/платформу/день.
export const ACTIVITY_FROM = '2026-10-07';
const DAY = 86400000;
const COMPARISON_DAYS = 7;
const minuteMsk = time => Math.floor(((time + 3 * 3600000) % DAY) / 60000);
const validMinute = minute => Number.isInteger(minute) && minute >= 0 && minute < 1440;
const MASK = (1n << 90n) - 1n;
const PLATFORMS = ['android', 'ios', 'web', 'unknown'];
export const activityDay = time => new Date(time + 3 * 3600000).toISOString().slice(0, 10);
const ordinal = date => Date.parse(date + 'T00:00:00Z') / DAY;
function bits(value) { return /^[0-9a-f]{1,23}$/.test(value || '') ? BigInt('0x' + value) : 0n; }
export function recordActivity(user, now = Date.now(), captureFirstVisit = true) {
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
  // Offsets from activity.date: [today, yesterday, …]. No write is needed
  // for repeat visits within a day. A legacy daily bit has no known time.
  const first = [];
  if (Array.isArray(old.first)) {
    for (let i = 0; i + shift <= COMPARISON_DAYS && i < old.first.length; i++) {
      if (validMinute(old.first[i])) first[i + shift] = old.first[i];
    }
  }
  if (captureFirstVisit && (shift > 0 || validMinute(first[0]))) {
    first[0] = Math.min(first[0] ?? 1440, minuteMsk(seen));
  }
  if (first.length) activity.first = first;
  user.activity = activity;
}
export function activitySnapshot(users, dates, now = Date.now()) {
  const earliest = activityDay(now - 89 * DAY);
  const from = earliest > ACTIVITY_FROM ? earliest : ACTIVITY_FROM;
  const today = activityDay(now);
  const cutoff = minuteMsk(now);
  const todayIndex = ordinal(today);
  const buckets = Array.from({ length: COMPARISON_DAYS + 1 }, () => ({ count: 0, complete: true }));
  let firstMeasuredDay = Infinity;
  const histories = users.map(user => {
    // Today's lastSeenAt can establish activity, but never the first visit.
    const copy = { ...user };
    recordActivity(copy, now, false);
    const history = copy.activity || {};
    const index = ordinal(history.date);
    const masks = PLATFORMS.map(key => bits(history[key]));
    const total = masks.reduce((a, b) => a | b, 0n);
    const known = Array.isArray(history.first) ? history.first : [];
    const seen = Date.parse(user.lastSeenAt || '');
    const seenDay = Number.isFinite(seen) ? ordinal(activityDay(seen)) : -Infinity;
    const recordedThrough = user.activity?.date ? ordinal(user.activity.date) : -Infinity;
    for (let i = 0; i <= COMPARISON_DAYS; i++) {
      if (Number.isInteger(index) && validMinute(known[i])) firstMeasuredDay = Math.min(firstMeasuredDay, index - i);
      const date = todayIndex - i;
      // A trimmed/missing history cannot certify completeness for a day
      // on which the account could have been active.
      if (seenDay > recordedThrough && date <= seenDay && date > recordedThrough) buckets[i].complete = false;
      const offset = index - date;
      if (!Number.isInteger(offset) || offset < 0 || offset >= 90 || !(total & (1n << BigInt(offset)))) continue;
      const minute = known[offset];
      if (!validMinute(minute)) buckets[i].complete = false;
      else if (minute < cutoff) buckets[i].count++;
    }
    return { index, masks, total };
  });

  // Collection may start mid-day. A baseline is usable only after the first
  // measured Moscow date, and only when every known active account is covered.
  const complete = (bucket, i) => bucket.complete && todayIndex - i > firstMeasuredDay;
  const previous = buckets.slice(1).filter((bucket, i) => complete(bucket, i + 1));
  const comparison = {
    minute: cutoff,
    today: complete(buckets[0], 0) ? buckets[0].count : null,
    days: previous.length,
    average: previous.length ? Math.round(previous.reduce((n, b) => n + b.count, 0) / previous.length) : null,
  };

  return { from, comparison, days: dates.map(date => {
    if (date < from) return { date, total: null, android: null, ios: null, web: null, unknown: null };
    const row = { date, total: 0, android: 0, ios: 0, web: 0, unknown: 0 };
    const day = ordinal(date);
    for (const { index, masks, total } of histories) {
      const offset = index - day;
      if (!Number.isInteger(offset) || offset < 0 || offset >= 90) continue;
      const bit = 1n << BigInt(offset);
      if (total & bit) {
        row.total++;
        for (let i = 0; i < PLATFORMS.length; i++) if (masks[i] & bit) row[PLATFORMS[i]]++;
      }
    }
    return row;
  }) };
}
