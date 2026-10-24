import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';
import 'package:pdd_app/l10n/gen/app_localizations.dart';
import 'package:pdd_app/presentation/screens/signs/markup_category_screen.dart';
import 'package:pdd_app/presentation/screens/signs/signs_screen.dart';

const _questions = 'assets/countries/ru/questions';
const _images = 'assets/countries/ru/images/markup';

Map<String, dynamic> readMap(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final reference = readMap('tools/ru_content/official_markup.json');
  final official = (reference['entries'] as Map).cast<String, dynamic>();

  for (final lang in ['ru', 'en', 'kk']) {
    test(
      'Every official marking loads with number, image and text in $lang',
      () async {
        final source = QuestionsDataSource();
        final data = await source.loadMarkup(lang);
        expect(data.values.map((g) => g.length), [39, 9]);
        final entries = data.values.expand((g) => g).toList();
        expect(entries.map((s) => s['number']).toSet(), official.keys.toSet());
        expect(entries.length, 48);
        for (final entry in entries) {
          final number = entry['number']!;
          expect(entry['title']!.trim(), isNotEmpty);
          expect(entry['description']!.trim(), isNotEmpty);
          final filename = entry['image']!.split('/').last;
          expect(filename, official[number]['image']);
          expect(File('$_images/$filename').existsSync(), isTrue);
          if (lang == 'ru') {
            final def = official[number];
            expect(
              entry['description'],
              [def['definition'], ...def['rules'] as List].join('\n\n'),
            );
          }
        }
        for (final group in [
          ['1.14.1', '1.14.2', '1.14.3'],
          ['1.16.1', '1.16.2', '1.16.3'],
          ['1.17.1', '1.17.2'],
          ['1.24.1', '1.24.2', '1.24.3'],
          ['2.1.1', '2.1.2', '2.1.3'],
        ]) {
          expect(
            entries
                .where((e) => group.contains(e['number']))
                .map((e) => e['image'])
                .toSet()
                .length,
            group.length,
          );
        }
      },
    );
  }

  test('All 48 marking vectors decode and render in Flutter', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xffeeeeee), ui.BlendMode.src);
    var i = 0;
    for (final entry in official.entries) {
      final svg = File('$_images/${entry.value['image']}').readAsStringSync();
      final picture = await vg.loadPicture(SvgStringLoader(svg), null);
      expect(picture.size.isEmpty, isFalse, reason: entry.key);
      canvas.save();
      canvas.translate((i % 6) * 200.0 + 10, (i ~/ 6) * 140.0 + 25);
      final scale = (180 / picture.size.width).clamp(
        0.0,
        100 / picture.size.height,
      );
      canvas.scale(scale);
      canvas.drawPicture(picture.picture);
      canvas.restore();
      picture.picture.dispose();
      i++;
    }
    final contact = recorder.endRecording();
    if (Platform.environment['MARKUP_CATALOG_PREVIEW'] == '1') {
      final image = await contact.toImage(1200, 8 * 140);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('scratch/official-markings')
        ..createSync(recursive: true);
      File('${dir.path}/flutter-preview.png').writeAsBytesSync(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      image.dispose();
    }
    contact.dispose();
  });

  for (final lang in ['ru', 'en', 'kk']) {
    for (final size in [const Size(360, 740), const Size(740, 360)]) {
      testWidgets('Number search opens marking card and zoom: $lang $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final suffix = lang == 'ru' ? '' : '_$lang';
        final raw = readMap('$_questions/markup$suffix.json');
        final data = raw.map(
          (k, v) => MapEntry(
            k,
            (v as List).map((e) => (e as Map).cast<String, String>()).toList(),
          ),
        );
        final horizontal = data.keys.first;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              signsProvider.overrideWith((ref) async => <String, dynamic>{}),
              markupProvider.overrideWith((ref) async => data),
            ],
            child: MaterialApp(
              locale: Locale(lang),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const SignsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '1.17.2');
        await tester.pumpAndSettle();
        await tester.tap(find.text(horizontal));
        await tester.pumpAndSettle();
        expect(find.byType(MarkupCategoryScreen), findsOneWidget);
        expect(find.text('1.17.2'), findsOneWidget);
        final image = find.byKey(const ValueKey('markup-image-1.17.2'));
        await tester.ensureVisible(image);
        await tester.tap(image);
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
