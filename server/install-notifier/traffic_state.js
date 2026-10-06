import { buildUserRegistrationMessage } from './worker.js';

// One object per counter / weekly board. KV remains a compatibility snapshot;
// concurrent updates are committed to strongly consistent DO storage first.
export class TrafficState {
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
      const body = await request.json();
      const { key, action } = body;
      if (!/^(counter(?::(?:by|rs|registered_users))?|game_lb:\d{4}-W\d{2})$/.test(key || '')) {
        return new Response('invalid key', { status: 400 });
      }
      const savedKey = await this.state.storage.get('key');
      if (savedKey && savedKey !== key) return new Response('wrong object', { status: 400 });
      if (!savedKey) {
        // Do not swallow a KV failure: starting from zero would lose old totals.
        const raw = await this.env.INSTALLS.get(key);
        const value = key.startsWith('game_lb:') ? (raw ? JSON.parse(raw) : {}) : (Number(raw) || 0);
        await this.state.storage.put({ key, value });
      }
      if (action === 'read') return Response.json(await this.state.storage.get('value'));
      if (!(await this.state.storage.getAlarm())) await this.state.storage.setAlarm(Date.now() + 60000);
      if (action === 'install') {
        const marker = 'id:' + String(body.installId || '');
        if (body.installId) {
          const known = await this.state.storage.get(marker);
          if (known !== undefined) return Response.json({ value: known, isNew: false });
          const legacy = await this.env.INSTALLS.get(body.legacyKey);
          if (legacy !== null) {
            const number = legacy === 'returning' ? null : Number(legacy);
            await this.state.storage.put(marker, number);
            return Response.json({ value: number, isNew: false });
          }
        }
        const nonNew = ['returning', 'unclassified'].includes(body.analytics?.kind);
        const value = await this.state.storage.transaction(async txn => {
          const next = nonNew ? null : (await txn.get('value')) + 1;
          if (!nonNew) await txn.put('value', next);
          if (body.installId) await txn.put(marker, next);
          if (body.analytics || body.registrationUser) {
            const event = body.analytics || { type: 'registration', marketingSource: body.registrationUser.marketingSource, app: body.registrationUser.app, platform: body.registrationUser.platform };
            const outbox = { id: key + ':' + (body.installId || next), ts: Date.now(), kind: 'analytics', event };
            if (body.registrationUser) outbox.telegram = { text: buildUserRegistrationMessage(body.registrationUser, next), dedupKey: body.legacyKey };
            await txn.put('out:' + (nonNew ? crypto.randomUUID() : String(next).padStart(16, '0')), outbox);
          }
          return next;
        });
        return Response.json({ value, isNew: true });
      }
      if (action === 'increment') {
        const value = await this.state.storage.transaction(async txn => {
          const next = (await txn.get('value')) + 1;
          await txn.put('value', next);
          return next;
        });
        return Response.json(value);
      }
      if (action === 'score' || action === 'delete') {
        const doc = await this.state.storage.get('value');
        const userId = body.userId;
        if (!userId || ['__proto__', 'constructor', 'prototype'].includes(userId)) return new Response('invalid user', { status: 400 });
        if (action === 'delete') delete doc[userId];
        else {
          const e = doc[userId] || { score: 0, runs: 0, best: 0 };
          const input = body.score;
          e.name = String(input.name || e.name || 'Игрок').slice(0, 40);
          if (input.delta !== undefined) {
            e.score = Math.max(0, e.score + Math.max(-20000, Math.min(20000, Math.trunc(Number(input.delta) || 0))));
            if (input.newRun === true) e.runs += 1;
            e.best = Math.max(e.best, Math.max(0, Math.min(1000000, Math.floor(Number(input.runScore) || 0))));
          } else {
            const score = Math.max(0, Math.min(1000000, Math.floor(Number(input.score) || 0)));
            e.score += score; e.runs += 1; e.best = Math.max(e.best, score);
          }
          e.updatedAt = new Date().toISOString();
          doc[userId] = e;
        }
        await this.state.storage.put('value', doc);
        return Response.json(doc);
      }
      return new Response('invalid action', { status: 400 });
    });
  }

  alarm() {
    return this.serial(async () => {
      const key = await this.state.storage.get('key');
      const value = await this.state.storage.get('value');
      try {
        // Outbox was committed together with the number. Retrying delivery
        // cannot double-count analytics or enqueue duplicate Telegram messages.
        const entries = await this.state.storage.list({ prefix: 'out:', limit: 100 });
        for (const [outKey, item] of entries) {
          const { telegram, ...analytics } = item;
          if (this.env.STATS) {
            const stats = this.env.STATS.get(this.env.STATS.idFromName('main'));
            const result = await stats.fetch('https://stats/enqueue', { method: 'POST', body: JSON.stringify(analytics) });
            if (!result.ok) throw new Error('analytics queue unavailable');
          } else throw new Error('analytics binding missing');
          if (telegram && this.env.BOT_TOKEN && this.env.CHAT_ID) {
            if (!this.env.TELEGRAM) throw new Error('telegram binding missing');
            const queue = this.env.TELEGRAM.get(this.env.TELEGRAM.idFromName(String(this.env.CHAT_ID)));
            const result = await queue.fetch('https://telegram/enqueue', { method: 'POST', body: JSON.stringify(telegram) });
            if (!result.ok) throw new Error('telegram queue unavailable');
          }
          await this.state.storage.delete(outKey);
        }
        if ((await this.state.storage.list({ prefix: 'out:', limit: 1 })).size) await this.state.storage.setAlarm(Date.now() + 60000);
        await this.env.INSTALLS.put(key, typeof value === 'number' ? String(value) : JSON.stringify(value),
          key.startsWith('game_lb:') ? { expirationTtl: 21 * 86400 } : undefined);
      } catch (error) {
        await this.state.storage.setAlarm(Date.now() + 60000);
        throw error;
      }
    });
  }
}

export async function trafficRequest(env, key, action, body = {}) {
  const stub = env.TRAFFIC.get(env.TRAFFIC.idFromName(key));
  const response = await stub.fetch('https://traffic/action', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ...body, key, action }),
  });
  if (!response.ok) throw new Error('traffic state unavailable: ' + response.status);
  return response.json();
}
