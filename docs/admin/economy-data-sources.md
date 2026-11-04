# Финансовые источники экономики

Проверено 4 ноября 2026 года по официальным документам и реальными read-only
запросами с уже существующими доступами. Секреты, идентификаторы заказов,
персональные данные и подписанные ссылки в документацию не включены.

## Что уже работает на странице

- Подтверждённые платежи СБП из журнала заказов; комиссия Platega по ставке 8%.
- Ручные доходы, расходы, комиссии и выводы; только комиссия вывода уменьшает прибыль.
- Текущие балансы Platega через admin-only `GET /api/admin/economy/platega`.
- Продажи магазинов пока **оценены по тарифам** на основе сохранённых покупок.
  Финансовые отчёты ниже проверены, но их импорт в страницу ещё не реализован.

## Проверенные возможности

| Источник | Доступные данные | Проверка текущего доступа | Ограничение |
| --- | --- | --- | --- |
| Platega `/balance/all` | Остаток по валютам, замороженные USDT | Работает из опубликованного Worker | Остаток сейчас, не прибыль за период |
| Apple Analytics: App Store Purchases Standard | Покупки/возвраты, Sales и Proceeds в USD | Реальные snapshot и ongoing segments доступны через существующий ASC Team key | Оценки; данные обычно полны через два дня |
| Apple Sales / Finance Reports | Цены, валюты, итоговые proceeds, финансовые корректировки | Ключ подходящего типа есть; Finance не проверен без Vendor Number | Для обоих нужен Vendor Number; Finance — по финансовым месяцам Apple |
| Google Play Orders | Фактическая оплата, налог, доход разработчика, история возвратов | Реальный заказ приложения успешно прочитан | Нужны известные order IDs; валюта покупателя не равна валюте банковской выплаты |
| Google Play GCS reports | История продаж; earnings — удержания и конвертация | Отчёт продаж за октябрь доступен; earnings пока пуст при успешном доступе | Earnings публикуется позднее, обычно к пятому числу следующего месяца |
| RuStore invoices | Реальные суммы с учётом скидок, даты, статусы, возвраты | Авторизованный запрос списка платежей успешно выполнен | Текущая сборка PDD продаёт через Platega; повторный учёт недопустим |

## Platega

[Балансы](https://docs.platega.io/получение-балансов-33582950e0): массив
`{amount,currency,frozenBalance?}`; frozenBalance только для USDT.
Не вычитать frozenBalance из amount автоматически: документация не определяет
amount как сумму до блокировки. USD и USDT — отдельные валюты.

[Транзакция](https://docs.platega.io/transactionstatusresponse-13226219d0)
содержит `comission`, `comissionUsdt`, `amountUsdt`, `comissionType`.
Единицы comission и смысл comissionType публичная схема не уточняет, поэтому
эти значения не заменяют расчётную комиссию 8%. Существующий
`payments.js:readPaymentTransaction` уже читает транзакции для проверки оплаты.
Публичный метод истории выводов не найден; создание выплат не нужно для учёта.

## App Store

Существующий локальный ASC Team key позволяет читать активные ONGOING и
ONE_TIME_SNAPSHOT отчёты [App Store Purchases Standard](https://developer.apple.com/documentation/analytics-reports/app-store-purchase).
Проверено скачивание реальных сегментов нашего приложения. Импортировать по дате
события, заменяя дневные разделы более свежей processingDate; не складывать
перекрывающиеся snapshot и ongoing. Sales − Proceeds включает комиссии **и налоги**.

Для [Sales Reports](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-salesreports)
нужны `reportType=SALES`, `reportSubType=SUMMARY`, frequency, reportDate и vendorNumber.
Для [Finance Reports](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-financereports)
нужны reportType, regionCode, финансовый месяц и vendorNumber; итоговые суммы
сверять с [полями финансового отчёта](https://developer.apple.com/help/app-store-connect/reference/reporting/financial-report-fields/).
Vendor Number не найден в текущей конфигурации; он доступен в App Store Connect
в финансовых отчётах под юридическим лицом. Права и номер проверяются перед
подключением месячной сверки. Банковскую выплату нельзя заменять proceeds.

Apple отдельно предупреждает: price/currency из
[App Store Server API](https://developer.apple.com/documentation/appstoreserverapi/jwstransactiondecodedpayload)
не являются источником финансовой сверки; использовать отчёты App Store Connect.

## Google Play

[Orders API](https://developers.google.com/android-publisher/api-ref/rest/v3/orders):
`GET /androidpublisher/v3/applications/{package}/orders/{orderId}` возвращает
`total`, `tax`, `developerRevenueInBuyerCurrency`, `state`, `orderHistory`.
Все эти поля подтверждены реальным ответом на существующий заказ приложения.
[BatchGet](https://developers.google.com/android-publisher/api-ref/rest/v3/orders/batchget)
читает до 1000 известных IDs, но не перечисляет все заказы самостоятельно.

Сервисный аккаунт из существующего `tools/store_release/publish.py:Play`
читает финансовый bucket со scope devstorage.read_only; это проверено скачиванием
отчёта sales за октябрь. В проекте уже есть GCS-интеграция `acquisition_reports.py`.
Историю заказов брать из `sales/salesreport_YYYYMM.zip`; итоговую комиссию,
пересчёт в валюту выплат и месячную сверку — из `earnings/earnings_YYYYMM.zip`.
[Состав и доступность отчётов](https://support.google.com/googleplay/android-developer/answer/6135870?hl=en).

Worker сейчас не сохраняет latestSuccessfulOrderId из subscriptionsv2 в
verifiedPurchase. Для восстановления ID можно читать подписку по уже сохранённому
purchaseToken. recurringPrice — цена плана, не итоговая сумма заказа.
Разность total и developerRevenueInBuyerCurrency нельзя целиком называть комиссией:
она учитывает также налог и возвраты.

## RuStore

[Список платежей](https://www.rustore.ru/help/work-with-rustore-api/api-subscription-payment/applications-appid-invoices):
`GET /public/applications/{appId}/invoices` с invoiceDate, invoiceStatuses, пагинацией.
Проверенный query status — **confirmed**: вариант CONFIRMED из перечня enum
возвращает 400. Авторизация текущим JWE-ключом работает.

[Карточка v2](https://www.rustore.ru/help/work-with-rustore-api/api-subscription-payment/v2-purchase-invoiceid)
возвращает order.amountCurrent в копейках, валюту, invoiceStatus,
paymentInfo.paymentDate, refundDate и идентификаторы продукта/покупки.
Комиссии, чистой выплаты и баланса в актуальной схеме нет.
[Финансовые отчёты](https://www.rustore.ru/help/developers/monetization/financial-reports)
документированы для консоли владельца компании, публичный endpoint не найден.

В `iap_service.dart` и `payment_mode.dart` магазинный billing RuStore выключен;
сборка принимает СБП. Такие продажи уже входят в Platega. Отдельный импорт
invoice станет нужен после подключения RuStore Pay SDK.

## Как подключать магазинные отчёты

Расширять существующий локальный importer с ключами в Keychain; отдавать Worker
нормализованные снимки через защищённый admin endpoint. Ключи публикации приложений
не переносить в браузер. По каждой валюте хранить gross, deductions, net, дату
события, источник, дату обработки и полноту покрытия. Фактические данные должны
**заменять** оценку магазина за покрытый период, а не прибавляться к ней.
Возвраты и пересмотренные отчёты должны пересчитывать прежний период без дублей.
Отдельно показывать продажи, proceeds и банковские поступления.
