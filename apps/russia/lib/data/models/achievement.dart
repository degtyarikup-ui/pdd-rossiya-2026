import 'package:pdd_app/data/models/achievement_stats.dart';

/// Порядок значений — порядок в сетке при равном уровне.
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
  quiz,
  violator,
  parking,
  crossroads,
  marathon,
  perfect,
  examReady,
  signsExpert,
  earlyBird,
  nightDriver,
  comeback,
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
  static const List<int> game = [100, 200, 300, 450];
  static const List<int> trafficController = [150, 300, 600, 900];
  static const List<int> signSwiper = [100, 200, 300, 450];

  /// «Знаток квиза»: лучшая серия верных ответов в «Дорожных знаках».
  static const List<int> quiz = [10, 25, 50, 100];

  /// «Инспектор»: всего пойманных нарушителей.
  static const List<int> violator = [25, 100, 250, 500];

  /// «Мастер парковки»: всего выполненных парковок.
  static const List<int> parking = [5, 20, 50, 100];

  /// «Разрулил»: всего решённых перекрёстков.
  static const List<int> crossroads = [10, 30, 75, 150];

  /// «Марафонец»: больше всего вопросов в одном марафоне.
  static const List<int> marathon = [50, 150, 400, 800];

  /// «Отличник ПДД»: билетов без единой ошибки; последний уровень — все.
  static const List<int> perfectBase = [10, 20, 30];

  /// «Готов к экзамену»: экзаменов, сданных подряд без провала.
  static const List<int> examReady = [3, 5, 10, 20];

  /// «Знаток знаков»: разных знаков, открытых в справочнике (всего 312).
  static const List<int> signsExpert = [20, 60, 150, 300];

  /// «Ранняя пташка»: дней с учёбой с 5 до 9 утра.
  static const List<int> earlyBird = [5, 15, 30, 60];

  /// «Ночной водитель»: дней с учёбой с 22 до 4 часов.
  static const List<int> nightDriver = [10, 30, 60, 100];

  /// «Возвращение»: возвращений к учёбе после перерыва в неделю.
  static const List<int> comeback = [1, 3, 5, 10];

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

  /// Progress within the next tier, excluding thresholds already earned.
  double get nextLevelProgress {
    final currentLevel = level;
    if (currentLevel == levels.length) return 1;
    final previous = currentLevel == 0 ? 0 : levels[currentLevel - 1];
    final next = levels[currentLevel];
    return ((value - previous) / (next - previous)).clamp(0.0, 1.0);
  }
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
  int quizBestCombo = 0,
  int violatorsCaught = 0,
  int parkingSolved = 0,
  int crossroadsSolved = 0,
  AchievementStats extra = const AchievementStats(),
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
  AchievementProgress simple(AchievementId id, List<int> levels, int value) =>
      AchievementProgress(id: id, levels: levels, value: value);
  result
    ..add(simple(AchievementId.quiz, AchievementThresholds.quiz, quizBestCombo))
    ..add(
      simple(
        AchievementId.violator,
        AchievementThresholds.violator,
        violatorsCaught,
      ),
    )
    ..add(
      simple(
        AchievementId.parking,
        AchievementThresholds.parking,
        parkingSolved,
      ),
    )
    ..add(
      simple(
        AchievementId.crossroads,
        AchievementThresholds.crossroads,
        crossroadsSolved,
      ),
    )
    ..add(
      simple(
        AchievementId.marathon,
        AchievementThresholds.marathon,
        extra.marathonBest,
      ),
    );
  if (totalTickets > 0) {
    result.add(
      simple(AchievementId.perfect, [
        ...AchievementThresholds.perfectBase.where((t) => t < totalTickets),
        totalTickets,
      ], stats['perfectTickets'] ?? 0),
    );
  }
  result
    ..add(
      simple(
        AchievementId.examReady,
        AchievementThresholds.examReady,
        longestPassedExamRun(examResults),
      ),
    )
    ..add(
      simple(
        AchievementId.signsExpert,
        AchievementThresholds.signsExpert,
        extra.signsViewed.length,
      ),
    )
    ..add(
      simple(
        AchievementId.earlyBird,
        AchievementThresholds.earlyBird,
        extra.earlyDays,
      ),
    )
    ..add(
      simple(
        AchievementId.nightDriver,
        AchievementThresholds.nightDriver,
        extra.nightDays,
      ),
    )
    ..add(
      simple(
        AchievementId.comeback,
        AchievementThresholds.comeback,
        extra.comebacks,
      ),
    )
    ..add(rankAchievement);

  return result;
}

/// Самая длинная серия сданных экзаменов подряд, по времени завершения.
int longestPassedExamRun(List<Map<String, dynamic>> examResults) {
  DateTime when(Map<String, dynamic> r) =>
      DateTime.tryParse('${r['completedAt'] ?? r['date'] ?? ''}') ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final ordered = [...examResults]..sort((a, b) => when(a).compareTo(when(b)));
  var best = 0, run = 0;
  for (final r in ordered) {
    run = r['passed'] == true ? run + 1 : 0;
    if (run > best) best = run;
  }
  return best;
}

/// Полученные значки сначала; при равном уровне сохраняем порядок типов.
List<AchievementProgress> achievementsForDisplay(
  Iterable<AchievementProgress> achievements,
) => List<AchievementProgress>.of(achievements)
  ..sort((a, b) {
    final byLevel = b.level.compareTo(a.level);
    return byLevel != 0 ? byLevel : a.id.index.compareTo(b.id.index);
  });
