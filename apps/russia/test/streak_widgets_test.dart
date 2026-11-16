import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/burning_flame.dart';
import 'package:pdd_app/presentation/widgets/flame_icon.dart';
import 'package:pdd_app/presentation/widgets/streak_calendar_sheet.dart';
import 'package:pdd_app/presentation/widgets/streak_celebration_dialog.dart';
import 'package:pdd_app/presentation/widgets/streak_widgets.dart';

/// Серия дней: блок профиля, календарь и поздравление.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initAppDateFormatting);
  setUp(() => SoundEffectsService.instance.setEnabled(false));
  tearDown(() {
    SoundEffectsService.instance.setEnabled(true);
    updateAppLocale(const Locale('ru'));
  });

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
    expect(find.text('Сегодня ещё не занимались'), findsOneWidget);
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
    // Горение продолжается бесконечно — ждём конца появления, не покоя.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Новый рекорд'), findsOneWidget);
    expect(find.text('Продолжить'), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      AppColors.gold,
    );
    expect(find.byType(BurningFlame), findsOneWidget);
    // Ни одной обводки: состояние передаёт только цвет.
    final borders = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border != null || (d.boxShadow?.isNotEmpty ?? false));
    expect(borders, isEmpty);
  });

  testWidgets(
    'нажатие на плашку серии открывает календарь с огоньками на днях занятий',
    (tester) async {
      final streak = Streak(
        current: 5,
        longest: 11,
        lastActiveDate: today,
        startDate: DateTime(2026, 10, 4),
        activeDays: {
          DateTime(2026, 9, 15),
          DateTime(2026, 9, 28),
          DateTime(2026, 10, 1),
          DateTime(2026, 10, 4),
          DateTime(2026, 10, 5),
          DateTime(2026, 10, 6),
          DateTime(2026, 10, 7),
          DateTime(2026, 10, 8),
        },
      );

      await pump(tester, StreakCard(streak: streak, today: today));
      await tester.tap(find.byType(StreakCard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(StreakCalendarSheet), findsOneWidget);
      expect(find.text('Октябрь 2026'), findsOneWidget);
      expect(find.text('6 дней с занятиями'), findsOneWidget);
      expect(find.text('Личный рекорд'), findsOneWidget);
      expect(find.text('11 дней'), findsOneWidget);

      // Занятия в октябре (1 и 4..8) отмечены огоньком.
      for (final day in [1, 4, 5, 6, 7, 8]) {
        final cell = find.byKey(
          ValueKey('streak_calendar_day_2026-10-${day.toString().padLeft(2, '0')}'),
        );
        expect(
          find.descendant(of: cell, matching: find.byType(FlameIcon)),
          findsOneWidget,
        );
      }

      // Пропущенные и будущие дни без огонька.
      for (final day in [2, 3, 9, 15]) {
        final cell = find.byKey(
          ValueKey('streak_calendar_day_2026-10-${day.toString().padLeft(2, '0')}'),
        );
        expect(
          find.descendant(of: cell, matching: find.byType(FlameIcon)),
          findsNothing,
        );
      }

      // На текущем месяце кнопка вперёд не перелистывает в будущее.
      await tester.tap(find.byKey(const ValueKey('streak_calendar_next_month')));
      await tester.pump();
      expect(find.text('Октябрь 2026'), findsOneWidget);

      // Листаем на предыдущий месяц — видим сентябрьские занятия.
      await tester.tap(find.byKey(const ValueKey('streak_calendar_prev_month')));
      await tester.pump();
      expect(find.text('Сентябрь 2026'), findsOneWidget);
      expect(find.text('2 дня с занятиями'), findsOneWidget);

      final sep15 = find.byKey(
        const ValueKey('streak_calendar_day_2026-09-15'),
      );
      expect(
        find.descendant(of: sep15, matching: find.byType(FlameIcon)),
        findsOneWidget,
      );
      final sep16 = find.byKey(
        const ValueKey('streak_calendar_day_2026-09-16'),
      );
      expect(
        find.descendant(of: sep16, matching: find.byType(FlameIcon)),
        findsNothing,
      );

      // Возвращаемся в октябрь.
      await tester.tap(find.byKey(const ValueKey('streak_calendar_next_month')));
      await tester.pump();
      expect(find.text('Октябрь 2026'), findsOneWidget);
    },
  );

  testWidgets('календарь при незавершённом сегодня не ставит огонёк на сегодня', (
    tester,
  ) async {
    await pump(
      tester,
      StreakCard(streak: streakOf(3, 3, today_: false), today: today),
    );
    await tester.tap(find.byType(StreakCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final todayCell = find.byKey(
      const ValueKey('streak_calendar_day_2026-10-08'),
    );
    expect(
      find.descendant(of: todayCell, matching: find.byType(FlameIcon)),
      findsNothing,
    );
    final yesterdayCell = find.byKey(
      const ValueKey('streak_calendar_day_2026-10-07'),
    );
    expect(
      find.descendant(of: yesterdayCell, matching: find.byType(FlameIcon)),
      findsOneWidget,
    );
  });

  testWidgets('календарь: пустая серия, тёмная тема и крупный шрифт без overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: StreakCard(streak: Streak.empty(), today: today),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(StreakCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(StreakCalendarSheet), findsOneWidget);
    expect(find.text('0 дней с занятиями'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('локализация календаря серии заполнена на ru, en и kk', () {
    for (final lang in ['ru', 'en', 'kk']) {
      final l10n = lookupAppLocalizations(Locale(lang));
      expect(l10n.streakCalendarMonthActiveDays(0), isNotEmpty);
      expect(l10n.streakCalendarMonthActiveDays(1), isNotEmpty);
      expect(l10n.streakCalendarMonthActiveDays(5), isNotEmpty);
      expect(l10n.streakCalendarPrevMonth, isNotEmpty);
      expect(l10n.streakCalendarNextMonth, isNotEmpty);
      expect(l10n.streakCalendarToday, isNotEmpty);
      expect(l10n.streakCalendarStudied, isNotEmpty);
    }
  });
}
