enum AchievementId {
  streak,
  coverage,
  tickets,
  attempts,
  exams,
  flawless,
  mistakes,
  game,
}

abstract final class AchievementThresholds {
  static const List<int> streak = [3, 7, 14, 30];
  static const List<int> coverageBase = [100, 300, 500];
  static const List<int> ticketsBase = [1, 10, 20];
  static const List<int> attempts = [100, 500, 1000, 3000];
  static const List<int> exams = [1, 3, 5, 10];
  static const List<int> flawless = [1, 3, 5, 10];
  static const List<int> mistakes = [10, 50, 100, 200];
  static const List<int> game = [1000, 2500, 5000, 7500];
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

  return result;
}
