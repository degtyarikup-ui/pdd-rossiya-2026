import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/services/notification_service.dart';

Streak _streak({required int current, DateTime? lastActive}) => Streak(
      current: current,
      longest: current,
      lastActiveDate: lastActive,
      startDate: lastActive,
      activeDays: const <DateTime>{},
    );

void main() {
  group('computeStreakReminderTime', () {
    final today = DateTime(2026, 7, 17);
    final yesterday = DateTime(2026, 7, 16);

    test('нет серии → null (нечего терять)', () {
      final now = DateTime(2026, 7, 17, 15);
      expect(computeStreakReminderTime(_streak(current: 0), now), isNull);
    });

    test('серия активна, сегодня НЕ тренировался, до 20:00 → сегодня 20:00', () {
      final now = DateTime(2026, 7, 17, 15);
      final t = computeStreakReminderTime(
        _streak(current: 5, lastActive: yesterday),
        now,
      );
      expect(t, DateTime(2026, 7, 17, 20));
    });

    test('серия активна, сегодня уже тренировался → завтра 20:00', () {
      final now = DateTime(2026, 7, 17, 15);
      final t = computeStreakReminderTime(
        _streak(current: 5, lastActive: today),
        now,
      );
      expect(t, DateTime(2026, 7, 18, 20));
    });

    test('серия активна, НЕ тренировался, но уже позже 20:00 → завтра 20:00', () {
      final now = DateTime(2026, 7, 17, 21, 30);
      final t = computeStreakReminderTime(
        _streak(current: 5, lastActive: yesterday),
        now,
      );
      expect(t, DateTime(2026, 7, 18, 20));
    });

    test('ровно 20:00 и не тренировался → завтра (окно на сегодня закрыто)', () {
      final now = DateTime(2026, 7, 17, 20);
      final t = computeStreakReminderTime(
        _streak(current: 5, lastActive: yesterday),
        now,
      );
      expect(t, DateTime(2026, 7, 18, 20));
    });
  });
}
