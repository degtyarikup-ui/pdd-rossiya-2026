import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/services/device_region.dart';

/// Как оплачивать Премиум в Android-приложении.
enum PaymentMode {
  /// СБП через Platega: открывается страница оплаты в браузере.
  sbp,

  /// Покупка магазина (Google Play Billing).
  storeBilling,

  /// This distribution has no supported payment method in this region.
  unavailable,
}

/// Человек в России: так говорит устройство (сеть, SIM, локаль) или сам
/// Google Play — страна его платёжного аккаунта. Российскому аккаунту Play
/// Billing недоступен, поэтому без второго признака человек с иностранной SIM
/// или английской локалью оставался без способа оплаты.
bool _inRussia(String? deviceCountry, String? playCountry) =>
    deviceCountry?.toUpperCase() == 'RU' || playCountry?.toUpperCase() == 'RU';

/// RuStore использует СБП без проверки страны.
/// Google Play: СБП только в России; вне России и без страны — Billing.
PaymentMode androidPaymentMode({
  required AppStore store,
  required String? deviceCountry,
  String? playCountry,
}) {
  if (store == AppStore.rustore) {
    return PaymentMode.sbp;
  }
  return _inRussia(deviceCountry, playCountry)
      ? PaymentMode.sbp
      : PaymentMode.storeBilling;
}

/// Какие способы оплаты показать в Android-приложении, лучший — первым.
///
/// Google Play, Россия: на выбор СБП (работает у всех российских карт) и
/// покупка через Play. Остальные страны — только Play, как требуют правила
/// магазина. RuStore — СБП без ограничений по стране.
List<PaymentMode> androidPaymentModes({
  required AppStore store,
  required String? deviceCountry,
  String? playCountry,
}) {
  if (store == AppStore.rustore) {
    return [androidPaymentMode(store: store, deviceCountry: deviceCountry)];
  }
  return _inRussia(deviceCountry, playCountry)
      ? const [PaymentMode.sbp, PaymentMode.storeBilling]
      : const [PaymentMode.storeBilling];
}

/// Способы оплаты для этой сборки и этого человека, лучший — первым.
/// Страну аккаунта Play спрашиваем, только если устройство не российское:
/// иначе ответ уже ясен, и пейвол не ждёт магазин.
Future<List<PaymentMode>> currentAndroidPaymentModes() async {
  final store = StoreConfig.current;
  if (store == AppStore.rustore) {
    return androidPaymentModes(store: store, deviceCountry: null);
  }
  final device = await DeviceRegion.countryCode();
  final play = device == 'RU' ? null : await DeviceRegion.playCountry();
  return androidPaymentModes(
    store: store,
    deviceCountry: device,
    playCountry: play,
  );
}
