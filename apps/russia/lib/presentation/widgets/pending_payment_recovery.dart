import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:pdd_app/presentation/widgets/premium_celebration_screen.dart';

/// One pending-order check and its result UI, shared by Home and a paused game.
/// The future includes dismissal of the celebration, so native game windows
/// cannot cover it when returning from an external checkout.
class PendingPaymentRecovery {
  PendingPaymentRecovery({
    Future<String?> Function()? checkPayment,
    Future<void> Function(BuildContext)? celebrate,
    void Function(BuildContext)? canceled,
    void Function(BuildContext)? unreachable,
  }) : _unreachable = unreachable ?? _showUnreachable,
       _checkPayment =
           checkPayment ?? PremiumService.instance.checkPendingPayment,
       _celebrate = celebrate ?? _showCelebration,
       _canceled = canceled ?? _showCanceled;

  static final instance = PendingPaymentRecovery();

  final Future<String?> Function() _checkPayment;
  final Future<void> Function(BuildContext) _celebrate;
  final void Function(BuildContext) _canceled;
  final void Function(BuildContext) _unreachable;
  bool _unreachableShown = false;
  Future<void>? _inFlight;
  BuildContext? _presentationContext;
  BuildContext? _callerContext;

  Future<void> recover(BuildContext context) {
    if (!context.mounted) return Future<void>.value();
    final navigator = Navigator.of(context, rootNavigator: true);
    // The launching Home route may disappear while the order is checked. Its
    // root overlay lives through that navigation; a later caller can replace it.
    _callerContext = context;
    _presentationContext = navigator.overlay?.context ?? navigator.context;
    return _inFlight ??= _recover().whenComplete(() {
      _inFlight = null;
      _presentationContext = null;
      _callerContext = null;
    });
  }

  Future<void> _recover() async {
    final status = await _checkPayment();
    final caller = _callerContext;
    final context = caller != null && caller.mounted
        ? caller
        : _presentationContext;
    if (context == null || !context.mounted) return;
    if (status == 'confirmed') {
      await _celebrate(context);
    } else if (status == 'canceled') {
      _canceled(context);
    } else if (status == PremiumService.pendingPaymentUnreachable &&
        !_unreachableShown) {
      // Once per launch: the check repeats on every return to the app.
      _unreachableShown = true;
      _unreachable(context);
    }
  }

  static void _showUnreachable(BuildContext context) =>
      AppToast.show(context, appL10n.webPayCheckUnreachable);

  static Future<void> _showCelebration(BuildContext context) =>
      PremiumCelebrationScreen.show(
        context,
        reason: PremiumCelebrationReason.purchased,
        expiresAt: PremiumService.instance.expiresAt,
      );

  static void _showCanceled(BuildContext context) =>
      AppToast.show(context, appL10n.webPayCanceled);

  /// `launchUrl` may finish just before Android delivers its background event.
  /// Observe that handover instead of bringing the game over the browser. The
  /// short settle period only handles an already-completed/no-background trip;
  /// an actual background waits for resumed without a payment timeout.
  static Future<void> waitForForeground() async {
    final waiter = _PaymentForegroundWaiter();
    await waiter.wait();
  }
}

class _PaymentForegroundWaiter with WidgetsBindingObserver {
  final _returned = Completer<void>();
  Timer? _settle;

  Future<void> wait() async {
    WidgetsBinding.instance.addObserver(this);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
        WidgetsBinding.instance.lifecycleState == null) {
      _settle = Timer(const Duration(milliseconds: 500), () {
        if (!_returned.isCompleted) _returned.complete();
      });
    }
    try {
      await _returned.future;
    } finally {
      _settle?.cancel();
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _settle?.cancel();
    if (state == AppLifecycleState.resumed && !_returned.isCompleted) {
      _returned.complete();
    }
  }
}
