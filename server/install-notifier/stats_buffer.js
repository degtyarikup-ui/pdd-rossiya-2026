// Analytics are accepted into durable storage before batching into KV.
// A persisted write plan makes partial KV failures safe to retry: counters
// are replaced with the same totals, rather than incremented a second time.
import { flushBufferedStats } from './worker.js';

const FLUSH_MS = 5 * 60 * 1000;
const RETRY_MS = 65 * 1000; // KV permits only one write/second/key.
const BATCH_SIZE = 1000;

export class StatsBuffer {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.tail = Promise.resolve();
  }
  serial(fn) {
    const result = this.tail.then(fn);
    this.tail = result.catch(() => {});
    return result;
  }
  fetch(request) {
    return this.serial(async () => {
      const url = new URL(request.url);
      if (request.method !== 'POST') return new Response('not found', { status: 404 });
      if (url.pathname === '/enqueue') {
        let item;
        try { item = await request.json(); } catch (_) { return new Response('bad json', { status: 400 }); }
        if (item.id && await this.state.storage.get('seen:' + item.id)) return new Response('duplicate');
        const alarmAt = await this.state.storage.getAlarm();
        // Old deployments flushed hourly; shorten their persisted alarm too.
        if (alarmAt === null || alarmAt > Date.now() + FLUSH_MS) {
          await this.state.storage.setAlarm(Date.now() + FLUSH_MS);
        }
        const key = `q:${String(item.ts || Date.now()).padStart(13, '0')}:${crypto.randomUUID()}`;
        await this.state.storage.transaction(async txn => {
          await txn.put(key, item);
          if (item.id) await txn.put('seen:' + item.id, true);
        });
        return new Response('ok');
      }
      if (url.pathname === '/flush') {
        const complete = await this.flush();
        return new Response(complete ? 'ok' : 'pending', { status: complete ? 200 : 202 });
      }
      return new Response('not found', { status: 404 });
    });
  }
  alarm() { return this.serial(() => this.flush()); }

  async flush() {
    // Persist a plan BEFORE the first KV write. Keep it until all writes and
    // queue cleanup succeed. Durable shadows avoid KV's stale cached reads.
    let pending = await this.state.storage.get('pending');
    const lastWrite = await this.state.storage.get('lastWrite') || 0;
    if (Date.now() - lastWrite < RETRY_MS) {
      await this.state.storage.setAlarm(lastWrite + RETRY_MS);
      return false;
    }
    try {
      if (!pending) {
        const entries = await this.state.storage.list({ prefix: 'q:', limit: BATCH_SIZE });
        if (!entries.size) return true;
        const kv = this.env.INSTALLS;
        const env = { ...this.env, INSTALLS: {
          get: async key => (await this.state.storage.get('shadow:' + key)) ?? kv.get(key),
        } };
        await flushBufferedStats(env, [...entries.values()], async writes => {
          pending = { keys: [...entries.keys()], writes };
          await this.state.storage.put('pending', pending);
        });
      }
    } catch (_) {
      console.error('StatsBuffer prepare failed; events retained');
      await this.state.storage.setAlarm(Date.now() + RETRY_MS);
      return false;
    }
    // If this invocation dies during KV writes, an alarm resumes the plan.
    await this.state.storage.setAlarm(Date.now() + RETRY_MS);
    try {
      // Finish all started writes before returning a failure.
      const results = await Promise.allSettled(pending.writes.map(w => this.env.INSTALLS.put(w.key, w.value, w.options)));
      const failure = results.find(r => r.status === 'rejected');
      if (failure) throw failure.reason;
      await this.state.storage.transaction(async txn => {
        for (const w of pending.writes) await txn.put('shadow:' + w.key, w.value);
        await txn.put('lastWrite', Date.now());
        for (let i = 0; i < pending.keys.length; i += 128) await txn.delete(pending.keys.slice(i, i + 128));
        await txn.delete('pending');
      });
    } catch (_) {
      console.error('StatsBuffer flush failed; persisted batch will retry');
      await this.state.storage.setAlarm(Date.now() + RETRY_MS);
      return false;
    }
    const rest = await this.state.storage.list({ prefix: 'q:', limit: 1 });
    if (rest.size) await this.state.storage.setAlarm(Date.now() + RETRY_MS);
    else await this.state.storage.deleteAlarm();
    return !rest.size;
  }
}
