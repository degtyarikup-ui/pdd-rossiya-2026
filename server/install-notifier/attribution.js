const CHANNELS = new Set(['threads', 'instagram', 'youtube', 'tiktok', 'telegram', 'vk', 'yandex', 'google', 'bing', 'duckduckgo', 'chatgpt', 'perplexity', 'copilot', 'gemini', 'claude', 'google_play_organic', 'direct', 'other']);
const ALIASES = { th: 'threads', thread: 'threads', yt: 'youtube', ig: 'instagram', insta: 'instagram', tt: 'tiktok', tg: 'telegram', vkontakte: 'vk', 'chatgpt.com': 'chatgpt', 'chat.openai.com': 'chatgpt', 'perplexity.ai': 'perplexity' };
export const SOURCE_LABELS = { unknown: 'Не определён', direct: 'Прямой переход', other: 'Другой сайт', threads: 'Threads', instagram: 'Instagram', youtube: 'YouTube', tiktok: 'TikTok', telegram: 'Telegram', vk: 'VK', yandex: 'Яндекс', google: 'Google', bing: 'Bing', duckduckgo: 'DuckDuckGo', chatgpt: 'ChatGPT', perplexity: 'Perplexity', copilot: 'Copilot', gemini: 'Gemini', claude: 'Claude', google_play_organic: 'Органика Google Play' };
export function marketingSource(raw) {
  const value = String(raw || '').trim().toLowerCase();
  const source = Object.hasOwn(ALIASES, value) ? ALIASES[value] : value;
  return CHANNELS.has(source) ? source : 'unknown';
}
export function campaignToken(raw) {
  const value = String(raw || '');
  return /^[A-Za-z0-9._-]{1,64}$/.test(value) && !Object.hasOwn(Object.prototype, value) && value !== 'prototype' ? value : '';
}
export function landingPath(raw) {
  const path = String(raw || '').split(/[?#]/, 1)[0];
  return path.length <= 240 && /^\/(?!\/)[A-Za-z0-9._~%/-]*$/.test(path) ? path : '';
}
export function referrerHost(raw) {
  const host = String(raw || '').trim().toLowerCase();
  return host.length <= 160 && /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(host) ? host : '';
}
export function acquisitionFields(user = {}) {
  const out = { marketingSource: marketingSource(user.marketingSource), marketingCampaign: campaignToken(user.marketingCampaign),
    attributionMethod: ['play_referrer', 'play_organic', 'rustore_referrer', 'web_utm', 'web_referrer'].includes(user.attributionMethod) ? user.attributionMethod : '',
    marketingMedium: campaignToken(user.marketingMedium), marketingContent: campaignToken(user.marketingContent),
    landingPage: landingPath(user.landingPage), referrerHost: referrerHost(user.referrerHost) };
  return out;
}
// Preserve the acquisition as one snapshot. A later device/login must not mix
// its campaign or article with an already recorded first source.
export function mergeAcquisition(existing, incoming) {
  return acquisitionFields(marketingSource(existing?.marketingSource) !== 'unknown' ? existing : incoming);
}
export function metadataFields(user = {}) {
  const out = {};
  for (const key of ['device', 'os', 'locale', 'ipCity', 'ipRegion']) out[key] = String(user[key] || '').slice(0, 100);
  out.installStore = ['App Store', 'Google Play', 'RuStore', 'TestFlight', 'Web'].includes(user.installStore) ? user.installStore : '';
  return { ...out, ...acquisitionFields(user) };
}
export function attributionLines(user, esc) {
  const m = metadataFields(user);
  const methods = { play_referrer: 'Google Play Referrer', play_organic: 'органический referrer Google Play (поиск/рекомендации не различимы)', rustore_referrer: 'RuStore Install Referrer', web_utm: 'метке ссылки', web_referrer: 'переходу с сайта' };
  return [
    `• <b>Установка:</b> ${esc(m.installStore) || '—'}`,
    `• <b>Источник:</b> ${SOURCE_LABELS[m.marketingSource]}${m.marketingCampaign ? ' · ' + esc(m.marketingCampaign) : ''}`,
    m.marketingSource === 'unknown' && m.installStore === 'App Store' ? '  App Store сообщает канал привлечения в сводном отчёте.' : null,
    m.marketingMedium ? `• <b>Канал:</b> ${esc(m.marketingMedium)}` : null,
    m.landingPage ? `• <b>Первая страница:</b> ${esc(m.landingPage)}` : null,
    m.referrerHost ? `• <b>Сайт-источник:</b> ${esc(m.referrerHost)}` : null,
    m.attributionMethod ? `• <b>Определён по:</b> ${methods[m.attributionMethod]}` : null,
    m.device || m.os ? `• <b>Устройство:</b> ${[m.device, m.os].filter(Boolean).map(esc).join(' · ')}` : null,
    m.locale ? `• <b>Язык устройства:</b> ${esc(m.locale)}` : null,
  ].filter(Boolean);
}
// Pass the same snapshot across browser/app/store boundaries. App Store ct is
// an aggregate campaign tag, never a deferred per-account identifier.
export function attributedDestination(destination, source, campaign, context = {}) {
  const url = new URL(destination);
  const m = acquisitionFields({ ...context, marketingSource: source, marketingCampaign: campaign });
  if (m.marketingSource === 'unknown') return url.href;
  const medium = m.marketingMedium || (m.marketingSource === 'google_play_organic' ? 'organic'
    : ['yandex', 'google', 'bing', 'duckduckgo'].includes(m.marketingSource) ? 'referral'
    : ['chatgpt', 'perplexity', 'copilot', 'gemini', 'claude'].includes(m.marketingSource) ? 'ai'
    : m.marketingSource === 'direct' ? 'direct' : m.marketingSource === 'other' ? 'referral' : 'social');
  const tags = new URLSearchParams({ utm_source: m.marketingSource, utm_medium: medium });
  if (m.marketingCampaign) tags.set('utm_campaign', m.marketingCampaign);
  if (m.marketingContent) tags.set('utm_content', m.marketingContent);
  if (m.landingPage) tags.set('landing_page', m.landingPage);
  if (m.referrerHost) tags.set('referrer_host', m.referrerHost);
  if (url.hostname === 'play.google.com') url.searchParams.set('referrer', tags.toString());
  else if (['rustore.ru', 'www.rustore.ru'].includes(url.hostname)) url.searchParams.set('referrerId', tags.toString());
  else if (url.hostname === 'apps.apple.com' && m.marketingSource !== 'direct') url.searchParams.set('ct', m.marketingCampaign || m.marketingSource);
  else if (['app.pdd-drive.ru', 'pdd-drive.ru', 'pdd-drive.online', 'rs.pdd-drive.online'].includes(url.hostname)) for (const [k, v] of tags) url.searchParams.set(k, v);
  return url.href;
}
