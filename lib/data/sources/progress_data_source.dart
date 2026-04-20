import 'dart:async';
import 'dart:convert';

import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальный кэш прогресса + опциональная синхронизация с Supabase (см. [configureCloudSync]).
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
  static const String _keyGuestMode = 'guest_mode';

  static const String _keyProgressOwnerId = 'progress_cloud_owner_id';
  static const String _keyLocalProgressUpdatedMs = 'progress_local_updated_ms';

  late SharedPreferences _prefs;

  /// Вызывается после локальных изменений (не при импорте из облака).
  void Function()? onAfterLocalMutation;

  bool _suppressMutationCallbacks = false;
  Timer? _cloudPushTimer;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _migrateLegacyIfNeeded();
    _seedLocalUpdatedMsIfNeeded();
  }

  void _seedLocalUpdatedMsIfNeeded() {
    if (_prefs.getInt(_keyLocalProgressUpdatedMs) != null) return;
    if (!_hasAnyProgressPayload()) return;
    _bumpLocalUpdatedMs();
  }

  bool _hasAnyProgressPayload() {
    for (final key in [
      _keyProgressAb,
      _keyProgressCd,
      _keyTicketProgressAb,
      _keyTicketProgressCd,
      _keyFavoritesAb,
      _keyFavoritesCd,
      _keyExamResultsAb,
      _keyExamResultsCd,
    ]) {
      final s = _prefs.getString(key);
      if (s != null && s.isNotEmpty && s != '{}' && s != '[]') {
        return true;
      }
    }
    return false;
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

  void _putMap(String key, Map<String, dynamic> data) {
    _prefs.setString(key, json.encode(data));
  }

  void _saveMap(String key, Map<String, dynamic> data) {
    _putMap(key, data);
    _afterMutation();
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

  void _putList(String key, List<String> data) {
    _prefs.setString(key, json.encode(data));
  }

  void _saveList(String key, List<String> data) {
    _putList(key, data);
    _afterMutation();
  }

  void _bumpLocalUpdatedMs() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _prefs.setInt(_keyLocalProgressUpdatedMs, now);
  }

  void _afterMutation() {
    if (_suppressMutationCallbacks) return;
    _bumpLocalUpdatedMs();
    onAfterLocalMutation?.call();
  }

  int get localProgressUpdatedMs =>
      _prefs.getInt(_keyLocalProgressUpdatedMs) ?? 0;

  /// Гарантирует ненулевую метку времени перед первой отправкой в облако.
  void ensureProgressTimestamp() {
    if (localProgressUpdatedMs == 0) {
      _bumpLocalUpdatedMs();
    }
  }

  String? get storedProgressOwnerId => _prefs.getString(_keyProgressOwnerId);

  Future<void> setStoredProgressOwnerId(String? userId) async {
    if (userId == null || userId.isEmpty) {
      await _prefs.remove(_keyProgressOwnerId);
    } else {
      await _prefs.setString(_keyProgressOwnerId, userId);
    }
  }

  /// Строка для upsert в `user_progress`.
  Map<String, dynamic> buildCloudUpsertRow(String userId) {
    return {
      'user_id': userId,
      'question_progress_ab': _loadMap(_keyProgressAb),
      'question_progress_cd': _loadMap(_keyProgressCd),
      'ticket_progress_ab': _loadMap(_keyTicketProgressAb),
      'ticket_progress_cd': _loadMap(_keyTicketProgressCd),
      'favorites_ab': _loadList(_keyFavoritesAb),
      'favorites_cd': _loadList(_keyFavoritesCd),
      'exam_results_ab': _decodeExamResultsList(_keyExamResultsAb),
      'exam_results_cd': _decodeExamResultsList(_keyExamResultsCd),
      'app_settings': _loadMap(_keySettings),
      'updated_at_ms': localProgressUpdatedMs,
    };
  }

  List<dynamic> _decodeExamResultsList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = json.decode(raw) as List;
      return List<dynamic>.from(list);
    } catch (_) {
      return [];
    }
  }

  /// Заменить локальные данные из облака (без триггера push).
  Future<void> importFromCloudRow(Map<String, dynamic> row) async {
    _suppressMutationCallbacks = true;
    try {
      _putMap(
        _keyProgressAb,
        _asStringKeyMap(row['question_progress_ab']),
      );
      _putMap(
        _keyProgressCd,
        _asStringKeyMap(row['question_progress_cd']),
      );
      _putMap(
        _keyTicketProgressAb,
        _asStringKeyMap(row['ticket_progress_ab']),
      );
      _putMap(
        _keyTicketProgressCd,
        _asStringKeyMap(row['ticket_progress_cd']),
      );
      _putList(
        _keyFavoritesAb,
        _asStringList(row['favorites_ab']),
      );
      _putList(
        _keyFavoritesCd,
        _asStringList(row['favorites_cd']),
      );
      _putList(
        _keyExamResultsAb,
        _examResultsToPrefsStrings(row['exam_results_ab']),
      );
      _putList(
        _keyExamResultsCd,
        _examResultsToPrefsStrings(row['exam_results_cd']),
      );
      _putMap(_keySettings, _asStringKeyMap(row['app_settings']));
      final ms = row['updated_at_ms'];
      final msInt = ms is num ? ms.toInt() : int.tryParse('$ms') ?? 0;
      await _prefs.setInt(_keyLocalProgressUpdatedMs, msInt);
    } finally {
      _suppressMutationCallbacks = false;
    }
  }

  Map<String, dynamic> _asStringKeyMap(dynamic value) {
    if (value == null) return {};
    if (value is! Map) return {};
    return value.map((k, v) => MapEntry(k.toString(), v));
  }

  List<String> _asStringList(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value.map((e) => e.toString()).toList();
  }

  /// В БД exam_results — jsonb-массив строк или объектов; в prefs — JSON-строки.
  List<String> _examResultsToPrefsStrings(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value.map((e) {
      if (e is String) return e;
      return json.encode(e);
    }).toList();
  }

  void configureCloudSync({
    required bool enabled,
    required Future<void> Function() pushNow,
  }) {
    _cloudPushTimer?.cancel();
    _cloudPushTimer = null;
    onAfterLocalMutation = null;

    if (!enabled) {
      return;
    }

    onAfterLocalMutation = () {
      _cloudPushTimer?.cancel();
      _cloudPushTimer = Timer(const Duration(seconds: 1), () {
        unawaited(pushNow());
      });
    };
  }

  void cancelCloudDebounce() {
    _cloudPushTimer?.cancel();
    _cloudPushTimer = null;
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

  bool getGuestMode() {
    return _prefs.getBool(_keyGuestMode) ?? false;
  }

  Future<void> setGuestMode(bool enabled) async {
    await _prefs.setBool(_keyGuestMode, enabled);
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
    _afterMutation();
  }

  /// Сброс прогресса при смене аккаунта: не обновляет `updated_ms`, не вызывает push.
  Future<void> clearAllProgressForAccountSwitch() async {
    _suppressMutationCallbacks = true;
    try {
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
      await _prefs.remove(_keyLocalProgressUpdatedMs);
    } finally {
      _suppressMutationCallbacks = false;
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
        'completedAt': DateTime.now().toIso8601String(),
      }),
    );
    _saveList(ekey, results);
  }
}
