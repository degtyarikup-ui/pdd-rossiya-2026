import 'package:flutter/foundation.dart';

/// Снимок состояния серии (стрика) пользователя.
///
/// Серия — количество последовательных календарных дней, в которые
/// пользователь запустил тренировку или игру. Локальные календарные дни.
@immutable
class Streak {
  /// Текущая длина серии (в днях). 0 — серии нет.
  final int current;

  /// Лучшая серия за всё время.
  final int longest;

  /// Дата (без времени) последней активности. null — никогда не тренировался.
  final DateTime? lastActiveDate;

  /// Дата (без времени) старта текущей серии. null — серии нет / никогда
  /// не тренировался. Если серия прервалась — равно дате нового начала
  /// после запуска занятия.
  final DateTime? startDate;

  /// Набор дат (без времени) с активностью за последние ~30 дней.
  /// Используется для отрисовки недельной ленты на главной.
  final Set<DateTime> activeDays;

  const Streak({
    required this.current,
    required this.longest,
    required this.lastActiveDate,
    required this.startDate,
    required this.activeDays,
  });

  factory Streak.empty() => const Streak(
    current: 0,
    longest: 0,
    lastActiveDate: null,
    startDate: null,
    activeDays: <DateTime>{},
  );

  /// Проверка, есть ли активность на указанную дату (учитывается только день).
  bool isActiveOn(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return activeDays.contains(d);
  }

  static DateTime day(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  static DateTime shiftDay(DateTime date, int count) =>
      DateTime(date.year, date.month, date.day + count);
  static int dayDistance(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  /// Pure projection used by the embedded engine before its launch is confirmed.
  Streak withActivity(DateTime date) {
    final today = day(date);
    final last = lastActiveDate;
    if (last != null && !today.isAfter(last)) return this;
    final consecutive = last != null && dayDistance(last, today) == 1;
    final next = consecutive ? current + 1 : 1;
    return Streak(
      current: next,
      longest: next > longest ? next : longest,
      lastActiveDate: today,
      startDate: consecutive ? startDate : today,
      activeDays: {...activeDays, today},
    );
  }

  /// 7 дней, начиная с дня старта серии (или продолжения за пределами
  /// первой недели — окно сдвигается по 7 дней).
  ///
  /// Если серии нет — возвращается календарная неделя начиная с понедельника
  /// (для отрисовки пустого состояния).
  List<DateTime> weekStripDays({required DateTime today}) {
    final base = DateTime(today.year, today.month, today.day);
    final start = startDate;
    if (start == null) {
      // Серии нет — показываем календарную неделю (Пн–Вс) текущей недели.
      final monday = shiftDay(base, 1 - base.weekday);
      return List.generate(7, (i) => shiftDay(monday, i));
    }

    // Сколько дней прошло с начала серии (включая сегодня = 1).
    final daysFromStart = dayDistance(start, base);
    // Какая по счёту 7-дневная «неделя» серии: 0 = первая, 1 = вторая, и т.д.
    final weekIndex = daysFromStart >= 0 ? daysFromStart ~/ 7 : 0;
    final weekStart = shiftDay(start, weekIndex * 7);
    return List.generate(7, (i) => shiftDay(weekStart, i));
  }
}
