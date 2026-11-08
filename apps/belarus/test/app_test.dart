import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_belarus/main.dart';
import 'package:pdd_belarus/domain/question_bank.dart';
import 'fixtures.dart';

void main() {
  testWidgets('shipped bank is BY only and never starts an unreviewed exam', (
    tester,
  ) async {
    final loaded = QuestionBank.fromJson(
      jsonDecode(File('assets/countries/by/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    await tester.pumpWidget(BelarusApp(bankLoader: () async => loaded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    final bank = loaded;
    expect(bank.questions, isEmpty);
    expect(bank.canStartExam, isFalse);
  });
  testWidgets('small screen, dark theme, large accessibility text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });
    final loaded = QuestionBank.fromJson(
      jsonDecode(File('assets/countries/by/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    await tester.pumpWidget(BelarusApp(bankLoader: () async => loaded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('load failure offers a working retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      BelarusApp(
        bankLoader: () async {
          if (++calls == 1) throw const FormatException('Invalid data');
          return QuestionBank.fromJson(
            bankJson()..['reviewStatus'] = 'pending',
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(ElevatedButton), findsOneWidget);
  });
  testWidgets('reviewed fixture opens exam and completes all questions', (
    tester,
  ) async {
    await tester.pumpWidget(
      BelarusApp(bankLoader: () async => QuestionBank.fromJson(bankJson())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.widgetWithText(OutlinedButton, 'A'));
      await tester.pump();
    }
    expect(find.textContaining('10 of 10'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(ElevatedButton), 300);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
