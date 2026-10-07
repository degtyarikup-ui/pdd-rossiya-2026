# Запуск оплаты на сайте (Platega, СБП)

Код готов и задеплоен в выключенном виде: без ключей веб-пейвол показывает
заглушку «СБП скоро» и собирает почту. Оплата включается секретами воркера,
пересобирать приложение не нужно.

## Как устроено

- Веб-пейвол → вход → почта для чека → `POST /api/user/pay-intent`.
  Сервер записывает выбор (`pay_intent:<userId>`) и создаёт платёж в Platega
  (`POST https://app.platega.io/transaction/process`, метод 2 — СБП).
  Заказ — `pay_order:<orderId>`, индекс `pay_tx:<transactionId>`.
- Человек платит на форме Platega и возвращается на
  `https://pdd-drive.ru/app/?pay=done&order=<id>` (неудача — `?pay=failed`).
- Доступ начисляется, когда Platega подтверждает платёж:
  - уведомление `POST /api/pay/platega/callback` (проверка заголовков
    `X-MerchantId`/`X-Secret`);
  - или проверка после возврата `POST /api/user/pay-check`.
  В обоих случаях статус и сумма перечитываются у Platega
  (`GET /transaction/{id}`). Срок — `extendEntitlement(user, 'web', days)`:
  добавляется после действующего срока из любого источника, один раз на
  заказ (`user.webPayments`). Возврат денег (`CHARGEBACKED`) снимает срок.
- Страница `/tarify/`: кнопки «Оплатить» по тарифам. Пока оплата выключена —
  окно «скоро» и почта без входа (`POST /api/pay/lead` → `pay_lead:<email>`,
  тот же список `/api/admin/pay-intents`); включена — переход в веб-версию.
- Тарифы: `WEB_TARIFFS` в `server/install-notifier/payments.js` = страница
  `web_landing/ru/tarify/` = веб-пейвол (99 ₽ / 7 дней, 290 ₽ / 90 дней).

## Чек-лист запуска

1. Получить у Platega MerchantId и API-ключ.
2. В кабинете Platega указать адрес уведомлений (Callback URL):
   `https://pdd-install-notifier.sergei-pdd.workers.dev/api/pay/platega/callback`
3. Положить ключи в воркер (значения вводятся в терминале, в код не попадают):
   ```bash
   cd server/install-notifier
   npx wrangler secret put PLATEGA_MERCHANT_ID
   npx wrangler secret put PLATEGA_SECRET
   ```
4. Проверить: `GET /api/pay/status` → `"available": true`.
5. Купить неделю за 99 ₽ своим аккаунтом в веб-версии; в Telegram придёт
   «💰 Оплата на сайте», премиум появится и в приложении на телефоне.
6. Страница `/tarify/` переключится сама: кнопки «Оплатить» поведут в
   веб-версию, фраза «оплата подключается» скроется (`/api/pay/status`).

Выключить оплату — удалить секреты (`npx wrangler secret delete …`):
пейвол снова станет заглушкой.

## Что дальше

- Подписки с автопродлением — Platega подключает через ~1 месяц работы при
  обороте от 5 000 ₽/сутки (`docs.platega.io` → «Создать подписку»).
- СБП в Android-приложении — только для пользователей в России (правило
  Google Play от 02.08.2022); RuStore сторонние платежи разрешает. В iOS —
  только покупки App Store, без ссылок на оплату на сайте.
