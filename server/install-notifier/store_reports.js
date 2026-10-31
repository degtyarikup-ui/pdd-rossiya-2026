// Store dates are the reporting dates assigned by each provider.
export async function storeReportSnapshot(env, dateKeys, appFilter) {
  if (!['all', 'ru'].includes(appFilter)) return null;
  const entries = await Promise.all(['googleplay', 'appstore'].map(async store => {
    try {
      const raw = await env.INSTALLS.get('store-reports:v1:' + store);
      if (!raw) return [store, null];
      const { checkedAt, days } = JSON.parse(raw);
      const covered = dateKeys.filter(day => Object.hasOwn(days, day));
      const counts = new Map();
      for (const day of covered) for (const [source, value] of Object.entries(days[day])) {
        if (!Number.isSafeInteger(value) || value < 0) throw new Error('invalid count');
        counts.set(source, (counts.get(source) || 0) + value);
      }
      return [store, { checkedAt, first: covered[0], last: covered.at(-1), days: covered.length,
        latestAvailable: Object.keys(days).sort().at(-1), rows: [...counts].sort((a, b) => b[1] - a[1]) }];
    } catch {
      console.error('Store report unavailable', store);
      return [store, null];
    }
  }));
  return Object.fromEntries(entries);
}
