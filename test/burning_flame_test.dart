import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/presentation/widgets/burning_flame.dart';

void main() {
  testWidgets(
    'white flame changes shape, keeps its base and obeys reduced motion',
    (tester) async {
      final key = GlobalKey();
      var reduced = false;
      Widget scene() => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(
                color: AppColors.gold,
                child: BurningFlame(size: 160),
              ),
            ),
          ),
        ),
      );
      Future<Uint8List> pixels({String? file}) async => (await tester.runAsync(
        () async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (file != null) {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File(file).parent.createSync(recursive: true);
            File(file).writeAsBytesSync(png!.buffer.asUint8List());
          }
          image.dispose();
          return bytes!.buffer.asUint8List();
        },
      ))!;

      await tester.pumpWidget(scene());
      final first = await pixels();
      await tester.pump(const Duration(milliseconds: 300));
      final burning = await pixels();
      expect(listEquals(first, burning), isFalse);
      // White base stays anchored while the tips and the inner flame move.
      final base = (146 * 160 + 80) * 4;
      expect(first.sublist(base, base + 4), [255, 255, 255, 255]);
      expect(burning.sublist(base, base + 4), [255, 255, 255, 255]);
      expect(first.sublist(0, 4), [255, 165, 60, 255]);
      expect(tester.binding.hasScheduledFrame, isTrue);

      if (const bool.fromEnvironment('PDD_CAPTURE_STREAK_FIRE')) {
        for (var frame = 0; frame < 48; frame++) {
          await pixels(
            file:
                'output/streak-flame/frames/fire-${frame.toString().padLeft(3, '0')}.png',
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      reduced = true;
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      final frozen = await pixels();
      await tester.pump(const Duration(seconds: 2));
      expect(listEquals(frozen, await pixels()), isTrue);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
