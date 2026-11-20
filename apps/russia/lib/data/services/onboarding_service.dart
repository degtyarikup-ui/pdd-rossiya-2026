import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Варианты ежедневного темпа подготовки, выбираемые на онбординге.
enum OnboardingPace {
  calm(minutesPerDay: 10, forecastDays: 28),
  optimal(minutesPerDay: 15, forecastDays: 18),
  intensive(minutesPerDay: 30, forecastDays: 10);

  const OnboardingPace({
    required this.minutesPerDay,
    required this.forecastDays,
  });

  final int minutesPerDay;
  final int forecastDays;

  static OnboardingPace fromMinutes(int? minutes) {
    for (final pace in OnboardingPace.values) {
      if (pace.minutesPerDay == minutes) return pace;
    }
    return OnboardingPace.optimal;
  }
}

/// Управляет показом стартового онбординга для новых пользователей.
///
/// Существующие пользователи, у которых в хранилище уже есть прогресс,
/// настройки, серия дней или активная авторизация, автоматически получают
/// отметку завершения и переходят сразу на главный экран без сброса их
/// выбранной категории билетов.
class OnboardingService {
  OnboardingService._();

  static final OnboardingService instance = OnboardingService._();

  static const String completedKey = 'onboarding_v1_completed';
  static const String dailyGoalKey = 'onboarding_daily_goal_minutes';

  static const Set<String> _existingUserStateKeys = <String>{
    'app_settings',
    'question_progress_ab',
    'question_progress_cd',
    'ticket_progress_ab',
    'ticket_progress_cd',
    'favorites_ab',
    'favorites_cd',
    'favorite_states_ab',
    'favorite_states_cd',
    'exam_results_ab',
    'exam_results_cd',
    'question_progress',
    'ticket_progress',
    'favorites',
    'exam_results',
    'unfinished_session',
    'marathon_v1_ab',
    'marathon_v1_cd',
    'streak_last_active',
    'streak_active_days',
    'streak_current',
    'achievement_stats',
    'progress_reset_at',
    'traffic_controller_progress',
    'sign_swiper_progress',
    'crossroads_priority_progress',
    'parking_progress',
    'road_signs_progress',
    'violator_progress',
    'game_best_score',
    'auth_user_profile',
    'install_reported',
  };

  bool _shouldShow = false;
  OnboardingPace _pace = OnboardingPace.optimal;

  bool get shouldShow => _shouldShow;
  OnboardingPace get pace => _pace;
  int get dailyGoalMinutes => _pace.minutesPerDay;

  /// Вызывать в стартовой последовательности после `InstallReporter.captureLaunchState()`,
  /// чтобы запись `onboarding_v1_completed = false` не превращала свежую установку
  /// в обновление для аналитики установок.
  Future<void> init({bool isAuthenticated = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawCompleted = prefs.get(completedKey);
      final storedCompleted = rawCompleted is bool ? rawCompleted : null;

      final rawMinutes = prefs.get(dailyGoalKey);
      if (rawMinutes is int) {
        _pace = OnboardingPace.fromMinutes(rawMinutes);
      } else {
        _pace = OnboardingPace.optimal;
      }

      if (storedCompleted == true) {
        _shouldShow = false;
        return;
      }

      if (storedCompleted == false) {
        _shouldShow = true;
        return;
      }

      if (isAuthenticated) {
        _shouldShow = false;
        await prefs.setBool(completedKey, true);
        return;
      }

      final hasExistingUserData = prefs.getKeys().any(
        _existingUserStateKeys.contains,
      );
      if (hasExistingUserData) {
        _shouldShow = false;
        await prefs.setBool(completedKey, true);
      } else {
        _shouldShow = true;
        await prefs.setBool(completedKey, false);
      }
    } catch (e) {
      debugPrint('OnboardingService init error: $e');
      _shouldShow = false;
    }
  }

  /// Помечает онбординг завершённым и сохраняет выбранный дневной темп.
  Future<void> complete({required OnboardingPace pace}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setInt(dailyGoalKey, pace.minutesPerDay) ||
        !await prefs.setBool(completedKey, true)) {
      throw StateError('Failed to save onboarding');
    }
    _pace = pace;
    _shouldShow = false;
  }

  @visibleForTesting
  void resetForTest({
    bool shouldShow = false,
    OnboardingPace pace = OnboardingPace.optimal,
  }) {
    _shouldShow = shouldShow;
    _pace = pace;
  }
}
