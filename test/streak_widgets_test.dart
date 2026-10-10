import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/presentation/widgets/streak_celebration_dialog.dart';
import 'package:pdd_app/presentation/widgets/streak_widgets.dart';

/// Серия дней: блок профиля и поздравление.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Четверг: неделя Пн–Вс вокруг него.
  final today = DateTime(2026, 10, 8);
  Streak streakOf(int current, int longest, {bool today_ = true}) {
    final days = <DateTime>{
      for (var i = today_ ? 0 : 1; i < current + (today_ ? 0 : 1); i++)
        today.subtract(Duration(days: i)),
    };
    return Streak(
      current: current,
      longest: longest,
      lastActiveDate: days.isEmpty ? null : days.first,
      startDate: days.isEmpty ? null : days.last,
      activeDays: days,
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );

  test('ближайшая цель — следующая ступень лестницы', () {
    expect(nextStreakMilestone(0), 3);
    expect(nextStreakMilestone(3), 7);
    expect(nextStreakMilestone(12), 14);
    expect(nextStreakMilestone(365), isNull);
    expect(previousStreakMilestone(12), 7);
  });

  testWidgets('карточка: число, рекорд, неделя и цель', (tester) async {
    await pump(tester, StreakCard(streak: streakOf(5, 11), today: today));
    expect(find.text('5 '), findsNothing); // число и слово — один абзац
    expect(find.textContaining('дней подряд'), findsOneWidget);
    expect(find.text('Рекорд 11'), findsOneWidget);
    expect(find.text('Сегодня засчитано'), findsOneWidget);
    expect(find.text('Ещё 2 дня до 7'), findsOneWidget);
    expect(find.text('5/7'), findsOneWidget);
    // Пн–Чт закрыты (4 дня этой недели), Пт–Вс впереди.
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
  });

  testWidgets('день ещё не засчитан — карточка напоминает', (tester) async {
    await pump(
      tester,
      StreakCard(streak: streakOf(3, 3, today_: false), today: today),
    );
    expect(find.textContaining('Сегодня ещё не занимались'), findsOneWidget);
  });

  testWidgets('без серии — приглашение начать, без рекорда', (tester) async {
    await pump(tester, StreakCard(streak: Streak.empty(), today: today));
    expect(find.textContaining('зажжётся огонёк'), findsOneWidget);
    expect(find.textContaining('Рекорд'), findsNothing);
    expect(find.text('Ещё 3 дня до 3'), findsOneWidget);
  });

  testWidgets('поздравление: без обводок, без лишнего текста', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StreakCelebrationView(streak: streakOf(7, 7), today: today),
      ),
    );
    // Огонёк спокойно «дышит» без конца — ждём конца появления, не покоя.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Новый рекорд'), findsOneWidget);
    expect(find.text('Продолжить'), findsOneWidget);
    // Ни одной обводки: состояние передаёт только цвет.
    final borders = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border != null || (d.boxShadow?.isNotEmpty ?? false));
    expect(borders, isEmpty);
  });
}
