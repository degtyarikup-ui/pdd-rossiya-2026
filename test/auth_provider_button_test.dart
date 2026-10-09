import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/presentation/widgets/auth_provider_button.dart';

void main() {
  testWidgets(
    'all providers retain equal geometry during loading and rebuilds',
    (tester) async {
      var taps = 0;
      Future<void> show({
        bool busy = false,
        bool enabled = true,
        bool dark = false,
      }) => tester.pumpWidget(
        MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final provider in ['apple', 'google', 'yandex'])
                      AuthProviderButton(
                        key: ValueKey(provider),
                        svgAsset: 'assets/icons/auth/$provider.svg',
                        label: provider,
                        busy: busy && provider == 'google',
                        onTap: enabled ? () => taps++ : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await show();
      await tester.pump();
      final sizes = [
        for (final p in ['apple', 'google', 'yandex'])
          tester.getSize(find.byKey(ValueKey(p))),
      ];
      expect(sizes.toSet().length, 1);
      expect(sizes.first, const Size(340, 50));
      final googlePosition = tester.getTopLeft(
        find.byKey(const ValueKey('google')),
      );
      await tester.tap(find.byKey(const ValueKey('google')));
      expect(taps, 1);
      await show(busy: true, enabled: false, dark: true);
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('google'))), sizes.first);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('google'))),
        googlePosition,
      );
      await tester.tap(find.byKey(const ValueKey('google')));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large text wraps without overflow or reducing the tap target', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox(
                width: 280,
                child: AuthProviderButton(
                  svgAsset: 'assets/icons/auth/google.svg',
                  label: 'Продолжить с Google',
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.getSize(find.byType(AuthProviderButton)).height,
      greaterThanOrEqualTo(50),
    );
    expect(tester.takeException(), isNull);
  });
}
