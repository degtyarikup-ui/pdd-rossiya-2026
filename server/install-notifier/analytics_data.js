// Показатели аналитики, которые берутся из профилей пользователей, а не из
// счётчиков событий: регистрации по дням, активные, Premium. Профили — это
// сводки из метаданных KV (user_store.js), поэтому считать их дёшево.

const DAY_MS = 86400000;

function isRegistered(u) {
  return !u.pending && String(u.provider || 'guest').toLowerCase() !== 'guest';
}

function premiumActive(u, now) {
  if (!u.isPremium) return false;
  return !u.premiumExpiresAt || Date.parse(u.premiumExpiresAt) > now;
}

/**
 * @param users   сводки пользователей
 * @param days    длина периода (дней, включая сегодня)
 * @param app     'all' | 'ru' | 'by' | 'rs'
 * @param dayKey  функция Date → 'YYYY-MM-DD' по Москве (как у счётчиков событий)
 */
export function usersSnapshot(users, days, app, dayKey, now = Date.now()) {
  const list = users.filter(u => isRegistered(u) && (app === 'all' || String(u.app || 'ru').toLowerCase() === app));
  const periodKeys = [];
  for (let i = days - 1; i >= 0; i--) periodKeys.push(dayKey(new Date(now - i * DAY_MS)));
  const inPeriod = new Set(periodKeys);
  const prevKeys = new Set();
  for (let i = days * 2 - 1; i >= days; i--) prevKeys.add(dayKey(new Date(now - i * DAY_MS)));

  const perDay = Object.fromEntries(periodKeys.map(k => [k, 0]));
  let registrations = 0;
  let previousRegistrations = 0;
  let active1 = 0, active7 = 0, active30 = 0, premium = 0;
  const premiumBySource = {};
  const byApp = {};

  for (const u of list) {
    const created = Date.parse(u.createdAt || '');
    if (Number.isFinite(created)) {
      const key = dayKey(new Date(created));
      if (inPeriod.has(key)) { perDay[key]++; registrations++; }
      else if (prevKeys.has(key)) previousRegistrations++;
    }
    const seen = now - Date.parse(u.lastSeenAt || u.createdAt || 0);
    if (seen <= DAY_MS) active1++;
    if (seen <= 7 * DAY_MS) active7++;
    if (seen <= 30 * DAY_MS) active30++;
    if (premiumActive(u, now)) {
      premium++;
      const source = u.premiumSource || 'unknown';
      premiumBySource[source] = (premiumBySource[source] || 0) + 1;
    }
    const code = String(u.app || 'ru').toLowerCase();
    if (!byApp[code]) byApp[code] = { registered: 0, active7: 0, premium: 0 };
    byApp[code].registered++;
    if (seen <= 7 * DAY_MS) byApp[code].active7++;
    if (premiumActive(u, now)) byApp[code].premium++;
  }

  return {
    registered: list.length,
    registrations,
    previousRegistrations,
    registrationsByDay: perDay,
    active1,
    active7,
    active30,
    premium,
    premiumBySource,
    byApp,
  };
}
