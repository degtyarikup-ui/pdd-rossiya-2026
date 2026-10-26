import 'dart:convert';
import 'dart:async';
import 'package:pdd_app/data/models/marathon_progress.dart';
import 'package:pdd_app/data/models/progress_snapshot.dart';
import 'package:pdd_app/data/models/question_identity.dart';

import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/data/models/traffic_controller_progress.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/data/models/crossroads_priority_progress.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/data/models/violator_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальный кэш прогресса в [SharedPreferences].
class ProgressDataSource {
  static const String _keyTrafficController = 'traffic_controller_progress';
  static const String _keySignSwiper = 'sign_swiper_progress';
  static const String _keyCrossroadsPriority = 'crossroads_priority_progress';
  static const String _keyParking = 'parking_progress';
  static const String _keyRoadSigns = 'road_signs_progress';
  static const String _keyViolator = 'violator_progress';
  static const String _keyRoadSignsBest = 'roadSignsBest';
  static const String _keyViolatorBest = 'violatorBest';
  static const String _legacyProgress = 'question_progress';
  static const String _legacyTicketProgress = 'ticket_progress';
  static const String _legacyFavorites = 'favorites';
  static const String _legacyExamResults = 'exam_results';

  static const String _keyProgressAb = 'question_progress_ab';
  static const String _keyProgressCd = 'question_progress_cd';
  static const String _keyTicketProgressAb = 'ticket_progress_ab';
  static const String _keyTicketProgressCd = 'ticket_progress_cd';
  static const String _keyResetAt = 'progress_reset_at';
  static const String _keyFavoriteStatesAb = 'favorite_states_ab';
  static const String _keyFavoriteStatesCd = 'favorite_states_cd';
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
  static const String _keyStreakCelebrationPending =
      'streak_celebration_pending';

  /// Незаконченная тренировка: куда вернуться одним нажатием с главной.
  static const String _keyUnfinishedSession = 'unfinished_session';
  static String _marathonKey(TicketCategory category) =>
      'marathon_v1_${category.name}';

  /// Максимум хранимых дней активности в локальном кэше.
  static const int _maxStoredActiveDays = 30;

  /// Ключи прежней облачной синхронизации — чистим один раз при апгрейде.
  static const List<String> _obsoleteCloudKeys = [
    'guest_mode',
    'progress_cloud_owner_id',
    'progress_local_updated_ms',
  ];

  late SharedPreferences _prefs;
  final _imports = StreamController<int>.broadcast();
  Stream<int> get imports => _imports.stream;
  int _importRevision = 0;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _migrateLegacyIfNeeded();
    _migrateQuestionIdentities();
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

  // Older versions shared one record between different ticket illustrations.
  // Preserve that initial state for both variants, then store future changes
  // independently. An explicit new favorite tombstone must never be recreated.
  void _migrateQuestionIdentities() {
    for (final category in TicketCategory.values) {
      final progress = _loadMap(_progressKey(category));
      final favorites = _loadList(_favoritesKey(category));
      final stateKey = category == TicketCategory.ab
          ? _keyFavoriteStatesAb
          : _keyFavoriteStatesCd;
      final states = _loadMap(stateKey);
      var progressChanged = false;
      var favoritesChanged = false;
      var statesChanged = false;
      for (final entry in QuestionIdentity.aliases[category]!.entries) {
        final variant = entry.key;
        final legacy = entry.value;
        if (!progress.containsKey(variant) && progress[legacy] is Map) {
          progress[variant] = jsonDecode(jsonEncode(progress[legacy]));
          progressChanged = true;
        }
        if (!states.containsKey(variant)) {
          final oldState = states[legacy];
          final present = oldState is Map
              ? oldState['present'] == true
              : favorites.contains(legacy);
          if (present) {
            states[variant] = oldState is Map
                ? Map<String, dynamic>.from(oldState)
                : {'present': true, 'updatedAt': 0};
            statesChanged = true;
            if (!favorites.contains(variant)) {
              favorites.add(variant);
              favoritesChanged = true;
            }
          }
        }
      }
      if (progressChanged) _saveMap(_progressKey(category), progress);
      if (favoritesChanged) _saveList(_favoritesKey(category), favorites);
      if (statesChanged) _saveMap(stateKey, states);
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
      'answeredAt': DateTime.fromMillisecondsSinceEpoch(
        _nextMutationTime(),
      ).toIso8601String(),
      'attemptsCount': attemptsCount + 1,
      'correctAttempts': correctAttempts + (isCorrect ? 1 : 0),
      'wrongAttempts': wrongAttempts + (isCorrect ? 0 : 1),
    };
    _saveMap(key, progress);
    _markStreakActivityToday();
    ProgressSyncService.instance.scheduleSync();
  }

