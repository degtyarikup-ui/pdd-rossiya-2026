import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ненавязчивый запрос оценки приложения в сторе.
///
/// Момент показа выбран так, чтобы просьба попадала на пик удовлетворения:
/// пользователь только что закрыл поздравление за серию (см.
/// `home_screen.dart` → `_maybeShowStreakCelebration`), то есть занимается
/// регулярно и видел приятный экран. Просить сразу после установки или после
/// проваленного экзамена — верный способ получить одну звезду.
///
/// Что важно знать про нативный API (Google Play In-App Review /
/// StoreKit `SKStoreReviewController`):
/// - **Узнать, оставил ли пользователь оценку, технически нельзя** — обе
///   платформы это намеренно не отдают. Поэтому «не показывать повторно» мы
///   реализуем единственным доступным способом: локальным флагом «уже
///   просили». Один запрос на устройство за всё время.
/// - Показ диалога решает сама платформа (квоты Google/Apple). Вызов может
///   тихо ничего не показать — это нормально и не считается ошибкой.
/// - Никакого своего UI поверх нативного диалога («Вам нравится приложение?»)
///   быть не должно: Google это прямо запрещает.
class ReviewPromptService {
  ReviewPromptService._();

  /// Флаг «нативный запрос оценки уже отправлялся».
  static const String _keyRequested = 'review_prompt_requested';

  /// С какой серии просим оценку. Три дня подряд — уже привычка, но ещё не
  /// так далеко, чтобы момент был упущен.
  static const int minStreakDays = 3;

  /// Веб-сборке просить нечего — там нет стора.
  static bool get _supportedPlatform => !kIsWeb;

  /// Просит оценку, если выполнены все условия. Полностью «fire-and-forget»:
  /// любая ошибка проглатывается и не мешает пользователю.
  ///
  /// [currentStreak] — текущая серия в днях.
  static Future<void> maybeRequest({required int currentStreak}) async {
    if (!_supportedPlatform) return;
    if (currentStreak < minStreakDays) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyRequested) ?? false) return;

      final inAppReview = InAppReview.instance;
      if (!await inAppReview.isAvailable()) return;

      // Флаг ставим ДО запроса: если платформа решит показать диалог, второго
      // шанса всё равно не будет, а повторно дёргать API при каждой серии —
      // способ впустую сжечь квоту.
      await prefs.setBool(_keyRequested, true);
      await inAppReview.requestReview();
    } catch (_) {
      // Оценка — необязательная механика: молчим и живём дальше.
    }
  }
}
