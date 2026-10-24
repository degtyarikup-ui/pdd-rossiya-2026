import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/auth_service.dart';

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
    load: () async {
      // Read local progress without subscribing to profile/ranking network work.
      final questions = data.getAllQuestionProgress(category);
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
  AchievementAwardService({required this.scope, required this.load});

  final String scope;
  final Future<List<AchievementProgress>> Function() load;
  String get storageKey => 'achievement_awards_v1/$scope';
  Future<void>? _preparing;

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
