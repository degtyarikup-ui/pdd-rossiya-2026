import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Presentation receipts, independent of earned progress. There is deliberately
/// no listener that can open an award while someone is answering or driving.
final achievementAwardServiceProvider = Provider<AchievementAwardService>((
  ref,
) {
  final category = ref.watch(
    appSettingsProvider.select((s) => s.ticketCategory),
  );
  final data = ref.read(progressDataSourceProvider);
  return AchievementAwardService(
    scope: category.name,
    activity: data,
    load: () async {
      // Read local progress without subscribing to profile/ranking network work.
      final questions = ref.read(trackedQuestionProgressProvider.future);
      final exams = data.getExamResults(category);
      final streak = data.loadStreak();
      final stats = ref.read(statsProvider.future);
      final userId = AuthService.instance.currentUser?.id;
      return computeAchievements(
        longestStreak: (await streak).longest,
        stats: await stats,
        questionProgress: await questions,
        examResults: await exams,
        gameBestScore: data.getGameBestScore(),
        bestWeeklyRank: userId == null ? null : data.getGameBestRank(userId),
        trafficControllerBestScore: data
            .getTrafficControllerProgress()
            .bestScore,
        signSwiperBestScore: data.getSignSwiperProgress().bestScore,
      );
    },
  );
});

class AchievementAwardService {
  AchievementAwardService({
    required this.scope,
    required this.load,
    this.activity,
  });

  final String scope;
  final ProgressDataSource? activity;
  final Future<List<AchievementProgress>> Function() load;
  String get storageKey => 'achievement_awards_v1/$scope';
  Future<void>? _preparing;
  Future<void>? _activityWrite;

  Future<void> startActivity() => _activityWrite = _startActivity();

  Future<void> _startActivity() async {
    await prepare();
    await activity?.recordActivity();
  }

  Future<Streak?> pendingStreak() async {
    await _activityWrite;
    return activity?.pendingStreakCelebration();
  }

  Future<void> acknowledgeStreak(Streak streak) async {
    final day = streak.lastActiveDate;
    if (day != null) await activity?.acknowledgeStreakCelebration(day);
  }

  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>?> nativeStreak(DateTime started) async {
    final data = activity;
    if (data == null) return null;
    final before = await data.loadStreak(now: started);
    final projected = before.withActivity(started);
    final pending = await data.pendingStreakCelebration();
    return {
      'day': dayKey(started),
      'current': projected.current,
      'longest': projected.longest,
      'pending': pending != null || !before.isActiveOn(started),
      'heading': appL10n.streakTitle,
      'today': appL10n.streakToday,
      'record': appL10n.streakNewRecord,
      'day_words': {
        for (final n in [1, 2, 5, 11]) '$n': appL10n.streakDaysWord(n),
      },
    };
  }

  /// A native summary confirms actual launch. Failed/unavailable launches
  /// never book the projection sent to the engine.
  Future<void> recordNativeActivity(Map summary, DateTime started) async {
    final data = activity;
    if (data == null) return;
    final today = Streak.day(DateTime.now());
    final first = Streak.day(started);
    final days = <DateTime>{first};
    final raw = summary['activity_days'];
    if (raw is List) {
      for (final value in raw.whereType<String>()) {
        final day = DateTime.tryParse(value);
        if (day != null && !day.isBefore(first) && !day.isAfter(today)) {
          days.add(Streak.day(day));
        }
      }
    }
    final ordered = days.toList()..sort();
    for (final day in ordered) {
      await data.recordActivity(date: day);
    }
    final presented = summary['streak_celebrated_day'];
    if (presented is String) {
      final day = DateTime.tryParse(presented);
      if (day != null && days.contains(Streak.day(day))) {
        await data.acknowledgeStreakCelebration(day);
      }
    }
  }

  /// On upgrade, existing badges become the baseline without a backlog of
  /// congratulations. Call before the first answer, never first at the result.
  Future<void> prepare() => _preparing ??= _prepare();

  Future<void> _prepare() async {
    try {
      final progress = await load();
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(storageKey)) return;
      await prefs.setString(
        storageKey,
        jsonEncode({for (final item in progress) item.id.name: item.level}),
      );
    } catch (_) {
      // A missing content file or storage must never prevent a lesson starting.
      _preparing = null;
    }
  }

  Future<List<AchievementProgress>> pending() async {
    try {
      await prepare();
      await _activityWrite;
      final current = await load();
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(storageKey)) return [];
      final shown = _read(prefs);
      // One card for the highest newly reached tier of each achievement.
      return current.where((a) => a.level > (shown[a.id.name] ?? 0)).toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, int> _read(SharedPreferences prefs) {
    final raw = jsonDecode(prefs.getString(storageKey) ?? '{}') as Map;
    return raw.map((key, value) => MapEntry('$key', (value as num).toInt()));
  }

  Future<void> acknowledge(AchievementId id, int level) async {
    final prefs = await SharedPreferences.getInstance();
    final shown = _read(prefs);
    if (level <= (shown[id.name] ?? 0)) return;
    shown[id.name] = level;
    await prefs.setString(storageKey, jsonEncode(shown));
  }

  Future<Map<String, int>> receipts() async {
    await prepare();
    return _read(await SharedPreferences.getInstance());
  }
}
