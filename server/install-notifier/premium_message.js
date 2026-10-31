import { deviceLine, installSourceLines, metadataFields } from './attribution.js';

export function premiumBanner(tier, renewal) {
  const stars = tier === 'threeMonths' ? '⭐⭐⭐⭐⭐⭐' : '⭐⭐⭐';
  return renewal ? stars + '\n✅✅✅' : stars;
}

export function premiumDate(value) {
  const date = new Date(value);
  if (!value || !Number.isFinite(date.getTime())) return 'Не указан';
  return date.toLocaleString('ru-RU', { timeZone: 'Europe/Moscow', day: '2-digit', month: '2-digit',
    year: 'numeric', hour: '2-digit', minute: '2-digit' }) + ' МСК';
}

export function premiumContextLines(context, esc) {
  const meta = metadataFields(context);
  const origin = { android: '🤖 Android', ios: '🍎 iOS', web: '🌐 Сайт / веб-приложение' };
  const source = meta.marketingSource === 'google_play_organic' ? 'Органика' : undefined;
  meta.os = meta.os.replace(/\s*\(SDK \d+\)$/i, '');
  return [
    `• <b>Начата из:</b> ${Object.hasOwn(origin, context.platform) ? origin[context.platform] : 'Не указан'}`,
    ...installSourceLines(meta, esc, source),
    meta.marketingMedium ? `• <b>Канал:</b> ${esc(meta.marketingMedium)}` : null,
    '',
    deviceLine(meta, esc),
    meta.locale ? `• <b>Язык устройства:</b> ${esc(meta.locale)}` : null,
    context.appVersion ? `• <b>Версия:</b> ${esc(context.appVersion)}` : null,
  ];
}
