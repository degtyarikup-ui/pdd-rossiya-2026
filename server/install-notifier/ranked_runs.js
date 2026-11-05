import { boundedJson, HttpFailure, digest } from './request_security.js';
import { validGameRunId, GAME_RUN_LIMIT, gameDayKey } from './game_scoring.js';

// Rankings accept only runs opened online before play. A per-account server
// clock bounds all games/devices together, rather than trusting a new client ID.
// This is an abuse bound, not device attestation or a claim that a human played.
const POINTS_PER_SECOND = 40;
const RUN_LIFETIME_MS = 24 * 3600000;
export async function rankedRequest(env, userId, operation, body) {
  if (!env.RANKED_RUNS) throw new HttpFailure(503, 'ranked game storage unavailable');
  const key = await digest('ranked-v1:' + userId);
  const response = await env.RANKED_RUNS.get(env.RANKED_RUNS.idFromName(key)).fetch('https://ranking/' + operation, { method: 'POST', body: JSON.stringify(body) });
  if (!response.ok) throw new HttpFailure(response.status, 'ranking request rejected', response.status === 429 ? { 'Retry-After': response.headers.get('retry-after') || '30' } : {});
  return response.json();
}
export class RankedRuns {
  constructor(state) { this.state = state; this.queue = Promise.resolve(); }
  fetch(request) {
    const result = this.queue.then(() => this.handle(request));
    this.queue = result.catch(() => {}); return result;
  }
  async handle(request) {
    const body = await boundedJson(request, 8192), path = new URL(request.url).pathname, now = Date.now();
    if (path === '/delete') {
      if (!Number.isFinite(body.before)) return new Response(null, { status: 400 });
      const saved = await this.state.storage.get('ranking');
      if (saved) {
        for (const [id, run] of Object.entries(saved.runs)) if (run.startedAt <= body.before) delete saved.runs[id];
        if (Object.keys(saved.runs).length) await this.state.storage.put('ranking', saved);
        else await this.state.storage.delete('ranking');
      }
      return Response.json({ ok: true });
    }
    if (path === '/verify' && body.runId === undefined) return Response.json({ ok: true, ranked: false, reason: 'unverified_run' });
    if (!validGameRunId(body.runId)) return Response.json({ error: 'invalid runId' }, { status: 400 });
    const saved = await this.state.storage.get('ranking') || { runs: {}, starts: {}, wallet: { at: now, points: 0 } };
    for (const [id, run] of Object.entries(saved.runs)) if (run.expiresAt <= now) delete saved.runs[id];
    if (path === '/start') {
      if (Object.hasOwn(saved.runs, body.runId)) return Response.json({ ok: true, ranked: true });
      const minute = Math.floor(now / 60000), day = gameDayKey(now);
      if ((saved.starts.minute === minute && saved.starts.count >= 10) || (saved.starts.day === day && saved.starts.daily >= 1000)) return Response.json({ error: 'run budget exhausted' }, { status: 429, headers: { 'Retry-After': '60' } });
      if (Object.keys(saved.runs).length >= 512) return Response.json({ error: 'too many runs' }, { status: 429 });
      saved.starts = { minute, count: saved.starts.minute === minute ? saved.starts.count + 1 : 1, day, daily: saved.starts.day === day ? saved.starts.daily + 1 : 1 };
      saved.runs[body.runId] = { startedAt: now, expiresAt: now + RUN_LIFETIME_MS, high: 0, weeks: {} };
      await this.state.storage.put('ranking', saved);
      const alarm = await this.state.storage.getAlarm?.();
      if (!alarm || alarm > now + RUN_LIFETIME_MS) await this.state.storage.setAlarm?.(now + RUN_LIFETIME_MS);
      return Response.json({ ok: true, ranked: true });
    }
    if (path !== '/verify') return new Response(null, { status: 404 });
    let run = Object.hasOwn(saved.runs, body.runId) ? saved.runs[body.runId] : null;
    if (!run) {
      // Godot mini-games append a round sequence to their registered session.
      const parentId = body.runId.replace(/-\d+$/, '');
      const parent = Object.hasOwn(saved.runs, parentId) ? saved.runs[parentId] : null;
      if (parent && Object.keys(saved.runs).length < 512) {
        run = { startedAt: parent.startedAt, expiresAt: parent.expiresAt, high: 0, weeks: {} };
        saved.runs[body.runId] = run;
      }
    }
    if (!run) return Response.json({ ok: true, ranked: false, reason: 'unverified_run' });
    const raw = body.runScore ?? body.score;
    if (!Number.isFinite(raw) || raw < 0 || raw > GAME_RUN_LIMIT || !Number.isInteger(raw)) return Response.json({ error: 'invalid score' }, { status: 400 });
    const score = raw, increase = Math.max(0, score - run.high);
    const wallet = saved.wallet;
    const available = Math.min(GAME_RUN_LIMIT, wallet.points + Math.max(0, now - wallet.at) / 1000 * POINTS_PER_SECOND);
    const plausible = Math.floor(Math.max(0, now - run.startedAt) / 1000 * POINTS_PER_SECOND);
    if (increase > available || score > plausible) return Response.json({ error: 'implausible score rate' }, { status: 429, headers: { 'Retry-After': String(Math.max(1, Math.ceil(Math.max(increase - available, score - plausible) / POINTS_PER_SECOND))) } });
    if (!/^\d{4}-W\d{2}$/.test(body.week || '')) return Response.json({ error: 'invalid week' }, { status: 400 });
    if (!Object.hasOwn(run.weeks, body.week)) run.weeks[body.week] = run.high;
    const baseline = run.weeks[body.week];
    run.high = Math.max(run.high, score);
    saved.wallet = { at: now, points: available - increase };
    await this.state.storage.put('ranking', saved);
    // Retries return the same cumulative allowance; TrafficState applies its
    // high-water mark atomically. A lost response cannot consume points twice.
    return Response.json({ ok: true, ranked: true, score: { runId: body.runId, runScore: score, delta: Math.max(0, score - baseline), newRun: baseline === 0 } });
  }
  alarm() {
    const result = this.queue.then(async () => {
      const saved = await this.state.storage.get('ranking');
      if (!saved) return;
      const now = Date.now(); let next = Infinity;
      for (const [id, run] of Object.entries(saved.runs)) {
        if (run.expiresAt <= now) delete saved.runs[id]; else next = Math.min(next, run.expiresAt);
      }
      await this.state.storage.put('ranking', saved);
      if (Number.isFinite(next)) await this.state.storage.setAlarm(next);
    });
    this.queue = result.catch(() => {}); return result;
  }
}
