// Durable Object «буфер статистики».
//
// Принимает события аналитики от воркера (POST /enqueue), складывает их в
// своё хранилище и раз в FLUSH_MS применяет к KV одной пачкой через
// flushBufferedStats из worker.js. Смысл — уложиться в бесплатный лимит KV
// (1000 записей в сутки): вместо 4–5 put на каждый просмотр страницы
// получается несколько put на десять минут, сколько бы людей ни зашло.
//
// POST /flush — сбросить буфер немедленно (перед отчётом в Telegram).
//
// Класс намеренно не наследует DurableObject из 'cloudflare:workers', чтобы
// worker.js по-прежнему импортировался в локальных тестах под Node.

import { flushBufferedStats } from './worker.js';

const FLUSH_MS = 10 * 60 * 1000;
const RETRY_MS = 5 * 60 * 1000;
// Предохранитель: старше этого события не копим, чтобы хранилище не росло
// бесконечно, если KV долго недоступен (например, лимит уже исчерпан).
const MAX_QUEUE = 20000;
const DELETE_CHUNK = 128;

export class StatsBuffer {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (request.method !== 'POST') return new Response('not found', { status: 404 });

    if (url.pathname === '/enqueue') {
      let item;
      try { item = await request.json(); } catch (_) {
        return new Response('bad json', { status: 400 });
      }
      // Ключ с временем и случайным хвостом: события ложатся по порядку,
      // а одновременные запросы не затирают друг друга.
      const key = `q:${String(item.ts || Date.now()).padStart(13, '0')}:${Math.random().toString(36).slice(2, 8)}`;
      await this.state.storage.put(key, item);
      if ((await this.state.storage.getAlarm()) === null) {
        await this.state.storage.setAlarm(Date.now() + FLUSH_MS);
      }
      return new Response('ok');
    }

    if (url.pathname === '/flush') {
      await this.flush();
      return new Response('ok');
    }

    return new Response('not found', { status: 404 });
  }

  async alarm() {
    await this.flush();
  }

  async flush() {
    const entries = await this.state.storage.list({ prefix: 'q:' });
    if (!entries.size) return;

    const keys = [...entries.keys()];
    const items = [...entries.values()];

    try {
      await flushBufferedStats(this.env, items);
    } catch (e) {
      // KV не принял запись (например, 429 по лимиту) — события остаются в
      // хранилище, пробуем позже. Лишнее с головы очереди отбрасываем.
      console.error('StatsBuffer flush failed', e && e.message);
      if (keys.length > MAX_QUEUE) await this.deleteKeys(keys.slice(0, keys.length - MAX_QUEUE));
      await this.state.storage.setAlarm(Date.now() + RETRY_MS);
      return;
    }

    await this.deleteKeys(keys);
    // Пока шла запись, могли прийти новые события — им нужен свой будильник.
    const rest = await this.state.storage.list({ prefix: 'q:', limit: 1 });
    if (rest.size) await this.state.storage.setAlarm(Date.now() + FLUSH_MS);
  }

  async deleteKeys(keys) {
    for (let i = 0; i < keys.length; i += DELETE_CHUNK) {
      await this.state.storage.delete(keys.slice(i, i + DELETE_CHUNK));
    }
  }
}
