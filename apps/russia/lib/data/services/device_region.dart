import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Страна устройства (ISO-код, например `RU`) по данным Android: сеть
/// мобильного оператора, затем SIM, затем системная локаль. Это не IP,
/// поэтому VPN на результат не влияет. Вне Android и при ошибке — null.
class DeviceRegion {
  DeviceRegion._();

  static const MethodChannel _channel = MethodChannel('pdd/device_region');

  /// Только для тестовых сборок: `--dart-define=DEVICE_REGION=RU` подменяет
  /// страну, чтобы увидеть российский пейволл не из России. В магазинных
  /// сборках не задаётся.
  static const String _override = String.fromEnvironment('DEVICE_REGION');

  /// Сколько ждать ответа Google Play о стране аккаунта.
  @visibleForTesting
  static Duration playTimeout = const Duration(seconds: 3);

  /// Как спросить у Google Play страну платёжного аккаунта. Заменяется в тестах.
  @visibleForTesting
  static Future<String> Function() readPlayCountry = () =>
      InAppPurchase.instance.countryCode();

  static Future<String?>? _play;

  /// Страна платёжного аккаунта Google Play (ISO-код) — её сообщает сам
  /// магазин, VPN на неё тоже не влияет. Ответ запоминается до конца сеанса;
  /// при ошибке или без ответа — null, и следующий вызов спросит снова.
  static Future<String?> playCountry() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(null);
    }
    if (_override.isNotEmpty) return Future.value(_override.toUpperCase());
    return _play ??= _readPlay().then((code) {
      if (code == null) _play = null;
      return code;
    });
  }

  static Future<String?> _readPlay() async {
    try {
      final code = await Future.sync(readPlayCountry).timeout(playTimeout);
      return code.isEmpty ? null : code.toUpperCase();
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void resetPlayCountry() => _play = null;

  static Future<String?> countryCode() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    if (_override.isNotEmpty) return _override.toUpperCase();
    try {
      final code = await _channel.invokeMethod<String>('countryCode');
      return code == null || code.isEmpty ? null : code.toUpperCase();
    } catch (_) {
      return null;
    }
  }
}
