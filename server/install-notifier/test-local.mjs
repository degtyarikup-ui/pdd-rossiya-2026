// Локальный прогон рендера сообщений — БЕЗ деплоя и без реального Telegram.
// Запуск:  node server/install-notifier/test-local.mjs
import {
  buildSlotReportMessage,
  buildReportMessage,
  buildUserRegistrationMessage,
  buildPremiumPurchaseMessage,
} from './worker.js';

console.log('========================================');
console.log('1. УТРЕННИЙ ОТЧЕТ (10:00 МСК)');
console.log('========================================');
const morningSample = buildSlotReportMessage({
  slotType: 'night',
  slotData: {
    installs: 12,
    installsByStore: {
      'RuStore': 7,
      'Google Play': 4,
      'App Store': 1,
    },
    views: 84,
    viewsBySource: {
      yandex: 46,
      google: 24,
      social_other: 14,
    },
    clicks: 19,
    clicksByStore: {
      'RuStore': 11,
      'Google Play': 6,
      'App Store': 2,
    },
    aiRequests: 14,
    aiCostUsd: 0.0018,
  },
  grandTotal: 1428,
});
console.log(morningSample);

console.log('\n========================================');
console.log('2. ВЕЧЕРНИЙ ОТЧЕТ (22:00 МСК)');
console.log('========================================');
const eveningSample = buildSlotReportMessage({
  slotType: 'day',
  slotData: {
    installs: 28,
    installsByStore: {
      'RuStore': 16,
      'Google Play': 9,
      'App Store': 3,
    },
    views: 210,
    viewsBySource: {
      yandex: 118,
      google: 64,
      social_other: 28,
    },
    clicks: 48,
    clicksByStore: {
      'RuStore': 27,
      'Google Play': 15,
      'App Store': 6,
    },
    aiRequests: 32,
    aiCostUsd: 0.0041,
  },
  dayTotals: {
    installs: 40,
    views: 294,
    clicks: 67,
    aiRequests: 46,
    aiCostUsd: 0.0059,
  },
  grandTotal: 1456,
});
console.log(eveningSample);

console.log('\n========================================');
console.log('3. НОВАЯ РЕГИСТРАЦИЯ ПОЛЬЗОВАТЕЛЯ (Мгновенная)');
console.log('========================================');
console.log(buildUserRegistrationMessage({
  id: 'yandex_98127341',
  name: 'Сергей Иванов',
  email: 'sergei.ivanov@yandex.ru',
  provider: 'yandex',
  country: 'ru',
  app: 'ru',
  platform: 'android',
  appVersion: '1.0.6+20',
}, 42));

console.log('\n--- Регистрация Apple ID ---');
console.log(buildUserRegistrationMessage({
  id: 'apple_001239.abc',
  name: 'Алексей',
  email: '',
  provider: 'apple',
  country: 'ru',
  app: 'ru',
  platform: 'ios',
  appVersion: '1.0.6+20',
}, 43));

console.log('\n========================================');
console.log('4. ПОКУПКА PREMIUM-ДОСТУПА (Мгновенная)');
console.log('========================================');
console.log(buildPremiumPurchaseMessage({
  name: 'Сергей Иванов',
  email: 'sergei.ivanov@yandex.ru',
  tier: 'threeMonths',
  tierName: '3 месяца',
  price: '290 ₽',
  store: 'rustore',
  expiresAt: '2026-11-30T19:00:00.000Z',
  platform: 'android',
  appVersion: '1.0.6+20',
  country: 'ru',
}));

console.log('\n--- Покупка в App Store ---');
console.log(buildPremiumPurchaseMessage({
  name: 'Елена',
  email: 'elena@gmail.com',
  tier: 'weekly',
  tierName: '1 неделя',
  price: '99 ₽',
  store: 'appstore',
  expiresAt: '2026-09-06T19:00:00.000Z',
  platform: 'ios',
  appVersion: '1.0.6+20',
  country: 'ru',
}));

console.log('\n========================================');
console.log('5. ЖАЛОБА НА ВОПРОС (Мгновенная)');
console.log('========================================');
console.log(buildReportMessage({
  country: 'ru',
  ticket: 1,
  topic: 'Общие положения',
  mode: 'exam',
  question_id: 'q_01_03',
  question_text: 'Разрешен ли вам обгон...',
  message: 'В пояснении опечатка в номере пункта ПДД',
  version: '1.0.6+20',
  platform: 'android',
}));

