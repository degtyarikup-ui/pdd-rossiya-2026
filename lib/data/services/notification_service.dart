import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Локальные напоминания о серии (стрике).
///
/// Одно уведомление в 20:00 по локальному времени — **только если серия активна
/// и пользователь сегодня ещё не тренировался**. Текст — случайный из пула
/// (локализован под язык сборки: RU/BY → русский, RS → сербский).
///
/// Сервер не нужен: планируем и пересчитываем из событий приложения (старт,
/// resume, pause) через [refreshStreakReminder]. Одна запись с фиксированным id —
/// каждый пересчёт отменяет прошлую и ставит новую под актуальное состояние.
class StreakNotifier {
  StreakNotifier._();
  static final StreakNotifier instance = StreakNotifier._();

  /// Час напоминания по локальному времени.
  static const int reminderHour = 20;

  static const int _reminderId = 1001;
  static const String _channelId = 'streak_reminder';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _tzReady = false;

  /// Инициализация плагина и таймзон. Idempotent. No-op на web.
  Future<void> init() async {
    if (kIsWeb || _initialized) return;

    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
      _tzReady = true;
    } catch (_) {
      // Не удалось определить зону устройства — планирование остаётся рабочим,
      // но час считается от UTC (редкий фолбэк).
      _tzReady = false;
    }

    const androidInit = AndroidInitializationSettings('ic_notification');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
    );
    _initialized = true;
  }

  /// Запросить разрешение на уведомления (Android 13+ / iOS). Idempotent, no-op на web.
  Future<void> requestPermission() async {
    if (kIsWeb || !_initialized) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Пересчитать напоминание под текущее состояние серии.
  /// Правила — в [computeStreakReminderTime].
  Future<void> refreshStreakReminder(Streak streak) async {
    if (kIsWeb || !_initialized) return;

    await _plugin.cancel(_reminderId);
    final target = computeStreakReminderTime(streak, DateTime.now());
    if (target == null) return;

    final (title, body) = _randomMessage();
    await _schedule(target, title, body);
  }

  /// Полностью снять напоминание (напр. при сбросе статистики). No-op на web.
  Future<void> cancelStreakReminder() async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancel(_reminderId);
  }

  /// ТОЛЬКО ДЛЯ ДЕБАГА: пройти всю цепочку и вернуть человекочитаемый статус —
  /// где именно ломается (инициализация / разрешение / показ). Запрашивает
  /// разрешение (покажет системный диалог, если ещё не выдано) и, если всё ок,
  /// показывает уведомление немедленно.
  Future<String> debugDiagnose() async {
    if (kIsWeb) return 'web: уведомления не поддерживаются';
    if (!_initialized) {
      try {
        await init();
      } catch (e) {
        return 'init упал: $e';
      }
      if (!_initialized) return 'init не завершился (без исключения)';
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    bool? enabled;
    if (android != null) {
      final req = await android.requestNotificationsPermission();
      enabled = await android.areNotificationsEnabled();
      if (enabled == false) {
        return 'разрешение НЕ выдано (req=$req, enabled=$enabled).\n'
            'Включи вручную: Настройки → Приложения → это приложение → Уведомления.';
      }
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      await ios.requestPermissions(alert: true, badge: true, sound: true);
    }

    try {
      final (title, body) = _randomMessage();
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        appL10n.notifChannelName,
        channelDescription: appL10n.notifChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
      );
      await _plugin.show(
        _reminderId + 1,
        title,
        body,
        NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(),
        ),
      );
      return 'OK: показано (разрешение=$enabled, tz=$_tzReady).\n'
          'Открой шторку — уведомление должно быть там.';
    } catch (e) {
      return 'show упал: $e';
    }
  }

  /// ТОЛЬКО ДЛЯ ТЕСТА: показать случайное уведомление из пула через [delay],
  /// чтобы вживую проверить текст/иконку/тап. Вызывается лишь под флагом
  /// `--dart-define=NOTIF_TEST=true` (в прод-сборку не попадает).
  Future<void> showTestReminder({
    Duration delay = const Duration(seconds: 6),
  }) async {
    if (kIsWeb || !_initialized) return;
    await Future<void>.delayed(delay);
    final (title, body) = _randomMessage();
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      appL10n.notifChannelName,
      channelDescription: appL10n.notifChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
    );
    await _plugin.show(
      _reminderId + 1,
      title,
      body,
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  (String, String) _randomMessage() {
    final l = appL10n;
    final pool = <(String, String)>[
      (l.notifStreakTitle1, l.notifStreakBody1),
      (l.notifStreakTitle2, l.notifStreakBody2),
      (l.notifStreakTitle3, l.notifStreakBody3),
      (l.notifStreakTitle4, l.notifStreakBody4),
      (l.notifStreakTitle5, l.notifStreakBody5),
      (l.notifStreakTitle6, l.notifStreakBody6),
    ];
    return pool[Random().nextInt(pool.length)];
  }

  Future<void> _schedule(DateTime when, String title, String body) async {
    final tzWhen = _tzReady
        ? tz.TZDateTime.from(when, tz.local)
        : tz.TZDateTime.from(when, tz.UTC);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      appL10n.notifChannelName,
      channelDescription: appL10n.notifChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
    );
    const iosDetails = DarwinNotificationDetails();

    try {
      await _plugin.zonedSchedule(
        _reminderId,
        title,
        body,
        tzWhen,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        // Неточное планирование не требует SCHEDULE_EXACT_ALARM и щадит батарею;
        // для «напоминания в районе 20:00» точность до минуты не нужна.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('StreakNotifier: schedule failed: $e');
    }
  }
}

/// Когда должно сработать напоминание о серии, или `null` — если не нужно.
///
/// Чистая функция (вынесена для тестируемости):
/// - Серия не активна (`current <= 0`) → `null`.
/// - Активна, сегодня уже тренировался → следующее [hour]:00 завтра.
/// - Активна, сегодня НЕ тренировался, сейчас < [hour]:00 → сегодня [hour]:00.
/// - Активна, сегодня НЕ тренировался, сейчас ≥ [hour]:00 → завтра [hour]:00.
DateTime? computeStreakReminderTime(
  Streak streak,
  DateTime now, {
  int hour = StreakNotifier.reminderHour,
}) {
  if (streak.current <= 0) return null;

  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  final today = dateOnly(now);
  final trainedToday = streak.lastActiveDate != null &&
      dateOnly(streak.lastActiveDate!) == today;

  var target = DateTime(now.year, now.month, now.day, hour);
  if (trainedToday || !now.isBefore(target)) {
    target = target.add(const Duration(days: 1));
  }
  return target;
}
