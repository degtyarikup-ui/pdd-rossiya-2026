import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/services/game_runs_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late List<DateTime> reminders;

  GameRunsService service() => GameRunsService.forTesting(
    now: () => now,
    scheduleReminder: (at) async => reminders.add(at),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 18, 12);
    reminders = [];
  });

  test('without premium an empty stock blocks starting and resuming', () {
    expect(GameRunsService.canRide(premium: false, runs: 0), isFalse);
    expect(GameRunsService.canRide(premium: false, runs: 1), isTrue);
    expect(GameRunsService.canRide(premium: true, runs: 0), isTrue);
  });

  test('new stock has three runs without a refill deadline', () async {
    final runs = service();
    expect(await runs.load(), 3);
    expect(runs.runs, 3);
    expect(runs.nextRefillAt, isNull);
    expect(runs.firstUnitAt, isNull);
    now = now.add(const Duration(hours: 4));
    expect(runs.refresh(), 3);
    expect(runs.nextRefillAt, isNull);
  });

  test('later runs keep the first-spend deadline and its reminder', () async {
    final runs = service();
    await runs.load();
    final deadline = now.add(const Duration(hours: 1));
    expect(await runs.consume(), isTrue);
    expect(runs.runs, 2);
    expect(runs.nextRefillAt, deadline);
    expect(runs.firstUnitAt, isNull);

    now = now.add(const Duration(minutes: 20));
    expect(await runs.consume(), isTrue);
    now = now.add(const Duration(minutes: 20));
    expect(await runs.consume(), isTrue);
    expect(runs.runs, 0);
    expect(runs.nextRefillAt, deadline);
    expect(runs.firstUnitAt, deadline);
    expect(reminders, [deadline]);
    expect(await runs.consume(), isFalse);
    expect(reminders, [deadline]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('game_runs'), 0);
    expect(
      prefs.getInt('game_runs_since'),
      deadline.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
  });

  test('nothing returns early, then all three return at one hour', () async {
    final runs = service();
    await runs.load();
    await runs.consume();
    await runs.consume();
    await runs.consume();
    final started = now;

    now = started.add(const Duration(minutes: 30));
    expect(runs.refresh(), 0);
    now = started.add(const Duration(minutes: 59, seconds: 59));
    expect(runs.refresh(), 0);
    now = started.add(const Duration(hours: 1));
    expect(runs.refresh(), 3);
    expect(runs.nextRefillAt, isNull);
    expect(runs.firstUnitAt, isNull);

    await runs.consume();
    expect(runs.runs, 2);
    expect(runs.nextRefillAt, now.add(const Duration(hours: 1)));
  });

  test(
    'partially spent stock also refills completely on the deadline',
    () async {
      final runs = service();
      await runs.load();
      await runs.consume();
      now = now.add(const Duration(hours: 1));
      expect(runs.refresh(), 3);
      expect(reminders, isEmpty);
    },
  );

  test('restart preserves the count and first-spend deadline', () async {
    final runs = service();
    await runs.load();
    final deadline = now.add(const Duration(hours: 1));
    await runs.consume();
    now = now.add(const Duration(minutes: 25));
    await runs.consume();

    final restarted = service();
    expect(await restarted.load(), 1);
    expect(restarted.nextRefillAt, deadline);
    now = deadline;
    expect(restarted.refresh(), 3);
  });

  test('overdue saved stock refills on load without a foreground timer', () async {
    SharedPreferences.setMockInitialValues({
      'game_runs': 0,
      'game_runs_since': now
          .subtract(const Duration(hours: 3))
          .millisecondsSinceEpoch,
    });
    final runs = service();
    expect(await runs.load(), 3);
    expect(runs.nextRefillAt, isNull);
    // A new service reads the persisted refill, rather than an old empty stock.
    await Future<void>.delayed(Duration.zero);
    expect(await service().load(), 3);
  });

  test(
    'old partial stock and its saved clock migrate without a reset',
    () async {
      final firstSpend = now.subtract(const Duration(minutes: 40));
      SharedPreferences.setMockInitialValues({
        'game_runs': 1,
        'game_runs_since': firstSpend.millisecondsSinceEpoch,
      });
      final runs = service();
      expect(await runs.load(), 1);
      expect(runs.nextRefillAt, firstSpend.add(const Duration(hours: 1)));
      now = now.add(const Duration(minutes: 20));
      expect(runs.refresh(), 3);
    },
  );

  test(
    'corrupt counts are bounded and future clocks wait at most an hour',
    () async {
      for (final count in [-12, 99]) {
        SharedPreferences.setMockInitialValues({
          'game_runs': count,
          'game_runs_since': now
              .add(const Duration(days: 5))
              .millisecondsSinceEpoch,
        });
        final runs = service();
        expect(await runs.load(), count < 0 ? 0 : 3);
        expect(
          runs.nextRefillAt,
          count < 0 ? now.add(const Duration(hours: 1)) : isNull,
        );
        now = now.add(const Duration(hours: 1));
        expect(runs.refresh(), 3);
      }
    },
  );

  test(
    'moving the device clock backwards cannot create a longer wait',
    () async {
      final runs = service();
      await runs.load();
      await runs.consume();
      now = now.subtract(const Duration(days: 1));
      expect(runs.refresh(), 2);
      expect(runs.nextRefillAt, now.add(const Duration(hours: 1)));
      now = now.add(const Duration(hours: 1));
      expect(runs.refresh(), 3);
    },
  );

  test('reminder cancellation still delegates to the notifier', () async {
    var cancellations = 0;
    final runs = GameRunsService.forTesting(
      now: () => now,
      cancelReminder: () async => cancellations++,
    );
    await runs.cancelReminder();
    expect(cancellations, 1);
  });

  testWidgets('all spent slots show the same batch-refill countdown', (
    tester,
  ) async {
    final deadline = DateTime.now().add(const Duration(minutes: 45));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GameRunsSheet(
            maxRuns: 3,
            questions: 20,
            refillMinutes: 60,
            unlimited: false,
            runs: () => 0,
            nextRefillAt: () => deadline,
          ),
        ),
      ),
    );
    final countdowns = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .where((text) => RegExp(r'^\d+:\d{2}$').hasMatch(text))
        .toList();
    expect(countdowns, hasLength(3));
    expect(countdowns.toSet(), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
