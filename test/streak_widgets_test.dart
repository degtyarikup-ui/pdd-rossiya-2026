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
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  test('ближайшая цель — следующая ступень лестницы', () {
    expect(nextStreakMilestone(0), 3);
    expect(nextStreakMilestone(3), 7);
    expect(nextStreakMilestone(12), 14);
    expect(nextStreakMilestone(365), isNull);
    expect(previousStreakMilestone(12), 7);
  });

  testWidgets('карточка: огонёк, число и неделя — без рекорда и цели', (
    tester,
  ) async {
    await pump(tester, StreakCard(streak: streakOf(5, 11), today: today));
    expect(find.textContaining('дней подряд'), findsOneWidget);
    expect(find.text('Сегодня засчитано'), findsOneWidget);
    expect(find.textContaining('Рекорд'), findsNothing);
    expect(find.textContaining('Ещё'), findsNothing);
    expect(find.byType(StreakFlameBadge), findsOneWidget);
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
  });

  testWidgets('лента не расходится с числом: дни серии закрашены', (
    tester,
  ) async {
    // Счётчик говорит 6, а в списке нет вторника: лента всё равно закрывает
    // все шесть дней ряда (исправление самого счётчика — в ProgressDataSource).
    final days = {for (var i = 0; i < 6; i++) today.subtract(Duration(days: i))}
      ..remove(DateTime(2026, 10, 6));
    await pump(
      tester,
      StreakCard(
        streak: Streak(
          current: 6,
          longest: 6,
          lastActiveDate: today,
          startDate: today.subtract(const Duration(days: 5)),
          activeDays: days,
        ),
        today: today,
      ),
    );
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
  });

  testWidgets('огонёк без серии — серый и неподвижный', (tester) async {
    await pump(tester, const StreakFlameBadge(active: false));
    await tester.pumpAndSettle();
    expect(find.byType(StreakFlameBadge), findsOneWidget);
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
