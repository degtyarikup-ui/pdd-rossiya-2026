import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/presentation/widgets/app_loading_indicator.dart';
import 'package:pdd_app/presentation/widgets/app_startup_gate.dart';

void main() {
  testWidgets('renders loading before initialization and mounts the app once', (
    tester,
  ) async {
    final ready = Completer<Widget>();
    var calls = 0;
    await tester.pumpWidget(
      AppStartupGate(
        initialize: () {
          expect(find.byType(AppLoadingIndicator), findsOneWidget);
          calls++;
          return ready.future;
        },
      ),
    );
    expect(find.byType(AppLoadingIndicator), findsOneWidget);
    // Real asset IO runs outside the fake widget clock. This also checks that
    // bootstrap waits for a presentable poster, rather than an arbitrary delay.
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage(AppLoadingIndicator.posterAsset),
        tester.element(find.byType(AppLoadingIndicator)),
      );
    });
    await tester.pump();
    await tester.pump();
    expect(calls, 1);
    ready.complete(
      const MaterialApp(home: Scaffold(body: Text('Application ready'))),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Application ready'), findsOneWidget);
    expect(find.byType(AppLoadingIndicator), findsNothing);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late initialization never mounts after disposal', (
    tester,
  ) async {
    final ready = Completer<Widget>();
    await tester.pumpWidget(AppStartupGate(initialize: () => ready.future));
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage(AppLoadingIndicator.posterAsset),
        tester.element(find.byType(AppLoadingIndicator)),
      );
    });
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    ready.complete(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
