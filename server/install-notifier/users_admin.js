// API раздела «Пользователи» админки: список, подробная карточка, Premium на
// срок, заметка администратора, история действий, выход со всех устройств.
//
// Служебные данные админа (заметка и история) лежат отдельно, в ключе
// `user_admin:<id>`: профиль `user:<id>` приложение пересобирает при каждом
// входе (saveUserProfile) и лишние поля оттуда бы пропадали.

import { putUserRecord } from './user_store.js';

const DAY_MS = 86400000;
const MAX_DAYS = 3650;
const HISTORY_LIMIT = 50;
const NOTE_LIMIT = 2000;

export function isPremiumActive(user, now = Date.now()) {
  if (!user || !user.isPremium) return false;
  return !user.premiumExpiresAt || Date.parse(user.premiumExpiresAt) > now;
}

// Новый срок Premium. mode: 'extend' — прибавить к текущему сроку (если он ещё
// идёт), 'set' — отсчитать от сегодня. `until` — конкретная дата (YYYY-MM-DD,
// действует до конца дня по UTC). Возвращает ISO-строку или null (навсегда).
export function computePremiumExpiry(user, { days, until, isLifetime, mode } = {}, now = Date.now()) {
  if (isLifetime) return { expiresAt: null };
  if (until) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(until));
    if (!match) return { error: 'bad date' };
    const end = Date.UTC(+match[1], +match[2] - 1, +match[3], 23, 59, 59);
    if (!Number.isFinite(end) || end <= now) return { error: 'date must be in the future' };
    if (end - now > MAX_DAYS * DAY_MS) return { error: 'date too far' };
    return { expiresAt: new Date(end).toISOString() };
  }
  const count = Number.parseInt(days, 10);
  if (!Number.isFinite(count) || count < 1 || count > MAX_DAYS) return { error: 'days must be 1..' + MAX_DAYS };
  const current = user && user.isPremium && user.premiumExpiresAt ? Date.parse(user.premiumExpiresAt) : 0;
  const base = mode !== 'set' && current > now ? current : now;
  return { expiresAt: new Date(base + count * DAY_MS).toISOString() };
}

