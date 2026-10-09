// Usage is stored alongside existing day counters: no extra KV writes per event.
export const USAGE_FROM = '2026-10-08';
export const USAGE_FEATURES = ['tickets', 'topics', 'exam', 'feed', 'game', 'sign_swiper', 'traffic_controller', 'roundabout'];
const DAY = 86400000;

export async function acceptUsage(request, env, { jsonResponse, trackStats }, now = Date.now()) {
  if (!env.INSTALLS || !env.STATS) return jsonResponse({ error: 'storage unavailable' }, 503);
  let body;
  try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'bad json' }, 400); }
  if (!/^[a-f0-9]{32}$/.test(body?.installId || '') || !Array.isArray(body?.events)
    || !body.events.length || body.events.length > 50
    || !['android', 'ios', 'web'].includes(body.platform)) return jsonResponse({ error: 'bad usage batch' }, 400);
  if (body.events.some(e => !e || !/^[a-f0-9]{32}$/.test(e.id || '') || !USAGE_FEATURES.includes(e.feature)
    || !Number.isSafeInteger(e.ts) || e.ts < now - 90 * DAY || e.ts > now + 5 * 60000
    || new Date(e.ts + 3 * 3600000).toISOString().slice(0, 10) < USAGE_FROM)) {
    return jsonResponse({ error: 'bad usage event' }, 400);
  }
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('usage:' + body.installId));
  const installation = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('').slice(0, 32);
  // Await durable acceptance. A partially accepted batch is safe to resend.
  for (const event of body.events) await trackStats(env, null, {
    id: 'usage:' + installation + ':' + event.id, kind: 'usage', ts: event.ts,
    feature: event.feature, installation, platform: body.platform,
  });
  return jsonResponse({ ok: true });
}

export function applyUsage(day, item) {
  if (!USAGE_FEATURES.includes(item.feature) || !/^[a-f0-9]{32}$/.test(item.installation || '')) return;
  const features = day.usage ||= {};
  const feature = features[item.feature] ||= { starts: 0, installations: {} };
  feature.starts++;
  feature.installations[item.installation] = true;
}

// Only aggregates leave the admin API. Unique installations are a union over
// the selected period, never a sum of daily uniques.
export function usageSnapshot(days, app = 'all') {
  const totals = Object.fromEntries(USAGE_FEATURES.map(key => [key, { starts: 0, ids: new Set() }]));
  const timeline = days.map(({ date, data }) => {
    const available = date >= USAGE_FROM;
    const features = {};
    for (const key of USAGE_FEATURES) {
      const feature = ['all', 'ru'].includes(app) ? data?.usage?.[key] : null;
      const ids = Object.keys(feature?.installations || {});
      totals[key].starts += feature?.starts || 0;
      for (const id of ids) totals[key].ids.add(id);
      features[key] = { starts: available ? feature?.starts || 0 : null, installations: available ? ids.length : null };
    }
    return { date, features };
  });
  return { from: USAGE_FROM, timeline, features: Object.fromEntries(USAGE_FEATURES.map(key => [key, {
    starts: totals[key].starts, installations: totals[key].ids.size,
  }])) };
}
