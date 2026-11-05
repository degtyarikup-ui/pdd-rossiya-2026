import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/exam_hero_card.dart';

/// Отступ вокруг карточки на снимке: чтобы увидеть то, что карточка обрезала бы.
const double _overscan = 120;

/// Слабое свечение может заходить под текст, сама картинка — нет.
const int _solidAlpha = 60;

const ValueKey<String> _cardKey = ValueKey('card');
final Finder _artFinder = find.byKey(const ValueKey('exam-hero-art'));

Future<void> _loadOnest(WidgetTester tester) => tester.runAsync(() async {
  final loader = FontLoader('Onest');
  for (final file in Directory('assets/fonts').listSync().whereType<File>()) {
    if (file.path.endsWith('.ttf')) {
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
  }
  await loader.load();
});

Future<void> _pumpCard(
  WidgetTester tester, {
  required String locale,
  required double textScale,
  required Size size,
}) {
  final l10n = lookupAppLocalizations(Locale(locale));
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Onest'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            child: ExamHeroCard(
              key: _cardKey,
              height: size.height,
              onTap: () {},
              questionsBadge: l10n.examQuestionsBadge(20),
              timeBadge: l10n.examMinutesBadge(20),
              categoryBadge: 'A/B',
              forcedConcept: ExamCardConcept.license,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Непрозрачные точки картинки в координатах карточки.
Future<List<Offset>> _solidPixels(
  WidgetTester tester,
  ExamCardConcept concept,
  Size card,
  Rect art,
) async {
  final boundary = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: card.width + _overscan * 2,
            height: card.height + _overscan * 2,
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: art.shift(const Offset(_overscan, _overscan)),
                  child: ExamHeroArtwork(concept: concept),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => render.toImage()))!;
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final pixels = <Offset>[];
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (bytes.getUint8((y * image.width + x) * 4 + 3) >= _solidAlpha) {
        pixels.add(Offset(x - _overscan, y - _overscan));
      }
    }
  }
  image.dispose();
  return pixels;
}

void main() {
  testWidgets(
    'exam artwork stays clear of the text and card edges on every screen',
    (tester) async {
      await _loadOnest(tester);
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => updateAppLocale(const Locale('ru')));

      for (final locale in const ['ru', 'en', 'kk']) {
        updateAppLocale(Locale(locale));
        for (final textScale in const [1.0, 1.3]) {
          for (final width in const [288.0, 343.0, 358.0, 430.0, 720.0]) {
            for (final height in const [130.0, 146.0, 220.0]) {
              final card = Size(width, height);
              await _pumpCard(
                tester,
                locale: locale,
                textScale: textScale,
                size: card,
              );
              await tester.pump();

              final origin = tester.getTopLeft(find.byKey(_cardKey));
              final art = tester.getRect(_artFinder).shift(-origin);
              final texts = find
                  .descendant(
                    of: find.byKey(_cardKey),
                    matching: find.byType(Text),
                  )
                  .evaluate()
                  .map(
                    (element) => tester
                        .getRect(find.byWidget(element.widget))
                        .shift(-origin)
                        .inflate(2),
                  )
                  .map(
                    (rect) => Rect.fromLTRB(
                      rect.left,
                      rect.top,
                      rect.right.clamp(0, width - 16),
                      rect.bottom,
                    ),
                  )
                  .toList();

              for (final concept in ExamCardConcept.values) {
                final pixels = await _solidPixels(tester, concept, card, art);
                final context =
                    '${concept.name}, $locale, x$textScale, '
                    '${width.toInt()}×${height.toInt()}';
                expect(pixels, isNotEmpty, reason: context);

                for (final text in texts) {
                  expect(
                    pixels.where(text.contains),
                    isEmpty,
                    reason: 'covers text $text: $context',
                  );
                }

                // Дорога намеренно уходит за края карточки.
                if (concept == ExamCardConcept.overpass) continue;
                final inside = Rect.fromLTWH(0, 0, width, height).deflate(3);
                expect(
                  pixels.where((pixel) => !inside.contains(pixel)),
                  isEmpty,
                  reason: 'touches the card edge: $context',
                );
              }
            }
          }
        }
      }
    },
  );
}
