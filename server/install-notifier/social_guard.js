// Serialize publication of one account and retain write outcomes independently
// of the eventually-consistent admin KV list. An uncertain write is never replayed.
export class SocialPublisher {
  constructor(state) { this.state = state; this.tail = Promise.resolve(); }
  fetch(request) {
    const result = this.tail.then(() => this.handle(request));
    this.tail = result.catch(() => {});
    return result;
  }
  async handle(request) {
    if (request.method !== 'POST') return new Response('method', { status: 405 });
    const body = await request.json();
    const path = new URL(request.url).pathname;
    const now = Date.now();
    if (path === '/claim') {
      const lease = await this.state.storage.get('lease');
      if (lease?.until > now) return Response.json({ busy: true });
      const owner = crypto.randomUUID();
      await this.state.storage.put('lease', { owner, until: now + 15 * 60000 });
      return Response.json({ owner });
    }
    const lease = await this.state.storage.get('lease');
    if (!lease || lease.owner !== body.owner || lease.until <= now) return new Response('lease', { status: 409 });
    if (path === '/release') {
      await this.state.storage.delete('lease');
      return Response.json({ ok: true });
    }
    if (typeof body.key !== 'string' || body.key.length > 800 || !/^(instagram|youtube):/.test(body.key)) return new Response('key', { status: 400 });
    const key = 'write:' + body.key;
    const previous = await this.state.storage.get(key);
    if (path === '/read') return Response.json(previous || { state: 'absent' });
    if (path === '/abandon' && previous?.state === 'pending') {
      await this.state.storage.delete(key);
      return Response.json({ ok: true });
    }
    if (path === '/begin') {
      if (previous) return Response.json(previous);
      await this.state.storage.put(key, { state: 'pending', at: now });
      return Response.json({ state: 'new' });
    }
    if (path === '/complete' && previous?.state === 'pending') {
      const value = body.value;
      if (!value || typeof value.id !== 'string' || !/^[A-Za-z0-9_-]{1,100}$/.test(value.id)) return new Response('value', { status: 400 });
      const saved = { state: 'done', id: value.id, at: now };
      await this.state.storage.put(key, saved);
      return Response.json(saved);
    }
    return new Response('state', { status: 409 });
  }
}

export async function socialGuard(env, accountId, path, body = {}) {
  if (!env.SOCIAL_PUBLISHER) {
    if (env.SOCIAL_PUBLISHER_REQUIRED === 'true') throw new Error('Publication guard unavailable');
    return null; // Isolated/offline fixtures; production requires the binding.
  }
  const stub = env.SOCIAL_PUBLISHER.get(env.SOCIAL_PUBLISHER.idFromName(accountId));
  const response = await stub.fetch('https://social' + path, {
    method: 'POST', body: JSON.stringify(body), signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error('Publication guard unavailable');
  return response.json();
}

export async function beginSocialWrite(env, post, platform, reserve = true) {
  const key = platform + ':' + (post.contentMd5 || post.driveFileId || post.id) + ':'
    + (platform === 'instagram' ? post.instagramReplacementAttempt?.sourceContainerId || post.instagramReplacementAttempt?.id || 'initial' : 'initial');
  const result = await socialGuard(env, post.accountId, reserve ? '/begin' : '/read', { key, owner: env.__SOCIAL_OWNER });
  if (result?.state === 'pending') {
    const error = new Error('Результат предыдущей загрузки ' + (platform === 'instagram' ? 'Instagram' : 'YouTube') + ' не подтверждён. Повтор остановлен до проверки');
    error.code = platform === 'instagram' ? 'ERR_IG_PUBLICATION_UNCONFIRMED' : 'ERR_YT_PUBLICATION_UNCONFIRMED';
    error.instagramReviewReason = 'upload_unconfirmed';
    throw error;
  }
  return { key, result };
}

export async function completeSocialWrite(env, post, write, id) {
  await socialGuard(env, post.accountId, '/complete', { key: write.key, owner: env.__SOCIAL_OWNER, value: { id } });
}

export async function abandonSocialWrite(env, post, write) {
  await socialGuard(env, post.accountId, '/abandon', { key: write.key, owner: env.__SOCIAL_OWNER });
}

export async function withSocialPublicationLease(env, accountId, run) {
  if (env.__SOCIAL_OWNER) return run(env);
  const lease = await socialGuard(env, accountId, '/claim');
  if (lease?.busy) return { status: 'processing', message: 'Публикация этого аккаунта уже выполняется' };
  try { return await run(lease ? { ...env, __SOCIAL_OWNER: lease.owner } : env); }
  finally {
    if (lease) {
      try { await socialGuard(env, accountId, '/release', { owner: lease.owner }); }
      catch (_) { console.warn('Social publication lease release deferred'); }
    }
  }
}
