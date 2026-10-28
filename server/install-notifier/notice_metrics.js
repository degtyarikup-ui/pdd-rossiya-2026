import { campaignMatches } from './notifications.js';
import { privatePushTopic } from './notification_identity.js';

const reply = (body, status = 200) => Response.json(body, { status, headers: { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' } });
const DAY = 86400000;
// Views and taps of every kind: banner and window shown, push or inbox entry
// opened. Authenticated accounts are unique across devices. Guests are unique per
// installation. Only opaque hashes enter the analytics buffer, never emails.
export async function acceptNoticeMetrics(request, env, { trackStats, notificationRequest, readSession }, now = Date.now()) {
  if (!env.STATS || !env.INSTALLS) return reply({ error: 'storage unavailable' }, 503);
  let body;
  try { body = await request.json(); } catch { return reply({ error: 'invalid json' }, 400); }
  if (!/^[a-f0-9]{32}$/.test(body?.installId || '') || !['android', 'ios', 'web'].includes(body.platform)
    || !Array.isArray(body.events) || !body.events.length || body.events.length > 50
    || body.events.some(e => !e || !/^[a-f0-9-]{36}$/.test(e.campaignId || '') || !['view','click'].includes(e.event)
      || !Number.isSafeInteger(e.ts) || e.ts < now - 30 * DAY || e.ts > now + 300000)) return reply({ error: 'invalid events' }, 400);
  const session = await readSession(request, env);
  const identity = await privatePushTopic(env, session ? 'account:' + session.user.id : 'installation:' + body.installId);
  const response = await notificationRequest(env, '/admin');
  if (!response.ok) return reply({ error: 'notifications unavailable' }, 503);
  const { messages } = await response.json();
  for (const event of body.events) {
    const campaign = messages.find(m => m.id === event.campaignId);
    // Accept delayed offline deliveries even after a campaign was disabled.
    if (!campaign || event.ts < (campaign.startAt || campaign.createdAt) || event.ts >= campaign.expiresAt
      || !campaignMatches({ ...campaign, enabled: true }, 'ru', body.platform, event.ts,
        { userId: session?.user?.id, email: session?.user?.email }, body.store || '')) continue;
    // A click also proves a view. Two devices and retries share these IDs.
    for (const type of event.event === 'click' ? ['view', 'click'] : ['view']) await trackStats(env, null, {
      id: `notice:${campaign.id}:${identity}:${type}`, kind: 'notice', campaignId: campaign.id, event: type, ts: event.ts,
    });
  }
  return reply({ ok: true });
}

export async function noticeMetricsForAdmin(env, response) {
  if (!response.ok) return response;
  const data = await response.json();
  await Promise.all(data.messages.map(async message => {
    const raw = await env.INSTALLS.get('notice_metrics:' + message.id);
    message.metrics = raw ? JSON.parse(raw) : { view: 0, click: 0 };
  }));
  return new Response(JSON.stringify(data), { status: 200, headers: response.headers });
}