function num(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function parseExam(entry) {
  if (typeof entry === 'string') {
    try { return JSON.parse(entry); } catch (_) { return null; }
  }
  return entry && typeof entry === 'object' ? entry : null;
}

function summarizeCategory(progress, suffix) {
  const questions = Object.values(progress['questionProgress' + suffix] || {});
  const tickets = Object.values(progress['ticketProgress' + suffix] || {});
  const exams = (progress['examResults' + suffix] || []).map(parseExam).filter(Boolean);
  exams.sort((a, b) => Date.parse(b.completedAt || b.date || 0) - Date.parse(a.completedAt || a.date || 0));
  return {
    answered: questions.length,
    correct: questions.filter(q => q && q.isCorrect === true).length,
    ticketsStarted: tickets.length,
    ticketsSolved: tickets.filter(t => t && num(t.totalAnswered) > 0 && num(t.correctAnswers) === num(t.totalAnswered)).length,
    exams: exams.length,
    examsPassed: exams.filter(e => e.passed === true).length,
    recentExams: exams.slice(0, 8).map(e => ({
      ticketNumber: e.ticketNumber ?? null,
      correctAnswers: num(e.correctAnswers),
      wrongAnswers: num(e.wrongAnswers),
      passed: e.passed === true,
      completedAt: e.completedAt || e.date || null,
    })),
    favorites: (progress['favorites' + suffix] || []).length,
  };
}

// Сводка облачного прогресса для карточки — сам слепок бывает большим.
export function summarizeProgress(progress) {
  if (!progress || typeof progress !== 'object') return null;
  const streak = progress.streak || {};
  const game = progress.game || {};
  return {
    ab: summarizeCategory(progress, 'Ab'),
    cd: summarizeCategory(progress, 'Cd'),
    streak: {
      current: num(streak.current),
      longest: num(streak.longest),
      lastActiveDate: streak.lastActiveDate || null,
      activeDays: Array.isArray(streak.activeDays) ? streak.activeDays.slice(-60) : [],
    },
    game: {
      bestScore: num(game.bestScore),
      cars: Array.isArray(game.garageCars) ? game.garageCars.length : 0,
      vehicle: game.vehicle || null,
    },
    updatedAt: progress.updatedAt || null,
  };
}

async function readJson(env, key) {
  try {
    const raw = await env.INSTALLS.get(key);
    return raw ? JSON.parse(raw) : null;
  } catch (_) { return null; }
}

async function readAdminMeta(env, userId) {
  const meta = await readJson(env, 'user_admin:' + userId);
  return {
    note: meta && typeof meta.note === 'string' ? meta.note : '',
    noteUpdatedAt: meta?.noteUpdatedAt || null,
    history: Array.isArray(meta?.history) ? meta.history : [],
  };
}

async function writeAdminMeta(env, userId, meta, event) {
  if (event) meta.history = [{ at: new Date().toISOString(), ...event }, ...meta.history].slice(0, HISTORY_LIMIT);
  await env.INSTALLS.put('user_admin:' + userId, JSON.stringify(meta));
  return meta;
}

function adminUser(user) {
  if (!user) return null;
  const { pushToken, ...rest } = user;
  return { ...rest, hasPushToken: Boolean(pushToken), premiumActive: isPremiumActive(user) };
}

async function readBody(request) {
  try { return await request.json(); } catch (_) { return null; }
}

/**
 * Обрабатывает /api/admin/users*. Возвращает Response или null, если путь не
 * наш. Зависимости воркера передаются явно, чтобы модуль тестировался отдельно.
 */
export async function handleUsersAdmin(request, env, url, deps) {
  if (!url.pathname.startsWith('/api/admin/users')) return null;
  const { verifyAdminAuth, getAllUsers, revokeUserSessions, readGameBoard, gameWeekKey, jsonResponse } = deps;
  if (!await verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
  if (!env.INSTALLS) return jsonResponse({ error: 'storage unavailable' }, 503);
  const path = url.pathname;

  if (path === '/api/admin/users' && request.method === 'GET') {
    const users = await getAllUsers(env);
    return jsonResponse({ ok: true, users });
  }

  if (path === '/api/admin/users/detail' && request.method === 'GET') {
    const userId = String(url.searchParams.get('id') || '');
    const user = userId ? await readJson(env, 'user:' + userId) : null;
    if (!user) return jsonResponse({ error: 'user not found' }, 404);
    const [progress, meta] = await Promise.all([
      readJson(env, 'user_progress:' + userId),
      readAdminMeta(env, userId),
    ]);
    let weeklyGame = null;
    try {
      const board = await readGameBoard(env, gameWeekKey());
      if (board && board[userId]) weeklyGame = board[userId];
    } catch (_) {}
    return jsonResponse({ ok: true, user: adminUser(user), progress: summarizeProgress(progress), weeklyGame, admin: meta });
  }

  if (request.method !== 'POST') return jsonResponse({ error: 'not found' }, 404);
  const body = await readBody(request);
  if (!body) return jsonResponse({ error: 'bad json' }, 400);
  const userId = String(body.userId || '').trim();
  if (!userId) return jsonResponse({ error: 'missing userId' }, 400);

  if (path === '/api/admin/users/delete') {
    const user = await readJson(env, 'user:' + userId);
    await revokeUserSessions(env, userId);
    await env.INSTALLS.delete('user:' + userId);
    await env.INSTALLS.delete('user_progress:' + userId);
    await env.INSTALLS.delete('user_admin:' + userId);
    if (user?.email) await env.INSTALLS.delete('user_email:' + user.email.toLowerCase().trim());
    try {
      const week = gameWeekKey();
      const board = await readGameBoard(env, week);
      if (board && board[userId]) {
        delete board[userId];
        await env.INSTALLS.put('game_lb:' + week, JSON.stringify(board), { expirationTtl: 60 * 60 * 24 * 21 });
      }
    } catch (_) {}
    try {
      const list = await readJson(env, 'users_list');
      if (Array.isArray(list) && list.includes(userId)) {
        await env.INSTALLS.put('users_list', JSON.stringify(list.filter(id => id !== userId)));
      }
    } catch (_) {}
    return jsonResponse({ ok: true, deleted: userId });
  }

  const user = await readJson(env, 'user:' + userId);
  if (!user) return jsonResponse({ error: 'user not found' }, 404);
  const meta = await readAdminMeta(env, userId);

  if (path === '/api/admin/users/grant-premium') {
    const result = computePremiumExpiry(user, body);
    if (result.error) return jsonResponse({ error: result.error }, 400);
    const previous = isPremiumActive(user) ? (user.premiumExpiresAt || 'lifetime') : null;
    user.isPremium = true;
    user.premiumSource = 'admin_grant';
    user.grantedAt = new Date().toISOString();
    user.premiumExpiresAt = result.expiresAt;
    await putUserRecord(env, user);
    await writeAdminMeta(env, userId, meta, {
      action: 'grant',
      days: body.isLifetime || body.until ? null : Number.parseInt(body.days, 10),
      mode: body.isLifetime ? 'lifetime' : body.until ? 'until' : (body.mode === 'set' ? 'set' : 'extend'),
      from: previous,
      until: result.expiresAt,
      comment: typeof body.comment === 'string' ? body.comment.slice(0, 200) : undefined,
    });
    return jsonResponse({ ok: true, user: adminUser(user), admin: meta });
  }

  if (path === '/api/admin/users/revoke-premium') {
    const previous = isPremiumActive(user) ? (user.premiumExpiresAt || 'lifetime') : null;
    user.isPremium = false;
    user.premiumSource = null;
    user.premiumExpiresAt = null;
    await putUserRecord(env, user);
    await writeAdminMeta(env, userId, meta, { action: 'revoke', from: previous });
    return jsonResponse({ ok: true, user: adminUser(user), admin: meta });
  }

  if (path === '/api/admin/users/note') {
    meta.note = String(body.note || '').slice(0, NOTE_LIMIT);
    meta.noteUpdatedAt = new Date().toISOString();
    await writeAdminMeta(env, userId, meta);
    return jsonResponse({ ok: true, admin: meta });
  }

  if (path === '/api/admin/users/suspect') {
    user.suspect = body.suspect === true;
    await putUserRecord(env, user);
    await writeAdminMeta(env, userId, meta, { action: user.suspect ? 'flag' : 'unflag' });
    return jsonResponse({ ok: true, user: adminUser(user), admin: meta });
  }

  if (path === '/api/admin/users/revoke-sessions') {
    await revokeUserSessions(env, userId);
    await writeAdminMeta(env, userId, meta, { action: 'sessions' });
    return jsonResponse({ ok: true, admin: meta });
  }

  return jsonResponse({ error: 'not found' }, 404);
}
