import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/achievement_award_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final today = Streak.day(DateTime.now());
  String iso(DateTime day) => AchievementAwardService.dayKey(day);

  Future<ProgressDataSource> data([
    Map<String, Object> values = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(values);
    final source = ProgressDataSource();
    await source.init();
    return source;
  }

  AchievementAwardService service(ProgressDataSource source) =>
      AchievementAwardService(
        scope: 'ab',
        activity: source,
        load: () async => [
          AchievementProgress(
            id: AchievementId.streak,
            value: (await source.loadStreak()).longest,
            levels: const [3, 7, 14, 30],
          ),
        ],
      );

  test(
    'launch without answers counts once; pending survives an aborted lesson',
    () async {
      final source = await data();
      final awards = service(source);
      await awards.startActivity();
      expect((await source.loadStreak()).current, 1);
      expect((await awards.pendingStreak())!.lastActiveDate, today);
      expect(await source.getAllQuestionProgress(TicketCategory.ab), isEmpty);
      // A different format/category can finish the day started in the first one.
      final reopened = service(source);
      await reopened.startActivity();
      expect((await source.loadStreak()).current, 1);
      final pending = (await reopened.pendingStreak())!;
      await reopened.acknowledgeStreak(pending);
      await service(source).startActivity();
      expect(await service(source).pendingStreak(), isNull);
    },
  );

  test(
    'baseline precedes new streak milestone, not its presentation',
    () async {
      final source = await data({
        'streak_current': 2,
        'streak_longest': 2,
        'streak_last_active': iso(Streak.shiftDay(today, -1)),
        'streak_active_days': [
          iso(Streak.shiftDay(today, -2)),
          iso(Streak.shiftDay(today, -1)),
        ],
      });
      final awards = service(source);
      await awards.startActivity();
      expect((await awards.pendingStreak())!.current, 3);
      expect((await awards.pending()).single.id, AchievementId.streak);
      expect((await awards.pending()).single.level, 1);
      // Reading the completion queue does not acknowledge either screen.
      expect(await service(source).pendingStreak(), isNotNull);
      expect((await service(source).pending()).single.level, 1);
    },
  );

  test(
    'missed day resets current, preserves record; leap day remains consecutive',
    () async {
      final source = await data();
      await source.recordActivity(date: DateTime(2024, 2, 28));
      await source.recordActivity(date: DateTime(2024, 2, 29));
      await source.recordActivity(date: DateTime(2024, 3, 1));
      expect((await source.loadStreak(now: DateTime(2024, 3, 1))).current, 3);
      await source.recordActivity(date: DateTime(2024, 3, 3));
      final reset = await source.loadStreak(now: DateTime(2024, 3, 3));
      expect(reset.current, 1);
      expect(reset.longest, 3);
      expect(reset.startDate, DateTime(2024, 3, 3));
      // Calendar arithmetic also works across daylight-saving changes.
      expect(
        Streak.dayDistance(DateTime(2026, 3, 29), DateTime(2026, 3, 30)),
        1,
      );
      expect(
        Streak.shiftDay(DateTime(2026, 10, 25), 1),
        DateTime(2026, 10, 26),
      );
    },
  );

  test('acknowledging yesterday cannot consume the new day', () async {
    final source = await data();
    final yesterday = Streak.shiftDay(today, -1);
    await source.recordActivity(date: yesterday);
    await source.recordActivity(date: today);
    await source.acknowledgeStreakCelebration(yesterday);
    expect((await source.pendingStreakCelebration())!.current, 2);
    await source.acknowledgeStreakCelebration(today);
    expect(await source.pendingStreakCelebration(), isNull);
  });

  test(
    'native launch is projected, then credited even with zero answers',
    () async {
      final source = await data();
      final awards = service(source);
      await awards.prepare();
      final projection = (await awards.nativeStreak(today))!;
      expect(projection['current'], 1);
      expect(projection['pending'], true);
      // A failed/unavailable engine never confirms the projection.
      expect((await source.loadStreak()).current, 0);
      expect(await awards.pendingStreak(), isNull);
      await awards.recordNativeActivity({
        'run_started': true,
        'answered': 0,
      }, today);
      expect((await source.loadStreak()).current, 1);
      expect(await awards.pendingStreak(), isNotNull);
      // A later native result reports exactly which day was presented.
      await awards.recordNativeActivity({
        'streak_celebrated_day': iso(today),
      }, today);
      expect(await awards.pendingStreak(), isNull);
      expect((await awards.nativeStreak(today))!['pending'], false);
    },
  );

  test(
    'native midnight activity is ordered, validates dates and receipts',
    () async {
      final source = await data();
      final awards = service(source);
      final yesterday = Streak.shiftDay(today, -1);
      await awards.recordNativeActivity({
        'activity_days': [
          iso(today),
          'bad date',
          iso(yesterday),
          iso(Streak.shiftDay(today, 1)),
        ],
        'streak_celebrated_day': iso(yesterday),
      }, yesterday);
      expect((await source.loadStreak()).current, 2);
      expect((await source.loadStreak()).activeDays, {yesterday, today});
      expect(await awards.pendingStreak(), isNotNull);
      await awards.recordNativeActivity({
        'activity_days': [iso(yesterday), iso(today)],
        'streak_celebrated_day': iso(today),
      }, yesterday);
      expect(await awards.pendingStreak(), isNull);
    },
  );
}
