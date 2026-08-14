// Локальный прогон рендера сообщений — БЕЗ деплоя и без реального Telegram.
// Запуск:  node server/install-notifier/test-local.mjs
import { buildMessage, buildMonthlyMessage } from './worker.js';

const samples = [
  {
    label: 'Android-приложение из RuStore',
    num: 102,
    data: {
      platform: 'android', country: 'ru', source: 'RuStore',
      device: 'Samsung SM-A536B', os: 'Android 14 (SDK 34)',
      version: '1.0.6+20', locale: 'ru-RU', install_id: 'deadbeefcafe1234',
    },
  },
  {
    label: 'Android dev-установка (adb → com.android.shell скрыт)',
    num: 66,
    data: {
      platform: 'android', country: 'ru', source: 'com.android.shell',
      device: 'Google Pixel 7', os: 'Android 17 (SDK 37)',
      version: '1.0.6+20', locale: 'pl-PL', install_id: 'a1b2c3d4e5f6a7b8',
    },
  },
  {
    label: 'iOS нативное приложение (TestFlight → com.apple.testflight скрыт)',
    num: 70,
    data: {
      platform: 'iOS', country: 'ru', source: 'com.apple.testflight',
      device: 'iPhone12,1', os: 'iOS 26.5',
      version: '1.0.6+20', locale: 'be-BY', install_id: '0011223344556677',
    },
  },
  {
    label: 'Веб-версия на айфоне (Safari)',
    num: 67,
    data: {
      platform: 'web', country: 'by', source: 'Web',
      device: 'Safari', os: 'iPhone',
      version: '1.0.6+17', locale: 'en-US', install_id: 'e184bf1a35dc47ce',
    },
  },
];

for (const s of samples) {
  console.log(`--- ${s.label} ---`);
  console.log(buildMessage(s.data, s.num));
  console.log();
}

console.log('--- ежемесячная сводка ---');
console.log(
  buildMonthlyMessage('2026-07', {
    fresh: 42,
    grandTotal: 101,
    sources: [
      { name: 'Google Play', count: 25 },
      { name: 'RuStore', count: 10 },
      { name: 'Web', count: 5 },
    ],
  }),
);
