import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/presentation/widgets/progress_panel_card.dart';

/// Панель прогресса на главном экране.
///
/// Смысл правки был в иерархии: ответ на главный вопрос («я готов?») должен
/// быть самым крупным на экране, а не самым мелким. Тесты стерегут именно это
/// и арифметику остатка.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const stats = {
    'correctAnswers': 357,
    'answeredQuestions': 409,
    'wrongQuestions': 52,
    'passedTickets': 16,
    'totalQuestions': 800,
    'totalTickets': 40,
  };

  Future<void> pump(WidgetTester tester, {Map<String, int> s = stats}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressPanelCard(stats: s, streak: null),
        ),
      ),
    );
  }

  /// Число готовности собрано из спанов («45» + «%»), поэтому обычный
  /// find.text его не видит — достаём из TextSpan.
  ({String text, double size}) gaugeValue(WidgetTester tester) {
    final rich = tester.widget<Text>(
      find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
    );
    final span = (rich.textSpan! as TextSpan).children!.first as TextSpan;
    return (text: span.text!, size: span.style!.fontSize!);
  }

  testWidgets('готовность считается по верным ответам от всех вопросов',
      (tester) async {
    await pump(tester);
    // 357 из 800 — 44.6%, округляется до 45.
    expect(gaugeValue(tester).text, '45');
  });

  testWidgets('остаток — сколько верных ответов не хватает', (tester) async {
    await pump(tester);
    // 800 − 357. Именно это число двигает к действию, в отличие от процента.
    expect(find.textContaining('443'), findsOneWidget);
  });

  testWidgets('главное число крупнее всех прочих на панели', (tester) async {
    await pump(tester);

    final microSize = tester.widget<Text>(find.text('409')).style!.fontSize!;

    expect(
      gaugeValue(tester).size,
      greaterThan(microSize),
      reason: 'ради этого всё и затевалось: ответ на главный вопрос '
          'должен доминировать, а не теряться среди прочих чисел',
    );
  });

  testWidgets('нулевой прогресс не ломает шкалу', (tester) async {
    await pump(tester, s: const {
      'correctAnswers': 0,
      'answeredQuestions': 0,
      'wrongQuestions': 0,
      'passedTickets': 0,
      'totalQuestions': 0,
      'totalTickets': 0,
    });
    // Деления на ноль нет, процент нулевой, а не NaN.
    expect(gaugeValue(tester).text, '0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('всё пройдено — вместо остатка похвала, а не «осталось 0»',
      (tester) async {
    await pump(tester, s: const {
      'correctAnswers': 800,
      'answeredQuestions': 800,
      'wrongQuestions': 0,
      'passedTickets': 40,
      'totalQuestions': 800,
      'totalTickets': 40,
    });
    expect(gaugeValue(tester).text, '100');
    expect(find.textContaining('осталось 0'), findsNothing);
  });

  testWidgets('серия показывается строкой внутри той же карточки',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressPanelCard(
            stats: stats,
            streak: Streak(
              current: 4,
              longest: 11,
              lastActiveDate: DateTime.now(),
              startDate: DateTime.now(),
              activeDays: const {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('4 дня'), findsOneWidget);
    expect(find.text('Рекорд 11'), findsOneWidget);
  });
}
