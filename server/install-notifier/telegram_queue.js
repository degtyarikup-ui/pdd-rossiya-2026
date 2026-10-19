import { processTelegramMessageUpdate } from './support_chat.js';
import { isReportPhotoUrl } from './report_questions.js';
import { buildIncidentMessage } from './diagnostics.js';
import { setupTelegramTopics } from './telegram_topics.js';
import { EXPORT_COMMAND_MAX_AGE_MS, buildErrorCsv, errorLevelLabel, errorLogKey, errorLogRecord, exportStart, mskStamp, parseExportCommand, ERROR_LOG_PREFIX } from './telegram_export.js';

export function telegramChatId(env) {
  const id = env?.CHAT_ID ? String(env.CHAT_ID) : '';
  if (id === '-5556420560') return '-1004472386966';
  return id;
}

export function resolveTopicThreadId(env, topic) {
  if (!topic) return null;
  const key = 'TELEGRAM_TOPIC_' + String(topic).toUpperCase();
  const altKey = 'TG_TOPIC_' + String(topic).toUpperCase();
  const val = env?.[key] ?? env?.[altKey];
  if (val !== undefined && val !== null && val !== '') {
    const num = Number(val);
    if (Number.isInteger(num) && num > 0) return num;
  }
  return null;
}

export async function getTopicThreadId(env, topic, fallback = null) {
  if (!topic) return fallback;
  const fromEnv = resolveTopicThreadId(env, topic);
  if (fromEnv) return fromEnv;
  if (env?.INSTALLS) {
    try {
      const raw = await env.INSTALLS.get('telegram_topics');
      if (raw) {
        const map = typeof raw === 'string' ? JSON.parse(raw) : raw;
        const val = map?.[topic];
        const num = Number(val);
        if (Number.isInteger(num) && num > 0) return num;
      }
    } catch (_) {}
  }
  return fallback;
}

// Резервный опрос без webhook. Тот же экземпляр очереди, что и у алертов:
// журнал и отправка идут через одну сериализованную очередь.
export async function pollErrorCommands(env) {
  if (!env?.TELEGRAM || !env.BOT_TOKEN || !env.CHAT_ID) return null;
  const stub = env.TELEGRAM.get(env.TELEGRAM.idFromName(String(env.CHAT_ID)));
  const response = await stub.fetch('https://telegram/poll-commands', { method: 'POST' });
  return response.ok ? response.json() : null;
}

