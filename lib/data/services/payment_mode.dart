import 'package:pdd_app/core/config/store_config.dart';

/// Как оплачивать Премиум в Android-приложении.
enum PaymentMode {
  /// СБП через Platega: открывается страница оплаты в браузере.
  sbp,

  /// Покупка магазина (Google Play Billing).
  storeBilling,
}

/// Способ оплаты для Android.
///
/// RuStore — оплата через СБП без ограничений: сторонние платёжные системы
/// там разрешены, комиссии магазина нет.
///
/// Google Play — СБП только для пользователей в России. Правило Google о
/// Play Billing для России не действует (с 02.08.2022, «на данный момент»),
/// а для остальных стран остаётся обычная покупка через Play. Страна
/// определяется по устройству ([deviceCountry], ISO-код), а не по IP:
/// VPN её не меняет. Если страну определить не удалось, покупка идёт
/// через Play — это безопасный вариант по правилам магазина.
PaymentMode androidPaymentMode({
  required AppStore store,
  required String? deviceCountry,
}) {
  if (store == AppStore.rustore) return PaymentMode.sbp;
  return deviceCountry?.toUpperCase() == 'RU'
      ? PaymentMode.sbp
      : PaymentMode.storeBilling;
}
