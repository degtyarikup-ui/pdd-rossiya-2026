import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/data/models/achievement_stats.dart';
import 'package:pdd_app/data/models/marathon_progress.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProgressDataSource> source() async {
    final data = ProgressDataSource();
    await data.init();
    return data;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'утро и ночь засчитываются раз в день, даже в уже зачтённый день',
    () async {
      final data = await source();
      await data.recordActivity(date: DateTime(2026, 11, 2, 7, 30));
      await data.recordActivity(date: DateTime(2026, 11, 2, 8, 10));
      await data.recordActivity(date: DateTime(2026, 11, 2, 23, 5));
      await data.recordActivity(date: DateTime(2026, 11, 3, 1, 0));
      await data.recordActivity(date: DateTime(2026, 11, 3, 12, 0));
      final stats = data.getAchievementStats();
      expect(stats.earlyDays, 1);
      expect(stats.nightDays, 2);
      expect(stats.comebacks, 0);
    },
  );

  test('возвращение — новый день после перерыва в неделю', () async {
    final data = await source();
    await data.recordActivity(date: DateTime(2026, 10, 1, 12));
    await data.recordActivity(date: DateTime(2026, 10, 7, 12));
    expect(data.getAchievementStats().comebacks, 0);
    await data.recordActivity(date: DateTime(2026, 10, 14, 12));
    await data.recordActivity(date: DateTime(2026, 10, 14, 18));
    expect(data.getAchievementStats().comebacks, 1);
  });

  test('марафон хранит лучший результат, знаки — без повторов', () async {
    final data = await source();
    await data.saveMarathon(
      TicketCategory.ab,
      const MarathonProgress(answers: {'a': 0, 'b': 1, 'c': 2}),
    );
    await data.saveMarathon(
      TicketCategory.ab,
      const MarathonProgress(answers: {'a': 0}),
    );
    await data.recordSignViewed('1.1');
    await data.recordSignViewed('1.1');
    await data.recordSignViewed('2.4');
    final stats = data.getAchievementStats();
    expect(stats.marathonBest, 3);
    expect(stats.signsViewed, {'1.1', '2.4'});
  });

  test('серия сданных экзаменов считается по времени', () {
    Map<String, dynamic> exam(int day, bool passed) => {
      'passed': passed,
      'completedAt': DateTime(2026, 11, day).toIso8601String(),
    };
    expect(
      longestPassedExamRun([
        exam(5, true),
        exam(1, true),
        exam(2, true),
        exam(3, false),
        exam(4, true),
        exam(6, true),
      ]),
      3,
    );
  });

  test('новые ачивки берут свои счётчики', () {
    final list = computeAchievements(
      longestStreak: 0,
      stats: {'totalQuestions': 800, 'totalTickets': 40, 'perfectTickets': 40},
      questionProgress: {},
      examResults: [],
      gameBestScore: 0,
      quizBestCombo: 25,
      violatorsCaught: 500,
      parkingSolved: 4,
      crossroadsSolved: 30,
      extra: const AchievementStats(marathonBest: 800, comebacks: 1),
    );
    int level(AchievementId id) => list.firstWhere((a) => a.id == id).level;
    expect(level(AchievementId.quiz), 2);
    expect(level(AchievementId.violator), 4);
    expect(level(AchievementId.parking), 0);
    expect(level(AchievementId.crossroads), 2);
    expect(level(AchievementId.marathon), 4);
    expect(level(AchievementId.perfect), 4);
    expect(level(AchievementId.comeback), 1);
    expect(list.map((a) => a.id).toSet(), AchievementId.values.toSet());
  });
}