// Webhook and polling share the log-owning DO and its serial command handler.
export async function handleErrorExportUpdate(env, update) {
  if (!env?.TELEGRAM || !parseExportCommand(update?.message?.text)) return false;
  // Keep the storage identity used by diagnostics, including pre-migration
  // group IDs. Only the outgoing Telegram destination is normalized.
  const stub = env.TELEGRAM.get(env.TELEGRAM.idFromName(String(env.CHAT_ID)));
  const response = await stub.fetch('https://telegram/export-command', {
    method: 'POST', body: JSON.stringify(update),
  });
  if (!response.ok) throw new Error('error export unavailable');
  return Boolean((await response.json()).handled);
}

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
      if (new URL(request.url).pathname === '/incident') return this.enqueueIncident(await request.json());
      if (new URL(request.url).pathname === '/export-command') return Response.json({ handled: await this.handleExportUpdate(await request.json()) });
      if (new URL(request.url).pathname === '/poll-commands') return Response.json(await this.pollErrorCommands());
      if (new URL(request.url).pathname === '/setup-topics') {
        return setupTelegramTopics(request, this.env, (_env, text, dedupKey, options) => this.enqueue({ text, dedupKey, ...options }));
      }
      return this.enqueue(await request.json());
    });
  }
  async enqueue(body) {
    const { text, dedupKey, photoBase64, messages, topic } = body;
    const explicitThreadId = body.threadId ?? body.message_thread_id;
    const resolvedThreadId = explicitThreadId ? Number(explicitThreadId) : await getTopicThreadId(this.env, topic);
    const items = messages || [{ text, ...(photoBase64 ? { photoBase64 } : {}) }];
    if (!Array.isArray(items) || items.length < 1 || items.length > 2 || items.some(item =>
      typeof item.text !== 'string' || !item.text || item.text.length > (item.photoBase64 || item.photoUrl ? 1024 : 4096) ||
      (item.photoUrl !== undefined && !isReportPhotoUrl(item.photoUrl)) ||
      (item.photoUrl && item.photoBase64) ||
      (item.photoBase64 && (typeof item.photoBase64 !== 'string' || item.photoBase64.length > 100000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(item.photoBase64)))
    )) return new Response('invalid message', { status: 400 });
    if (!this.env.BOT_TOKEN || !this.env.CHAT_ID) return new Response('not configured', { status: 503 });
    if (dedupKey && await this.state.storage.get('seen:' + dedupKey)) return Response.json({ ok: true, duplicate: true });
    if (!(await this.state.storage.getAlarm())) await this.state.storage.setAlarm(Date.now() + 1000);
    const sequence = (await this.state.storage.get('sequence') || 0) + 1;
    await this.state.storage.transaction(async txn => {
      for (let i=0; i<items.length; i++) {
        const itemThreadId = items[i].threadId ?? items[i].message_thread_id ?? resolvedThreadId;
        await txn.put('q:' + String(sequence+i).padStart(16, '0'), {
          text: items[i].text,
          ...(items[i].photoBase64 ? { photoBase64: items[i].photoBase64 } : {}),
          ...(items[i].photoUrl ? { photoUrl: items[i].photoUrl } : {}),
          ...(itemThreadId ? { threadId: Number(itemThreadId) } : {})
        });
      }
      await txn.put('sequence', sequence+items.length-1);
      if (dedupKey) await txn.put('seen:' + dedupKey, Date.now());
    });
    return Response.json({ ok: true, queued: true });
  }
  async enqueueIncident({ incident, fingerprint }) {
    if (!incident || !/^[a-f0-9]{64}$/.test(fingerprint || '')) return new Response('invalid incident', { status: 400 });
    if (!this.env.BOT_TOKEN || !this.env.CHAT_ID) return new Response('not configured', { status: 503 });
    const threadId = await getTopicThreadId(this.env, 'errors');
    const now = Date.now(), windowMs = 10 * 60000;
    const stored = await this.state.storage.get('errors:state') || { recent: [], groups: {}, window: now, count: 0, overflow: 0 };
    stored.recent = stored.recent.filter(item => now - item.at < 86400000);
    if (stored.recent.some(item => item.id === incident.id)) return Response.json({ ok: true, duplicate: true });
    stored.recent.push({ id: incident.id, at: now });
    stored.recent = stored.recent.slice(-2000);
    for (const [key, group] of Object.entries(stored.groups)) if (now - group.at >= 86400000) delete stored.groups[key];
    const group = stored.groups[fingerprint];
    if (now - stored.window >= windowMs) { stored.window = now; stored.count = 0; }
    let text = null;
    if (group && now - group.at < windowMs) group.repeats++;
    else if (stored.count >= 20) stored.overflow++;
    else {
      stored.count++;
      stored.groups[fingerprint] = { at: now, repeats: 0 };
      text = buildIncidentMessage(incident, group?.repeats || 0, stored.overflow);
      stored.overflow = 0;
    }
    if (text && !(await this.state.storage.getAlarm())) await this.state.storage.setAlarm(now + 1000);
    await this.state.storage.transaction(async txn => {
      await txn.put('errors:state', stored);
      if (text) {
        const sequence = (await txn.get('sequence') || 0) + 1;
        await txn.put('q:' + String(sequence).padStart(16, '0'), { text, ...(threadId ? { threadId: Number(threadId) } : {}) });
        await txn.put('sequence', sequence);
      }
    });
    await this.logIncident(incident, Boolean(text), now);
    return Response.json({ ok: true, suppressed: !text });
  }
  // Журнал для выгрузки. Запись после очереди и в отдельном try: сбой журнала
  // не должен терять уведомление или менять ответ.
  async logIncident(incident, sent, now) {
    try {
      const ts = Number.isFinite(incident.ts) ? incident.ts : now;
      const record = errorLogRecord(incident, { ts, sent, level: errorLevelLabel(incident) });
      await this.state.storage.put(errorLogKey(ts, record.id || now), record);
    } catch (error) {
      console.error('Error log write failed', error?.name || 'unknown');
    }
  }
  // Webhook is the primary path. Poll only when Telegram has no webhook;
  // support messages must go through this same consumer, never a second offset.
  async pollErrorCommands() {
    if (!this.env.BOT_TOKEN || !this.env.CHAT_ID) return { ok: false, reason: 'not configured' };
    try {
      const infoResponse = await fetch(`https://api.telegram.org/bot${this.env.BOT_TOKEN}/getWebhookInfo`, {
        signal: AbortSignal.timeout(10000),
      });
      const info = await infoResponse.json().catch(() => null);
      if (!infoResponse.ok || !info?.ok) return { ok: false, status: infoResponse.status };
      if (info.result?.url) return { ok: true, webhook: true };
      const offset = (await this.state.storage.get('tg:offset')) || 0;
      const response = await fetch(`https://api.telegram.org/bot${this.env.BOT_TOKEN}/getUpdates`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ offset, timeout: 0, limit: 50, allowed_updates: ['message'] }),
        signal: AbortSignal.timeout(10000),
      });
      const result = await response.json().catch(() => null);
      if (!response.ok || !result?.ok || !Array.isArray(result.result)) return { ok: false, status: response.status };
      let handled = 0;
      for (const update of result.result) {
        if (await this.handleExportUpdate(update)) handled++;
        else await processTelegramMessageUpdate(update.message, this.env);
        // A failed export leaves the offset unchanged so the command can retry.
        await this.state.storage.put('tg:offset', update.update_id + 1);
      }
      return { ok: true, updates: result.result.length, handled };
    } catch (error) {
      console.error('Telegram command poll failed', error?.name || 'unknown');
      return { ok: false, reason: 'poll failed' };
    }
  }
  async handleExportUpdate(update) {
    if (!Number.isSafeInteger(update?.update_id) || update.update_id < 0) return false;
    const completed = await this.state.storage.get('export:completed') || [];
    if (completed.includes(update.update_id)) return true;
    const handled = await this.handleErrorCommand(update.message);
    if (handled) await this.state.storage.put('export:completed', [...completed.slice(-127), update.update_id]);
    return handled;
  }
  async handleErrorCommand(message) {
    const mode = parseExportCommand(message?.text);
    if (!mode || message.from?.is_bot || String(message.chat?.id) !== telegramChatId(this.env)) return false;
    const now = Date.now();
    if (now - Number(message.date || 0) * 1000 > EXPORT_COMMAND_MAX_AGE_MS) return false;
    const errorsThread = await getTopicThreadId(this.env, 'errors');
    const replyThread = message.message_thread_id;
    if (mode === 'help' || !errorsThread || Number(replyThread) !== errorsThread) {
      const text = mode === 'help'
        ? 'Выгрузка журнала ошибок:\n/export_day — за последние сутки\n/export_all — за всё время работы журнала (раньше записей нет)\nКоманды работают в подчате «Ошибки и падения».'
        : 'Выгрузка работает в подчате «Ошибки и падения».';
      await this.sendBotMessage(replyThread, text);
      return true;
    }
    const records = await this.readErrorLog(exportStart(mode, now));
    if (!records.length) {
      await this.sendBotMessage(errorsThread, mode === 'day'
        ? 'За последние сутки записей об ошибках нет.'
        : 'Записей об ошибках пока нет.');
      return true;
    }
    const first = records.reduce((min, record) => Math.min(min, record.ts), Infinity);
    const label = mode === 'day' ? 'за последние сутки' : 'за всё время';
    const caption = `Журнал ошибок ${label}: записей ${records.length}.` + (mode === 'all' ? ` Самая ранняя запись: ${mskStamp(first).slice(0, 10)}.` : '');
    const fileName = `pdd-errors-${mode === 'day' ? 'sutki' : 'vse'}-${new Date(now + 3 * 3600000).toISOString().slice(0, 10)}.csv`;
    await this.sendBotDocument(errorsThread, fileName, buildErrorCsv(records.sort((a, b) => a.ts - b.ts)), caption);
    return true;
  }
  // Записи читаются страницами: за всё время их может накопиться много.
  async readErrorLog(since) {
    const records = [];
    let start = ERROR_LOG_PREFIX + String(since).padStart(15, '0');
    for (;;) {
      const page = await this.state.storage.list({ prefix: ERROR_LOG_PREFIX, start, limit: 1000 });
      if (!page.size) break;
      for (const value of page.values()) records.push(value);
      start = [...page.keys()].pop() + '\u0000';
    }
    return records;
  }
  async sendBotMessage(threadId, text) {
    const payload = { chat_id: telegramChatId(this.env), text, disable_web_page_preview: true };
    if (threadId) payload.message_thread_id = Number(threadId);
    const response = await fetch(`https://api.telegram.org/bot${this.env.BOT_TOKEN}/sendMessage`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload), signal: AbortSignal.timeout(10000),
    });
    const result = await response.json().catch(() => null);
    if (!response.ok || !result?.ok) throw new Error('error export message failed');
  }
  async sendBotDocument(threadId, fileName, csv, caption) {
    const body = new FormData();
    body.set('chat_id', telegramChatId(this.env));
    body.set('message_thread_id', String(threadId));
    body.set('caption', caption);
    body.set('document', new Blob([csv], { type: 'text/csv' }), fileName);
    const response = await fetch(`https://api.telegram.org/bot${this.env.BOT_TOKEN}/sendDocument`, {
      method: 'POST', body, signal: AbortSignal.timeout(30000),
    });
    const result = await response.json().catch(() => null);
    if (!response.ok || !result?.ok) throw new Error('error export upload failed');
  }
  alarm() {
    return this.serial(async () => {
      const entries = await this.state.storage.list({ prefix: 'q:', limit: 1 });
      if (!entries.size) return;
      const [key, item] = entries.entries().next().value;
      let delay = 3100;
      try {
        let body, headers = {}, method = 'sendMessage';
        const chatId = telegramChatId(this.env);
        const threadId = item.threadId ?? item.message_thread_id;
        if (item.photoBase64) {
          method = 'sendPhoto';
          body = new FormData();
          body.set('chat_id', chatId);
          if (threadId) body.set('message_thread_id', String(threadId));
          body.set('caption', item.text);
          body.set('parse_mode', 'HTML');
          body.set('photo', new Blob([Uint8Array.from(atob(item.photoBase64), c => c.charCodeAt(0))], { type: 'image/png' }), 'pdd-daily.png');
        } else if (item.photoUrl) {
          method = 'sendPhoto';
          headers = { 'content-type': 'application/json' };
          body = JSON.stringify({ chat_id: chatId, photo: item.photoUrl, caption: item.text,
            parse_mode: 'HTML', ...(threadId ? { message_thread_id: Number(threadId) } : {}) });
        } else {
          headers = { 'content-type': 'application/json' };
          const payload = { chat_id: chatId, text: item.text, parse_mode: 'HTML', disable_web_page_preview: true };
          if (threadId) payload.message_thread_id = Number(threadId);
          body = JSON.stringify(payload);
        }
        const response = await fetch(`https://api.telegram.org/bot${this.env.BOT_TOKEN}/${method}`, {
          method: 'POST', headers, body,
          signal: AbortSignal.timeout(10000),
        });
        const result = await response.json();
        if (response.ok && result.ok) await this.state.storage.delete(key);
        else if (response.status === 429) delay = Math.max(delay, (Number(result.parameters?.retry_after) || 60) * 1000 + 1000);
        else if (response.status === 400 && threadId && (result.description?.includes('thread') || result.description?.includes('topic'))) {
          // If the topic was deleted or threadId is invalid in Telegram, retry once without topic so notification is never lost!
          delete item.threadId;
          delete item.message_thread_id;
          await this.state.storage.put(key, item);
        } else if (response.status === 400 && (item.photoBase64 || item.photoUrl)) {
          // Preserve the report even if Telegram rejects an image.
          await this.state.storage.put(key, { text: item.photoUrl ? `${item.text}\n${item.photoUrl}` : item.text, ...(threadId ? { threadId: Number(threadId) } : {}) });
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
