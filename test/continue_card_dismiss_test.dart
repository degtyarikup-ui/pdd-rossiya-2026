import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/presentation/widgets/continue_session_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Скрытие карточки «Продолжить».
///
/// Проверяем не картинку, а порядок: карточка должна уехать анимацией ДО
/// того, как тронуто хранилище. При обратном порядке (так было раньше) экран
/// сперва перечитывал данные, и карточка пропадала рывком.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProgressDataSource> pumpCard(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final data = ProgressDataSource();
    await data.init();
    await data.saveUnfinishedSession(
      title: 'Билет 1',
      questionIds: const ['a', 'b', 'c'],
      index: 1,
      category: TicketCategory.ab,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [progressDataSourceProvider.overrideWithValue(data)],
        child: MaterialApp(
          home: Scaffold(
            body: ContinueSessionCard(
              session: const {
                'kind': 'training',
                'title': 'Билет 1',
                'questions': <Map<String, dynamic>>[],
                'index': 1,
                'total': 20,
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return data;
  }

  testWidgets('карточка уезжает анимацией, а не пропадает рывком',
      (tester) async {
    final data = await pumpCard(tester);

    expect(find.text('Продолжить'), findsOneWidget);
    final fullHeight = tester.getSize(find.byType(SizeTransition)).height;
    expect(fullHeight, greaterThan(0));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    // На середине анимации карточка уже ниже, но ещё на экране.
    await tester.pump(const Duration(milliseconds: 130));
    final midHeight = tester.getSize(find.byType(SizeTransition)).height;
    expect(midHeight, lessThan(fullHeight));
    expect(midHeight, greaterThan(0));

    // И главное: пока карточка уезжает, хранилище не тронуто. Чистка после
    // анимации — иначе перечитывание данных дёргает экран прямо под ней.
    expect(
      data.loadUnfinishedSession(TicketCategory.ab),
      isNotNull,
      reason: 'чистка до анимации — это и есть тот самый рывок',
    );

    await tester.pumpAndSettle();
    expect(data.loadUnfinishedSession(TicketCategory.ab), isNull);
  });

  testWidgets('свёрнутая карточка не занимает места', (tester) async {
    await pumpCard(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Отступ снизу живёт внутри анимируемой части, поэтому после схлопывания
    // не остаётся пустой полосы.
    expect(tester.getSize(find.byType(SizeTransition)).height, 0);
  });
}
