import 'package:flutter/foundation.dart';

/// Снимок состояния серии (стрика) пользователя.
///
/// Серия — количество последовательных календарных дней, в которые
/// пользователь ответил хотя бы на один вопрос. Локальное время устройства.
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
  /// после ответа.
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
      final monday = base.subtract(Duration(days: base.weekday - 1));
      return List.generate(7, (i) => monday.add(Duration(days: i)));
    }

    // Сколько дней прошло с начала серии (включая сегодня = 1).
    final daysFromStart = base.difference(start).inDays;
    // Какая по счёту 7-дневная «неделя» серии: 0 = первая, 1 = вторая, и т.д.
    final weekIndex = daysFromStart >= 0 ? daysFromStart ~/ 7 : 0;
    final weekStart = start.add(Duration(days: weekIndex * 7));
    return List.generate(7, (i) => weekStart.add(Duration(days: i)));
  }
}
