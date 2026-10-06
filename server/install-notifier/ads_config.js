const emptyConfig = () => ({ enabled: false, frequency: 5, storeRules: {}, promoCards: [] });

export async function getAdsConfig(env) {
  if (!env.INSTALLS) return emptyConfig();
  try {
    const raw = await env.INSTALLS.get('ADS_CONFIG');
    const config = raw ? JSON.parse(raw) : null;
    return config && typeof config === 'object' && !Array.isArray(config) ? config : emptyConfig();
  } catch (_) { return emptyConfig(); }
}

const storeKey = value => String(value || '').toLowerCase().replace(/[^a-z]/g, '');
function matches(targets, value, normalize = v => String(v).toLowerCase()) {
  if (value === 'all' || targets == null) return true;
  const values = Array.isArray(targets) ? targets : [targets];
  return !values.length || values.some(v => normalize(v) === 'all' || normalize(v) === value);
}

export function filterAdsForClient(config, platform, store) {
  const key = storeKey(store);
  const rule = config.storeRules?.[key];
  const result = {
    ...config,
    enabled: config.enabled === true && (key === 'all' || rule?.enabled === true),
    promoCards: (Array.isArray(config.promoCards) ? config.promoCards : []).filter(card =>
      card && card.enabled !== false && matches(card.platforms, platform) && matches(card.stores, key, storeKey)),
  };
  if (key !== 'all') {
    result.mode = rule?.mode || 'none';
    result.yandexAdUnitId = String(rule?.yandexAdUnitId || '');
  }
  return result;
}