  Future<int> getCorrectAnswersCount(TicketCategory category) async {
    final progress = _loadMap(_progressKey(category));
    int count = 0;
    progress.forEach((key, value) {
      if (value is Map && value['isCorrect'] == true) count++;
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
      'answeredAt': DateTime.fromMillisecondsSinceEpoch(
        _nextMutationTime(),
      ).toIso8601String(),
    };
    _saveMap(tkey, ticketProgress);
    ProgressSyncService.instance.scheduleSync();
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
    final stateKey = category == TicketCategory.ab
        ? _keyFavoriteStatesAb
        : _keyFavoriteStatesCd;
    final states = _loadMap(stateKey);
    states[questionId] = {
      'present': favs.contains(questionId),
      'updatedAt': _nextMutationTime(),
    };
    _saveMap(stateKey, states);
    ProgressSyncService.instance.scheduleSync();
  }

  Future<List<String>> getFavoriteQuestionIds(TicketCategory category) async {
    return _loadList(_favoritesKey(category));
  }

  Future<AppSettings> loadAppSettings() async {
    final settings = _loadMap(_keySettings);
    return AppSettings.fromJson(settings);
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    _saveMap(_keySettings, settings.toJson());
    ProgressSyncService.instance.scheduleSync();
  }

  int _nextMutationTime() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final previous = [
      _prefs.getInt('progress_mutation_clock') ?? 0,
      _prefs.getInt(_keyResetAt) ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final next = now > previous ? now : previous + 1;
    _prefs.setInt('progress_mutation_clock', next);
    return next;
  }

  Future<void> resetAllProgress() async {
    await _prefs.setInt(_keyResetAt, _nextMutationTime());
    await _prefs.remove(_keyFavoriteStatesAb);
    await _prefs.remove(_keyFavoriteStatesCd);
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
    // Незаконченная тренировка тоже часть прогресса: после сброса
    // возвращать человека в старую сессию было бы странно.
    await _prefs.remove(_keyUnfinishedSession);
    for (final category in TicketCategory.values) {
      await _prefs.remove(_marathonKey(category));
    }
    // Стрик — часть прогресса, чистим вместе со всем.
    await _prefs.remove(_keyStreakCurrent);
    await _prefs.remove(_keyStreakLongest);
    await _prefs.remove(_keyStreakLastActive);
    await _prefs.remove(_keyStreakStartDate);
    await _prefs.remove(_keyStreakActiveDays);
    await _prefs.remove(_keyStreakCelebrationPending);
    ProgressSyncService.instance.scheduleSync();
    _imports.add(++_importRevision);
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
  void _markStreakActivityToday() => unawaited(recordActivity());

  /// Any successfully started learning/game activity counts, even before an
  /// answer. The receipt is consumed only by a completed activity's queue.
  Future<void> recordActivity({DateTime? date}) async {
    final today = _dateOnly(date ?? DateTime.now());
    final lastIso = _prefs.getString(_keyStreakLastActive);
    final last = lastIso != null ? DateTime.tryParse(lastIso) : null;
    final lastDay = last != null ? _dateOnly(last) : null;

    if (lastDay != null && !today.isAfter(lastDay)) {
      // День уже зачтён — стрик и так растёт корректно.
      return;
    }

    final yesterday = Streak.shiftDay(today, -1);
    final stored = _prefs.getInt(_keyStreakCurrent) ?? 0;
    final isConsecutive =
        lastDay != null && lastDay.isAtSameMomentAs(yesterday);
    final nextCurrent = isConsecutive ? stored + 1 : 1;

    final storedLongest = _prefs.getInt(_keyStreakLongest) ?? 0;
    final nextLongest = nextCurrent > storedLongest
        ? nextCurrent
        : storedLongest;

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

    await Future.wait([
      _prefs.setInt(_keyStreakCurrent, nextCurrent),
      _prefs.setInt(_keyStreakLongest, nextLongest),
      _prefs.setString(_keyStreakLastActive, _isoDate(today)),
      _prefs.setStringList(_keyStreakActiveDays, activeSorted),
      _prefs.setBool(_keyStreakCelebrationPending, true),
    ]);
    ProgressSyncService.instance.scheduleSync();
  }

  /// Прочитать текущее состояние серии.
  ///
  /// Логика возврата `current`:
  /// - Никогда не тренировался → 0
  /// - Последняя активность сегодня или вчера → сохранённое значение
  /// - Перерыв больше суток → 0 (серия прервана, но UI узнаёт об этом)
  ///
  /// Если счётчик разошёлся со списком дней (синхронизация с другим
  /// устройством), он исправляется по списку и сохраняется.
  Future<Streak> loadStreak({DateTime? now}) async {
    final storedCurrent = _prefs.getInt(_keyStreakCurrent) ?? 0;
    final storedLongest = _prefs.getInt(_keyStreakLongest) ?? 0;
    final lastIso = _prefs.getString(_keyStreakLastActive);
    final last = lastIso != null ? DateTime.tryParse(lastIso) : null;
    final lastDay = last != null ? _dateOnly(last) : null;
    final startIso = _prefs.getString(_keyStreakStartDate);
    final start = startIso != null ? DateTime.tryParse(startIso) : null;
    final startDay = start != null ? _dateOnly(start) : null;

    final today = _dateOnly(now ?? DateTime.now());
    int actualCurrent = storedCurrent;
    DateTime? effectiveStart = startDay;
    if (lastDay == null) {
      actualCurrent = 0;
      effectiveStart = null;
    } else {
      final diff = Streak.dayDistance(lastDay, today);
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

    // Источник правды — сами дни с занятиями. Счётчик и дата последней
    // активности приходят ещё и с сервера (с другого устройства), и раньше
    // могли разойтись со списком дней: «11 дней подряд» при пустой пятнице.
    // Серия — это непрерывный ряд дней, кончающийся последним активным.
    // Список хранит 30 дней: ряд длиннее упирается в его край, тогда верим
    // сохранённому числу.
    if (actualCurrent > 0 && lastDay != null && activeDays.contains(lastDay)) {
      var run = 0;
      var d = lastDay;
      while (activeDays.contains(d)) {
        run++;
        d = Streak.shiftDay(d, -1);
      }
      final oldest = activeDays.reduce((a, b) => a.isBefore(b) ? a : b);
      final reachesWindowEdge =
          !d.isAfter(Streak.shiftDay(oldest, -1)) &&
          activeDays.length >= _maxStoredActiveDays;
      if (!reachesWindowEdge && run != actualCurrent) {
        actualCurrent = run;
        effectiveStart = Streak.shiftDay(lastDay, 1 - run);
        await _prefs.setInt(_keyStreakCurrent, run);
        await _prefs.setString(_keyStreakStartDate, _isoDate(effectiveStart));
      }
    }

    return Streak(
      current: actualCurrent,
      longest: storedLongest < actualCurrent ? actualCurrent : storedLongest,
      lastActiveDate: lastDay,
      startDate: effectiveStart,
      activeDays: activeDays,
    );
  }

  /// Проверить и сбросить флаг «нужно показать поздравление».
  /// Возвращает `true`, если флаг был выставлен (и теперь снят).
  // --- Незаконченная тренировка ------------------------------------------
  // Хранятся не сами вопросы, а их id: список восстанавливается из базы при
  // возврате. Так запись остаётся крошечной, а если вопрос из базы исчез
  // (пересобрали контент) — он просто выпадет из восстановленного набора,
  // вместо того чтобы тянуть за собой устаревшую копию текста.

  /// Запоминает, где человек остановился. Вызывается по ходу тренировки,
  /// поэтому пишем без await-цепочек на каждый ответ.
  Future<void> saveUnfinishedSession({
    String? usageFeature,
    required String title,
    required List<String> questionIds,
    required int index,
    required TicketCategory category,
  }) async {
    await _prefs.setString(
      _keyUnfinishedSession,
      jsonEncode({
        'title': title,
        'questionIds': questionIds,
        'usageFeature': ?usageFeature,
        'index': index,
        'category': category.name,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  /// Запоминает прерванный экзамен целиком: кроме набора вопросов нужны
  /// ответы, остаток времени и состояние доп. фазы — без них возврат
  /// означал бы новый экзамен, а не продолжение прежнего.
  ///
  /// Остаток времени сохраняется намеренно: продолжить с полным таймером
  /// значило бы дать способ обнулять время выходом на главный экран.
  Future<void> saveUnfinishedExam({
    required List<String> questionIds,
    required List<int?> answers,
    required int index,
    required int remainingSeconds,
    required int totalSeconds,
    required bool additionalPhase,
    required int additionalQuestionsCount,
    required int initialWrongCount,
    List<int>? examGroups,
    required TicketCategory category,
  }) async {
    await _prefs.setString(
      _keyUnfinishedSession,
      jsonEncode({
        'kind': 'exam',
        'questionIds': questionIds,
        'answers': answers,
        'index': index,
        'remainingSeconds': remainingSeconds,
        'totalSeconds': totalSeconds,
        'additionalPhase': additionalPhase,
        'additionalQuestionsCount': additionalQuestionsCount,
        'initialWrongCount': initialWrongCount,
        'examGroups': ?examGroups,
        'category': category.name,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  /// Возвращает сохранённую сессию или null, если её нет либо она относится
  /// к другой категории билетов (человек переключил A/B ↔ C/D — набор
  /// вопросов там другой, возвращать в него бессмысленно).
  Map<String, dynamic>? loadUnfinishedSession(TicketCategory category) {
    final raw = _prefs.getString(_keyUnfinishedSession);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['category'] != category.name) return null;
      final ids = (map['questionIds'] as List?)?.cast<String>() ?? const [];
      if (ids.isEmpty) return null;
      return map;
    } catch (_) {
      // Битая запись — молча забываем, это всего лишь удобство.
      return null;
    }
  }

  Future<void> clearUnfinishedSession() async {
    await _prefs.remove(_keyUnfinishedSession);
  }

  MarathonProgress? loadMarathon(TicketCategory category) {
    final raw = _prefs.getString(_marathonKey(category));
    if (raw == null) return null;
    try {
      return MarathonProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMarathon(
    TicketCategory category,
    MarathonProgress progress,
  ) async {
    final saved = await _prefs.setString(
      _marathonKey(category),
      jsonEncode(progress.toJson()),
    );
    if (!saved) throw StateError('Could not save marathon');
  }

  Future<bool> consumePendingStreakCelebration() async {
    final pending = _prefs.getBool(_keyStreakCelebrationPending) ?? false;
    if (pending) {
      await _prefs.setBool(_keyStreakCelebrationPending, false);
    }
    return pending;
  }

  Future<Streak?> pendingStreakCelebration() async {
    if (!(_prefs.getBool(_keyStreakCelebrationPending) ?? false)) return null;
    final streak = await loadStreak();
    return streak.current > 0 ? streak : null;
  }

  Future<void> acknowledgeStreakCelebration(DateTime day) async {
    if (_prefs.getString(_keyStreakLastActive) == _isoDate(day)) {
      await _prefs.setBool(_keyStreakCelebrationPending, false);
    }
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
        'completedAt': DateTime.fromMillisecondsSinceEpoch(
          _nextMutationTime(),
        ).toIso8601String(),
      }),
    );
    _saveList(ekey, results);
    ProgressSyncService.instance.scheduleSync();
  }

  Future<List<Map<String, dynamic>>> getExamResults(
    TicketCategory category,
  ) async {
    final ekey = _examResultsKey(category);
    final List<dynamic> rawList;
    try {
      final raw = _prefs.get(ekey);
      if (raw is List) {
        rawList = raw;
      } else if (raw is String) {
        final decoded = json.decode(raw);
        if (decoded is List) {
          rawList = decoded;
        } else {
          return [];
        }
      } else {
        return [];
      }
    } catch (_) {
      return [];
    }

    final List<Map<String, dynamic>> results = [];
    for (final item in rawList) {
      try {
        if (item is Map) {
          results.add(Map<String, dynamic>.from(item));
        } else if (item is String) {
          final decoded = json.decode(item);
          if (decoded is Map) {
            results.add(Map<String, dynamic>.from(decoded));
          }
        }
      } catch (_) {
        // Пропускаем битые записи
      }
    }
    return results;
  }

  /// Экспорт полного слепка прогресса пользователя для облачной синхронизации.
  Map<String, dynamic> exportProgressSnapshot() {
    return {
      'miniGames': {
        'regulator': getTrafficControllerProgress().toJson(),
        'signs': getSignSwiperProgress().toJson(),
        'crossroads': getCrossroadsPriorityProgress().toJson(),
        'parking': getParkingProgress().toJson(),
      },
      'resetAt': _prefs.getInt(_keyResetAt) ?? 0,
      'favoriteStatesAb': _loadMap(_keyFavoriteStatesAb),
      'favoriteStatesCd': _loadMap(_keyFavoriteStatesCd),
      'questionProgressAb': _loadMap(_keyProgressAb),
      'questionProgressCd': _loadMap(_keyProgressCd),
      'ticketProgressAb': _loadMap(_keyTicketProgressAb),
      'ticketProgressCd': _loadMap(_keyTicketProgressCd),
      'favoritesAb': _loadList(_keyFavoritesAb),
      'favoritesCd': _loadList(_keyFavoritesCd),
      'examResultsAb': _loadList(_keyExamResultsAb),
      'examResultsCd': _loadList(_keyExamResultsCd),
      'streak': {
        'current': _prefs.getInt(_keyStreakCurrent) ?? 0,
        'longest': _prefs.getInt(_keyStreakLongest) ?? 0,
        'lastActiveDate': _prefs.getString(_keyStreakLastActive),
        'startDate': _prefs.getString(_keyStreakStartDate),
        'activeDays': _prefs.getStringList(_keyStreakActiveDays) ?? <String>[],
      },
      'settings': _loadMap(_keySettings),
      // Driving game: best score, the earned garage and the chosen car.
      // Fuel stays on the device on purpose.
      'game': {
        'bestScore': _prefs.getInt('game_best_score') ?? 0,
        'garageCars': _loadGarageCars(),
        'garageCorrect': _prefs.getInt('game_garage_correct') ?? 0,
        'garageUnlocks': _prefs.getInt('game_garage_unlocks') ?? 0,
        'vehicle': _prefs.getString('game_vehicle'),
        'vehiclePaint': _prefs.getString('game_vehicle_paint'),
      },
    };
  }

  /// Лучший счёт в игре — тот же ключ, что пишет игра и синхронизирует
  /// снапшот (`game.bestScore`). «Сбросить статистику» его не трогает.
  int getGameBestScore() => _prefs.getInt('game_best_score') ?? 0;

  /// Прогресс игры «Регулировщик».
  TrafficControllerProgress getTrafficControllerProgress() {
    final raw = _prefs.getString(_keyTrafficController);
    if (raw == null) return const TrafficControllerProgress();
    try {
      return TrafficControllerProgress.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const TrafficControllerProgress();
    }
  }

  Future<void> saveTrafficControllerProgress(
    TrafficControllerProgress progress,
  ) async {
    await _prefs.setString(
      _keyTrafficController,
      jsonEncode(progress.toJson()),
    );
    ProgressSyncService.instance.scheduleSync();
  }

  SignSwiperProgress getSignSwiperProgress() {
    final raw = _prefs.getString(_keySignSwiper);
    if (raw == null || raw.isEmpty) {
      return const SignSwiperProgress();
    }
    try {
      return SignSwiperProgress.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const SignSwiperProgress();
    }
  }

  Future<void> saveSignSwiperProgress(SignSwiperProgress progress) async {
    await _prefs.setString(_keySignSwiper, jsonEncode(progress.toJson()));
    ProgressSyncService.instance.scheduleSync();
  }

  CrossroadsPriorityProgress getCrossroadsPriorityProgress() {
    final raw = _prefs.getString(_keyCrossroadsPriority);
    if (raw == null || raw.isEmpty) {
      return const CrossroadsPriorityProgress();
    }
    try {
      return CrossroadsPriorityProgress.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const CrossroadsPriorityProgress();
    }
  }

  Future<void> saveCrossroadsPriorityProgress(
    CrossroadsPriorityProgress progress,
  ) async {
    await _prefs.setString(
      _keyCrossroadsPriority,
      jsonEncode(progress.toJson()),
    );
    ProgressSyncService.instance.scheduleSync();
  }

  /// «Парковка» хранит те же поля, что и «Перекрёсток»: рекорд, серия, решено.
  CrossroadsPriorityProgress getParkingProgress() {
    final raw = _prefs.getString(_keyParking);
    if (raw == null || raw.isEmpty) return const CrossroadsPriorityProgress();
    try {
      return CrossroadsPriorityProgress.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const CrossroadsPriorityProgress();
    }
  }

  Future<void> saveParkingProgress(CrossroadsPriorityProgress progress) async {
    await _prefs.setString(_keyParking, jsonEncode(progress.toJson()));
    ProgressSyncService.instance.scheduleSync();
  }

  RoadSignsProgress getRoadSignsProgress() {
    final raw = _prefs.getString(_keyRoadSigns);
    if (raw == null || raw.isEmpty) {
      final directBest =
          _prefs.getInt(_keyRoadSignsBest) ??
          _prefs.getInt('road_signs_best') ??
          0;
      if (directBest > 0) {
        return RoadSignsProgress(bestScore: directBest);
      }
      return const RoadSignsProgress();
    }
    try {
      final progress = RoadSignsProgress.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      final directBest =
          _prefs.getInt(_keyRoadSignsBest) ??
          _prefs.getInt('road_signs_best') ??
          0;
      if (directBest > progress.bestScore) {
        return progress.copyWith(bestScore: directBest);
      }
      return progress;
    } catch (_) {
      return const RoadSignsProgress();
    }
  }

  Future<void> saveRoadSignsProgress(RoadSignsProgress progress) async {
    await _prefs.setString(_keyRoadSigns, jsonEncode(progress.toJson()));
    await _prefs.setInt(_keyRoadSignsBest, progress.bestScore);
    await _prefs.setInt('road_signs_best', progress.bestScore);
    ProgressSyncService.instance.scheduleSync();
  }

  int getRoadSignsBest() =>
      _prefs.getInt(_keyRoadSignsBest) ??
      _prefs.getInt('road_signs_best') ??
      getRoadSignsProgress().bestScore;

  Future<void> saveRoadSignsBest(int score) async {
    await _prefs.setInt(_keyRoadSignsBest, score);
    await _prefs.setInt('road_signs_best', score);
    final current = getRoadSignsProgress();
    if (score > current.bestScore) {
      await _prefs.setString(
        _keyRoadSigns,
        jsonEncode(current.copyWith(bestScore: score).toJson()),
      );
    }
    ProgressSyncService.instance.scheduleSync();
  }

  ViolatorProgress getViolatorProgress() {
    final raw = _prefs.getString(_keyViolator);
    if (raw == null || raw.isEmpty) {
      final directBest =
          _prefs.getInt(_keyViolatorBest) ??
          _prefs.getInt('violator_best') ??
          0;
      if (directBest > 0) {
        return ViolatorProgress(bestScore: directBest);
      }
      return const ViolatorProgress();
    }
    try {
      final progress = ViolatorProgress.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      final directBest =
          _prefs.getInt(_keyViolatorBest) ??
          _prefs.getInt('violator_best') ??
          0;
      if (directBest > progress.bestScore) {
        return progress.copyWith(bestScore: directBest);
      }
      return progress;
    } catch (_) {
      return const ViolatorProgress();
    }
  }

  Future<void> saveViolatorProgress(ViolatorProgress progress) async {
    await _prefs.setString(_keyViolator, jsonEncode(progress.toJson()));
    await _prefs.setInt(_keyViolatorBest, progress.bestScore);
    await _prefs.setInt('violator_best', progress.bestScore);
    ProgressSyncService.instance.scheduleSync();
  }

  int getViolatorBest() =>
      _prefs.getInt(_keyViolatorBest) ??
      _prefs.getInt('violator_best') ??
      getViolatorProgress().bestScore;

  Future<void> saveViolatorBest(int score) async {
    await _prefs.setInt(_keyViolatorBest, score);
    await _prefs.setInt('violator_best', score);
    final current = getViolatorProgress();
    if (score > current.bestScore) {
      await _prefs.setString(
        _keyViolator,
        jsonEncode(current.copyWith(bestScore: score).toJson()),
      );
    }
    ProgressSyncService.instance.scheduleSync();
  }

  /// Лучшее место в недельном рейтинге игры, запомненное на устройстве.
  /// Источник правды — сервер; кэш нужен, чтобы ачивка не пропадала без сети.
  /// Хранится по id аккаунта (на устройстве могут входить разные люди) и
  /// «Сбросить статистику» его не трогает.
  int? getGameBestRank(String userId) {
    final rank = _prefs.getInt('game_best_rank:$userId');
    return rank != null && rank > 0 ? rank : null;
  }

  Future<void> setGameBestRank(String userId, int rank) =>
      _prefs.setInt('game_best_rank:$userId', rank);

  List<Map<String, dynamic>> _loadGarageCars() {
    try {
      final raw = _prefs.getString('game_garage_cars');
      if (raw == null) return const [];
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _importGame(
    Map<String, dynamic> g, {
    bool Function()? stillCurrent,
  }) => GameGarageService.instance.importFromCloud(
    () => _importGameUnlocked(g, stillCurrent: stillCurrent),
  );

  Future<void> _importGameUnlocked(
    Map<String, dynamic> g, {
    bool Function()? stillCurrent,
  }) async {
    bool current() => stillCurrent?.call() ?? true;
    if (!current()) return;
    final best = (g['bestScore'] as num?)?.toInt() ?? 0;
    if (best > (_prefs.getInt('game_best_score') ?? 0)) {
      await _prefs.setInt('game_best_score', best);
      if (!current()) return;
    }
    final correct = (g['garageCorrect'] as num?)?.toInt() ?? 0;
    if (correct > (_prefs.getInt('game_garage_correct') ?? 0)) {
      await _prefs.setInt('game_garage_correct', correct);
      if (!current()) return;
    }
    final unlocks = (g['garageUnlocks'] as num?)?.toInt() ?? 0;
    if (unlocks > (_prefs.getInt('game_garage_unlocks') ?? 0)) {
      await _prefs.setInt('game_garage_unlocks', unlocks);
      if (!current()) return;
    }
    if (g['garageCars'] is List) {
      // Union by model+paint, keeping the local order first.
      final seen = <String>{};
      final merged = <Map<String, dynamic>>[];
      for (final car in [..._loadGarageCars(), ...(g['garageCars'] as List)]) {
        if (car is! Map) continue;
        final id = car['id'], paint = car['paint'];
        if (id is! String || paint is! String) continue;
        if (seen.add('$id:$paint')) merged.add({'id': id, 'paint': paint});
      }
      if (merged.isNotEmpty) {
        await _prefs.setString('game_garage_cars', jsonEncode(merged));
        if (!current()) return;
      }
    }
    if (!_prefs.containsKey('game_vehicle') && g['vehicle'] is String) {
      await _prefs.setString('game_vehicle', g['vehicle'] as String);
      if (!current()) return;
      if (g['vehiclePaint'] is String) {
        await _prefs.setString(
          'game_vehicle_paint',
          g['vehiclePaint'] as String,
        );
        if (!current()) return;
      }
    }
  }

  /// Импорт и сохранение слепка прогресса из облака.
  Future<void> importProgressSnapshot(
    Map<String, dynamic> data, {
    bool Function()? stillCurrent,
  }) async {
    bool current() => stillCurrent?.call() ?? true;
    if (data.isEmpty || !current()) return;
    final previousReset = _prefs.getInt(_keyResetAt) ?? 0;
    data = mergeProgressSnapshots(exportProgressSnapshot(), data);
    final reset = data['resetAt'] as int;
    var clock = (_prefs.getInt('progress_mutation_clock') ?? 0);
    if (reset > clock) clock = reset;
    for (final suffix in ['Ab', 'Cd']) {
      for (final entry in (data['favoriteStates$suffix'] as Map).values) {
        final stamp = (entry['updatedAt'] as num?)?.toInt() ?? 0;
        if (stamp > clock) clock = stamp;
      }
    }
    _prefs.setInt('progress_mutation_clock', clock);

    if (reset > previousReset) {
      _prefs.setInt(_keyResetAt, reset);
      _prefs.remove(_keyUnfinishedSession);
      for (final category in TicketCategory.values) {
        await _prefs.remove(_marathonKey(category));
        if (!current()) return;
      }
      for (final key in [
        _keyStreakCurrent,
        _keyStreakLongest,
        _keyStreakLastActive,
        _keyStreakStartDate,
        _keyStreakActiveDays,
        _keyStreakCelebrationPending,
      ]) {
        _prefs.remove(key);
      }
    }
    if (!current()) return;
    data = mergeProgressSnapshots(exportProgressSnapshot(), data);
    final games = Map<String, dynamic>.from(data['miniGames'] as Map);
    _saveMap(
      _keyTrafficController,
      Map<String, dynamic>.from(games['regulator'] as Map),
    );
    _saveMap(_keySignSwiper, Map<String, dynamic>.from(games['signs'] as Map));
    _saveMap(
      _keyCrossroadsPriority,
      Map<String, dynamic>.from(games['crossroads'] as Map),
    );
    if (games['parking'] is Map) {
      _saveMap(_keyParking, Map<String, dynamic>.from(games['parking'] as Map));
    }
    _saveMap(
      _keyFavoriteStatesAb,
      Map<String, dynamic>.from(data['favoriteStatesAb'] as Map),
    );
    _saveMap(
      _keyFavoriteStatesCd,
      Map<String, dynamic>.from(data['favoriteStatesCd'] as Map),
    );
    if (data['questionProgressAb'] is Map) {
      _saveMap(
        _keyProgressAb,
        Map<String, dynamic>.from(data['questionProgressAb'] as Map),
      );
    }
    if (data['questionProgressCd'] is Map) {
      _saveMap(
        _keyProgressCd,
        Map<String, dynamic>.from(data['questionProgressCd'] as Map),
      );
    }
    if (data['ticketProgressAb'] is Map) {
      _saveMap(
        _keyTicketProgressAb,
        Map<String, dynamic>.from(data['ticketProgressAb'] as Map),
      );
    }
    if (data['ticketProgressCd'] is Map) {
      _saveMap(
        _keyTicketProgressCd,
        Map<String, dynamic>.from(data['ticketProgressCd'] as Map),
      );
    }
    if (data['favoritesAb'] is List) {
      _saveList(_keyFavoritesAb, (data['favoritesAb'] as List).cast<String>());
    }
    if (data['favoritesCd'] is List) {
      _saveList(_keyFavoritesCd, (data['favoritesCd'] as List).cast<String>());
    }
    if (data['examResultsAb'] is List) {
      _saveList(
        _keyExamResultsAb,
        (data['examResultsAb'] as List).cast<String>(),
      );
    }
    if (data['examResultsCd'] is List) {
      _saveList(
        _keyExamResultsCd,
        (data['examResultsCd'] as List).cast<String>(),
      );
    }
    if (data['game'] is Map) {
      await _importGame(
        Map<String, dynamic>.from(data['game'] as Map),
        stillCurrent: stillCurrent,
      );
      if (!current()) return;
    }
    if (data['streak'] is Map) {
      final s = data['streak'] as Map;
      final cur = s['current'] as int? ?? 0;
      final lon = s['longest'] as int? ?? 0;
      final last = s['lastActiveDate'] as String?;
      final start = s['startDate'] as String?;
      final active = (s['activeDays'] as List?)?.cast<String>() ?? <String>[];

      if (cur > (_prefs.getInt(_keyStreakCurrent) ?? 0)) {
        await _prefs.setInt(_keyStreakCurrent, cur);
        if (!current()) return;
      }
      if (lon > (_prefs.getInt(_keyStreakLongest) ?? 0)) {
        await _prefs.setInt(_keyStreakLongest, lon);
        if (!current()) return;
      }
      // Дата с сервера принимается, только если она не старше своей:
      // иначе устройство «забывало» сегодняшний день.
      final localLast = _prefs.getString(_keyStreakLastActive);
      if (last != null &&
          last.isNotEmpty &&
          (localLast == null || last.compareTo(localLast) >= 0)) {
        await _prefs.setString(_keyStreakLastActive, last);
        if (!current()) return;
        if (start != null && start.isNotEmpty) {
          await _prefs.setString(_keyStreakStartDate, start);
          if (!current()) return;
        }
      }
      if (active.isNotEmpty) {
        final existingActive =
            _prefs.getStringList(_keyStreakActiveDays) ?? <String>[];
        final union = {...existingActive, ...active}.toList()..sort();
        await _prefs.setStringList(_keyStreakActiveDays, union);
        if (!current()) return;
      }
    }
    _migrateQuestionIdentities();
    _imports.add(++_importRevision);
  }
}
