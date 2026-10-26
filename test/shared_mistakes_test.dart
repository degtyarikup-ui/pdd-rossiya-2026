import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/question_identity.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

Question question(String id, int number) => Question(
  id: id,
  question: 'Question $number',
  ticketNumber: 1,
  questionNumber: number,
  answers: const [
    Answer(text: 'Yes', isCorrect: true),
    Answer(text: 'No', isCorrect: false),
  ],
);

class _Bank extends QuestionsDataSource {
  final variant = QuestionIdentity.aliases[TicketCategory.ab]!.entries.first;
  @override
  Future<List<Question>> loadTickets(
    TicketCategory category, [
    String? lang,
  ]) async => category == TicketCategory.cd
      ? [question('cd-only', 1)]
      : [
          for (final id in [
            'training',
            'exam',
            'city',
            'legacy',
            'feed',
            'feed-correct',
            'mini-game',
            'invalid',
            variant.value,
            variant.key,
          ])
            question(id, 1),
        ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProgressDataSource data;
  late ProviderContainer container;
  final bank = _Bank();
  Map<String, Object> answer(bool correct, [String? source]) {
    final result = <String, Object>{
      'isCorrect': correct,
      'answeredAt': '2026-10-01T10:00:00',
    };
    if (source != null) result['source'] = source;
    return result;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'question_progress_ab': jsonEncode({
        'training': answer(false, 'training'),
        'exam': answer(false, 'exam'),
        'city': answer(false, 'city'),
        'legacy': answer(true),
        'feed': answer(false, 'feed'),
        'feed-correct': answer(true, 'feed'),
        'mini-game': answer(false, 'signs'),
        'invalid': {'isCorrect': 0},
        'sign_8_4_6': answer(false),
        'removed-question': answer(false),
        'cd-only': answer(false),
        bank.variant.value: answer(true),
        bank.variant.key: answer(false),
      }),
      'question_progress_cd': jsonEncode({'cd-only': answer(false)}),
    });
    data = ProgressDataSource();
    await data.init();
    container = ProviderContainer(
      overrides: [
        progressDataSourceProvider.overrideWithValue(data),
        questionsDataSourceProvider.overrideWithValue(bank),
      ],
    );
    await container.read(appSettingsProvider.notifier).ready;
  });
  tearDown(() => container.dispose());

  test(
    'counter and mistake list share only canonical training, exam and city answers',
    () async {
      final stats = await container.read(statsProvider.future);
      final wrong = await container.read(wrongQuestionIdsProvider.future);
      expect(
        wrong,
        unorderedEquals(['training', 'exam', 'city', bank.variant.key]),
      );
      expect(stats['wrongQuestions'], wrong.length);
      expect(stats['correctAnswers'], 2);
      expect(stats['answeredQuestions'], 6);
      expect(
        (await data.getAllQuestionProgress(TicketCategory.ab))['sign_8_4_6'],
        isNotNull,
        reason:
            'Display filtering preserves old cloud data without a destructive migration',
      );
    },
  );

  test(
    'new imports cannot resurrect phantom mistakes; category and correction refresh both views',
    () async {
      await container.read(statsProvider.future);
      await data.importProgressSnapshot({
        'questionProgressAb': {'another-sign': answer(false)},
      });
      await container.pump();
      expect(
        (await container.read(wrongQuestionIdsProvider.future)),
        isNot(contains('another-sign')),
      );
      await data.saveAnswer(
        questionId: 'training',
        isCorrect: true,
        selectedAnswerIndex: 0,
        category: TicketCategory.ab,
      );
      container.read(appDataRefreshProvider.notifier).state++;
      expect((await container.read(statsProvider.future))['wrongQuestions'], 3);
      expect(
        (await container.read(wrongQuestionIdsProvider.future)),
        isNot(contains('training')),
      );
      await container
          .read(appSettingsProvider.notifier)
          .setTicketCategory(TicketCategory.cd);
      expect(await container.read(wrongQuestionIdsProvider.future), [
        'cd-only',
      ]);
      expect(
        (await container.read(statsProvider.future))['answeredQuestions'],
        1,
      );
      expect((await container.read(statsProvider.future))['wrongQuestions'], 1);
    },
  );
}
