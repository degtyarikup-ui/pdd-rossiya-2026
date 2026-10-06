// Persist before acknowledging a notification. One chat is drained at a
// conservative group-safe rate; Telegram retry_after survives worker restarts.
export class TelegramQueue {
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
      const { text, dedupKey, photoBase64, messages } = await request.json();
      const items = messages || [{ text, ...(photoBase64 ? { photoBase64 } : {}) }];
      if (!Array.isArray(items) || items.length < 1 || items.length > 2 || items.some(item =>
        typeof item.text !== 'string' || !item.text || item.text.length > (item.photoBase64 ? 1024 : 4096) ||
        (item.photoBase64 && (typeof item.photoBase64 !== 'string' || item.photoBase64.length > 100000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(item.photoBase64)))
      )) return new Response('invalid message', { status: 400 });
      if (!this.env.BOT_TOKEN || !this.env.CHAT_ID) return new Response('not configured', { status: 503 });
      if (dedupKey && await this.state.storage.get('seen:' + dedupKey)) return Response.json({ ok: true, duplicate: true });
      if (!(await this.state.storage.getAlarm())) await this.state.storage.setAlarm(Date.now() + 1000);
      const sequence = (await this.state.storage.get('sequence') || 0) + 1;
      await this.state.storage.transaction(async txn => {
        for (let i=0; i<items.length; i++) await txn.put('q:' + String(sequence+i).padStart(16, '0'), { text: items[i].text, ...(items[i].photoBase64 ? { photoBase64: items[i].photoBase64 } : {}) });
        await txn.put('sequence', sequence+items.length-1);
        if (dedupKey) await txn.put('seen:' + dedupKey, Date.now());
      });
      return Response.json({ ok: true, queued: true });
    });
  }
  alarm() {
    return this.serial(async () => {
      const entries = await this.state.storage.list({ prefix: 'q:', limit: 1 });
      if (!entries.size) return;
      const [key, item] = entries.entries().next().value;
      let delay = 3100;
      try {
        let body, headers = {}, method = 'sendMessage';
        if (item.photoBase64) {
          method = 'sendPhoto';
          body = new FormData();
          body.set('chat_id', this.env.CHAT_ID); body.set('caption', item.text); body.set('parse_mode', 'HTML');
          body.set('photo', new Blob([Uint8Array.from(atob(item.photoBase64), c => c.charCodeAt(0))], { type: 'image/png' }), 'pdd-daily.png');
        } else {
          headers = { 'content-type': 'application/json' };
          body = JSON.stringify({ chat_id: this.env.CHAT_ID, text: item.text, parse_mode: 'HTML', disable_web_page_preview: true });
        }
        const response = await fetch(`https://api.telegram.org/bot${this.env.BOT_TOKEN}/${method}`, {
          method: 'POST', headers, body,
          signal: AbortSignal.timeout(10000),
        });
        const result = await response.json();
        if (response.ok && result.ok) await this.state.storage.delete(key);
        else if (response.status === 429) delay = Math.max(delay, (Number(result.parameters?.retry_after) || 60) * 1000 + 1000);
        else if (response.status === 400 && item.photoBase64) {
          // Preserve the report even if Telegram rejects an image.
          await this.state.storage.put(key, { text: item.text });
        } else if (response.status === 400) {
          // A malformed message must not block purchases/reports behind it.
          await this.state.storage.put('failed:' + key, { ...item, status: 400, at: Date.now() });
          await this.state.storage.delete(key);
          console.error('Telegram message quarantined', key);
        } else delay = 60000;
      } catch (_) { delay = 60000; }
      if ((await this.state.storage.list({ prefix: 'q:', limit: 1 })).size) {
        await this.state.storage.setAlarm(Date.now() + delay);
      }
    });
  }
}
