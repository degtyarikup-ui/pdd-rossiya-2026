# Настройка серверной авторизации и проверки покупок

Не публикуйте новый клиент раньше этого Worker: клиент использует /api/auth/session. После обновления Worker старые клиенты без серверных сессий не смогут синхронизировать прогресс или удалять облачный аккаунт. Локальные данные не удаляются. Новая версия попросит войти заново один раз.

## Google Play

1. Подготовить сервисный аккаунт с доступом к нужным приложениям Google Play и включённым Google Play Developer API. Ключ хранить вне репозитория.
2. Передать JSON сервисного аккаунта в Cloudflare secret GOOGLE_PLAY_SERVICE_ACCOUNT, например через `wrangler secret put GOOGLE_PLAY_SERVICE_ACCOUNT` с вводом из локального файла. Не добавлять JSON в wrangler.toml, код, логи или чат.
3. По умолчанию принимаются ru.pdd.pddapp.premium.week и ru.pdd.pddapp.premium.3months. Если реальные ID отличаются, настроить переменную GOOGLE_PLAY_PRODUCT_IDS (список через запятую) и согласовать выбор продуктов в клиенте.
4. Пакеты привязаны к стране: ru.pdd.pdd_app / by.pdd.pdd_app / rs.pdd.pdd_app. Проверка идёт через purchases.subscriptionsv2.get; клиентский expiresAt не принимается.
5. Google OAuth audience по умолчанию совпадает с AuthService.googleClientId. Дополнительные реальные client ID задаются GOOGLE_CLIENT_IDS через запятую. Не ослаблять проверку audience ради прохождения теста; зарегистрировать SHA-1/SHA-256 подписи Google Play для Android-клиента.

## Apple (до выпуска iOS)

Настроить секреты APPLE_IAP_PRIVATE_KEY (ключ App Store Server API в PEM), APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID. APPLE_IAP_BUNDLE_ID по умолчанию ru.pdd.pddApp. APPLE_PRODUCT_IDS по умолчанию u.pdd.pddApp.premium.week,ru.pdd.pddApp.sub.3months. APPLE_IAP_ENVIRONMENT=sandbox допустим только для отдельной тестовой конфигурации сервера; production не принимает выбор sandbox со стороны клиента.

OAuth audiences APPLE_CLIENT_IDS по умолчанию ru.pdd.pddApp,ru.pdd.pddapp.auth. Для Яндекса YANDEX_CLIENT_ID по умолчанию совпадает с AuthService.yandexClientId.

## Порядок проверки и выпуска

- `npm ci`
- `npm run test:security`, `npm test`, `node test-admin-local.mjs`
- `npx wrangler deploy --dry-run`
- Проверить секреты и реальные product/client ID. Новый PURCHASE_CLAIMS Durable Object хранит владельца чека атомарно; wrangler.toml содержит миграцию v2.
- Согласовать влияние на старые приложения, опубликовать Worker обычным процессом проекта. Не убирать проверку сессий ради старых клиентов.
- Проверить Google/Yandex/Apple OAuth и сохранение сессии после перезапуска на целевых платформах.
- Во внутреннем треке Google Play пройти покупку, восстановление того же чека без продления срока, отмену, удержание/истечение, отказ сети и смену аккаунта. Не подтверждать доставку без успешного ответа сервера.
- Только затем выпускать AAB с новым доступным versionCode.

Store credentials и настройка доступа не были проверены реальным запросом к магазинам: на момент аудита соответствующие секреты отсутствовали. Статус configured предотвращает оплату при отсутствующих реквизитах, но не заменяет проверку их прав доступа.

Документация: https://developers.google.com/identity/sign-in/web/backend-auth,
https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2,
https://developer.apple.com/documentation/appstoreserverapi.
