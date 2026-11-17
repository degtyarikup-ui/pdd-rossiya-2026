import { ReviewStores, STORE_NAMES, REPLY_LIMITS } from './review_stores.js';
import { telegramChatId } from './telegram_queue.js';
import { telegramWebhookSecret } from './telegram_auth.js';

const escape = value => String(value ?? '').replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
function excerpt(value, limit) {
  let result = '';
  for (const char of String(value ?? '')) { const next = escape(char); if (result.length + next.length > limit) return result + '…'; result += next; }
  return result;
}
const statusName = status => ({ PUBLISHED: 'Опубликован', MODERATION: 'На модерации', PENDING_PUBLISH: 'Ожидает публикации', REJECTED: 'Отклонён магазином', DELETED: 'Удалён' }[status] || status || '');
export async function reviewHash(value) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))].map(x => x.toString(16).padStart(2, '0')).join('').slice(0, 24);
}
export const reviewVersion = r => JSON.stringify([r.text, r.rating, r.date]);
export function reviewCard(r, changed = false) {
  return [`<b>${changed ? 'Обновлённый отзыв' : 'Отзыв'} · ${STORE_NAMES[r.store]} · ПДД Россия</b>`,
    '⭐'.repeat(Math.min(5, Math.max(0, Number(r.rating) || 0))),
    `<b>${excerpt(r.author || 'Аноним', 150)}</b> · ${escape(String(r.date || '').slice(0, 10))}${r.version ? ' · версия ' + excerpt(r.version, 60) : ''}`,
    '', excerpt(r.text, 2100), '', r.response ? `<b>Наш ответ:</b> ${excerpt(r.response, 600)}` : '<b>Пока без ответа</b>',
    r.responseStatus ? escape(statusName(r.responseStatus)) : '', '',
    'Чтобы ответить, используйте «Ответить» на это сообщение. Бот покажет предпросмотр и попросит подтвердить публикацию.'
  ].filter(x => x !== null).join('\n');
}
function stub(env) { return env.STORE_REVIEWS?.get(env.STORE_REVIEWS.idFromName('pdd-russia')); }
export async function pollStoreReviews(env) {
  if (!env.STORE_REVIEW_CREDENTIALS || !env.STORE_REVIEWS_ENABLED) return;
  const response = await stub(env)?.fetch('https://reviews/poll', { method: 'POST' });
  if (response && !response.ok) throw new Error('store_reviews_poll_failed');
}
// Use the existing authenticated Telegram webhook and the existing polling
// fallback. A second webhook for the same bot would break support and login.
export async function handleStoreReviewUpdate(update, env) {
  if (!env.STORE_REVIEWS || !env.STORE_REVIEWS_ENABLED) return false;
  const message = update?.message;
  const callback = update?.callback_query;
  if (!callback?.data?.startsWith('rv:') && !message?.reply_to_message && !/^\/reviews(?:@\w+)?(?:\s|$)/.test(message?.text || '')) return false;
  const response = await stub(env).fetch('https://reviews/update', { method: 'POST', body: JSON.stringify(update) });
  if (!response.ok) throw new Error('store_reviews_update_failed');
  return Boolean((await response.json()).handled);
}
export async function storeReviewsAdmin(request, env, path) {
  if (!env.STORE_REVIEWS) return Response.json({ error: 'not_configured' }, { status: 503 });
  return stub(env).fetch('https://reviews/' + path, { method: request.method, ...(request.method === 'POST' ? { body: await request.text() } : {}) });
}

