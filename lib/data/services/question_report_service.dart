import 'package:pdd_app/data/services/install_reporter.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Отправка жалобы на конкретный вопрос: «здесь опечатка», «ответ неверный»,
/// «картинка не та».
///
/// Уходит в тот же Cloudflare Worker, что и пинги об установке, а он
/// пересылает сообщение в Telegram-чат (см. `server/install-notifier/`).
///
/// Почему не письмо: mailto открывает почтовый клиент, которого у части
/// людей просто нет, а у остальных это лишний экран и повод передумать. До
/// отправки доходили бы единицы. Форма внутри приложения — два касания.
class QuestionReportService {
  QuestionReportService._();

  /// Максимальная длина сообщения. Ограничение и в поле ввода, и здесь:
  /// в Telegram у сообщения свой лимит, а длинную простыню всё равно никто
  /// не напишет с телефона.
  static const int maxMessageLength = 1000;

  /// Godot sends question data only. Identity and device metadata stay in Flutter.
  static Future<bool> sendGameReport(
    Map<String, dynamic> report, {
    AuthService? auth,
  }) async {
    final id = report['question_id'];
    final message = report['message'];
    final title = report['question_text'];
    if (id is! String || id.isEmpty || id.length > 120 || message is! String) {
      return false;
    }
    final ref = RegExp(r'^ticket_(?:cd_)?(\d+)_(\d+)$').firstMatch(id);
    return send(
      message: message,
      questionId: id,
      questionText: title is String ? title : null,
      ticketNumber: ref == null ? null : int.parse(ref.group(1)!),
      mode: 'city',
      auth: auth,
    );
  }

  /// Отправляет жалобу. Возвращает true при успехе.
  ///
  /// Идентификатор установки берём тот же, что у пинга об установке, — чтобы
  /// несколько жалоб от одного человека были видны как от одного человека
  /// (и чтобы работал антиспам на стороне воркера).
  static Future<bool> send({
    required String message,
    required String questionId,
    String? questionText,
    int? ticketNumber,
    String? category,
    String? topic,
    String? mode,
    AuthService? auth,
  }) async {
    if (!BackendConfig.hasNotifier) return false;
    final text = message.trim();
    if (text.isEmpty) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        ...await InstallReporter.clientMetadata(),
        'kind': 'report',
        'message': text.length > maxMessageLength
            ? text.substring(0, maxMessageLength)
            : text,
        'question_id': questionId,
        if (questionText != null && questionText.isNotEmpty)
          'question_text': questionText,
        if (ticketNumber != null && ticketNumber > 0) 'ticket': ticketNumber,
        if (category == 'ab' || category == 'cd') 'category': category,
        if (topic != null && topic.isNotEmpty) 'topic': topic,
        if (mode != null && mode.isNotEmpty) 'mode': mode,
        'country': CountryConfig.current.code,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'version': await _appVersion(),
        // install_id уже мог быть создан InstallReporter'ом; если его нет
        // (веб, где пинг отключён) — шлём без него, воркер это переживёт.
        if (prefs.getString('install_id') != null)
          'install_id': prefs.getString('install_id'),
      };

      final resp = await http
          .post(
            Uri.parse(BackendConfig.notifierUrl),
            // Сервер определяет автора по сессии, а не по имени/почте из
            // тела запроса. Для гостя serverHeaders не содержит authorization.
            headers: (auth ?? AuthService.instance).serverHeaders,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 15));

      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      // Оффлайн или сбой сети — пользователю покажем «не отправилось»,
      // он попробует позже.
      return false;
    }
  }

  static Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '';
    }
  }
}
