// Запись профиля пользователя `user:<id>` вместе с краткой сводкой в
// метаданных ключа KV. Список пользователей в админке читает только
// метаданные через list() — одна операция на 1000 пользователей вместо
// get() на каждого (лимит операций KV на запрос кончился бы на ~1000 людей).
// Дополнительных записей это не добавляет: сводка едет в том же put.

const META_LIMIT = 1024; // байт — ограничение Cloudflare на метаданные ключа

function cut(value, max) {
  return typeof value === 'string' ? value.slice(0, max) : (value ?? null);
}

export function userSummary(user) {
  const meta = {
    id: user.id,
    name: cut(user.name, 60),
    email: cut(user.email, 80),
    avatarUrl: user.avatarUrl && user.avatarUrl.length <= 300 ? user.avatarUrl : null,
    provider: cut(user.provider, 16),
    app: cut(user.app, 4),
    platform: cut(user.platform, 12),
    appVersion: cut(user.appVersion, 20),
    createdAt: user.createdAt || null,
    lastSeenAt: user.lastSeenAt || null,
    isPremium: Boolean(user.isPremium),
    premiumExpiresAt: user.premiumExpiresAt || null,
    premiumSource: cut(user.premiumSource, 20),
    hasPushToken: Boolean(user.pushToken),
    suspect: user.suspect === true,
    v: 1,
  };
  if (new TextEncoder().encode(JSON.stringify(meta)).length > META_LIMIT) meta.avatarUrl = null;
  return meta;
}

export async function putUserRecord(env, user, options = {}) {
  await env.INSTALLS.put('user:' + user.id, JSON.stringify(user), { ...options, metadata: userSummary(user) });
}

// Сколько старых записей без сводки дописывать за один заход в админку:
// каждая — это get и put, а бесплатный KV даёт 1000 записей в сутки.
const BACKFILL_PER_CALL = 150;

/** Все пользователи по сводкам; старые записи без сводки читаются и дописываются. */
export async function listUserSummaries(env) {
  const users = [];
  const missing = [];
  let cursor;
  do {
    const page = await env.INSTALLS.list({ prefix: 'user:', cursor });
    for (const key of page.keys || []) {
      if (key.metadata && key.metadata.v === 1) users.push(key.metadata);
      else missing.push(key.name);
    }
    cursor = page.list_complete === false ? page.cursor : undefined;
  } while (cursor);

  for (const [index, name] of missing.entries()) {
    // Остальные дочитаются при следующих заходах; пока — строка с одним ID.
    if (index >= BACKFILL_PER_CALL) { users.push({ id: name.slice(5), name: null, pending: true }); continue; }
    try {
      const raw = await env.INSTALLS.get(name);
      if (!raw) continue;
      const user = JSON.parse(raw);
      if (!user || !user.id) continue;
      await putUserRecord(env, user);
      users.push(userSummary(user));
    } catch (_) {}
  }

  users.sort((a, b) => Date.parse(b.lastSeenAt || b.createdAt || 0) - Date.parse(a.lastSeenAt || a.createdAt || 0));
  return users;
}
