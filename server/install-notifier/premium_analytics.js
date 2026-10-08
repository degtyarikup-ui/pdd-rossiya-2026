// A grant is access, not a purchase. Keep the source of the actual transaction
// separate from the user's effective premiumSource (a longer grant can win).
const PAID_SOURCES = new Set(['appstore', 'googleplay', 'rustore', 'web']);
const MANUAL_SOURCES = new Set(['admin', 'admingrant', 'manual', 'manualgrant', 'gift']);
const normalize = value => String(value || '').toLowerCase().replace(/[\s_-]/g, '');

export function premiumEventSource(event) {
  if (event?.manual === true || event?.isManual === true || MANUAL_SOURCES.has(normalize(event?.kind))) return 'admin_grant';
  const explicit = event?.purchaseSource ?? event?.store;
  const source = normalize(explicit ?? event?.source);
  if (MANUAL_SOURCES.has(source)) return 'admin_grant';
  if (PAID_SOURCES.has(source)) return source;
  if (source === 'legacy') return 'legacy';
  // Existing buffered purchase events predate source tagging. Only verified
  // store/web handlers emitted them; don't lose those genuine purchases.
  if (explicit == null && (!source || source === 'direct' || source === 'legacy')) return 'legacy';
  return 'unknown';
}

export function isPaidPremiumEvent(event) {
  const source = premiumEventSource(event);
  return event?.type === 'purchase' && (PAID_SOURCES.has(source) || source === 'legacy');
}
