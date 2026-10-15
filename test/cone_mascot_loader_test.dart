import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/presentation/widgets/cone_mascot_loader.dart';

Widget _host({
  double size = 144,
  bool reducedMotion = false,
  bool tickerEnabled = true,
  String? label,
  Key? captureKey,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: TickerMode(
      enabled: tickerEnabled,
      child: Center(
        child: RepaintBoundary(
          key: captureKey,
          child: ColoredBox(
            color: Colors.white,
            child: ConeMascotLoader(
              key: const ValueKey('cone'),
              size: size,
              semanticsLabel: label,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('paints the complete loop at compact and large sizes', (
    tester,
  ) async {
    for (final size in [72.0, 144.0, 240.0]) {
      await tester.pumpWidget(_host(size: size));
      expect(tester.getSize(find.byType(ConeMascotLoader)), Size.square(size));
      // Exercise the thumb, blink, wink and the exact loop boundary.
      for (final milliseconds in [1800, 850, 1850, 1500, 1]) {
        await tester.pump(Duration(milliseconds: milliseconds));
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion is static and reacts to preference changes', (
    tester,
  ) async {
    await tester.pumpWidget(_host(reducedMotion: true));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 8));
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_host());
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpWidget(_host(reducedMotion: true));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TickerMode stops work while the route is hidden', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(_host(tickerEnabled: false));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(_host());
    expect(tester.binding.transientCallbackCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only animates while the app is resumed', (tester) async {
    await tester.pumpWidget(_host());
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0, reason: '$state');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('announces one caller-supplied loading label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(reducedMotion: true, label: 'Loading'));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    handle.dispose();
  });

  if (const bool.fromEnvironment('CAPTURE_MASCOT')) {
    testWidgets('captures the native vector art for visual review', (
      tester,
    ) async {
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        _host(size: 240, reducedMotion: true, captureKey: captureKey),
      );
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final destination = File('output/mascot/flutter-mascot.png');
          await destination.parent.create(recursive: true);
          await destination.writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    });
  }
}
