import 'package:pdd_app/core/config/store_config.dart';

/// Как оплачивать Премиум в Android-приложении.
enum PaymentMode {
  /// СБП через Platega: открывается страница оплаты в браузере.
  sbp,

  /// Покупка магазина (Google Play Billing).
  storeBilling,

  /// This distribution has no supported payment method in this region.
  unavailable,
}

/// RuStore использует СБП без проверки страны.
/// Google Play: СБП только в России; вне России и без страны — Billing.
PaymentMode androidPaymentMode({
  required AppStore store,
  required String? deviceCountry,
}) {
  if (store == AppStore.rustore) {
    return PaymentMode.sbp;
  }
  return deviceCountry?.toUpperCase() == 'RU'
      ? PaymentMode.sbp
      : PaymentMode.storeBilling;
}

/// Какие способы оплаты показать в Android-приложении, лучший — первым.
///
/// Google Play, российское устройство: на выбор СБП (работает у всех
/// российских карт) и покупка через Play. Остальные страны — только Play,
/// как требуют правила магазина. RuStore — СБП без ограничений по стране.
List<PaymentMode> androidPaymentModes({
  required AppStore store,
  required String? deviceCountry,
}) {
  if (store == AppStore.rustore) {
    return [androidPaymentMode(store: store, deviceCountry: deviceCountry)];
  }
  return deviceCountry?.toUpperCase() == 'RU'
      ? const [PaymentMode.sbp, PaymentMode.storeBilling]
      : const [PaymentMode.storeBilling];
}
