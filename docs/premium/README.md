# Вход, оплата и Премиум — карта и инварианты

Самая чувствительная часть проекта: ошибка здесь стоит денег или доступа
людей к купленному. Перед правкой прочитать этот файл целиком; после правки
прогнать все проверки из раздела «Как проверить».

## Как это устроено

```
Приложение (Flutter)                          Воркер (Cloudflare, server/install-notifier)
──────────────────────                        ──────────────────────────────────────────
AuthService ── вход Google/Яндекс/Apple ──►   /api/auth/*        → сессия, user.id = <provider>_<sub>
PremiumService ─ syncWithServer ──────────►   /api/user/status   → isPremium / premiumExpiresAt / premiumSource
IapService ─ покупка в сторе ─► recordPurchase ► /api/user/purchase → store_verification.js проверяет чек
PremiumService.startWebPayment ───────────►   /api/user/pay-intent → payments.js → Platega (СБП)
PendingPayment + checkPendingPayment ─────►   /api/user/pay-check  → срок только по статусу от Platega
                                              /api/pay/platega/callback → settleOrder
```

Премиум привязан к **аккаунту на сервере**, не к устройству. Google, Яндекс и
Apple — разные аккаунты.

## Файлы

| Где | Что |
| --- | --- |
| `lib/data/services/auth_service.dart` | Вход/выход/удаление аккаунта, все провайдеры |
| `lib/data/services/auth_session_store.dart` | Хранение сессии (учётки провайдеров не пишутся в prefs) |
| `lib/data/services/web_oauth_*.dart`, `yandex_native_auth.dart` | Веб-OAuth (state-проверка), нативный Яндекс |
| `lib/data/services/premium_service.dart` | Статус Премиума, лимиты бесплатного режима, веб-оплата |
| `lib/data/services/iap_service.dart` | Покупки App Store / Google Play, восстановление |
| `lib/data/services/payment_mode.dart` | Какой способ оплаты показать (по сборке и стране) |
| `lib/data/services/pending_payment.dart` | Незавершённая СБП-оплата на Android |
| `lib/data/services/device_region.dart` | Страна устройства (сеть/SIM/локаль, **не IP**) |
| `lib/core/config/store_config.dart` | `--dart-define=STORE=play|rustore` |
| `lib/presentation/widgets/premium_paywall_sheet.dart`, `web_payment_dialog.dart`, `web_payment_return.dart`, `subscription_management_sheet.dart`, `premium_granted_dialog.dart` | Пейвол и экраны оплаты |
| `lib/presentation/widgets/auth_modal_sheet.dart`, `auth_provider_button.dart`, `yandex_*`, `google_web_sign_in_button*` | Экраны входа |
| `web_landing/ru/tarify/`, `pay-done/` | Тарифы на сайте и возврат после оплаты |
| `server/install-notifier/entitlements.js` | Сроки Премиума по источникам |
| `server/install-notifier/payments.js` | Тарифы `WEB_TARIFFS`, Platega, подтверждение оплаты |
| `server/install-notifier/store_verification.js`, `purchase_claims.js` | Проверка чеков сторов |
| `docs/premium/web-payments-launch.md` | Запуск веб-оплаты, секреты, устройство |
| `docs/premium/web-auth.md` | Веб-вход |
| `docs/premium/subscription-fix-2026-10-02.md` | История исправления подписок |

## Инварианты (нарушать нельзя)

1. Сроки пишутся только через `setEntitlement` / `extendEntitlement`
   (`entitlements.js`), итог — самый дальний срок из источников
   `appstore | googleplay | web | admin_grant`. Поля `isPremium` и т.п.
   напрямую не трогать.
2. Веб-оплата начисляет срок **только** по статусу, перечитанному у Platega,
   никогда по параметрам возврата или колбэка.
3. iOS — только IAP. В iOS-сборке не должно быть ссылок на оплату на сайте.
4. Android, Google Play: СБП только для устройств в России (страна по
   `DeviceRegion`), остальным — Play Billing. RuStore (`STORE=rustore`) — СБП для
   всех, Play Billing не используется.
5. Покупка сохраняет аккаунт того, кто её начал (`premium_owner_id`): вход
   другим аккаунтом не переносит Премиум.
6. Без секрета доступ закрывается, а не открывается. Значений по умолчанию
   для ключей нет (репозиторий публичный).
7. Веб-OAuth принимается только во вкладке, которая начала вход; личность
   подтверждает сервер.

## Как проверить

```bash
flutter test test/premium_service_test.dart test/premium_offline_session_test.dart \
  test/premium_granted_dialog_test.dart test/iap_recovery_test.dart \
  test/iap_account_owner_test.dart test/verified_purchase_test.dart \
  test/payment_mode_test.dart test/pending_payment_test.dart \
  test/auth_jwt_claim_test.dart test/auth_login_recovery_test.dart \
  test/auth_provider_button_test.dart test/auth_startup_sync_test.dart \
  test/web_oauth_state_test.dart test/yandex_native_auth_test.dart
cd server/install-notifier && npm run test:security
```

Тестовая СБП-сборка не из России: `DEVICE_REGION=RU ./scripts/install_dev.sh --build`.
