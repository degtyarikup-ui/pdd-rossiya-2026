import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provider credentials are exchanged once and never written to preferences.
class AuthSessionStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'pdd_server_session';

  static Future<Map<String, dynamic>?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> write(Map<String, dynamic> session) =>
      _storage.write(key: _key, value: jsonEncode(session));

  static Future<void> clear() => _storage.delete(key: _key);
}
