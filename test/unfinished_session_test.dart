import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Незаконченная тренировка: карточка «Продолжить» на главной.
///
/// Правила, которые стерегут тесты:
/// - сессия переживает перезапуск (лежит в SharedPreferences);
/// - сессия из ДРУГОЙ категории билетов не предлагается — там другой набор
///   вопросов, и возвращать в него бессмысленно;
/// - новая тренировка затирает прошлую сама, без отдельной кнопки сброса;
/// - сброс прогресса уносит и сессию.
void main() {
  late ProgressDataSource source;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    source = ProgressDataSource();
    await source.init();
  });

  Future<void> save({
    String title = 'Билет 14',
    List<String> ids = const ['q1', 'q2', 'q3'],
    int index = 1,
    TicketCategory category = TicketCategory.ab,
  }) {
    return source.saveUnfinishedSession(
      title: title,
      questionIds: ids,
      index: index,
      category: category,
    );
  }

  test('сохранённая сессия читается обратно', () async {
    await save();
    final loaded = source.loadUnfinishedSession(TicketCategory.ab);

    expect(loaded, isNotNull);
    expect(loaded!['title'], 'Билет 14');
    expect(loaded['index'], 1);
    expect((loaded['questionIds'] as List).cast<String>(), ['q1', 'q2', 'q3']);
  });

  test('сессия другой категории не предлагается', () async {
    await save(category: TicketCategory.ab);

    expect(source.loadUnfinishedSession(TicketCategory.cd), isNull,
        reason: 'у C/D свой набор вопросов, возвращать в набор A/B нельзя');
    expect(source.loadUnfinishedSession(TicketCategory.ab), isNotNull);
  });

  test('новая тренировка затирает прошлую', () async {
    await save(title: 'Билет 14', ids: ['q1', 'q2'], index: 1);
    await save(title: 'Тема: Знаки', ids: ['s1', 's2', 's3'], index: 0);

    final loaded = source.loadUnfinishedSession(TicketCategory.ab);
    expect(loaded!['title'], 'Тема: Знаки');
    expect(loaded['index'], 0);
  });

  test('очистка убирает сессию', () async {
    await save();
    await source.clearUnfinishedSession();

    expect(source.loadUnfinishedSession(TicketCategory.ab), isNull);
  });

  test('сброс всего прогресса уносит и сессию', () async {
    await save();
    await source.resetAllProgress();

    expect(source.loadUnfinishedSession(TicketCategory.ab), isNull);
  });

  test('битая запись не роняет приложение', () async {
    SharedPreferences.setMockInitialValues({
      'unfinished_session': 'это не JSON',
    });
    final fresh = ProgressDataSource();
    await fresh.init();

    expect(fresh.loadUnfinishedSession(TicketCategory.ab), isNull);
  });

  test('сессия без вопросов не предлагается', () async {
    await save(ids: const []);

    expect(source.loadUnfinishedSession(TicketCategory.ab), isNull,
        reason: 'пустой набор — возвращаться некуда');
  });
}
