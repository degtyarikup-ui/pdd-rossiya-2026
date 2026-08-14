import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/presentation/screens/training/training_result_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentTts implements TtsService {
  @override
  Future<void> speakQuestion({
    required String question,
    required List<String> answers,
  }) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
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

  Future<void> pumpTraining(
    WidgetTester tester, {
    required int questions,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final data = ProgressDataSource();
    await data.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          progressDataSourceProvider.overrideWithValue(data),
          ttsServiceProvider.overrideWithValue(_SilentTts()),
        ],
        child: MaterialApp(
          home: TrainingScreen(
            questions: buildQuestions(questions),
            title: 'Билет 1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> answer(WidgetTester tester, {required bool correct}) async {
    await tester.tap(
      find.text(correct ? 'Верный ответ' : 'Неверный ответ').hitTestable(),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }

  Future<void> nextOrFinish(WidgetTester tester) async {
    final next = find.text('Следующий вопрос');
    await tester.tap(next.evaluate().isNotEmpty ? next : find.text('Завершить'));
    await tester.pumpAndSettle();
  }

  testWidgets('после последнего вопроса показывается итог набора',
      (tester) async {
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

  testWidgets('без ошибок — итог хвалит и не предлагает повтор',
      (tester) async {
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

  testWidgets('«Повторить ошибки» открывает только те вопросы, где ошиблись',
      (tester) async {
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
    expect(
      training.questions.map((q) => q['id']),
      ['q0', 'q2'],
      reason: 'верно отвеченный вопрос повторять незачем',
    );
  });

  testWidgets('разбор одного вопроса итогом не заканчивается', (tester) async {
    await pumpTraining(tester, questions: 1);

    await answer(tester, correct: true);
    await nextOrFinish(tester);

    // Подводить итог по единственному вопросу — издевательство.
    expect(find.byType(TrainingResultScreen), findsNothing);
  });
}
