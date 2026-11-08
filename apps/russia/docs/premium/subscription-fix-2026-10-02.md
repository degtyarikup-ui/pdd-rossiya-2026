# Исправление активации подписок — 02.10.2026

## Воспроизведённая причина

`verifyStorePurchase()` в `server/install-notifier/store_verification.js` обращалась к необъявленной переменной `sandbox` после успешного ответа App Store Server API. Действительная покупка приводила к `ReferenceError`; `/api/user/purchase` возвращал 503 и не выдавал Premium. Тест до исправления воспроизвёл ошибку для production, sandbox и полного маршрута покупки.

Скриншоты подтверждают оплату без доступа. Идентификатор конкретной транзакции и её серверный журнал не предоставлены, поэтому сопоставление этого платежа с воспроизведённым исключением отдельно не выполнено.

## Изменения

- Среда фиксируется по серверному запросу Apple, включая переход production → sandbox. Проверяются bundle, продукт, transaction ID, original transaction ID, среда и срок. Проверка владельца через PurchaseClaims сохранена.
- Для обновления и восстановления старого периода запрашивается актуальный статус подписки. Продление обновляет сохранённый transaction ID и срок. Истечение, возврат, billing retry и grace period учитываются по ответу Apple.
- Периодический `/api/user/status` также обновляет состояние магазина. Проверка ограничена прежним интервалом 5 минут.
- Ручная выдача доступа остаётся независимой от проверки магазина, включая ошибки проверки.
- Клиент подписывается на поток покупок до проверки доступности магазина; параллельная инициализация объединяется.
- При временном отказе оплаченная транзакция остаётся незавершённой и повторно проверяется через 30 секунд, при возврате приложения и после авторизации. Между перезапусками очередь хранит магазин. Чеки не записываются в SharedPreferences.
- Подтверждение доставки магазину происходит после выдачи проверенного Premium. Ошибка подтверждения также допускает повтор. Неактивные и отклонённые покупки не запускают сетевой цикл повторов.
- Восстановленная транзакция может завершить ожидание кнопки покупки. Пустое восстановление завершается без ожидания таймаута.
- Ответ синхронизации, начавшейся до успешной покупки, не перезаписывает выданный доступ. Обновление статуса учитывает изменение срока уже активного Premium.
- Пояснение ошибки проверки добавлено в RU/SR ARB и сгенерированные локализации. Общая логика применяется к всем странам.

## Проверка

- `npm run test:security`: 37 тестов прошли, включая 12 новых сценариев Apple и маршрут purchase/status.
- `flutter analyze --no-pub lib/data/services/iap_service.dart lib/data/services/premium_service.dart lib/main.dart test/iap_recovery_test.dart test/verified_purchase_test.dart`: без замечаний.
- `flutter test --no-pub test/iap_recovery_test.dart test/verified_purchase_test.dart test/premium_service_test.dart test/premium_offline_session_test.dart test/premium_granted_dialog_test.dart test/exam_flow_test.dart`: 44 теста прошли, включая экзамены RU/BY/RS.
- `wrangler deploy --dry-run`: сборка успешна.
- `git diff --check`: без ошибок.

Ответы Apple и магазина в автоматических тестах подменены на границе HTTP/платформы. Реальная покупка на iPhone с последующим восстановлением после перезапуска не выполнена; права ключа Apple реальным transaction ID не проверялись. Проверено наличие требуемых имён секретов Cloudflare без чтения их значений.

## Публикация

Сервер опубликован в `pdd-install-notifier.sergei-pdd.workers.dev`.
Последняя версия Worker: `268e64b6-99e7-4a03-861e-d54ff8d9cc34`.
Основное исправление серверной проверки доступно текущим клиентам. Клиентские изменения находятся в исходниках; сборка и выпуск новой версии App Store не выполнялись. Существующие изменения игры и версии приложения сохранены.

Документация Apple: [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi), [Get Transaction Info](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info), [Get All Subscription Statuses](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses).
