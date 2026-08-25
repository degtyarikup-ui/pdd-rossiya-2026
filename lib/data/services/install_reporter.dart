import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/services/browser_info_stub.dart'
    if (dart.library.js_interop) 'package:pdd_app/data/services/browser_info_web.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Отправляет ОДНО уведомление в Telegram при первой установке приложения —
/// аналог «нового пользователя» в логах.
///
/// Архитектура: приложение шлёт событие на серверный прокси (Cloudflare
/// Worker), а тот уже дёргает Telegram Bot API. Токен бота в код приложения
/// НЕ попадает — он лежит в секрете воркера.
///
/// Правила надёжности:
/// - Полностью «fire-and-forget»: любые ошибки/оффлайн проглатываются и
///   никогда не ломают и не тормозят запуск приложения.
/// - Флаг об отправке ставится ТОЛЬКО при ответе 2xx. Если первый запуск был
///   офлайн — событие уедет на следующем запуске, а не потеряется.
/// - Пока не задан URL воркера — сервис молча ничего не делает (no-op).
class InstallReporter {
  InstallReporter._();

  /// URL воркера. Можно вставить прямо сюда (заменить PASTE_WORKER_URL_HERE),
  /// либо передавать при сборке через `--dart-define=INSTALL_NOTIFY_URL=...`.
  /// Адрес и секрет — общие с формой жалоб на вопрос (см. BackendConfig).
  static const String _endpoint = BackendConfig.notifierUrl;

  /// Опциональный общий секрет (защита эндпоинта от постороннего спама).
  /// Если задан на воркере — собирай приложение с тем же
  /// `--dart-define=INSTALL_NOTIFY_SECRET=...`.
  static const String _secret = BackendConfig.notifierSecret;

  static const String _keyInstallId = 'install_id';
  static const String _keyReported = 'install_reported';

  /// Вызывать один раз на старте приложения. НЕ await — fire-and-forget.
  ///
  /// iOS включён (2026-08-12, ранее был отключён ради декларации
  /// «Data Not Collected»). ⚠️ Пока сбор включён, в App Store Connect →
  /// App Privacy декларация обязана это отражать: Identifiers (Device ID) +
  /// Diagnostics, назначение Analytics, «not linked to identity»,
  /// «not used for tracking» (ATT-запрос при этом не нужен). Иначе апдейт
  /// рискует отлететь на модерации за расхождение с декларацией.
  static Future<void> reportIfNeeded() async {
    if (!_endpoint.startsWith('https://')) return; // не настроено — тихо выходим

    try {
      final prefs = await SharedPreferences.getInstance();
      // Отчитываемся РОВНО один раз за всё время жизни установки. Флаг живёт в
      // SharedPreferences, а он переживает обновления приложения — поэтому при
      // последующих апдейтах пользователь повторно НЕ считается.
      if (prefs.getBool(_keyReported) == true) return;

      // Свежая установка или обновившийся существующий пользователь — определяем
      // по наличию данных приложения (прогресс/настройки/стрик) на момент
      // первого отчёта. Считаем и тех, и других, но помечаем по-разному.
      final isExisting = prefs
          .getKeys()
          .any((k) => k != _keyReported && k != _keyInstallId);

      var installId = prefs.getString(_keyInstallId);
      if (installId == null) {
        installId = _generateId();
        await prefs.setString(_keyInstallId, installId);
      }

      final payload = <String, dynamic>{
        'install_id': installId,
        'kind': isExisting ? 'update' : 'new',
        'country': CountryConfig.current.code,
        'app': CountryConfig.current.appTitle,
        ...await _deviceFields(),
      };

      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              if (_secret.isNotEmpty) 'x-install-secret': _secret,
            },
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await prefs.setBool(_keyReported, true);
      }
    } catch (_) {
      // Оффлайн / ошибка сети / что угодно — молча игнорируем, повторим позже.
    }
  }

  /// Собирает описание устройства. Всё в try/catch — плагины на отдельных
  /// платформах могут кинуть, но это не должно ронять отправку.
  ///
  /// Веб — ОТДЕЛЬНЫЙ путь, без device_info_plus/package_info_plus: их
  /// веб-регистрация плагина (через `dart:ui_web`'s bootstrapEngine) надёжно
  /// не срабатывает на некоторых хостингах (проверено на pdd-drive.ru —
  /// GitHub Pages/Fastly: стабильный `MissingPluginException`, хотя тот же
  /// бандл локально работает без проблем — похоже на баг совместимости
  /// Flutter Web SDK с конкретным хостингом). Вместо плагина читаем те же
  /// данные напрямую: версию — из `version.json` обычным HTTP-запросом,
  /// браузер/платформу — из `navigator` (см. browser_info_web.dart).
  static Future<Map<String, dynamic>> _deviceFields() async {
    final result = <String, dynamic>{
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'locale': ui.PlatformDispatcher.instance.locale.toLanguageTag(),
      'source': kIsWeb ? 'Web' : 'unknown',
    };

    if (kIsWeb) {
      try {
        final resp = await http
            .get(Uri.parse('version.json'))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final version = data['version'] as String?;
          final build = data['build_number'] as String?;
          if (version != null && build != null) {
            result['version'] = '$version+$build';
          }
        }
      } catch (_) {}
      result.addAll(browserInfoFields());
      return result;
    }

    try {
      final info = await PackageInfo.fromPlatform();
      result['version'] = '${info.version}+${info.buildNumber}';
      result['source'] = _sourceFromInstaller(info.installerStore);
    } catch (_) {}

    try {
      final device = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await device.androidInfo;
        result['device'] = '${a.manufacturer} ${a.model}';
        result['os'] = 'Android ${a.version.release} (SDK ${a.version.sdkInt})';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await device.iosInfo;
        result['device'] = i.utsname.machine;
        result['os'] = '${i.systemName} ${i.systemVersion}';
      }
    } catch (_) {}

    return result;
  }

  /// Человекочитаемый источник по пакету-установщику (Android/iOS).
  /// Google Play, RuStore, App Store, TestFlight и т.п.; иначе — сам пакет.
  static String _sourceFromInstaller(String? installer) {
    if (installer == null || installer.isEmpty) return 'Sideload/неизвестно';
    const map = {
      'com.android.vending': 'Google Play',
      'ru.vk.store': 'RuStore',
      'com.apple.AppStore': 'App Store',
      'com.apple.TestFlight': 'TestFlight',
    };
    return map[installer] ?? installer;
  }

  /// Случайный 128-битный идентификатор установки (hex). Без внешних пакетов.
  static String _generateId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
