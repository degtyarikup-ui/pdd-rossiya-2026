import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/presentation/widgets/app_loading_indicator.dart';

Widget _host({
  bool reducedMotion = false,
  bool tickerEnabled = true,
  String label = 'Preparing lesson',
  double size = 160,
}) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: TickerMode(
      enabled: tickerEnabled,
      child: Center(
        child: AppLoadingIndicator(size: size, label: label),
      ),
    ),
  ),
);

Finder _asset(String asset) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == asset,
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'uses the approved 384 px 30 fps asset inside a fixed image area',
    (tester) async {
      await tester.pumpWidget(_host(size: 120));
      expect(_asset(AppLoadingIndicator.animationAsset), findsOneWidget);
      expect(
        AppLoadingIndicator.animationAsset,
        'assets/mascot/raster/cone-juggling-384-30.webp',
      );
      final imageArea = find
          .ancestor(
            of: _asset(AppLoadingIndicator.animationAsset),
            matching: find.byType(SizedBox),
          )
          .first;
      expect(tester.getSize(imageArea), const Size.square(120));
      expect(find.text('Preparing lesson'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion uses the static poster and responds to changes', (
    tester,
  ) async {
    await tester.pumpWidget(_host(reducedMotion: true));
    expect(_asset(AppLoadingIndicator.animationAsset), findsNothing);
    expect(_asset(AppLoadingIndicator.posterAsset), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(_asset(AppLoadingIndicator.animationAsset), findsNothing);

    await tester.pumpWidget(_host());
    expect(_asset(AppLoadingIndicator.animationAsset), findsOneWidget);
    await tester.pumpWidget(_host(reducedMotion: true));
    expect(_asset(AppLoadingIndicator.animationAsset), findsNothing);
    expect(_asset(AppLoadingIndicator.posterAsset), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden tickers replace the animation with the static poster', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    expect(_asset(AppLoadingIndicator.animationAsset), findsOneWidget);
    await tester.pumpWidget(_host(tickerEnabled: false));
    expect(_asset(AppLoadingIndicator.animationAsset), findsNothing);
    expect(_asset(AppLoadingIndicator.posterAsset), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(_host());
    expect(_asset(AppLoadingIndicator.animationAsset), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('background lifecycle states stop the animated asset', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      // Hidden/paused bindings stop scheduling UI frames. Inspect the observer's
      // next build explicitly rather than expecting a hidden window to repaint.
      tester.binding.scheduleForcedFrame();
      await tester.pump();
      expect(
        _asset(AppLoadingIndicator.animationAsset),
        findsNothing,
        reason: '$state',
      );
      expect(_asset(AppLoadingIndicator.posterAsset), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_asset(AppLoadingIndicator.animationAsset), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('announces its loading label once without image semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(reducedMotion: true));
    expect(find.bySemanticsLabel('Preparing lesson'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('Preparing lesson'));
    expect(node.getSemanticsData().label, 'Preparing lesson');
    expect(node.childrenCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('loading overlay shields input and can be closed twice safely', (
    tester,
  ) async {
    var taps = 0;
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) {
            pageContext = context;
            return Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Underlying action'),
                ),
              ),
            );
          },
        ),
      ),
    );
    final actionPoint = tester.getCenter(find.text('Underlying action'));
    final overlay = AppLoadingOverlay.show(pageContext, label: 'Loading game');
    await tester.pump();
    await tester.tapAt(actionPoint);
    await tester.pump();
    expect(taps, 0);
    expect(find.text('Loading game'), findsOneWidget);
    overlay.close();
    overlay.close();
    await tester.pump();
    await tester.tapAt(actionPoint);
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
