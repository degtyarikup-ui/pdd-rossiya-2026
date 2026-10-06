const CHANNELS = new Set(['threads', 'instagram', 'youtube', 'tiktok', 'telegram', 'vk', 'yandex', 'google', 'direct', 'other']);
const ALIASES = { th: 'threads', thread: 'threads', yt: 'youtube', ig: 'instagram', insta: 'instagram', tt: 'tiktok', tg: 'telegram', vkontakte: 'vk' };
export function marketingSource(raw) {
  const value = String(raw || '').trim().toLowerCase();
  const source = Object.hasOwn(ALIASES, value) ? ALIASES[value] : value;
  return CHANNELS.has(source) ? source : 'unknown';
}
export function campaignToken(raw) {
  const value = String(raw || '');
  return /^[A-Za-z0-9._-]{1,64}$/.test(value) && !['__proto__', 'constructor', 'prototype'].includes(value) ? value : '';
}
export function metadataFields(user) {
  const out = {};
  for (const key of ['device', 'os', 'locale', 'ipCity', 'ipRegion']) out[key] = String(user[key] || '').slice(0, 100);
  out.installStore = ['App Store', 'Google Play', 'RuStore', 'TestFlight', 'Web'].includes(user.installStore) ? user.installStore : '';
  if (!out.installStore && String(user.platform).toLowerCase() === 'ios') out.installStore = 'App Store';
  out.marketingSource = marketingSource(user.marketingSource);
  out.marketingCampaign = campaignToken(user.marketingCampaign);
  out.attributionMethod = ['play_referrer', 'web_utm', 'web_referrer'].includes(user.attributionMethod) ? user.attributionMethod : '';
  return out;
}
export function attributionLines(user, esc) {
  const m = metadataFields(user);
  const channel = { unknown: '—', direct: 'прямой переход', other: 'другой сайт', threads: 'Threads', instagram: 'Instagram', youtube: 'YouTube', tiktok: 'TikTok', telegram: 'Telegram', vk: 'VK', yandex: 'Яндекс', google: 'Google' }[m.marketingSource];
  return [
    `• <b>Установка:</b> ${esc(m.installStore) || '—'}`,
    m.marketingSource !== 'unknown' && m.marketingSource !== 'other' ? `• <b>Источник:</b> ${channel}${m.marketingCampaign ? ' · ' + esc(m.marketingCampaign) : ''}` : null,
    m.attributionMethod ? `• <b>Определён по:</b> ${m.attributionMethod === 'play_referrer' ? 'Google Play Referrer' : m.attributionMethod === 'web_utm' ? 'метке ссылки' : 'переходу с сайта'}` : null,
    m.device || m.os ? `• <b>Устройство:</b> ${[m.device, m.os].filter(Boolean).map(esc).join(' · ')}` : null,
    m.locale ? `• <b>Язык устройства:</b> ${esc(m.locale)}` : null,
  ].filter(Boolean);
}
// Pass campaign through the store boundary without using IP/device matching.
export function attributedDestination(destination, source, campaign) {
  const url = new URL(destination);
  const channel = marketingSource(source);
  if (channel === 'unknown' || channel === 'direct') return url.href;
  const tags = new URLSearchParams({ utm_source: channel, utm_medium: 'social' });
  if (campaignToken(campaign)) tags.set('utm_campaign', campaignToken(campaign));
  if (url.hostname === 'play.google.com') url.searchParams.set('referrer', tags.toString());
  else if (url.hostname === 'apps.apple.com') url.searchParams.set('ct', campaignToken(campaign) || channel);
  else if (['app.pdd-drive.ru', 'pdd-drive.online', 'rs.pdd-drive.online'].includes(url.hostname)) for (const [k, v] of tags) url.searchParams.set(k, v);
  return url.href;
}
