import 'dart:convert';

import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальный кэш прогресса в [SharedPreferences].
class ProgressDataSource {
  static const String _legacyProgress = 'question_progress';
  static const String _legacyTicketProgress = 'ticket_progress';
  static const String _legacyFavorites = 'favorites';
  static const String _legacyExamResults = 'exam_results';

  static const String _keyProgressAb = 'question_progress_ab';
  static const String _keyProgressCd = 'question_progress_cd';
  static const String _keyTicketProgressAb = 'ticket_progress_ab';
  static const String _keyTicketProgressCd = 'ticket_progress_cd';
  static const String _keyFavoritesAb = 'favorites_ab';
  static const String _keyFavoritesCd = 'favorites_cd';
  static const String _keyExamResultsAb = 'exam_results_ab';
  static const String _keyExamResultsCd = 'exam_results_cd';
  static const String _keySettings = 'app_settings';

  // --- Серия (стрик) ---
  static const String _keyStreakCurrent = 'streak_current';
  static const String _keyStreakLongest = 'streak_longest';
  static const String _keyStreakLastActive = 'streak_last_active';
  static const String _keyStreakStartDate = 'streak_start_date';
  static const String _keyStreakActiveDays = 'streak_active_days';
  static const String _keyStreakCelebrationPending = 'streak_celebration_pending';

  /// Максимум хранимых дней активности в локальном кэше.
  static const int _maxStoredActiveDays = 30;

