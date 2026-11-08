// Baseline is the first observed version per mobile platform. Only an increase
// after that baseline confirms an update; a new account is never an update.
export const VERSION_UPDATES_FROM = '2026-10-19';
function parts(value) {
  return String(value || '').length <= 40 && /^\d+(?:\.\d+){1,3}(?:\+\d+)?$/.test(value || '')
    ? value.split(/[.+]/).map(Number) : null;
}
export function recordVersion(user, now = Date.now()) {
  const platform = user.platform;
  const version = user.appVersion;
  if (!['android', 'ios'].includes(platform) || !parts(version)
      || !Number.isFinite(Date.parse(user.lastSeenAt))
      || Math.abs(now - Date.parse(user.lastSeenAt)) > 86400000) return;
  const observations = user.versionObservations ||= {};
  const previous = observations[platform];
  if (!previous) { observations[platform] = { version }; return; }
  const a = parts(version), b = parts(previous.version);
  if (!b) { observations[platform] = { version }; return; }
  let comparison = 0;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    comparison = (a[i] || 0) - (b[i] || 0);
    if (comparison) break;
  }
  // Keep the high-water mark: another older device must not fake an update.
  if (comparison > 0) observations[platform] = { version, updatedAt: new Date(now).toISOString() };
}
export function versionsSnapshot(users, dates, dayKey) {
  const period = new Set(dates);
  let updated = 0;
  const rows = new Map();
  for (const user of users) {
    if (Object.values(user.versionObservations || {}).some(v => v.updatedAt && period.has(dayKey(new Date(v.updatedAt))))) updated++;
    if (!['android', 'ios'].includes(user.platform)) continue;
    const version = parts(user.appVersion) ? user.appVersion : 'Неизвестна';
    const key = user.platform + ':' + version;
    if (!rows.has(key)) rows.set(key, { platform: user.platform, version, accounts: 0 });
    rows.get(key).accounts++;
  }
  return { from: VERSION_UPDATES_FROM, updated, rows: [...rows.values()].sort((a, b) => b.accounts - a.accounts) };
}
