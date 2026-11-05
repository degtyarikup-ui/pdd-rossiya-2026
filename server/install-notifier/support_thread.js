// One private thread. The Worker authenticates access before choosing this object.
// Internal receipt times are distinct from client/Telegram timestamps.
const MAX_MESSAGES = 200;
export const SUPPORT_RETENTION_MS = 90 * 86400000;
export class SupportThread {
  constructor(state) { this.state = state; this.queue = Promise.resolve(); }
  fetch(request) {
    const next = this.queue.then(() => this.handle(request));
    this.queue = next.catch(() => {}); return next;
  }
  async schedule(messages) {
    const next = messages.reduce((min, m) => Math.min(min, m._storedAt + SUPPORT_RETENTION_MS), Infinity);
    if (Number.isFinite(next)) await this.state.storage.setAlarm?.(next);
  }
  async handle(request) {
    const url = new URL(request.url), now = Date.now();
    if (request.method === 'POST' && url.pathname === '/delete') {
      const { before } = await request.json();
      if (!Number.isFinite(before)) return new Response(null, { status: 400 });
      await this.state.storage.transaction(async txn => {
        const cutoff = Math.max(before, await txn.get('deletedThrough') || 0);
        const saved = await txn.get('messages') || [];
        await txn.put('deletedThrough', cutoff);
        await txn.put('messages', saved.filter(m => m._storedAt > cutoff));
      });
      return Response.json({ ok: true });
    }
    if (request.method === 'POST' && ['/append', '/seed'].includes(url.pathname)) {
      const input = await request.json(), seed = url.pathname === '/seed';
      if (!seed && (!input || typeof input.id !== 'string' || !Number.isFinite(input.ts))) return new Response(null, { status: 400 });
      let result = [];
      await this.state.storage.transaction(async txn => {
        const stored = await txn.get('messages'), cutoff = await txn.get('deletedThrough') || 0;
        let msgs = (stored || []).map(m => ({ ...m, _storedAt: m._storedAt || now })).filter(m => m._storedAt > cutoff && m._storedAt + SUPPORT_RETENTION_MS > now);
        if (seed) {
          if (stored == null && Array.isArray(input) && !cutoff) msgs = input.slice(-MAX_MESSAGES).map(m => ({ ...m, _storedAt: now }));
        } else if (now > cutoff && !msgs.some(m => m.id === input.id)) msgs.push({ ...input, _storedAt: now });
        msgs = msgs.slice(-MAX_MESSAGES); result = msgs;
        await txn.put('messages', msgs);
      });
      await this.schedule(result);
      return Response.json({ ok: true });
    }
    if (request.method === 'GET' && url.pathname === '/list') {
      const since = Number(url.searchParams.get('since') || 0), stored = await this.state.storage.get('messages');
      const deletedThrough = await this.state.storage.get('deletedThrough') || 0;
      const msgs = (stored || []).map(m => ({ ...m, _storedAt: m._storedAt || now })).filter(m => m._storedAt > deletedThrough && m._storedAt + SUPPORT_RETENTION_MS > now);
      if (stored && JSON.stringify(msgs) !== JSON.stringify(stored)) await this.state.storage.put('messages', msgs);
      await this.schedule(msgs);
      return Response.json({ ok: true, initialized: stored != null || deletedThrough > 0, messages: msgs.filter(m => !(since > 0) || m.ts > since).map(({ _storedAt, ...m }) => m) });
    }
    return new Response(null, { status: 404 });
  }
  alarm() {
    const next = this.queue.then(() => this.prune());
    this.queue = next.catch(() => {}); return next;
  }
  async prune() {
    const saved = await this.state.storage.get('messages') || [], now = Date.now();
    const msgs = saved.filter(m => m._storedAt && m._storedAt + SUPPORT_RETENTION_MS > now);
    await this.state.storage.put('messages', msgs); await this.schedule(msgs);
  }
}
