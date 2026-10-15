# Сервер Cloudflare Worker

Рабочий код — `server/install-notifier/`. Название историческое: сейчас сервер
обслуживает аккаунты, Premium, оплаты, прогресс, игру, аналитику и админку.
Установка и эксплуатация — [README воркера](../../server/install-notifier/README.md).

## Карта модулей

| Область | Файлы в `server/install-notifier/` |
| --- | --- |
| Входная точка и маршруты | `worker.js`, `wrangler.toml` |
| Вход и аккаунты | `user_auth.js`, `user_store.js`, `telegram_auth.js`, `apple_web_callback.js` |
| Premium и оплата | `entitlements.js`, `payments.js`, `store_verification.js`, `purchase_claims.js` |
| Прогресс | `progress_merge.js` |
| Игра и экономика | `game_profile.js`, `game_scoring.js`, `game_weeks.js`, `economy_admin.js` |
| Буфер статистики | `stats_buffer.js` |
| Аналитика | `analytics_*.js`, `usage_analytics.js`, `premium_analytics.js`, `attribution.js` |
| Обновления и уведомления | `app_updates.js`, `notifications.js` |
| Telegram и диагностика | `diagnostics.js`, `incident_copy.js`, `telegram_queue.js`, `telegram_topics.js`, `telegram_export.js` |
| Публикации | `publications_data.js`, `social.js`, `threads.js` |
| Поддержка и задачи | `support_*.js`, `tasks_admin.js` |
| Панель управления | [карта админок](../admin/README.md) |

Перед изменением входа/оплаты прочитать [Premium](../premium/README.md) целиком.
Сроки изменять через `setEntitlement`/`extendEntitlement`. Статистику событий
писать через `trackStats`, чтобы не создавать KV-запись на каждый запрос.
Секреты задаются через `wrangler secret put`; значения не писать в код и документацию.

## Проверки

Команды запускать из `server/install-notifier/`: `npm test`, затем нужные
`npm run test:*` из `package.json`. Базовый `npm test` не запускает все модульные
проверки. Для безопасности — `npm run test:security`, для публикаций —
`npm run test:publications`, для прогресса — `npm run test:progress`.
Полный перечень актуальных команд — `package.json`, тесты — `test-*.mjs`.

`legacy/` — исторические одноразовые патчи, не рабочий способ редактирования.
Деплой — отдельная операция через `deploy.sh` или Wrangler; изменение файла
локально не меняет опубликованный Worker.
