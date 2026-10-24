// One authoritative queue in SQLite. KV is a delayed recovery/export projection,
// never the source for read-modify-write after the one-time import.
const QUEUE_KEY = 'social:posts';
const PREFIX = 'queue:post:';
const queueSnapshots = new WeakMap();
const queueEqual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function validatePosts(posts) {
  if (!Array.isArray(posts) || posts.some(p => !p || typeof p.id !== 'string' || !p.id || p.id.length > 200)
    || new Set(posts.map(p => p.id)).size !== posts.length) throw new Error('Social queue is invalid');
  return posts;
}

async function queueRequest(env, path, body = {}) {
  const stub = env.SOCIAL_PUBLISHER.get(env.SOCIAL_PUBLISHER.idFromName('queue-state-v1'));
  const response = await stub.fetch('https://social/queue/' + path, {
    method: 'POST', body: JSON.stringify(body), signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) {
    const error = new Error(response.status === 409
      ? 'Очередь изменилась во время операции. Обновите список и повторите'
      : 'Хранилище очереди временно недоступно');
    error.code = response.status === 409 ? 'ERR_SOCIAL_QUEUE_CONFLICT' : 'ERR_SOCIAL_QUEUE_UNAVAILABLE';
    throw error;
  }
  return response.json();
}

function usesQueue(env) {
  if (env.SOCIAL_QUEUE_REQUIRED !== 'true') return false;
  if (!env.SOCIAL_PUBLISHER) throw new Error('Social queue binding unavailable');
  return true;
}

export async function readSocialPosts(env) {
  const posts = usesQueue(env) ? (await queueRequest(env, 'read')).posts
    : JSON.parse((await env.INSTALLS.get(QUEUE_KEY)) ?? '[]');
  validatePosts(posts);
  queueSnapshots.set(posts, structuredClone(posts));
  return posts;
}

// Send only changed fields, together with their expected previous values. This
// merges unrelated admin edits while rejecting a stale change to the same field.
export async function saveSocialPosts(env, source, posts = source) {
  validatePosts(posts);
  const before = queueSnapshots.get(source);
  if (!before) throw new Error('Social queue write requires a read snapshot');
  if (!usesQueue(env)) {
    await env.INSTALLS.put(QUEUE_KEY, JSON.stringify(posts));
    return;
  }
  const old = new Map(before.map(p => [p.id, p])), next = new Map(posts.map(p => [p.id, p]));
  const changes = [];
  for (const [id, post] of next) {
    const previous = old.get(id);
    if (!previous) { changes.push({ id, add: post }); continue; }
    const fields = [...new Set([...Object.keys(previous), ...Object.keys(post)])]
      .filter(key => !queueEqual(previous[key], post[key]));
    if (fields.length) changes.push({ id, fields: fields.map(key => ({ key,
      before: previous[key] ?? null, after: post[key] ?? null })) });
  }
  for (const [id, post] of old) if (!next.has(id)) changes.push({ id, remove: post });
  if (changes.length) await queueRequest(env, 'change', { changes });
}

export class SocialQueueStore {
  constructor(state, env) { this.state = state; this.env = env; }

  async initialize() {
    if (await this.state.storage.get('queue:initialized')) return;
    // Failed/malformed reads must not become an empty queue or enable re-import.
    const posts = validatePosts(JSON.parse((await this.env.INSTALLS.get(QUEUE_KEY)) ?? '[]'));
    await this.state.storage.transaction(async tx => {
      for (const post of posts) await tx.put(PREFIX + post.id, post);
      await tx.put('queue:initialized', true);
    });
  }

  async posts() { return [...(await this.state.storage.list({ prefix: PREFIX })).values()]; }

  async handle(path, body) {
    await this.initialize();
    if (path === '/queue/read') return Response.json({ posts: await this.posts() });
    if (path !== '/queue/change' || !Array.isArray(body.changes)) return new Response('operation', { status: 400 });
    return this.state.storage.transaction(async tx => {
      const writes = new Map(), removals = [];
      const existing = body.changes.some(change => change.add)
        ? [...(await tx.list({ prefix: PREFIX })).values()] : [];
      for (const change of body.changes) {
        if (typeof change.id !== 'string' || !change.id || change.id.length > 200) return new Response('id', { status: 400 });
        const key = PREFIX + change.id, current = await tx.get(key);
        if (change.add) {
          if (change.add.id !== change.id) return new Response('id', { status: 400 });
          if (current && !queueEqual(current, change.add)) return new Response('conflict', { status: 409 });
          if ([...existing, ...writes.values()].some(post => post.id !== change.id && post.accountId === change.add.accountId
            && ((post.driveFileId && post.driveFileId === change.add.driveFileId)
              || (post.contentMd5 && post.contentMd5 === change.add.contentMd5)))) return new Response('duplicate', { status: 409 });
          if (!current) writes.set(key, change.add);
        } else if (change.remove) {
          if (current && !queueEqual(current, change.remove)) return new Response('conflict', { status: 409 });
          if (current) removals.push(key);
        } else {
          if (!current || !Array.isArray(change.fields)) return new Response('conflict', { status: 409 });
          const next = { ...current };
          for (const field of change.fields) {
            if (typeof field.key !== 'string' || ['id', '__proto__', 'constructor', 'prototype'].includes(field.key)) return new Response('field', { status: 400 });
            if (!queueEqual(current[field.key] ?? null, field.before) && !queueEqual(current[field.key] ?? null, field.after)) return new Response('conflict', { status: 409 });
            next[field.key] = field.after;
          }
          writes.set(key, next);
        }
      }
      if (writes.size || removals.length) {
        // Persist recovery before acknowledging state. No KV call in this path.
        if (!(await tx.getAlarm())) await tx.setAlarm(Date.now() + 65000);
        for (const [key, post] of writes) await tx.put(key, post);
        for (const key of removals) await tx.delete(key);
        await tx.put('queue:dirty', true);
      }
      return Response.json({ ok: true });
    });
  }

  async alarm() {
    if (!(await this.state.storage.get('queue:dirty'))) return;
    try {
      await this.env.INSTALLS.put(QUEUE_KEY, JSON.stringify(await this.posts()));
      await this.state.storage.delete('queue:dirty');
    } catch (_) {
      await this.state.storage.setAlarm(Date.now() + 65000);
      console.warn('Social queue projection deferred');
    }
  }
}