  /// Ключи прежней облачной синхронизации — чистим один раз при апгрейде.
  static const List<String> _obsoleteCloudKeys = [
    'guest_mode',
    'progress_cloud_owner_id',
    'progress_local_updated_ms',
  ];

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _migrateLegacyIfNeeded();
    _purgeObsoleteCloudKeys();
  }

  void _migrateLegacyIfNeeded() {
    void migrateString(String legacyKey, String newKey) {
      final legacy = _prefs.getString(legacyKey);
      if (legacy != null &&
          legacy.isNotEmpty &&
          _prefs.getString(newKey) == null) {
        _prefs.setString(newKey, legacy);
      }
      if (legacy != null) {
        _prefs.remove(legacyKey);
      }
    }

    migrateString(_legacyProgress, _keyProgressAb);
    migrateString(_legacyTicketProgress, _keyTicketProgressAb);
    migrateString(_legacyFavorites, _keyFavoritesAb);
    migrateString(_legacyExamResults, _keyExamResultsAb);
  }

  void _purgeObsoleteCloudKeys() {
    for (final key in _obsoleteCloudKeys) {
      if (_prefs.containsKey(key)) {
        _prefs.remove(key);
      }
    }
  }

  String _progressKey(TicketCategory c) =>
      c == TicketCategory.ab ? _keyProgressAb : _keyProgressCd;

  String _ticketProgressKey(TicketCategory c) =>
      c == TicketCategory.ab ? _keyTicketProgressAb : _keyTicketProgressCd;

  String _favoritesKey(TicketCategory c) =>
      c == TicketCategory.ab ? _keyFavoritesAb : _keyFavoritesCd;

  String _examResultsKey(TicketCategory c) =>
      c == TicketCategory.ab ? _keyExamResultsAb : _keyExamResultsCd;

  Map<String, dynamic> _loadMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(json.decode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  void _saveMap(String key, Map<String, dynamic> data) {
    _prefs.setString(key, json.encode(data));
  }

  List<String> _loadList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    try {
      return List<String>.from(json.decode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  void _saveList(String key, List<String> data) {
    _prefs.setString(key, json.encode(data));
  }

  Future<bool> isQuestionAnswered(
    String questionId,
    TicketCategory category,
  ) async {
    final progress = _loadMap(_progressKey(category));
    return progress.containsKey(questionId);
  }

  Future<Map<String, dynamic>?> getQuestionProgress(
    String questionId,
    TicketCategory category,
  ) async {
    final progress = _loadMap(_progressKey(category));
    return progress[questionId] as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>> getAllQuestionProgress(
    TicketCategory category,
  ) async {
    return _loadMap(_progressKey(category));
  }

  Future<void> saveAnswer({
    required String questionId,
    required bool isCorrect,
    required int selectedAnswerIndex,
    required TicketCategory category,
  }) async {
    final key = _progressKey(category);
    final progress = _loadMap(key);
    final previous = progress[questionId] is Map<String, dynamic>
        ? progress[questionId] as Map<String, dynamic>
        : <String, dynamic>{};

    final attemptsCount = previous['attemptsCount'] as int? ?? 0;
    final correctAttempts = previous['correctAttempts'] as int? ?? 0;
    final wrongAttempts = previous['wrongAttempts'] as int? ?? 0;

    progress[questionId] = {
      'isCorrect': isCorrect,
      'selectedAnswerIndex': selectedAnswerIndex,
      'answeredAt': DateTime.now().toIso8601String(),
      'attemptsCount': attemptsCount + 1,
      'correctAttempts': correctAttempts + (isCorrect ? 1 : 0),
      'wrongAttempts': wrongAttempts + (isCorrect ? 0 : 1),
    };
    _saveMap(key, progress);
    _markStreakActivityToday();
  }

  Future<int> getCorrectAnswersCount(TicketCategory category) async {
    final progress = _loadMap(_progressKey(category));
    int count = 0;
    progress.forEach((key, value) {
      if (value is Map && value['isCorrect'] == true) count++;
    });
    return count;
  }

  Future<int> getPassedTicketsCount(TicketCategory category) async {
    final ticketProgress = _loadMap(_ticketProgressKey(category));
    int count = 0;
    ticketProgress.forEach((key, value) {
      if (value is Map && (value['correctAnswers'] as num) >= 18) count++;
    });
    return count;
  }

  Future<void> saveTicketProgress({
    required int ticketNumber,
    required int correctAnswers,
    required int totalAnswered,
    required TicketCategory category,
  }) async {
    final tkey = _ticketProgressKey(category);
    final ticketProgress = _loadMap(tkey);
    ticketProgress[ticketNumber.toString()] = {
      'correctAnswers': correctAnswers,
      'totalAnswered': totalAnswered,
    };
    _saveMap(tkey, ticketProgress);
  }

  Future<int?> getTicketCorrectAnswers(
    int ticketNumber,
    TicketCategory category,
  ) async {
    final ticketProgress = _loadMap(_ticketProgressKey(category));
    final data = ticketProgress[ticketNumber.toString()];
    if (data is Map) return data['correctAnswers'] as int?;
    return null;
  }

  Future<Map<int, int>> getAllTicketProgress(TicketCategory category) async {
    final ticketProgress = _loadMap(_ticketProgressKey(category));
    final Map<int, int> result = {};
    ticketProgress.forEach((key, value) {
      if (value is Map) {
        result[int.tryParse(key) ?? 0] = value['correctAnswers'] as int? ?? 0;
      }
    });
    return result;
  }

  Future<bool> isFavorite(String questionId, TicketCategory category) async {
    final favs = _loadList(_favoritesKey(category));
    return favs.contains(questionId);
  }

  Future<void> toggleFavorite(
    String questionId,
    TicketCategory category,
  ) async {
    final fkey = _favoritesKey(category);
    final favs = _loadList(fkey);
    if (favs.contains(questionId)) {
      favs.remove(questionId);
    } else {
      favs.add(questionId);
    }
    _saveList(fkey, favs);
  }

  Future<List<String>> getFavoriteQuestionIds(
    TicketCategory category,
  ) async {
    return _loadList(_favoritesKey(category));
  }

  Future<AppSettings> loadAppSettings() async {
    final settings = _loadMap(_keySettings);
    return AppSettings.fromJson(settings);
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    _saveMap(_keySettings, settings.toJson());
  }

  Future<void> resetAllProgress() async {
    await _prefs.remove(_keyProgressAb);
    await _prefs.remove(_keyProgressCd);
    await _prefs.remove(_keyTicketProgressAb);
    await _prefs.remove(_keyTicketProgressCd);
    await _prefs.remove(_keyFavoritesAb);
    await _prefs.remove(_keyFavoritesCd);
    await _prefs.remove(_keyExamResultsAb);
    await _prefs.remove(_keyExamResultsCd);
    await _prefs.remove(_legacyProgress);
    await _prefs.remove(_legacyTicketProgress);
    await _prefs.remove(_legacyFavorites);
    await _prefs.remove(_legacyExamResults);
    // Стрик — часть прогресса, чистим вместе со всем.
    await _prefs.remove(_keyStreakCurrent);
    await _prefs.remove(_keyStreakLongest);
    await _prefs.remove(_keyStreakLastActive);
    await _prefs.remove(_keyStreakStartDate);
    await _prefs.remove(_keyStreakActiveDays);
    await _prefs.remove(_keyStreakCelebrationPending);
  }

  // --- Стрик: служебные методы ---

  /// Привести дату к началу календарного дня (локальное время устройства).
  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  /// Сериализация даты в формат `yyyy-MM-dd` (стабильный, парсится DateTime.parse).
  String _isoDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Записать активность за сегодня. Вызывается из [saveAnswer].
  ///
  /// Логика:
  /// - Если последняя активность была сегодня — ничего не делаем.
  /// - Если вчера — увеличиваем серию на 1.
  /// - Иначе — серия начинается заново (1).
  /// - Обновляем longest, сегодняшний день добавляем в список активных,
  ///   ставим флаг pendingCelebration, чтобы UI смог показать поздравление.
  void _markStreakActivityToday() {
    final today = _dateOnly(DateTime.now());
    final lastIso = _prefs.getString(_keyStreakLastActive);
    final last = lastIso != null ? DateTime.tryParse(lastIso) : null;
    final lastDay = last != null ? _dateOnly(last) : null;

    if (lastDay != null && lastDay.isAtSameMomentAs(today)) {
      // День уже зачтён — стрик и так растёт корректно.
      return;
    }

    final yesterday = today.subtract(const Duration(days: 1));
    final stored = _prefs.getInt(_keyStreakCurrent) ?? 0;
    final isConsecutive =
        lastDay != null && lastDay.isAtSameMomentAs(yesterday);
    final nextCurrent = isConsecutive ? stored + 1 : 1;

    final storedLongest = _prefs.getInt(_keyStreakLongest) ?? 0;
    final nextLongest =
        nextCurrent > storedLongest ? nextCurrent : storedLongest;

    // Дата старта серии. Не трогаем, если серия продолжается; перезаписываем
    // на сегодня, если серия начинается заново (новая или после перерыва).
    if (!isConsecutive) {
      _prefs.setString(_keyStreakStartDate, _isoDate(today));
    }

    // Поддерживаем компактный список активных дней (последние 30 уникальных).
    final activeRaw = _prefs.getStringList(_keyStreakActiveDays) ?? <String>[];
    final activeSet = activeRaw.toSet()..add(_isoDate(today));
    final activeSorted = activeSet.toList()..sort();
    if (activeSorted.length > _maxStoredActiveDays) {
      activeSorted.removeRange(0, activeSorted.length - _maxStoredActiveDays);
    }

    _prefs.setInt(_keyStreakCurrent, nextCurrent);
    _prefs.setInt(_keyStreakLongest, nextLongest);
    _prefs.setString(_keyStreakLastActive, _isoDate(today));
    _prefs.setStringList(_keyStreakActiveDays, activeSorted);
    _prefs.setBool(_keyStreakCelebrationPending, true);
  }

  /// Прочитать текущее состояние серии.
  ///
  /// Логика возврата `current`:
  /// - Никогда не тренировался → 0
  /// - Последняя активность сегодня или вчера → сохранённое значение
  /// - Перерыв больше суток → 0 (серия прервана, но UI узнаёт об этом)
  ///
  /// Сохранённое значение не меняем — оно будет перезаписано на следующей
  /// тренировке в [_markStreakActivityToday] корректно.
  Future<Streak> loadStreak() async {
    final storedCurrent = _prefs.getInt(_keyStreakCurrent) ?? 0;
    final storedLongest = _prefs.getInt(_keyStreakLongest) ?? 0;
    final lastIso = _prefs.getString(_keyStreakLastActive);
    final last = lastIso != null ? DateTime.tryParse(lastIso) : null;
    final lastDay = last != null ? _dateOnly(last) : null;
    final startIso = _prefs.getString(_keyStreakStartDate);
    final start = startIso != null ? DateTime.tryParse(startIso) : null;
    final startDay = start != null ? _dateOnly(start) : null;

    final today = _dateOnly(DateTime.now());
    int actualCurrent = storedCurrent;
    DateTime? effectiveStart = startDay;
    if (lastDay == null) {
      actualCurrent = 0;
      effectiveStart = null;
    } else {
      final diff = today.difference(lastDay).inDays;
      if (diff > 1) {
        // Серия прервана — стартовая дата уже не актуальна.
        actualCurrent = 0;
        effectiveStart = null;
      }
    }

    final activeRaw = _prefs.getStringList(_keyStreakActiveDays) ?? <String>[];
    final activeDays = activeRaw
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .map(_dateOnly)
        .toSet();

    return Streak(
      current: actualCurrent,
      longest: storedLongest,
      lastActiveDate: lastDay,
      startDate: effectiveStart,
      activeDays: activeDays,
    );
  }

  /// Проверить и сбросить флаг «нужно показать поздравление».
  /// Возвращает `true`, если флаг был выставлен (и теперь снят).
  Future<bool> consumePendingStreakCelebration() async {
    final pending = _prefs.getBool(_keyStreakCelebrationPending) ?? false;
    if (pending) {
      await _prefs.setBool(_keyStreakCelebrationPending, false);
    }
    return pending;
  }

  Future<void> saveExamResult({
    required int ticketNumber,
    required int correctAnswers,
    required int wrongAnswers,
    required bool passed,
    required TicketCategory category,
  }) async {
    final ekey = _examResultsKey(category);
    final results = _loadList(ekey);
    results.add(
      json.encode({
        'ticketNumber': ticketNumber,
        'correctAnswers': correctAnswers,
        'wrongAnswers': wrongAnswers,
        'passed': passed,
        'completedAt': DateTime.now().toIso8601String(),
      }),
    );
    _saveList(ekey, results);
  }
}
