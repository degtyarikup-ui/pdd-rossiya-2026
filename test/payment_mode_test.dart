import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/services/payment_mode.dart';

void main() {
  group('Android: способ оплаты по магазину и стране устройства', () {
    test('Google Play: российское устройство — СБП', () {
      expect(
        androidPaymentMode(store: AppStore.googlePlay, deviceCountry: 'RU'),
        PaymentMode.sbp,
      );
      expect(
        androidPaymentMode(store: AppStore.googlePlay, deviceCountry: 'ru'),
        PaymentMode.sbp,
      );
    });

    test('Google Play: устройство за пределами России — покупка через Play', () {
      for (final country in ['BY', 'KZ', 'DE', 'US']) {
        expect(
          androidPaymentMode(store: AppStore.googlePlay, deviceCountry: country),
          PaymentMode.storeBilling,
          reason: country,
        );
      }
    });

    test('Google Play: страна не определилась — покупка через Play', () {
      expect(
        androidPaymentMode(store: AppStore.googlePlay, deviceCountry: null),
        PaymentMode.storeBilling,
      );
      expect(
        androidPaymentMode(store: AppStore.googlePlay, deviceCountry: ''),
        PaymentMode.storeBilling,
      );
    });

    test('RuStore: СБП без ограничений, какая бы ни была страна', () {
      for (final country in ['RU', 'BY', 'DE', null]) {
        expect(
          androidPaymentMode(store: AppStore.rustore, deviceCountry: country),
          PaymentMode.sbp,
          reason: '$country',
        );
      }
    });
  });
}
