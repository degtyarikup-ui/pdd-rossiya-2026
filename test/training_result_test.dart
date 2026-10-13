import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/presentation/screens/training/training_result_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
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
          progressDataSourceProvider.overrideWithValue(data),
          ttsServiceProvider.overrideWithValue(_SilentTts()),
        ],
        child: MaterialApp(
          key: UniqueKey(),
          home: TrainingScreen(
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
