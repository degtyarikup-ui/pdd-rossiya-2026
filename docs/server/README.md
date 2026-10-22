# Сервер Cloudflare Worker

Рабочий код — `server/install-notifier/`. Название историческое: сейчас сервер
обслуживает аккаунты, Premium, оплаты, прогресс, игру, аналитику и админку.
Установка и эксплуатация — [README воркера](../../server/install-notifier/README.md).
Лимиты тарифа $5, измерения и сокращение операций KV/DO —
[стоимость Cloudflare](cloudflare-costs.md).

## Карта модулей

| Область | Файлы в `server/install-notifier/` |
| --- | --- |
| Входная точка и маршруты | `worker.js`, `wrangler.toml` |
| Вход и аккаунты | `account_state.js`, `account_maintenance.js`, `user_auth.js`, `user_store.js`, `telegram_auth.js`, `apple_web_callback.js`, `apple_account.js` |
| Premium и оплата | `entitlements.js`, `payments.js`, `store_verification.js`, `purchase_claims.js`, `store_account.js`, `store_notifications.js` |
| ИИ и квоты | `ai_request.js`, `ai_quota.js`, `ai_models.js` |
| Прогресс | `progress_merge.js` |
| Игра и экономика | `game_profile.js`, `game_scoring.js`, `game_weeks.js`, `economy_admin.js` |
| Буфер статистики | `stats_buffer.js` |
| Аналитика | `analytics_*.js`, `usage_analytics.js`, `premium_analytics.js`, `attribution.js` |
| Обновления и уведомления | `app_updates.js`, `notifications.js`, `notification_identity.js` |
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

Модели разбора вопросов задаются в `ai_models.js`: основная — стабильная
`gemini-3.8-flash`, экономичная — `gemini-3.5-flash-lite`. Удалённые из меню
настройки (включая 1.5/2.5/3.6) автоматически используют основную модель.
Админка и API берут список из одного каталога; «Проверить модель» использует
выбор без сохранения для пользователей, «Применить модель» сохраняет его.
Оба запроса используют `thinkingLevel: low`, общий таймаут 9 секунд и не
передают устаревший `temperature`. При недоступности провайдера приложение
сохраняет официальный комментарий как резервное объяснение.

Цены — Standard text из [Google](https://ai.google.dev/gemini-api/docs/pricing),
проверены 21.10.2026. Для 3.8 учтён переход с $0.75/$3.75 на $1.50/$7.50 за
миллион входных/выходных токенов 01.01.2027 UTC; для Flash-Lite — $0.30/$2.50.
Размышления входят в выходные токены. Буфер считает цену по времени события,
накопленные расходы и тарифы уже поставленных в очередь старых событий сохраняются.
Проверки моделей: `npm run test:ai` (также включены в `test:security`).

`legacy/` — исторические одноразовые патчи, не рабочий способ редактирования.
Деплой — отдельная операция через `deploy.sh` или Wrangler; изменение файла
локально не меняет опубликованный Worker.

Миграция аккаунтов в DO, платёжный журнал, новые контракты и обязательные
шаги выпуска — [AccountState rollout](../premium/account-state-rollout.md).
После включения DO нельзя откатываться на старую запись аккаунтов в KV.


Жалобы на вопросы: `report_questions.js` определяет подпись источника.
Flutter передаёт `source=training|game`; старый `mode=city` распознаётся
как «Игра „Живой город“» уже на сервере, без новой сборки. Другие непустые
`mode` старых клиентов — названия экранов обучения. Без контекста источник
показывается как «Не указан»: по `ticket_*` отличать игру от обучения нельзя.
Подпись выводится сразу под заголовком жалобы, режим обучения — отдельно
рядом с билетом. Проверки — `npm run test:reports` и
`test/question_report_service_test.dart`.
