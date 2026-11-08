import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/presentation/widgets/premium_motion.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    required VoidCallback onTap,
    bool enabled = true,
    bool reducedMotion = false,
  }) => tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: Scaffold(
        body: GestureDetector(
          onVerticalDragUpdate: (_) {},
          child: Center(
            child: PremiumPressFeedback(
              enabled: enabled,
              child: SizedBox(
                width: 240,
                height: 64,
                child: TextButton(
                  onPressed: enabled ? onTap : null,
                  child: const Text('Continue'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  double scale(WidgetTester tester) => tester
      .widget<Transform>(
        find
            .descendant(
              of: find.byType(PremiumPressFeedback),
              matching: find.byType(Transform),
            )
            .first,
      )
      .transform
      .storage[0];

  testWidgets('press feedback preserves the original single tap action', (
    tester,
  ) async {
    var taps = 0;
    await mount(tester, onTap: () => taps++);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scale(tester), closeTo(.98, .001));
    expect(taps, 0);
    await gesture.up();
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(scale(tester), 1);
  });

  testWidgets('scrolling releases the press and does not tap the button', (
    tester,
  ) async {
    var taps = 0;
    await mount(tester, onTap: () => taps++);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scale(tester), lessThan(1));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(scale(tester), 1);
    await gesture.up();
    expect(taps, 0);
  });

  testWidgets('disabled and reduced motion buttons stay still', (tester) async {
    var taps = 0;
    await mount(tester, onTap: () => taps++, enabled: false);
    var gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(scale(tester), 1);
    await gesture.up();
    expect(taps, 0);
    await mount(tester, onTap: () => taps++, reducedMotion: true);
    gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(scale(tester), 1);
    await gesture.up();
    expect(taps, 1);
    await tester.pumpAndSettle();
  });
}
