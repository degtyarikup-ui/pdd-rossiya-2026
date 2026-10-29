import 'helpers/achievement_awards.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/services/usage_reporter.dart';
import 'package:pdd_app/data/services/review_prompt_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/presentation/screens/training/training_result_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/continue_session_card.dart';
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
  }) async {
    return null;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> updateLanguage(String lang) async {}
  @override
  Future<void> dispose() async {}
}

class _HungStopTts extends _SilentTts {
  final pendingStop = Completer<void>();
  @override
  Future<void> stop() => pendingStop.future;
}

List<Map<String, dynamic>> buildQuestions(int n) => List.generate(
  n,
  (i) => <String, dynamic>{
    'id': 'q$i',
    'question': 'Вопрос ${i + 1}',
    'answers': [
      {'text': 'Верный ответ', 'correct': true},
      {'text': 'Неверный ответ', 'correct': false},
    ],
    'comment': '',
    'pddPoints': <String>[],
    'image': null,
    'topic': <String>[],
    'ticketNumber': 1,
  },
);

/// Итог пройденного билета или темы.
///
/// До этой правки «Завершить» просто закрывало экран: человек проходил билет
/// и не узнавал, как прошёл. Тесты стерегут, что итог показывается и считает
/// верно.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProgressDataSource> pumpTraining(
    WidgetTester tester, {
    required int questions,
    ProgressDataSource? source,
    ReviewPromptService? review,
    String? resumedFeature,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final data = source ?? ProgressDataSource();
    await data.init();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          noAchievementAwards,
          progressDataSourceProvider.overrideWithValue(data),
          ttsServiceProvider.overrideWithValue(_SilentTts()),
          if (review != null)
            reviewPromptServiceProvider.overrideWithValue(review),
        ],
        child: MaterialApp(
          key: UniqueKey(),
          home: resumedFeature != null
              ? Scaffold(
                  body: ContinueSessionCard(
                    session: {
                      'kind': 'training',
                      'title': 'Билет 1',
                      'questions': buildQuestions(questions),
                      'index': 0,
                      'usageFeature': resumedFeature,
                    },
                  ),
                )
              : TrainingScreen(
                  questions: buildQuestions(questions),
                  title: 'Билет 1',
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return data;
  }

  Future<void> answer(WidgetTester tester, {required bool correct}) async {
    final text = correct ? 'Верный ответ' : 'Неверный ответ';
    await tester.tap(
      find.ancestor(of: find.text(text), matching: find.byType(InkWell)).last,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }

  for (final feature in ['tickets', 'topics', 'unknown']) {
    testWidgets('resume preserves $feature analytics without guessing a mode', (
      tester,
    ) async {
      final sent = <Map>[];
      final reporter = UsageReporter(
        endpoint: 'https://test',
        secret: 'test',
        client: MockClient((r) async {
          sent.add(jsonDecode(r.body) as Map);
          return http.Response('{}', 200);
        }),
      );
      UsageReporter.setInstanceForTest(reporter);
      addTearDown(() => UsageReporter.setInstanceForTest(null));
      await pumpTraining(tester, questions: 2, resumedFeature: feature);
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      await tester.runAsync(reporter.flush);
      expect(find.byType(TrainingScreen), findsOneWidget);
      expect(
        sent
            .expand((batch) => batch['events'] as List)
            .map((event) => event['feature'])
            .toList(),
        feature == 'unknown' ? isEmpty : [feature],
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  Future<void> nextOrFinish(WidgetTester tester) async {
    final next = find.text('Следующий вопрос');
    await tester.tap(
      next.evaluate().isNotEmpty ? next : find.text('Завершить'),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'просмотр ответов не восстанавливает уже завершённую тренировку',
    (tester) async {
      final data = await pumpTraining(tester, questions: 2);
      await answer(tester, correct: true);
      await nextOrFinish(tester);
      await answer(tester, correct: true);
      expect(data.loadUnfinishedSession(TicketCategory.ab), isNull);
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(0);
      await tester.pumpAndSettle();
      expect(data.loadUnfinishedSession(TicketCategory.ab), isNull);
    },
  );

  testWidgets(
    'запоздавшее избранное другого вопроса не меняет текущую кнопку',
    (tester) async {
      final data = _DelayedFavoriteSource();
      await pumpTraining(tester, questions: 2, source: data);
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
      await tester.pumpAndSettle();
      data.favorite.complete(true);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star_border), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('завершение записи избранного после закрытия не использует ref', (
    tester,
  ) async {
    final data = _DelayedToggleSource();
    await pumpTraining(tester, questions: 1, source: data);
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    data.toggle.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('после последнего вопроса показывается итог набора', (
    tester,
  ) async {
    await pumpTraining(tester, questions: 3);

    await answer(tester, correct: true);
    await nextOrFinish(tester);
    await answer(tester, correct: false);
    await nextOrFinish(tester);
    await answer(tester, correct: true);
    await nextOrFinish(tester);

    expect(find.byType(TrainingResultScreen), findsOneWidget);
    expect(find.text('Билет 1'), findsOneWidget);
    // 2 верных, 1 ошибка, 3 всего.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('без ошибок — итог хвалит и не предлагает повтор', (
    tester,
  ) async {
    await pumpTraining(tester, questions: 2);

    await answer(tester, correct: true);
    await nextOrFinish(tester);
    await answer(tester, correct: true);
    await nextOrFinish(tester);

    expect(find.byType(TrainingResultScreen), findsOneWidget);
    expect(find.textContaining('Ни одной ошибки'), findsOneWidget);
    expect(
      find.text('Повторить ошибки'),
      findsNothing,
      reason: 'повторять нечего, кнопка была бы обманом',
    );
  });

  testWidgets('«Повторить ошибки» открывает только те вопросы, где ошиблись', (
    tester,
  ) async {
    await pumpTraining(tester, questions: 3);

    await answer(tester, correct: false);
    await nextOrFinish(tester);
    await answer(tester, correct: true);
    await nextOrFinish(tester);
    await answer(tester, correct: false);
    await nextOrFinish(tester);

    await tester.tap(find.text('Повторить ошибки'));
    await tester.pumpAndSettle();

    final training = tester.widget<TrainingScreen>(find.byType(TrainingScreen));
    expect(training.questions.length, 2);
    expect(training.questions.map((q) => q['id']), [
      'q0',
      'q2',
    ], reason: 'верно отвеченный вопрос повторять незачем');
  });

  testWidgets('разбор одного вопроса итогом не заканчивается', (tester) async {
    await pumpTraining(tester, questions: 1);

    await answer(tester, correct: true);
    await nextOrFinish(tester);

    // Подводить итог по единственному вопросу — издевательство.
    expect(find.byType(TrainingResultScreen), findsNothing);
  });

  for (final correct in [true, false]) {
    testWidgets(
      'completed training requests once regardless of success: $correct',
      (tester) async {
        var requests = 0;
        final review = ReviewPromptService.forTesting(
          platform: TargetPlatform.iOS,
          isAvailable: () async => true,
          requestReview: () async {
            requests++;
          },
        );
        await pumpTraining(tester, questions: 2, review: review);
        await answer(tester, correct: correct);
        expect(requests, 0);
        await nextOrFinish(tester);
        await answer(tester, correct: correct);
        expect(requests, 0);
        // Two taps in the same frame must replace the route only once.
        await tester.tap(find.text('Завершить'));
        await tester.tap(find.text('Завершить'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(requests, 1);
        expect(find.byType(TrainingResultScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('single-question review never requests a store review', (
    tester,
  ) async {
    var requests = 0;
    final review = ReviewPromptService.forTesting(
      platform: TargetPlatform.iOS,
      isAvailable: () async => true,
      requestReview: () async {
        requests++;
      },
    );
    await pumpTraining(tester, questions: 1, review: review);
    await answer(tester, correct: true);
    await nextOrFinish(tester);
    expect(requests, 0);
  });

  testWidgets('пустая тренировка показывает заглушку без ошибки индекса', (
    tester,
  ) async {
    await pumpTraining(tester, questions: 0);
    expect(find.text('Нет вопросов'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('закрытие тренировки не ждёт зависший плагин озвучки', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final data = ProgressDataSource();
    await data.init();
    final tts = _HungStopTts();
    addTearDown(() => tts.pendingStop.complete());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noAchievementAwards,
          progressDataSourceProvider.overrideWithValue(data),
          ttsServiceProvider.overrideWithValue(tts),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TrainingScreen(
                      questions: buildQuestions(1),
                      title: 'Билет 1',
                    ),
                  ),
                ),
                child: const Text('Открыть тренировку'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть тренировку'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(find.byType(TrainingScreen), findsNothing);
    expect(find.text('Открыть тренировку'), findsOneWidget);
    expect(tts.pendingStop.isCompleted, isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _DelayedFavoriteSource extends ProgressDataSource {
  final favorite = Completer<bool>();
  @override
  Future<bool> isFavorite(String id, TicketCategory category) =>
      id == 'q0' ? favorite.future : Future.value(false);
}

class _DelayedToggleSource extends ProgressDataSource {
  final toggle = Completer<void>();
  @override
  Future<void> toggleFavorite(String id, TicketCategory category) async {
    await toggle.future;
    await super.toggleFavorite(id, category);
  }
}
