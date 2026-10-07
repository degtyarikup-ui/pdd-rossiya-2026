import { activitySnapshot } from './analytics_activity.js';

// Показатели аналитики, которые берутся из профилей пользователей, а не из
// счётчиков событий: регистрации по дням, активные, Premium. Профили — это
// сводки из метаданных KV (user_store.js), поэтому считать их дёшево.

const DAY_MS = 86400000;

// Боты и тестовые устройства (suspect) не считаются — как и в Telegram.
function isRegistered(u) {
  return !u.pending && !u.suspect && String(u.provider || 'guest').toLowerCase() !== 'guest';
}

function isPaid(u) {
  return Boolean(u.purchasedAt) || (Boolean(u.premiumSource) && u.premiumSource !== 'admin_grant');
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
  // Когорта периода: кто зарегистрировался в период — вернулся ли через
  // сутки и купил ли Premium (оплата в магазине, не ручная выдача).
  let cohortReturned = 0, cohortPaid = 0, cohortActive7 = 0;
  const byApp = {};
  const geo = { countries: {}, regions: {}, cities: {}, known: 0, unknown: 0, total: 0 };
  function addGeo(map, key, label, country, u, seen) {
    if (!map[key]) map[key] = { name: label, country, accounts: 0, active7: 0, premium: 0 };
    map[key].accounts++;
    if (seen >= 0 && seen <= 7 * DAY_MS) map[key].active7++;
    if (premiumActive(u, now)) map[key].premium++;
  }

  for (const u of list) {
    const created = Date.parse(u.createdAt || '');
    if (Number.isFinite(created)) {
      const key = dayKey(new Date(created));
      if (inPeriod.has(key)) {
        perDay[key]++; registrations++;
        geo.total++;
        const country = String(u.ipCountry || '').trim().toUpperCase();
        if (/^[A-Z]{2}$/.test(country) && !['XX', 'T1'].includes(country)) {
          geo.known++;
          const seen = now - Date.parse(u.lastSeenAt || u.createdAt || '');
          addGeo(geo.countries, country, country, country, u, seen);
          const region = String(u.ipRegion || '').trim();
          const city = String(u.ipCity || '').trim();
          if (region) addGeo(geo.regions, country + ':' + region, region, country, u, seen);
          if (city) addGeo(geo.cities, country + ':' + region + ':' + city, city, country, u, seen);
        } else geo.unknown++;

        const seenAt = Date.parse(u.lastSeenAt || '');
        if (Number.isFinite(seenAt) && seenAt - created >= DAY_MS) cohortReturned++;
        if (Number.isFinite(seenAt) && now - seenAt <= 7 * DAY_MS) cohortActive7++;
        if (isPaid(u)) cohortPaid++;
      }
      else if (prevKeys.has(key)) previousRegistrations++;
    }
    const seen = now - Date.parse(u.lastSeenAt || u.createdAt || 0);
    if (seen >= 0 && seen <= DAY_MS) active1++;
    if (seen >= 0 && seen <= 7 * DAY_MS) active7++;
    if (seen >= 0 && seen <= 30 * DAY_MS) active30++;
    if (premiumActive(u, now)) {
      premium++;
      const source = u.premiumSource || 'unknown';
      premiumBySource[source] = (premiumBySource[source] || 0) + 1;
    }
    const code = String(u.app || 'ru').toLowerCase();
    if (!byApp[code]) byApp[code] = { registered: 0, active7: 0, premium: 0 };
    byApp[code].registered++;
    if (seen >= 0 && seen <= 7 * DAY_MS) byApp[code].active7++;
    if (premiumActive(u, now)) byApp[code].premium++;
  }

  return {
    geography: { ...geo,
      countries: Object.values(geo.countries).sort((a, b) => b.accounts - a.accounts),
      regions: Object.values(geo.regions).sort((a, b) => b.accounts - a.accounts),
      cities: Object.values(geo.cities).sort((a, b) => b.accounts - a.accounts),
    },
    activity: activitySnapshot(list, periodKeys, now),
    registered: list.length,
    registrations,
    previousRegistrations,
    registrationsByDay: perDay,
    cohort: { returned: cohortReturned, active7: cohortActive7, paid: cohortPaid },
    active1,
    active7,
    active30,
    premium,
    premiumBySource,
    byApp,
  };
}
