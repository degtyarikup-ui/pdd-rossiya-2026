import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
