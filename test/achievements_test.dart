import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/game_economy.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each game unlocks its own achievement tiers at the boundary', () {
    const tiers = {
      AchievementId.game: AchievementThresholds.game,
      AchievementId.trafficController: AchievementThresholds.trafficController,
      AchievementId.signSwiper: AchievementThresholds.signSwiper,
    };
    for (final entry in tiers.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        for (final justBelow in [true, false]) {
          final score = entry.value[i] - (justBelow ? 1 : 0);
          final list = computeAchievements(
            longestStreak: 0,
            stats: {},
            questionProgress: {},
            examResults: [],
            gameBestScore: entry.key == AchievementId.game ? score : 0,
            trafficControllerBestScore:
                entry.key == AchievementId.trafficController ? score : 0,
            signSwiperBestScore: entry.key == AchievementId.signSwiper
                ? score
                : 0,
          );
          for (final game in tiers.keys) {
            expect(
              list.firstWhere((a) => a.id == game).level,
              game == entry.key ? i + (justBelow ? 0 : 1) : 0,
            );
          }
        }
      }
    }
  });

  test('historical records retain every previously earned badge tier', () {
    const oldThresholds = [1000, 2500, 5000, 7500];
    for (var i = 0; i < oldThresholds.length; i++) {
      final score = oldThresholds[i];
      final list = computeAchievements(
        longestStreak: 0,
        stats: {},
        questionProgress: {},
        examResults: [],
        gameBestScore: score,
        trafficControllerBestScore: score,
        signSwiperBestScore: score,
      );
      for (final id in [
        AchievementId.game,
        AchievementId.trafficController,
        AchievementId.signSwiper,
      ]) {
        final progress = list.firstWhere((a) => a.id == id);
        expect(progress.value, score);
        expect(progress.level, greaterThanOrEqualTo(i + 1));
      }
    }
  });

  test('top game badges are attainable with a finite perfect round', () {
    int perfectScore(int answers, int Function(int) reward) =>
        List.generate(answers, (i) => reward(i + 1)).fold(0, (a, b) => a + b);
    expect(
      perfectScore(20, GameEconomy.city),
      greaterThanOrEqualTo(AchievementThresholds.game.last),
    );
    expect(
      perfectScore(30, (streak) => GameEconomy.regulator(streak)),
      greaterThanOrEqualTo(AchievementThresholds.trafficController.last),
    );
    expect(
      perfectScore(30, GameEconomy.signs),
      greaterThanOrEqualTo(AchievementThresholds.signSwiper.last),
    );
  });

  test('achievement descriptions match game tiers in every UI language', () {
    const tiers = {
      'achievementDescGame': AchievementThresholds.game,
      'achievementDescTrafficController':
          AchievementThresholds.trafficController,
      'achievementDescSignSwiper': AchievementThresholds.signSwiper,
    };
    for (final language in ['ru', 'en', 'kk']) {
      final arb =
          jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final entry in tiers.entries) {
        final description = arb[entry.key] as String;
        final describedTiers = RegExp(r'\d+')
            .allMatches(description)
            .map((match) => int.parse(match.group(0)!))
            .toList();
        expect(describedTiers, entry.value, reason: '$language: ${entry.key}');
      }
    }
  });

  test('profile puts earned badges first by tier with stable ties', () {
    final source = [
      const AchievementProgress(
        id: AchievementId.streak,
        levels: [3, 7, 14, 30],
        value: 3,
      ),
      const AchievementProgress(
        id: AchievementId.rank,
        levels: [1, 91, 98, 100],
        value: 0,
      ),
      const AchievementProgress(
        id: AchievementId.game,
        levels: AchievementThresholds.game,
        value: 400,
      ),
      const AchievementProgress(
        id: AchievementId.signSwiper,
        levels: AchievementThresholds.signSwiper,
        value: 100,
      ),
    ];
    expect(achievementsForDisplay(source).map((a) => a.id), [
      AchievementId.game,
      AchievementId.streak,
      AchievementId.signSwiper,
      AchievementId.rank,
    ]);
    expect(source.first.id, AchievementId.streak);
  });

  group('AchievementProgress thresholds and levels', () {
    test(
      'уровень считается правильно на границе порога (value == порог → уровень засчитан, value == порог − 1 → нет)',
      () {
        const thresholds = [3, 7, 14, 30];

        // value == 0 -> level 0, not unlocked
        final p0 = AchievementProgress(
          id: AchievementId.streak,
          levels: thresholds,
          value: 0,
        );
        expect(p0.level, 0);
        expect(p0.isUnlocked, isFalse);
        expect(p0.isMaxed, isFalse);
        expect(p0.nextTarget, 3);

        // value == 2 (порог - 1) -> level 0
        final p2 = AchievementProgress(
          id: AchievementId.streak,
          levels: thresholds,
          value: 2,
        );
        expect(p2.level, 0);
        expect(p2.isUnlocked, isFalse);
        expect(p2.nextTarget, 3);

        // value == 3 (порог) -> level 1
        final p3 = AchievementProgress(
          id: AchievementId.streak,
          levels: thresholds,
          value: 3,
        );
        expect(p3.level, 1);
        expect(p3.isUnlocked, isTrue);
        expect(p3.nextTarget, 7);

        // value == 6 (порог - 1) -> level 1
        final p6 = AchievementProgress(
          id: AchievementId.streak,
          levels: thresholds,
          value: 6,
        );
        expect(p6.level, 1);
        expect(p6.nextTarget, 7);

        // value == 7 (порог) -> level 2
        final p7 = AchievementProgress(
          id: AchievementId.streak,
          levels: thresholds,
          value: 7,
        );
        expect(p7.level, 2);
        expect(p7.nextTarget, 14);

        // value == 13 (порог - 1) -> level 2
        final p13 = AchievementProgress(
          id: AchievementId.streak,
          levels: thresholds,
          value: 13,
        );
        expect(p13.level, 2);
        expect(p13.nextTarget, 14);

        // value == 14 (порог) -> level 3
        final p14 = AchievementProgress(
          id: AchievementId.streak,
          levels: thresholds,
          value: 14,
        );
        expect(p14.level, 3);
        expect(p14.nextTarget, 30);

        // value == 29 (порог - 1) -> level 3
        final p29 = AchievementProgress(
          id: AchievementId.streak,
          levels: thresholds,
          value: 29,
        );
        expect(p29.level, 3);
        expect(p29.nextTarget, 30);

        // value == 30 (порог) -> level 4 (максимум)
        final p30 = AchievementProgress(
          id: AchievementId.streak,
          levels: thresholds,
          value: 30,
        );
        expect(p30.level, 4);
        expect(p30.isMaxed, isTrue);
        expect(p30.nextTarget, isNull);

        // value > 30 -> level 4
        final p50 = AchievementProgress(
          id: AchievementId.streak,
          levels: thresholds,
          value: 50,
        );
        expect(p50.level, 4);
        expect(p50.isMaxed, isTrue);
        expect(p50.nextTarget, isNull);
      },
    );
  });

  group('computeAchievements', () {
    test(
      'coverage/tickets: последний уровень равен totalQuestions/totalTickets из stats',
      () {
        final list = computeAchievements(
          longestStreak: 5,
          stats: {
            'answeredQuestions': 150,
            'passedTickets': 15,
            'totalQuestions': 800,
            'totalTickets': 40,
          },
          questionProgress: {},
          examResults: [],
          gameBestScore: 0,
        );

        final coverage = list.firstWhere((a) => a.id == AchievementId.coverage);
        final tickets = list.firstWhere((a) => a.id == AchievementId.tickets);

        expect(coverage.levels, [100, 300, 500, 800]);
        expect(coverage.levels.last, 800);
        expect(coverage.value, 150);
        expect(coverage.level, 1);

        expect(tickets.levels, [1, 10, 20, 40]);
        expect(tickets.levels.last, 40);
        expect(tickets.value, 15);
        expect(tickets.level, 2);
      },
    );

    test(
      'coverage и tickets не показываются пока statsProvider не загружен (totalQuestions == 0)',
      () {
        final list = computeAchievements(
          longestStreak: 0,
          stats: {
            'answeredQuestions': 0,
            'passedTickets': 0,
            'totalQuestions': 0,
            'totalTickets': 0,
          },
          questionProgress: {},
          examResults: [],
          gameBestScore: 0,
        );

        expect(list.any((a) => a.id == AchievementId.coverage), isFalse);
        expect(list.any((a) => a.id == AchievementId.tickets), isFalse);
        expect(list.length, 9);
      },
    );

    test('запись прогресса без attemptsCount считается как 1 попытка', () {
      final list = computeAchievements(
        longestStreak: 0,
        stats: {'totalQuestions': 800, 'totalTickets': 40},
        questionProgress: {
          'q1': {'isCorrect': true}, // no attemptsCount -> counts as 1
          'q2': {'isCorrect': false, 'attemptsCount': 4},
          'q3': {'isCorrect': true, 'attemptsCount': 10},
        },
        examResults: [],
        gameBestScore: 0,
      );

      final attempts = list.firstWhere((a) => a.id == AchievementId.attempts);
      expect(attempts.value, 1 + 4 + 10);
    });

    test('flawless не считает несданный экзамен с 0 ошибок', () {
      final list = computeAchievements(
        longestStreak: 0,
        stats: {'totalQuestions': 800, 'totalTickets': 40},
        questionProgress: {},
        examResults: [
          {'passed': false, 'wrongAnswers': 0, 'correctAnswers': 10},
          {'passed': true, 'wrongAnswers': 2, 'correctAnswers': 18},
          {'passed': true, 'wrongAnswers': 0, 'correctAnswers': 20},
          {'passed': true, 'correctAnswers': 20}, // wrongAnswers defaults to 0
        ],
        gameBestScore: 0,
      );

      final exams = list.firstWhere((a) => a.id == AchievementId.exams);
      expect(exams.value, 3); // 3 passed

      final flawless = list.firstWhere((a) => a.id == AchievementId.flawless);
      expect(flawless.value, 2); // only 2 passed with 0 wrong
    });

    test(
      'mistakes не считает вопрос, где ошибок не было, и вопрос, который сейчас неверен',
      () {
        final list = computeAchievements(
          longestStreak: 0,
          stats: {'totalQuestions': 800, 'totalTickets': 40},
          questionProgress: {
            // Ошибок не было (wrongAttempts == 0) -> не считать
            'q1': {'wrongAttempts': 0, 'isCorrect': true},
            // Сейчас неверен (isCorrect == false) -> не считать
            'q2': {'wrongAttempts': 3, 'isCorrect': false},
            // Ошибался, но сейчас неверен -> не считать
            'q3': {'wrongAttempts': 1, 'isCorrect': false},
            // Ошибался (wrongAttempts > 0) и сейчас верен (isCorrect == true) -> считать
            'q4': {'wrongAttempts': 1, 'isCorrect': true},
            'q5': {'wrongAttempts': 5, 'isCorrect': true},
          },
          examResults: [],
          gameBestScore: 0,
        );

        final mistakes = list.firstWhere((a) => a.id == AchievementId.mistakes);
        expect(mistakes.value, 2);
      },
    );

    test('game: счёт 400 → уровень 2, счёт 0 → уровень 0', () {
      final list400 = computeAchievements(
        longestStreak: 0,
        stats: {'totalQuestions': 800, 'totalTickets': 40},
        questionProgress: {},
        examResults: [],
        gameBestScore: 400,
      );
      final game400 = list400.firstWhere((a) => a.id == AchievementId.game);
      expect(game400.levels, [200, 400, 700, 950]);
      expect(game400.value, 400);
      expect(game400.level, 2);
      expect(game400.isUnlocked, isTrue);

      final list0 = computeAchievements(
        longestStreak: 0,
        stats: {'totalQuestions': 800, 'totalTickets': 40},
        questionProgress: {},
        examResults: [],
        gameBestScore: 0,
      );
      final game0 = list0.firstWhere((a) => a.id == AchievementId.game);
      expect(game0.value, 0);
      expect(game0.level, 0);
      expect(game0.isUnlocked, isFalse);
    });
  });

  group('Achievement asset files existence', () {
    test(
      'для каждого AchievementId и уровня 1..4 файл assets/images/achievements/<id>_<level>.png существует',
      () {
        for (final id in AchievementId.values) {
          for (var level = 1; level <= 4; level++) {
            final filePath = 'assets/images/achievements/${id.name}_$level.png';
            final file = File(filePath);
            expect(
              file.existsSync(),
              isTrue,
              reason: 'Файл $filePath должен существовать на диске',
            );
          }
        }
      },
    );
  });

  group('ProgressDataSource getExamResults error handling', () {
    test(
      'битая строка в результатах экзаменов не роняет getExamResults',
      () async {
        SharedPreferences.setMockInitialValues({
          'exam_results_ab': [
            '{"passed": true, "correctAnswers": 20, "wrongAnswers": 0}',
            '{corrupted json}',
            'not a json at all',
            '{"passed": false, "correctAnswers": 15, "wrongAnswers": 5}',
          ],
        });

        final dataSource = ProgressDataSource();
        await dataSource.init();

        final results = await dataSource.getExamResults(TicketCategory.ab);
        expect(results.length, 2);
        expect(results[0]['passed'], isTrue);
        expect(results[1]['passed'], isFalse);
      },
    );

    test('битый JSON-массив строкой не роняет getExamResults', () async {
      SharedPreferences.setMockInitialValues({
        'exam_results_ab':
            '["{\\"passed\\": true, \\"wrongAnswers\\": 0}", "corrupted json"]',
      });

      final dataSource = ProgressDataSource();
      await dataSource.init();

      final results = await dataSource.getExamResults(TicketCategory.ab);
      expect(results.length, 1);
      expect(results[0]['passed'], isTrue);
    });

    group('Покоритель рейтинга (лучшее место в недельном рейтинге)', () {
      int levelFor(int? bestRank) {
        final list = computeAchievements(
          longestStreak: 0,
          stats: {'totalQuestions': 800, 'totalTickets': 40},
          questionProgress: {},
          examResults: [],
          gameBestScore: 0,
          bestWeeklyRank: bestRank,
        );
        return list.firstWhere((a) => a.id == AchievementId.rank).level;
      }

      test('нет места (не в топ-100 или нет данных) → ни одного уровня', () {
        expect(levelFor(null), 0);
        expect(levelFor(0), 0);
        expect(levelFor(101), 0);
        expect(levelFor(500), 0);
      });

      test('границы уровней: топ-100 / топ-10 / топ-3 / 1 место', () {
        expect(levelFor(100), 1);
        expect(levelFor(11), 1);
        expect(levelFor(10), 2);
        expect(levelFor(4), 2);
        expect(levelFor(3), 3);
        expect(levelFor(2), 3);
        expect(levelFor(1), 4);
      });

      test('ачивка есть в списке всегда, в том числе без места', () {
        final list = computeAchievements(
          longestStreak: 0,
          stats: {'totalQuestions': 800, 'totalTickets': 40},
          questionProgress: {},
          examResults: [],
          gameBestScore: 0,
        );
        expect(list.last.id, AchievementId.rank);
        expect(list.last.isUnlocked, false);
      });
    });
  });
}
