# Восстановление истории покупок

`restore.py` только читает существующие источники и сохраняет локальный
нормализованный снимок. Платежи, сроки Premium и рабочий KV он не изменяет.
Ключи берутся из существующих интеграций в Связке ключей macOS; Cloudflare
использует уже выполненный вход Wrangler.

Запуск из `apps/russia/`:

```sh
/usr/bin/python3 tools/store_revenue/restore.py
/usr/bin/python3 -m unittest discover -s tools/store_revenue -p 'test_*.py'
```

Результат — `output/store-revenue-restore/candidate.json` и сводка рядом,
права `0600`. Снимок не содержит аккаунтов, адресов, чеков, токенов и исходных
ID транзакций. Для сопоставления используется SHA-256 от `method:transactionId`.
Не коммитить рабочие результаты: они содержат финансовые данные.

App Store: исходные транзакции находятся в сохранённых ссылках профилей,
недавних метках уведомлений и общей истории серверных уведомлений Apple
за 179 дней. Для каждого найденного клиента читаются все страницы Transaction
History v2, включая продления. Проверяются приложение, продукт и среда;
цена, валюта, дата покупки и отзыв берутся из ответа Apple. Такая выборка
не доказывает отсутствие старых покупок за пределами сохранившейся истории.

Google Play: читаются все доступные месячные sales-архивы российского
приложения. Дополнительные IDs берутся из сохранённых подписок. Реальная
сумма и статус читаются через Orders API; используется дата обработки платежа,
при её отсутствии — дата создания заказа. Для частичных возвратов вычитаются
только подтверждённые суммы той же валюты. При недостающих данных импорт
останавливается. Цены тарифов и developer proceeds не заменяют оплату клиента.

Снимок имеет версию 1, поля `transactions`, `coverage`, `importedAt` и
`replaceLegacyBefore` с границей замены старых агрегатов. Проверенный снимок
можно импортировать в отдельный аналитический ключ `premium:revenue_history:v1`.
Он объединяется с новыми записями по стабильному ID, повторный импорт не
добавляет покупки. Нельзя устанавливать неограниченный `coverage.complete`
по результатам поиска только известных клиентов.

Официальные источники:

- [Apple Transaction History](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-history)
- [Apple Notification History](https://developer.apple.com/documentation/appstoreserverapi/get-notification-history)
- [Google Orders](https://developers.google.com/android-publisher/api-ref/rest/v3/orders)
- [Google Play reports](https://support.google.com/googleplay/android-developer/answer/6135870?hl=en)