export class StoreReviews {
  constructor(state, env) {
    this.state = state; this.env = env; this.stores = new ReviewStores(env); this.tail = Promise.resolve();
  }
  serial(fn) { const p = this.tail.then(fn); this.tail = p.catch(() => {}); return p; }
  fetch(request) {
    return this.serial(async () => {
      const path = new URL(request.url).pathname;
      if (path === '/status') return Response.json({ topic: await this.state.storage.get('topic'), stores: await this.state.storage.get('stores') || {},
        queued: (await this.state.storage.list({ prefix: 'out:' })).size });
      if (path === '/setup') return Response.json(await this.setup());
      if (path === '/poll') { await this.poll(); return Response.json({ ok: true }); }
      if (path === '/update') return Response.json({ handled: await this.update(await request.json()) });
      return new Response('not found', { status: 404 });
    });
  }
  async tg(method, body) {
    const response = await fetch(`https://api.telegram.org/bot${this.env.BOT_TOKEN}/${method}`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ chat_id: telegramChatId(this.env), ...body }),
      signal: AbortSignal.timeout(12000),
    });
    const data = await response.json();
    if (!response.ok || !data.ok) {
      const e = new Error('telegram_' + (data.error_code || response.status)); e.retryAfter = data.parameters?.retry_after; throw e;
    }
    return data.result;
  }
  async say(text, extra = {}) {
    return this.tg('sendMessage', { message_thread_id: await this.state.storage.get('topic'), parse_mode: 'HTML', text, disable_web_page_preview: true, ...extra });
  }
  async setup() {
    let topic = await this.state.storage.get('topic');
    if (!topic) {
      const result = await this.tg('createForumTopic', { name: 'Отзывы', icon_color: 0xFFD67E });
      topic = result.message_thread_id;
      await this.state.storage.put('topic', topic);
      // Also register the ID for diagnostics and existing admin tooling.
      const saved = JSON.parse(await this.env.INSTALLS.get('telegram_topics') || '{}');
      await this.env.INSTALLS.put('telegram_topics', JSON.stringify({ ...saved, reviews: topic }));
      await this.say('<b>Отзывы ПДД Россия</b>\nЗдесь собираются отзывы App Store, Google Play и RuStore.\n\nОтветьте на карточку отзыва — появится предпросмотр с кнопкой «Опубликовать». Публиковать могут администраторы чата.\n\n/reviews — состояние подключения.');
    }
    if (!await this.state.storage.get('webhookReady')) {
      const info = await this.tg('getWebhookInfo', {});
      const url = info.url || 'https://pdd-install-notifier.sergei-pdd.workers.dev/api/telegram/webhook';
      if (!['https://pdd-install-notifier.sergei-pdd.workers.dev/api/telegram/webhook', 'https://api.pdd-drive.app/api/telegram/webhook'].includes(url)) throw new Error('unexpected_telegram_webhook');
      const secret = await telegramWebhookSecret(this.env);
      if (!secret) throw new Error('webhook_secret_required');
      await this.tg('setWebhook', { url, secret_token: secret, allowed_updates: ['message', 'callback_query'] });
      await this.state.storage.put('webhookReady', true);
    }
    return { ok: true, topic };
  }
  async wake(delay = 1000) {
    const at = Date.now() + delay; const old = await this.state.storage.getAlarm();
    if (!old || old > at) await this.state.storage.setAlarm(at);
  }
  async poll() {
    await this.setup();
    const statuses = await this.state.storage.get('stores') || {};
    for (const store of Object.keys(STORE_NAMES)) {
      const previous = statuses[store] || {};
      if (Date.now() - (previous.checkedAt || 0) < 9 * 60000) continue;
      let count = 0, added = 0;
      try {
        for await (const fetched of this.stores.list(store)) {
          const hash = await reviewHash(store + ':' + fetched.id);
          const old = await this.state.storage.get('r:' + hash);
          let review = { ...old, ...fetched, hash };
          // RuStore's list may omit an answer still awaiting moderation.
          if (old?.responseId && store === 'rustore' && ['MODERATION', 'PENDING_PUBLISH'].includes(old.responseStatus)) {
            review = { ...review, responseId: old.responseId, ...(await this.stores.status(old) || {}) };
          }
          const changed = old && reviewVersion(old) !== reviewVersion(review);
          const responseChanged = old && (old.response !== review.response || old.responseStatus !== review.responseStatus);
          const notify = !old || changed;
          await this.state.storage.put('r:' + hash, review);
          if (notify || responseChanged && old.cardMessage) {
            // Durable outbox. Mark delivery only once Telegram accepted it.
            await this.state.storage.put('out:' + hash, { hash, changed: Boolean(changed), refresh: !notify, at: Date.now() });
            added++;
          }
          count++;
        }
        statuses[store] = { ok: true, count, checkedAt: Date.now(), initialized: true, lastSuccess: Date.now() };
      } catch (error) {
        statuses[store] = { ...previous, ok: false, checkedAt: Date.now(), error: error.status ? 'HTTP ' + error.status : 'Ошибка соединения' };
        if (!previous.alertAt || Date.now() - previous.alertAt > 6 * 3600000) {
          await this.say(`⚠️ ${STORE_NAMES[store]}: не удалось обновить отзывы (${escape(statuses[store].error)}). Повторим проверку автоматически.`);
          statuses[store].alertAt = Date.now();
        } else statuses[store].alertAt = previous.alertAt;
      }
      await this.state.storage.put('stores', statuses);
      if (added) await this.wake();
    }
    // Recover successful but unacknowledged writes by reading the store. Never
    // issue a second public write from this reconciliation path.
    for (const [key, draft] of await this.state.storage.list({ prefix: 'd:' })) {
      if (!['publishing', 'unknown'].includes(draft.status) || Date.now() - draft.createdAt > 86400000) continue;
      try {
        const review = await this.state.storage.get('r:' + draft.hash);
        const fresh = await this.stores.get(review);
        if (fresh.response !== draft.text) continue;
        draft.status = 'published'; await this.state.storage.put(key, draft);
        await this.state.storage.put('r:' + draft.hash, { ...review, ...fresh });
        await this.finish(draft, `<b>Ответ найден в магазине · ${STORE_NAMES[review.store]}</b>\n${excerpt(draft.text, 3200)}`);
      } catch { /* Retry read-only reconciliation during the next poll. */ }
    }
  }
  async alarm() {
    return this.serial(async () => {
      const pending = await this.state.storage.list({ prefix: 'out:', limit: 1 });
      for (const [key, item] of pending) {
        try {
          const review = await this.state.storage.get('r:' + item.hash);
          if (item.refresh && review.cardMessage) {
            try { await this.tg('editMessageText', { message_id: review.cardMessage, text: reviewCard(review), parse_mode: 'HTML' }); }
            catch (error) { if (error.message !== 'telegram_400') throw error; }
          } else {
            const sent = await this.say(reviewCard(review, item.changed));
            review.cardMessage = sent.message_id;
            await this.state.storage.put('r:' + item.hash, review);
            await this.state.storage.put('m:' + sent.message_id, item.hash);
          }
          await this.state.storage.delete(key);
        } catch (e) { await this.wake(Math.max(30000, Number(e.retryAfter || 0) * 1000)); return; }
      }
      if ((await this.state.storage.list({ prefix: 'out:', limit: 1 })).size) await this.wake(3500);
      // Bound draft storage; expiry also checked at confirmation time.
      const drafts = await this.state.storage.list({ prefix: 'd:' });
      for (const [key, d] of drafts) if (Date.now() - d.createdAt > 7 * 86400000) await this.state.storage.delete(key);
      for (const [key, at] of await this.state.storage.list({ prefix: 'u:' })) if (Date.now() - at > 7 * 86400000) await this.state.storage.delete(key);
    });
  }
  async isAdmin(from) {
    if (!from?.id || from.is_bot) return false;
    const user = await this.tg('getChatMember', { user_id: from.id });
    return ['creator', 'administrator'].includes(user.status);
  }
  async update(update) {
    const callback = update?.callback_query, message = callback?.message || update?.message;
    const topic = await this.state.storage.get('topic');
    if (!topic || String(message?.chat?.id) !== telegramChatId(this.env) || message?.message_thread_id !== topic) return false;
    const from = callback?.from || message.from;
    if (!await this.isAdmin(from)) {
      if (callback) await this.answer(callback, 'Публиковать могут только администраторы чата.');
      else await this.say('Публиковать ответы могут только администраторы чата.');
      return true;
    }
    if (callback) return this.confirm(callback);
    if (/^\/reviews(?:@\w+)?(?:\s|$)/.test(message.text || '')) {
      const statuses = await this.state.storage.get('stores') || {};
      await this.say('<b>Подключение магазинов</b>\n' + Object.keys(STORE_NAMES).map(s => {
        const x = statuses[s]; return `${x?.ok ? '✅' : '⚠️'} ${STORE_NAMES[s]}: ${x ? x.ok ? `отзывов получено: ${x.count}` : x.error : 'ожидание первой проверки'}${x?.lastSuccess ? ' · ' + new Date(x.lastSuccess).toLocaleString('ru-RU', { timeZone: 'Europe/Moscow' }) : ''}`;
      }).join('\n') + '\n\nПроверка каждые 10 минут. Ответьте текстом на карточку отзыва.');
      return true;
    }
    const hash = await this.state.storage.get('m:' + message.reply_to_message?.message_id);
    if (!hash) return false;
    if (await this.state.storage.get('u:' + update.update_id)) return true;
    const review = await this.state.storage.get('r:' + hash);
    const text = message.text?.trim(); const limit = REPLY_LIMITS[review.store];
    if (!text || text.length > limit) {
      await this.say(`Нужен текстовый ответ от 1 до ${limit} символов для ${STORE_NAMES[review.store]}.`, { reply_parameters: { message_id: message.message_id } }); return true;
    }
    const id = crypto.randomUUID().replace(/-/g, '').slice(0, 24);
    const draft = { id, hash, text, author: from.id, createdAt: Date.now(), version: reviewVersion(review), previousResponse: review.response, status: 'draft' };
    await this.state.storage.put('d:' + id, draft);
    await this.state.storage.put('u:' + update.update_id, Date.now());
    const preview = await this.say(`Предпросмотр · ${STORE_NAMES[review.store]}\nОтзыв: ${(review.author || 'Аноним').slice(0, 100)} · ${review.rating}⭐\n\n${text}\n\n${review.response ? 'Этот текст заменит текущий ответ.' : 'Ответ будет публичным от имени разработчика.'}\nПодтвердить может автор этого ответа. Черновик действует 24 часа.`, {
      parse_mode: undefined,
      reply_parameters: { message_id: review.cardMessage }, reply_markup: { inline_keyboard: [[
        { text: 'Опубликовать', callback_data: 'rv:p:' + id }, { text: 'Отменить', callback_data: 'rv:x:' + id },
      ]] },
    });
    draft.previewMessage = preview.message_id;
    await this.state.storage.put('d:' + id, draft);
    await this.wake();
    return true;
  }
  async answer(callback, text) {
    return this.tg('answerCallbackQuery', { callback_query_id: callback.id, text, show_alert: false });
  }
  async finish(draft, text) {
    await this.tg('editMessageText', { message_id: draft.previewMessage, text, parse_mode: 'HTML', reply_markup: { inline_keyboard: [] } });
  }
  async confirm(callback) {
    const match = /^rv:([px]):([a-f0-9]{24})$/.exec(callback.data || '');
    if (!match) { await this.answer(callback, 'Неизвестное действие.'); return true; }
    const draft = await this.state.storage.get('d:' + match[2]);
    if (!draft || draft.author !== callback.from.id || draft.previewMessage !== callback.message.message_id) {
      await this.answer(callback, 'Подтвердить может только автор этого ответа.'); return true;
    }
    if (draft.status !== 'draft') { await this.answer(callback, 'Этот черновик уже обработан. Повторной отправки не будет.'); return true; }
    if (Date.now() - draft.createdAt > 86400000) { draft.status = 'expired'; await this.state.storage.put('d:' + draft.id, draft); await this.answer(callback, 'Черновик устарел. Ответьте на карточку заново.'); return true; }
    if (match[1] === 'x') {
      draft.status = 'cancelled'; await this.state.storage.put('d:' + draft.id, draft);
      await this.answer(callback, 'Публикация отменена.'); await this.finish(draft, 'Ответ отменён. В магазин ничего не отправлено.'); return true;
    }
    await this.answer(callback, 'Проверяю отзыв и отправляю ответ…');
    let review = await this.state.storage.get('r:' + draft.hash);
    let fresh;
    try { fresh = await this.stores.get(review); }
    catch { await this.say('Не удалось проверить актуальность отзыва. Ответ не отправлен. Попробуйте подтвердить позже.'); return true; }
    // Protect a RuStore answer awaiting moderation from an empty list response.
    if (reviewVersion(fresh) !== draft.version || fresh.response !== draft.previousResponse) {
      draft.status = 'stale'; await this.state.storage.put('d:' + draft.id, draft);
      review = { ...review, ...fresh }; await this.state.storage.put('r:' + draft.hash, review);
      await this.state.storage.put('out:' + draft.hash, { hash: draft.hash, changed: true }); await this.wake();
      await this.finish(draft, 'Отзыв или ответ изменился после создания черновика. Публикация остановлена. Проверьте обновлённую карточку и ответьте заново.'); return true;
    }
    // Persist intent before the public write. Never blindly retry a timed-out
    // write: reconcile by reading the actual response after an ambiguous result.
    draft.status = 'publishing'; await this.state.storage.put('d:' + draft.id, draft);
    try {
      const result = await this.stores.publish({ ...review, ...fresh }, draft.text);
      const status = await this.stores.replyStatus(review, result);
      review = { ...review, ...status, response: draft.text };
      await this.state.storage.put('r:' + draft.hash, review);
      draft.status = 'published'; await this.state.storage.put('d:' + draft.id, draft);
      await this.state.storage.put('out:' + draft.hash, { hash: draft.hash, refresh: true }); await this.wake();
      await this.finish(draft, `<b>Ответ принят · ${STORE_NAMES[review.store]}</b>\n${escape(statusName(review.responseStatus))}\n\n${excerpt(draft.text, 3200)}`);
    } catch (error) {
      if (draft.status === 'published') return true; // Telegram failure after successful write.
      draft.status = error.status >= 400 && error.status < 500 && ![408, 429].includes(error.status) ? 'failed' : 'unknown';
      await this.state.storage.put('d:' + draft.id, draft);
      await this.finish(draft, draft.status === 'failed' ? `Магазин отклонил ответ (HTTP ${error.status}). Исправьте текст или доступ и создайте новый черновик.`
        : 'Результат отправки пока неизвестен. Автоматически повторять публикацию не будем. Проверьте ответ в магазине перед новой отправкой.');
    }
    return true;
  }
}
