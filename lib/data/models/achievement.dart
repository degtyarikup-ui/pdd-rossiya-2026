enum AchievementId {
  streak,
  coverage,
  tickets,
  attempts,
  exams,
  flawless,
  mistakes,
  game,
  trafficController,
  signSwiper,
  rank,
}

abstract final class AchievementThresholds {
  static const List<int> streak = [3, 7, 14, 30];
  static const List<int> coverageBase = [100, 300, 500];
  static const List<int> ticketsBase = [1, 10, 20];
  static const List<int> attempts = [100, 500, 1000, 3000];
  static const List<int> exams = [1, 3, 5, 10];
  static const List<int> flawless = [1, 3, 5, 10];
  static const List<int> mistakes = [10, 50, 100, 200];
  // Each tier is reachable within one finite round of its game. Historical
  // personal bests remain valid, so previously earned badges are preserved.
  static const List<int> game = [200, 400, 700, 950];
  static const List<int> trafficController = [150, 300, 600, 900];
  static const List<int> signSwiper = [100, 200, 300, 450];

  /// «Покоритель рейтинга»: уровни — топ-100 / топ-10 / топ-3 / 1 место.
  /// Модель считает «чем больше, тем лучше», а место — наоборот, поэтому
  /// значение = [rankCeiling] − место: 1 место → 100, топ-3 → ≥98,
  /// топ-10 → ≥91, топ-100 → ≥1 (см. [rankValue]).
  static const List<int> rank = [1, 91, 98, 100];
  static const int rankCeiling = 101;
}

/// Лучшее место в недельном рейтинге → значение для [AchievementProgress].
/// Нет места (не в топ-100 или нет данных) → 0, то есть ни одного уровня.
int rankValue(int? bestRank) {
  if (bestRank == null || bestRank < 1) return 0;
  return (AchievementThresholds.rankCeiling - bestRank).clamp(0, 100);
}

class AchievementProgress {
  final AchievementId id;
  final List<int> levels;
  final int value;

  const AchievementProgress({
    required this.id,
    required this.levels,
    required this.value,
  });

  /// Сколько порогов достигнуто (0..levels.length).
  /// Значение value >= порог означает, что уровень засчитан.
  int get level {
    int count = 0;
    for (final target in levels) {
      if (value >= target) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  bool get isUnlocked => level > 0;

  bool get isMaxed => level == levels.length;

  int? get nextTarget => isMaxed ? null : levels[level];
}

List<AchievementProgress> computeAchievements({
  required int longestStreak,
  required Map<String, int> stats,
  required Map<String, dynamic> questionProgress,
  required List<Map<String, dynamic>> examResults,
  required int gameBestScore,
  int? bestWeeklyRank,
  int trafficControllerBestScore = 0,
  int signSwiperBestScore = 0,
}) {
  final totalQuestions = stats['totalQuestions'] ?? 0;
  final totalTickets = stats['totalTickets'] ?? 0;

  // 1. streak: «Без пропусков»
  final streakAchievement = AchievementProgress(
    id: AchievementId.streak,
    levels: AchievementThresholds.streak,
    value: longestStreak,
  );

  // 2. coverage: «Эрудит» (показываем только если totalQuestions > 0)
  AchievementProgress? coverageAchievement;
  if (totalQuestions > 0) {
    coverageAchievement = AchievementProgress(
      id: AchievementId.coverage,
      levels: [...AchievementThresholds.coverageBase, totalQuestions],
      value: stats['answeredQuestions'] ?? 0,
    );
  }

  // 3. tickets: «Билет за билетом» (показываем только если totalTickets > 0)
  AchievementProgress? ticketsAchievement;
  if (totalTickets > 0) {
    ticketsAchievement = AchievementProgress(
      id: AchievementId.tickets,
      levels: [...AchievementThresholds.ticketsBase, totalTickets],
      value: stats['passedTickets'] ?? 0,
    );
  }

  // 4. attempts: «Неутомимый»
  int totalAttempts = 0;
  for (final entry in questionProgress.values) {
    if (entry is Map) {
      totalAttempts += (entry['attemptsCount'] as int?) ?? 1;
    }
  }
  final attemptsAchievement = AchievementProgress(
    id: AchievementId.attempts,
    levels: AchievementThresholds.attempts,
    value: totalAttempts,
  );

  // 5. exams: «Экзаменатор»
  int passedExams = 0;
  for (final r in examResults) {
    if (r['passed'] == true) {
      passedExams++;
    }
  }
  final examsAchievement = AchievementProgress(
    id: AchievementId.exams,
    levels: AchievementThresholds.exams,
    value: passedExams,
  );

  // 6. flawless: «Без единой ошибки»
  int flawlessExams = 0;
  for (final r in examResults) {
    if (r['passed'] == true && ((r['wrongAnswers'] as int?) ?? 0) == 0) {
      flawlessExams++;
    }
  }
  final flawlessAchievement = AchievementProgress(
    id: AchievementId.flawless,
    levels: AchievementThresholds.flawless,
    value: flawlessExams,
  );

  // 7. mistakes: «Работа над ошибками»
  int correctedMistakes = 0;
  for (final entry in questionProgress.values) {
    if (entry is Map) {
      final wrongAttempts = (entry['wrongAttempts'] as int?) ?? 0;
      final isCorrect = entry['isCorrect'] == true;
      if (wrongAttempts > 0 && isCorrect) {
        correctedMistakes++;
      }
    }
  }
  final mistakesAchievement = AchievementProgress(
    id: AchievementId.mistakes,
    levels: AchievementThresholds.mistakes,
    value: correctedMistakes,
  );

  // 8. game: «Гонщик»
  final gameAchievement = AchievementProgress(
    id: AchievementId.game,
    levels: AchievementThresholds.game,
    value: gameBestScore,
  );

  // 9. rank: «Покоритель рейтинга»
  final rankAchievement = AchievementProgress(
    id: AchievementId.rank,
    levels: AchievementThresholds.rank,
    value: rankValue(bestWeeklyRank),
  );

  final List<AchievementProgress> result = [];
  result.add(streakAchievement);
  if (coverageAchievement != null) {
    result.add(coverageAchievement);
  }
  if (ticketsAchievement != null) {
    result.add(ticketsAchievement);
  }
  result.add(attemptsAchievement);
  result.add(examsAchievement);
  result.add(flawlessAchievement);
  result.add(mistakesAchievement);
  result.add(gameAchievement);
  result.add(
    AchievementProgress(
      id: AchievementId.trafficController,
      levels: AchievementThresholds.trafficController,
      value: trafficControllerBestScore,
    ),
  );
  result.add(
    AchievementProgress(
      id: AchievementId.signSwiper,
      levels: AchievementThresholds.signSwiper,
      value: signSwiperBestScore,
    ),
  );
  result.add(rankAchievement);

  return result;
}

/// Полученные значки сначала; при равном уровне сохраняем порядок типов.
List<AchievementProgress> achievementsForDisplay(
  Iterable<AchievementProgress> achievements,
) => List<AchievementProgress>.of(achievements)
  ..sort((a, b) {
    final byLevel = b.level.compareTo(a.level);
    return byLevel != 0 ? byLevel : a.id.index.compareTo(b.id.index);
  });
