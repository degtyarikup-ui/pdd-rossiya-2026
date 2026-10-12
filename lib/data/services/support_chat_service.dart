import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис взаимодействия с чатом техподдержки приложения.
///
/// Управляет постоянным ID клиента (привязка к аккаунту или устройству),
/// кэшированием истории в [SharedPreferences] и сетевыми запросами к
/// Cloudflare Worker, пересылающему сообщения в темы Telegram.
class SupportChatService {
  SupportChatService._();
  static final SupportChatService instance = SupportChatService._();

  static const String _prefSupportClientId = 'support_client_id';
  static const String _prefInstallId = 'install_id';
  static const String _prefCachePrefix = 'support_chat_msgs_';

  String? _cachedClientId;
  String? _cachedAppVersion;

  /// Получить стабильный ID клиента для обращений в поддержку.
  Future<String> getClientId() async {
    final user = AuthService.instance.currentUser;
    if (user != null && user.id.isNotEmpty) {
      _cachedClientId = user.id;
      return user.id;
    }

    if (_cachedClientId != null && _cachedClientId!.isNotEmpty) {
      return _cachedClientId!;
    }

    final prefs = await SharedPreferences.getInstance();
    var clientId = prefs.getString(_prefSupportClientId);
    if (clientId != null && clientId.isNotEmpty) {
      _cachedClientId = clientId;
      return clientId;
    }

    final installId = prefs.getString(_prefInstallId);
    if (installId != null && installId.isNotEmpty) {
      _cachedClientId = installId;
      await prefs.setString(_prefSupportClientId, installId);
      return installId;
    }

    // Генерируем уникальный случайный 16-байтный hex ID
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    clientId = 'guest_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    await prefs.setString(_prefSupportClientId, clientId);
    _cachedClientId = clientId;
    return clientId;
  }

  /// Получить имя текущего пользователя (или null)
  String? getUserDisplayName() {
    final user = AuthService.instance.currentUser;
    if (user != null && user.name.isNotEmpty) {
      return user.name;
    }
    return null;
  }

  /// Загрузить локально закэшированные сообщения
  Future<List<SupportChatMessage>> loadCachedMessages() async {
    try {
      final clientId = await getClientId();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefCachePrefix$clientId');
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => SupportChatMessage.fromJson(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Сохранить сообщения в локальный кэш
  Future<void> saveCachedMessages(List<SupportChatMessage> messages) async {
    try {
      final clientId = await getClientId();
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(messages.map((m) => m.toJson()).toList());
      await prefs.setString('$_prefCachePrefix$clientId', encoded);
    } catch (_) {}
  }

  /// Получить версию приложения
  Future<String> _getAppVersion() async {
    if (_cachedAppVersion != null) return _cachedAppVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedAppVersion = '${info.version}+${info.buildNumber}';
      return _cachedAppVersion!;
    } catch (_) {
      return '1.0.0';
    }
  }

  /// Загрузить актуальные сообщения с сервера
  Future<List<SupportChatMessage>> fetchMessages({int? since}) async {
    if (!BackendConfig.hasNotifier) return [];
    final clientId = await getClientId();

    try {
      final response = await sendWithRetry(
        (host) => http.get(
          Uri.parse('$host/api/support/messages').replace(
            queryParameters: {
              'clientId': clientId,
              if (since != null && since > 0) 'since': since.toString(),
            },
          ),
          headers: {
            'content-type': 'application/json',
            if (BackendConfig.notifierSecret.isNotEmpty)
              'x-install-secret': BackendConfig.notifierSecret,
          },
        ),
        hosts: BackendConfig.notifierHosts,
        attempts: const [
          Duration(seconds: 4),
          Duration(seconds: 6),
        ],
      );

      if (response.statusCode != 200) return [];
      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      if (body == null || body['ok'] != true) return [];

      final list = body['messages'] as List<dynamic>?;
      if (list == null) return [];

      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => SupportChatMessage.fromJson(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Сбой отправки уходит в отчёты с операцией support.send (без текста сообщения).
  void _reportSendFailure(String code) {
    ErrorReporter.report(ErrorCategory.app, 'support.send', code: code);
  }

  /// Отправить сообщение в поддержку
  Future<SupportChatMessage?> sendMessage(String text) async {
    if (!BackendConfig.hasNotifier) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final clientId = await getClientId();
    final userName = getUserDisplayName();
    final appVersion = await _getAppVersion();
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    final isPremium = PremiumService.instance.isPremium;

    final payload = <String, dynamic>{
      'clientId': clientId,
      'platform': platform,
      'appVersion': appVersion,
      'isPremium': isPremium,
      'text': trimmed,
    };
    if (userName != null) {
      payload['userName'] = userName;
    }

    try {
      final response = await sendWithRetry(
        (host) => http.post(
          Uri.parse('$host/api/support/send'),
          headers: {
            'content-type': 'application/json',
            if (BackendConfig.notifierSecret.isNotEmpty)
              'x-install-secret': BackendConfig.notifierSecret,
          },
          body: jsonEncode(payload),
        ),
        hosts: BackendConfig.notifierHosts,
        attempts: const [
          Duration(seconds: 6),
          Duration(seconds: 8),
        ],
      );

      if (response.statusCode != 200) {
        _reportSendFailure('http_${response.statusCode}');
        return null;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      if (body == null || body['ok'] != true) {
        _reportSendFailure('bad_response');
        return null;
      }

      final msgJson = body['message'] as Map<String, dynamic>?;
      if (msgJson == null) {
        // Сервер ответил ok, но без сообщения: так отвечает старый воркер без этого маршрута.
        _reportSendFailure('no_message');
        return null;
      }

      return SupportChatMessage.fromJson(msgJson);
    } catch (error) {
      _reportSendFailure(ErrorReporter.codeFor(error));
      return null;
    }
  }
}
