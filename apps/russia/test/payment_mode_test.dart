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

    test(
      'Google Play: устройство за пределами России — покупка через Play',
      () {
        for (final country in ['BY', 'KZ', 'DE', 'US']) {
          expect(
            androidPaymentMode(
              store: AppStore.googlePlay,
              deviceCountry: country,
            ),
            PaymentMode.storeBilling,
            reason: country,
          );
        }
      },
    );

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

    test('RuStore: СБП независимо от страны, включая неизвестную', () {
      for (final country in ['RU', 'ru', 'BY', 'DE', 'US', null, '']) {
        expect(
          androidPaymentMode(store: AppStore.rustore, deviceCountry: country),
          PaymentMode.sbp,
          reason: '$country',
        );
      }
    });
  });

  group('Android: способы на выбор', () {
    test('Google Play, российское устройство: СБП и Play, СБП первым', () {
      expect(
        androidPaymentModes(store: AppStore.googlePlay, deviceCountry: 'ru'),
        [PaymentMode.sbp, PaymentMode.storeBilling],
      );
    });

    test('Google Play вне России или без страны: только Play', () {
      for (final country in ['BY', 'DE', null, '']) {
        expect(
          androidPaymentModes(
            store: AppStore.googlePlay,
            deviceCountry: country,
          ),
          [PaymentMode.storeBilling],
          reason: '$country',
        );
      }
    });

    test('Google Play: аккаунт Play российский — СБП и Play, как в России', () {
      for (final device in ['DE', 'US', null, '']) {
        expect(
          androidPaymentModes(
            store: AppStore.googlePlay,
            deviceCountry: device,
            playCountry: 'ru',
          ),
          [PaymentMode.sbp, PaymentMode.storeBilling],
          reason: '$device',
        );
        expect(
          androidPaymentMode(
            store: AppStore.googlePlay,
            deviceCountry: device,
            playCountry: 'RU',
          ),
          PaymentMode.sbp,
          reason: '$device',
        );
      }
    });

    test('Google Play: аккаунт Play не российский — правило по устройству', () {
      expect(
        androidPaymentModes(
          store: AppStore.googlePlay,
          deviceCountry: 'DE',
          playCountry: 'DE',
        ),
        [PaymentMode.storeBilling],
      );
      expect(
        androidPaymentModes(
          store: AppStore.googlePlay,
          deviceCountry: 'RU',
          playCountry: 'KZ',
        ),
        [PaymentMode.sbp, PaymentMode.storeBilling],
      );
    });

    test('RuStore: только СБП', () {
      expect(
        androidPaymentModes(store: AppStore.rustore, deviceCountry: 'DE'),
        [PaymentMode.sbp],
      );
    });
  });
}
