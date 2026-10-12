// The support messages of one client, strongly consistent: a reply written by the Telegram
// webhook is read at once by the app. Workers KV is eventually consistent (a write may be
// read from another location up to a minute later), so the messages are kept here.
const MAX_MESSAGES = 200;

export class SupportThread {
  constructor(state) { this.state = state; }

  async fetch(request) {
    const url = new URL(request.url);
    if (request.method === 'POST' && url.pathname === '/append') {
      const msg = await request.json();
      if (!msg || typeof msg.id !== 'string' || typeof msg.ts !== 'number') {
        return new Response(null, { status: 400 });
      }
      await this.state.storage.transaction(async (txn) => {
        const msgs = (await txn.get('messages')) || [];
        if (!msgs.some((m) => m.id === msg.id)) {
          msgs.push(msg);
          if (msgs.length > MAX_MESSAGES) msgs.splice(0, msgs.length - MAX_MESSAGES);
          await txn.put('messages', msgs);
        }
      });
      return Response.json({ ok: true });
    }
    if (request.method === 'POST' && url.pathname === '/seed') {
      // One-time copy of the messages kept in KV before this object existed.
      const legacy = await request.json();
      await this.state.storage.transaction(async (txn) => {
        const msgs = (await txn.get('messages')) || [];
        if (msgs.length === 0 && Array.isArray(legacy)) {
          await txn.put('messages', legacy.slice(-MAX_MESSAGES));
        }
      });
      return Response.json({ ok: true });
    }
    if (request.method === 'GET' && url.pathname === '/list') {
      const since = Number(url.searchParams.get('since') || 0);
      const msgs = (await this.state.storage.get('messages')) || [];
      return Response.json({ ok: true, messages: since > 0 ? msgs.filter((m) => m.ts > since) : msgs });
    }
    return new Response(null, { status: 404 });
  }
}
