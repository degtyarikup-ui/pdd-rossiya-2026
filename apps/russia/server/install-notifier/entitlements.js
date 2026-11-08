// Премиум из нескольких источников: App Store, Google Play, оплата на сайте
// (`web`) и выдача из админки (`admin_grant`). Каждый источник хранит свой
// срок в `user.entitlements[source] = { expiresAt }` (null — бессрочно), а
// итоговые поля isPremium / premiumExpiresAt / premiumSource — это источник
// с самым дальним действующим сроком. Поэтому покупка или продление в одном
// месте никогда не укорачивает доступ, полученный в другом, и купленное на
// сайте работает в приложении на любой платформе (статус — по аккаунту).

const DAY_MS = 86400000;

function isActive(entry, now) {
  return Boolean(entry) && (entry.expiresAt == null || Date.parse(entry.expiresAt) > now);
}

function endOf(entry) {
  return entry.expiresAt == null ? Infinity : Date.parse(entry.expiresAt);
}

/** Сроки по источникам; у записей до разделения — из старых полей. */
export function entitlementsOf(user) {
  if (user?.entitlements && typeof user.entitlements === 'object') return user.entitlements;
  const legacy = {};
  if (user?.isPremium && user.premiumSource) legacy[user.premiumSource] = { expiresAt: user.premiumExpiresAt || null };
  return legacy;
}

/** Пересчитывает итоговые поля по самому дальнему действующему сроку. */
export function applyEntitlements(user, now = Date.now()) {
  let best = null;
  for (const [source, entry] of Object.entries(entitlementsOf(user))) {
    if (isActive(entry, now) && (!best || endOf(entry) > endOf(best.entry))) best = { source, entry };
  }
  user.isPremium = Boolean(best);
  // Без действующих сроков последний источник и дата остаются для истории.
  if (best) {
    user.premiumSource = best.source;
    user.premiumExpiresAt = best.entry.expiresAt ?? null;
  }
  return user;
}

/** Ставит срок источника: ISO-дата, null — бессрочно, undefined — убрать. */
export function setEntitlement(user, source, expiresAt, now = Date.now()) {
  const entitlements = { ...entitlementsOf(user) };
  if (expiresAt === undefined) delete entitlements[source];
  else entitlements[source] = { expiresAt };
  user.entitlements = entitlements;
  return applyEntitlements(user, now);
}

/**
 * Разовая покупка периода без автопродления (оплата на сайте): дни
 * добавляются после самого дальнего действующего срока, чтобы оплаченное
 * не пропадало внахлёст с уже имеющимся доступом.
 */
export function extendEntitlement(user, source, days, now = Date.now()) {
  let start = now;
  for (const entry of Object.values(entitlementsOf(user))) {
    if (isActive(entry, now) && entry.expiresAt != null) start = Math.max(start, Date.parse(entry.expiresAt));
  }
  return setEntitlement(user, source, new Date(start + days * DAY_MS).toISOString(), now);
}

/** Снимает доступ из всех источников (отзыв в админке). */
export function clearEntitlements(user) {
  user.entitlements = {};
  user.isPremium = false;
  user.premiumSource = null;
  user.premiumExpiresAt = null;
  return user;
}
