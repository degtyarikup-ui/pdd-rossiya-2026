import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/presentation/widgets/app_notice_widgets.dart';

void main() {
  testWidgets('view requires sustained visibility and fires only once', (
    tester,
  ) async {
    var views = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoticeViewObserver(
            onViewed: () => views++,
            child: const SizedBox(width: 300, height: 120),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 750));
    expect(views, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(views, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(views, 1);
  });

  testWidgets('hidden tab, offscreen banner and background app do not count', (
    tester,
  ) async {
    var views = 0;
    Widget page({bool enabled = true, double top = 0}) => MaterialApp(
      home: Scaffold(
        body: TickerMode(
          enabled: enabled,
          child: Stack(
            children: [
              Positioned(
                top: top,
                child: NoticeViewObserver(
                  onViewed: () => views++,
                  child: const SizedBox(width: 300, height: 120),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(page(enabled: false));
    await tester.pump(const Duration(seconds: 2));
    expect(views, 0);
    await tester.pumpWidget(page(top: 2000));
    await tester.pump(const Duration(seconds: 2));
    expect(views, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(page());
    await tester.pump(const Duration(seconds: 2));
    expect(views, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(views, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(views, 1);
  });

  testWidgets('a modal covering the home screen suspends view measurement', (
    tester,
  ) async {
    var views = 0;
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return Scaffold(
              body: NoticeViewObserver(
                onViewed: () => views++,
                child: const SizedBox(width: 300, height: 120),
              ),
            );
          },
        ),
      ),
    );
    showDialog<void>(
      context: pageContext,
      builder: (_) => const AlertDialog(content: Text('Dialog')),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(views, 0);
    Navigator.of(pageContext).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(views, 1);
  });
}
