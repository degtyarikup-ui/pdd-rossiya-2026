import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/gen/app_localizations.dart';
import 'package:pdd_app/presentation/screens/tickets/tickets_screen.dart';
import 'package:pdd_app/presentation/screens/topics/topics_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final question = Question(
    id: 'q7',
    question: 'Вопрос',
    ticketNumber: 7,
    answers: const [Answer(text: 'Ответ', isCorrect: true)],
  );
  for (final tickets in [true, false]) {
    final name = tickets ? 'tickets' : 'topics';
    Future<ProgressDataSource> open(
      WidgetTester tester,
      Future<List<Map<String, dynamic>>> Function() load, {
      String language = 'ru',
      double textScale = 1,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final data = ProgressDataSource();
      await data.init();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressDataSourceProvider.overrideWithValue(data),
            if (tickets)
              ticketsProvider.overrideWith((_) => load())
            else
              topicsProvider.overrideWith((_) => load()),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: tickets ? const TicketsScreen() : const TopicsScreen(),
          ),
        ),
      );
      await tester.pump();
      return data;
    }

    final rows = [
      <String, dynamic>{
        'number': 7,
        'name': 'Тема',
        'questions': [question],
      },
    ];
    testWidgets('$name: cloud refresh retains the current scroll position', (
      tester,
    ) async {
      final items = List.generate(
        40,
        (i) => <String, dynamic>{
          'number': i + 1,
          'name': 'Тема ${i + 1}',
          'questions': [question],
        },
      );
      final data = await open(tester, () async => items);
      await tester.pumpAndSettle();
      final scrolling = find.byType(Scrollable).first;
      await tester.drag(scrolling, const Offset(0, -400));
      await tester.pumpAndSettle();
      final before = tester.state<ScrollableState>(scrolling).position.pixels;
      expect(before, greaterThan(100));
      await data.importProgressSnapshot({
        'questionProgressAb': {
          'q7': {'isCorrect': true, 'answeredAt': '2026-10-13T10:00:00Z'},
        },
      });
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrolling).position.pixels,
        closeTo(before, 1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$name: completing a load after disposal is safe', (
      tester,
    ) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      await open(tester, () => pending.future);
      await tester.pumpWidget(const SizedBox());
      pending.complete(rows);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      '$name: loading failure is rendered once without an unhandled refresh error',
      (tester) async {
        await open(tester, () async => throw StateError('load failed'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    for (final lang in ['ru', 'en', 'kk']) {
      testWidgets(
        '$name: $lang fits 320px at double text size and retains question metadata',
        (tester) async {
          await open(tester, () async => rows, language: lang, textScale: 2);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(tickets ? '№7' : 'Тема'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TrainingScreen>(find.byType(TrainingScreen))
                .questions
                .single['ticketNumber'],
            7,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
