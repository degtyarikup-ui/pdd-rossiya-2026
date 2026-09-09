import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';

/// Сервис фоновой облачной синхронизации прогресса пользователя (ответы на вопросы,
/// ошибки, билеты, экзамены, стрик и избранное).
///
/// Работает по принципу offline-first: всё сохраняется мгновенно локально,
/// а при наличии интернета и авторизованного аккаунта асинхронно синхронизируется с сервером.
class ProgressSyncService {
  ProgressSyncService._internal();
  static final ProgressSyncService instance = ProgressSyncService._internal();

  ProgressDataSource? _dataSource;
  Timer? _debounceTimer;
  bool _isSyncing = false;

  void init(ProgressDataSource dataSource) {
    _dataSource = dataSource;
  }

  /// Запланировать фоновую синхронизацию с debounce (по умолчанию 3 сек после последнего действия).
  void scheduleSync({Duration delay = const Duration(seconds: 3)}) {
    final user = AuthService.instance.currentUser;
    if (user == null || !BackendConfig.hasNotifier) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      unawaited(syncWithServer());
    });
  }

  /// Отменить запланированную синхронизацию.
  void cancel() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Полная двусторонняя синхронизация с сервером.
  Future<void> syncWithServer() async {
    if (_isSyncing) return;
    final user = AuthService.instance.currentUser;
    final ds = _dataSource;
    if (user == null || ds == null || !BackendConfig.hasNotifier) return;

    _isSyncing = true;
    try {
      final localSnapshot = ds.exportProgressSnapshot();
      final url = Uri.parse('${BackendConfig.notifierUrl}/api/user/progress/sync');

      // Получаем версию приложения и платформу для отображения в админке
      String appVersion = '';
      String platform = '';
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = '${info.version}+${info.buildNumber}';
        if (kIsWeb) {
          platform = 'web';
        } else if (Platform.isIOS) {
          platform = 'ios';
        } else if (Platform.isAndroid) {
          platform = 'android';
        } else {
          platform = Platform.operatingSystem;
        }
      } catch (_) {}

      final resp = await http
          .post(
            url,
            headers: {
              'content-type': 'application/json',
              if (BackendConfig.notifierSecret.isNotEmpty)
                'x-install-secret': BackendConfig.notifierSecret,
            },
            body: jsonEncode({
              'userId': user.id,
              'progress': localSnapshot,
              if (appVersion.isNotEmpty) 'appVersion': appVersion,
              if (platform.isNotEmpty) 'platform': platform,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (body['ok'] == true && body['progress'] is Map) {
          final mergedProgress = Map<String, dynamic>.from(body['progress'] as Map);
          await ds.importProgressSnapshot(mergedProgress);
        }
      }
    } catch (e) {
      debugPrint('ProgressSyncService: syncWithServer error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Скачать актуальный прогресс с сервера (например, после входа в аккаунт на новом устройстве).
  Future<void> pullFromServer() async {
    final user = AuthService.instance.currentUser;
    final ds = _dataSource;
    if (user == null || ds == null || !BackendConfig.hasNotifier) return;

    try {
      final url = Uri.parse(
        '${BackendConfig.notifierUrl}/api/user/progress?userId=${Uri.encodeComponent(user.id)}',
      );
      final resp = await http
          .get(
            url,
            headers: {
              if (BackendConfig.notifierSecret.isNotEmpty)
                'x-install-secret': BackendConfig.notifierSecret,
            },
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (body['ok'] == true && body['progress'] is Map) {
          final serverProgress = Map<String, dynamic>.from(body['progress'] as Map);
          if (serverProgress.isNotEmpty) {
            await ds.importProgressSnapshot(serverProgress);
          }
        }
      }
    } catch (e) {
      debugPrint('ProgressSyncService: pullFromServer error: $e');
    }
  }
}
