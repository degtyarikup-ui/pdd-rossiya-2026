import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/presentation/widgets/pending_payment_recovery.dart';

void main() {
  testWidgets('Home and game share check and wait for celebration dismissal', (
    tester,
  ) async {
    final check = Completer<String?>();
    var checks = 0;
    var celebrations = 0;
    var firstDone = false;
    var secondDone = false;
    late BuildContext caller;
    late StateSetter update;
    var showCaller = true;
    final recovery = PendingPaymentRecovery(
      checkPayment: () {
        checks++;
        return checks == 1 ? check.future : Future.value('pending');
      },
      celebrate: (context) async {
        celebrations++;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Premium confirmed'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: showCaller
                  ? Builder(
                      builder: (context) {
                        caller = context;
                        return const Text('Home');
                      },
                    )
                  : const Text('Game'),
            );
          },
        ),
      ),
    );
    final first = recovery.recover(caller).then((_) => firstDone = true);
    final second = recovery.recover(caller).then((_) => secondDone = true);
    expect(checks, 1);
    update(() => showCaller = false);
    await tester.pump();
    expect(caller.mounted, isFalse);
    check.complete('confirmed');
    await tester.pumpAndSettle();
    expect(find.text('Premium confirmed'), findsOneWidget);
    expect(celebrations, 1);
    expect(firstDone, isFalse);
    expect(secondDone, isFalse);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await Future.wait([first, second]);
    expect(firstDone && secondDone, isTrue);
    await recovery.recover(tester.element(find.text('Game')));
    expect(checks, 2, reason: 'Only in-flight checks coalesce');
    expect(celebrations, 1);
  });

  testWidgets('cancellation is shown once for concurrent callers', (
    tester,
  ) async {
    final check = Completer<String?>();
    var canceled = 0;
    final recovery = PendingPaymentRecovery(
      checkPayment: () => check.future,
      canceled: (_) => canceled++,
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Home'))),
    );
    final context = tester.element(find.text('Home'));
    final first = recovery.recover(context);
    final second = recovery.recover(context);
    check.complete('canceled');
    await tester.pump();
    await Future.wait([first, second]);
    expect(canceled, 1);
  });

  testWidgets('external browser is never covered before foreground return', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var returned = false;
    final wait = PendingPaymentRecovery.waitForForeground().then(
      (_) => returned = true,
    );
    // launchUrl can complete before this lifecycle handover reaches Flutter.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(returned, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await wait;
    expect(returned, isTrue);
  });

  testWidgets('already-returned external checkout does not leave a waiter', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final wait = PendingPaymentRecovery.waitForForeground();
    await tester.pump(const Duration(milliseconds: 500));
    await wait;
  });
}
