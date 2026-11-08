// Release announcements are separate from campaigns: no push, expiry, or
// per-user state. Enable only after this exact country/platform is published.
const APPS = ['ru', 'by', 'rs'];
const PLATFORMS = ['android', 'ios'];
export function updateKey(app, platform) {
  if (!APPS.includes(app) || !PLATFORMS.includes(platform)) throw new Error('Выберите страну и платформу');
  return 'release:' + app + ':' + platform;
}
export function validateRelease(input) {
  updateKey(input?.app, input?.platform);
  if (typeof input.enabled !== 'boolean') throw new Error('Укажите, включён ли показ');
  const text = (key, max) => {
    if (typeof input[key] !== 'string' || input[key].trim().length > max) throw new Error('Некорректное поле: ' + key);
    return input[key].trim();
  };
  const version = text('version', 40), packageId = text('packageId', 160), notes = text('notes', 1000);
  if (!/^\d{1,6}(\.\d{1,6}){1,3}$/.test(version)) throw new Error('Версия: например 2.1.9');
  if (!/^[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)+$/.test(packageId)) throw new Error('Укажите applicationId / bundle ID');
  if (!Number.isSafeInteger(input.build) || input.build < 1 || input.build > 2147483647) throw new Error('Номер сборки: положительное целое число');
  let url; try { url = new URL(text('storeUrl', 500)); } catch { throw new Error('Укажите ссылку магазина'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.port) throw new Error('Нужна прямая HTTPS-ссылка магазина');
  if (input.platform === 'android') {
    if (url.hostname !== 'play.google.com' || url.pathname !== '/store/apps/details' || url.searchParams.get('id') !== packageId) throw new Error('Ссылка Google Play должна соответствовать applicationId');
  } else if (url.hostname !== 'apps.apple.com' || !/\/id\d+\/?$/.test(url.pathname)) throw new Error('Нужна ссылка apps.apple.com с ID приложения');
  return { app: input.app, platform: input.platform, enabled: input.enabled, version, build: input.build, packageId, storeUrl: url.toString(), notes, updatedAt: Date.now() };
}
