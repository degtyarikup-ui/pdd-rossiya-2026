import 'package:flutter/services.dart';

/// Credentials are returned once; storage belongs to the server session store.
class YandexNativeAuth {
  static const _channel = MethodChannel('pdd/yandex_auth');

  static Future<String?> signIn() async {
    final token = await _channel.invokeMethod<String>('signIn');
    if (token != null && token.isEmpty) {
      throw PlatformException(code: 'missing_credential');
    }
    return token;
  }

  static Future<void> signOut() => _channel.invokeMethod<void>('signOut');
}
