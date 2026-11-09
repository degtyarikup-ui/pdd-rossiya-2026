import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_belarus/domain/question_bank.dart';
import 'package:pdd_belarus/main.dart';
import 'fixtures.dart';

class PreviewAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('.png')) {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3X8AAAAASUVORK5CYII=',
      );
      return ByteData.sublistView(bytes);
    }
    return rootBundle.load(key);
  }
}

void main() {
  test('preview never enables exam, even with approved flags', () {
    final bank = QuestionBank.fromJson(bankJson()..['previewOnly'] = true);
    expect(bank.canStartExam, isFalse);
    expect(bank.newExam, throwsStateError);
  });

  test('foreign, network and escaping images are rejected', () {
    for (final image in [
      'assets/countries/ru/a.png',
      '../a.jpg',
      'https://pdd.by/a.jpg',
    ]) {
      final data = bankJson();
      (data['questions'] as List).first['imageAssets'] = [image];
      expect(() => QuestionBank.fromJson(data), throwsFormatException);
    }
  });

  testWidgets(
    'pending preview shows local image, reveals answer and resets on next',
    (tester) async {
      final data = bankJson()
        ..['previewOnly'] = true
        ..['reviewStatus'] = 'pending';
      final questions = data['questions'] as List;
      questions.first['imageAssets'] = [
        'assets/countries/by/preview_${'a' * 64}.png',
      ];
      final bank = QuestionBank.fromJson(data);
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: PreviewAssets(),
          child: BelarusApp(bankLoader: () async => bank),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Browse questions'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Show answer'), 200);
      await tester.tap(find.text('Show answer'));
      await tester.pumpAndSettle();
      expect(find.text('Correct answer: A'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Next'), 200);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Correct answer: A'), findsNothing);
      expect(find.text('2 of 15'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
