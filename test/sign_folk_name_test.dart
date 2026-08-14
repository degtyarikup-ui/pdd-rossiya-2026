import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/signs/sign_detail_screen.dart';

import 'package:flutter/services.dart' show rootBundle;

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('народное название показано и подписано как народное', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SignDetailScreen(
          signNumber: '3.1',
          signName: 'Въезд запрещён',
          signFolkName: 'кирпич',
        ),
      ),
    );

    // Само слово видно — ради него всё и затевалось.
    expect(find.text('«кирпич»'), findsOneWidget);
    // И рядом обязательно подпись: иначе человек решит, что это официальное
    // название, и назовёт его так на экзамене.
    expect(find.text(appL10n.folkNameLabel), findsOneWidget);
    // Официальное название при этом никуда не делось.
    expect(find.text('Въезд запрещён'), findsOneWidget);
  });

  testWidgets('без народного названия плашки нет вовсе', (tester) async {
    await tester.pumpWidget(
      wrap(
        const SignDetailScreen(
          signNumber: '3.24',
          signName: 'Ограничение максимальной скорости',
        ),
      ),
    );

    expect(find.text(appL10n.folkNameLabel), findsNothing);
  });

  testWidgets('пустая строка не создаёт пустую плашку', (tester) async {
    await tester.pumpWidget(
      wrap(
        const SignDetailScreen(
          signNumber: '3.24',
          signName: 'Ограничение максимальной скорости',
          signFolkName: '   ',
        ),
      ),
    );

    expect(find.text(appL10n.folkNameLabel), findsNothing);
  });

  test('все народные названия ссылаются на существующие знаки', () async {
    final raw = await rootBundle.loadString(
      'assets/countries/ru/questions/signs.json',
    );
    final data = json.decode(raw) as Map<String, dynamic>;

    final withFolk = <String, String>{};
    for (final signs in data.values) {
      (signs as Map<String, dynamic>).forEach((number, sign) {
        final folk = (sign as Map<String, dynamic>)['folkName'] as String?;
        if (folk != null && folk.trim().isNotEmpty) withFolk[number] = folk;
      });
    }

    // Скрипт add_folk_names.py падает, если знак не найден, но данные могут
    // пересобраться из источника без него — тогда названия молча пропадут.
    expect(
      withFolk.length,
      greaterThanOrEqualTo(10),
      reason: 'народные названия потерялись при пересборке signs.json — '
          'перезапустите tools/ru_content/add_folk_names.py',
    );
    expect(withFolk['3.1'], 'кирпич');
    expect(withFolk['1.17'], 'лежачий полицейский');
  });
}
