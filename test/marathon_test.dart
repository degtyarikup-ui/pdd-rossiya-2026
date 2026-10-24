import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/marathon_progress.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/training/marathon_entry.dart';
import 'package:pdd_app/presentation/screens/training/training_result_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/question_number_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentTts implements TtsService {
  @override
  Future<void> speakQuestion({
    String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async {}
  @override
  Future<Duration?> speakOrPlayFeedItem({
    required String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async => null;
  @override
  Future<void> stop() async {}
  @override
  Future<void> updateLanguage(String lang) async {}
  @override
  Future<void> dispose() async {}
}

List<Question> questions(int n) => List.generate(
  n,
  (i) => Question(
    id: 'q$i',
    question: 'Ситуация ${i + 1}',
    ticketNumber: i ~/ 20 + 1,
    questionNumber: i % 20 + 1,
    answers: const [
      Answer(text: 'Верно', isCorrect: true),
      Answer(text: 'Неверно', isCorrect: false),
    ],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProgressDataSource source;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'notification_prompt_shown': true});
    source = ProgressDataSource();
    await source.init();
  });

  for (final category in ['ab', 'cd']) {
    test(
      'real $category bank retains all 800 positions and illustration variants in order',
      () {
        final json =
            jsonDecode(
                  File(
                    CountryConfig.current.questionsJson(category),
                  ).readAsStringSync(),
                )
                as Map;
        final bank = <Question>[];
        for (final ticket in json['tickets'] as List) {
          final list = ticket['questions'] as List;
          for (var i = 0; i < list.length; i++) {
            bank.add(
              Question.fromJson({
                ...Map<String, dynamic>.from(list[i] as Map),
                'ticketNumber': ticket['number'],
                'questionNumber': i + 1,
              }),
            );
          }
        }
        final ordered = marathonQuestions(bank.reversed);
        expect(ordered.length, 800);
        expect(ordered.map((q) => q['id']).toSet().length, 800);
        for (var i = 0; i < 800; i++) {
          expect(ordered[i]['ticketNumber'], i ~/ 20 + 1);
          expect(ordered[i]['questionNumber'], i % 20 + 1);
        }
      },
    );
  }

  test(
    'restart persists answers and position independently of category and training',
    () async {
      await source.saveMarathon(
        TicketCategory.ab,
        const MarathonProgress(answers: {'q0': 1}, currentQuestionId: 'q1'),
      );
      await source.saveMarathon(
        TicketCategory.cd,
        const MarathonProgress(
          answers: {'q0': 0, 'q1': 1},
          currentQuestionId: 'q2',
        ),
      );
      await source.saveUnfinishedSession(
        title: 'Билет',
        questionIds: ['q9'],
        index: 0,
        category: TicketCategory.ab,
      );
      final fresh = ProgressDataSource();
      await fresh.init();
      final bank = marathonQuestions(questions(3));
      expect(fresh.loadMarathon(TicketCategory.ab)!.restoreChoices(bank), [
        1,
        null,
        null,
      ]);
      expect(fresh.loadMarathon(TicketCategory.ab)!.resumeIndex(bank), 1);
      expect(fresh.loadMarathon(TicketCategory.cd)!.restoreChoices(bank), [
        0,
        1,
        null,
      ]);
      expect(fresh.loadUnfinishedSession(TicketCategory.ab)!['title'], 'Билет');
      await fresh.resetAllProgress();
      expect(fresh.loadMarathon(TicketCategory.ab), isNull);
      expect(fresh.loadMarathon(TicketCategory.cd), isNull);
    },
  );

  test(
    'invalid or changed content resumes at the first unanswered position',
    () async {
      final bank = marathonQuestions(questions(4));
      const progress = MarathonProgress(
        answers: {'q0': 1, 'q1': 9, 'q2': 0},
        currentQuestionId: 'q3',
      );
      expect(progress.restoreChoices(bank), [1, null, null, null]);
      expect(progress.resumeIndex(bank), 1);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('marathon_v1_ab', 'broken');
      expect(source.loadMarathon(TicketCategory.ab), isNull);
      await prefs.setString('marathon_v1_ab', '{"version":2,"answers":{}}');
      expect(source.loadMarathon(TicketCategory.ab), isNull);
    },
  );

  Future<void> pumpEntry(
    WidgetTester tester, {
    int count = 3,
    ProgressDataSource? data,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          progressDataSourceProvider.overrideWithValue(data ?? source),
          ttsServiceProvider.overrideWithValue(_SilentTts()),
          ticketsProvider.overrideWith(
            (ref) async => [
              {'number': 1, 'questions': questions(count).reversed.toList()},
            ],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => openMarathon(context, ref),
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).hitTestable());
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.close_rounded).hitTestable());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ordered play, cancellation, app restart, resume and correct final totals',
    (tester) async {
      await pumpEntry(tester);
      await tap(tester, 'Открыть');
      expect(find.byType(MarathonResumeDialog), findsNothing);
      expect(find.text('Ситуация 1'), findsOneWidget);
      expect(
        tester
            .widget<PageView>(find.byType(PageView))
            .childrenDelegate
            .estimatedChildCount,
        1,
      );
      final futureChip = tester.widget<QuestionNumberChip>(
        find.byWidgetPredicate((w) => w is QuestionNumberChip && w.number == 3),
      );
      expect(futureChip.onTap, isNull);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Вопрос 1 из 3'), findsOneWidget);
      await tap(tester, 'Неверно');
      await tap(tester, 'Следующий вопрос');
      await close(tester);
      expect(source.loadMarathon(TicketCategory.ab)!.answers, {'q0': 1});
      expect(source.loadUnfinishedSession(TicketCategory.ab), isNull);

      // Recreate both the widget tree and data source, as on a real cold launch.
      await tester.pumpWidget(const SizedBox());
      final fresh = ProgressDataSource();
      await fresh.init();
      await pumpEntry(tester, data: fresh);
      await tap(tester, 'Открыть');
      expect(find.text('Пройдено 1 из 3 вопросов'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Продолжить'), findsOneWidget);
      Navigator.of(tester.element(find.byType(MarathonResumeDialog))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(TrainingScreen), findsNothing);
      expect(fresh.loadMarathon(TicketCategory.ab)!.answers, {'q0': 1});
      await tap(tester, 'Открыть');
      await tap(tester, 'Продолжить');
      expect(find.text('Вопрос 2 из 3'), findsOneWidget);
      await tap(tester, 'Верно');
      await tap(tester, 'Следующий вопрос');
      await tap(tester, 'Верно');
      await tap(tester, 'Завершить');
      final result = tester.widget<TrainingResultScreen>(
        find.byType(TrainingResultScreen),
      );
      expect(result.correct, 2);
      expect(result.total, 3);
      expect(result.wrongQuestions.single['id'], 'q0');
      expect(fresh.loadMarathon(TicketCategory.ab)!.answers.length, 3);
      // Reopening a completed marathon shows its result without a new attempt.
      await tester.pumpWidget(const SizedBox());
      await pumpEntry(tester, data: fresh);
      await tap(tester, 'Открыть');
      await tap(tester, 'Посмотреть результат');
      expect(
        tester
            .widget<TrainingResultScreen>(find.byType(TrainingResultScreen))
            .correct,
        2,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('reset starts from question one and preserves other progress', (
    tester,
  ) async {
    await source.saveMarathon(
      TicketCategory.ab,
      const MarathonProgress(answers: {'q0': 1}, currentQuestionId: 'q1'),
    );
    await source.saveMarathon(
      TicketCategory.cd,
      const MarathonProgress(answers: {'q0': 0}, currentQuestionId: 'q1'),
    );
    await source.saveUnfinishedSession(
      title: 'Билет 7',
      questionIds: ['q7'],
      index: 0,
      category: TicketCategory.ab,
    );
    await pumpEntry(tester);
    await tap(tester, 'Открыть');
    await tap(tester, 'Сбросить и начать сначала');
    expect(find.text('Вопрос 1 из 3'), findsOneWidget);
    expect(source.loadMarathon(TicketCategory.ab)!.answers, isEmpty);
    expect(source.loadMarathon(TicketCategory.cd)!.answers, {'q0': 0});
    expect(
      source.loadUnfinishedSession(TicketCategory.ab)!['title'],
      'Билет 7',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'question 800 resumes and finishes with all prior answers counted',
    (tester) async {
      await source.saveMarathon(
        TicketCategory.ab,
        MarathonProgress(
          answers: {for (var i = 0; i < 799; i++) 'q$i': 0},
          currentQuestionId: 'q799',
        ),
      );
      await pumpEntry(tester, count: 800);
      await tap(tester, 'Открыть');
      await tap(tester, 'Продолжить');
      expect(find.text('Вопрос 800 из 800'), findsOneWidget);
      expect(find.text('800').hitTestable(), findsOneWidget);
      await tap(tester, 'Неверно');
      await tap(tester, 'Завершить');
      final result = tester.widget<TrainingResultScreen>(
        find.byType(TrainingResultScreen),
      );
      expect(result.correct, 799);
      expect(result.total, 800);
      expect(result.wrongQuestions.single['id'], 'q799');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
