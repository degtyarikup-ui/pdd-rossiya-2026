import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/presentation/screens/game/godot_web_screen.dart';

void main() {
  for (final mode in ['--regulator', '--crossroads', '--city']) {
    testWidgets('$mode returns its summary with a stationary fade', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Menu')),
        ),
      );
      final route = GodotWebScreen.route(args: [mode]);
      final result = navigator.currentState!.push(route);
      await tester.pumpAndSettle();
      final scene = find.byType(GodotWebScreen);
      final before = tester.getRect(scene);
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 120),
      );

      navigator.currentState!.pop('{"game":"$mode","score":12}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getRect(scene), before);
      expect(
        find.descendant(of: scene, matching: find.byType(SlideTransition)),
        findsNothing,
      );
      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: scene, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, greaterThan(0));
      expect(fade.opacity.value, lessThan(1));
      await tester.pumpAndSettle();
      expect(scene, findsNothing);
      expect(find.text('Menu'), findsOneWidget);
      expect(await result, '{"game":"$mode","score":12}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('system Back closes a mini-game only once', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Menu')),
      ),
    );
    final result = navigator.currentState!.push(
      GodotWebScreen.route(args: ['--crossroads']),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await result, '{"game":"crossroads","runs":[]}');
    expect(find.text('Menu'), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
