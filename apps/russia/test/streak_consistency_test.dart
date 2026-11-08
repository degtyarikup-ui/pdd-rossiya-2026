import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Серия считается по дням с занятиями: число не может разойтись с лентой.
void main() {
  String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final today = DateTime.now();
  DateTime ago(int n) =>
      DateTime(today.year, today.month, today.day).subtract(Duration(days: n));

  test('счётчик больше реального ряда — исправляется по дням', () async {
    // Сервер принёс «11», а вчера занятий не было: серия — только сегодня.
    SharedPreferences.setMockInitialValues({
      'streak_current': 11,
      'streak_longest': 11,
      'streak_last_active': iso(ago(0)),
      'streak_start_date': iso(ago(10)),
      'streak_active_days': [
        for (var i = 2; i <= 10; i++) iso(ago(i)),
        iso(ago(0)),
      ],
    });
    final ds = ProgressDataSource();
    await ds.init();
    final s = await ds.loadStreak();
    expect(s.current, 1);
    expect(s.longest, 11);
    // Исправленное значение сохранено: завтра серия продолжится с 1, а не с 11.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('streak_current'), 1);
  });

  test('непрерывный ряд не трогается', () async {
    SharedPreferences.setMockInitialValues({
      'streak_current': 5,
      'streak_longest': 8,
      'streak_last_active': iso(ago(0)),
      'streak_active_days': [for (var i = 0; i < 5; i++) iso(ago(i))],
    });
    final ds = ProgressDataSource();
    await ds.init();
    expect((await ds.loadStreak()).current, 5);
  });

  test('серия длиннее хранимых 30 дней — верим счётчику', () async {
    SharedPreferences.setMockInitialValues({
      'streak_current': 45,
      'streak_longest': 45,
      'streak_last_active': iso(ago(0)),
      'streak_active_days': [for (var i = 0; i < 30; i++) iso(ago(i))],
    });
    final ds = ProgressDataSource();
    await ds.init();
    expect((await ds.loadStreak()).current, 45);
  });
}
