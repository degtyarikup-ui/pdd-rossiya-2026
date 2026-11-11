import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final category in TicketCategory.values) {
    test(
      'all ${category.name} ticket slots reach 800 and award full coverage',
      () async {
        final questions = await QuestionsDataSource().loadTickets(
          category,
          'ru',
        );
        expect(questions, hasLength(800));
        final answers = {
          for (final question in questions)
            question.id: {'isCorrect': true, 'source': 'training'},
        };
        SharedPreferences.setMockInitialValues({
          'question_progress_${category.name}': jsonEncode(answers),
        });
        final progress = ProgressDataSource();
        await progress.init();
        final container = ProviderContainer(
          overrides: [progressDataSourceProvider.overrideWithValue(progress)],
        );
        addTearDown(container.dispose);
        await container.read(appSettingsProvider.notifier).ready;
        await container
            .read(appSettingsProvider.notifier)
            .setTicketCategory(category);

        final stats = await container.read(statsProvider.future);
        expect(stats['totalQuestions'], 800);
        expect(stats['answeredQuestions'], 800);
        expect(stats['correctAnswers'], 800);
        expect(stats['passedTickets'], 40);
        expect(stats['wrongQuestions'], 0);
        final awards = computeAchievements(
          longestStreak: 0,
          stats: stats,
          questionProgress: answers,
          examResults: const [],
          gameBestScore: 0,
        );
        expect(
          awards
              .firstWhere((award) => award.id == AchievementId.coverage)
              .isMaxed,
          isTrue,
        );
        expect(
          (await container.read(ticketProgressProvider.future)).values,
          everyElement(20),
        );
      },
    );
  }
}
