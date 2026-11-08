// Локальный прогон рендера сообщений — БЕЗ деплоя и без реального Telegram.
// Запуск:  node server/install-notifier/test-local.mjs
import {
  buildDailyReportMessage,
  buildReportMessage,
  buildUserRegistrationMessage,
  buildPremiumPurchaseMessage,
} from './worker.js';

console.log('========================================');
console.log('1. СУТОЧНЫЙ ОТЧЕТ (22:00 МСК)');
console.log('========================================');
console.log(buildDailyReportMessage({
  data: {
    installs: 40,
    installsByStore: { 'RuStore': 23, 'Google Play': 13, 'App Store': 4 },
    registrations: 9,
    views: 294,
    viewsBySource: { yandex: 164, google: 88, social_other: 42 },
    clicks: 67,
    clicksByStore: { 'RuStore': 38, 'Google Play': 21, 'App Store': 8 },
    aiRequests: 46,
    aiCostUsd: 0.0059,
  },
  grandTotal: 1456,
  registeredTotal: 46,
}));

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

