import 'package:flutter/material.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/presentation/widgets/premium_benefits_screen.dart';

/// Public entry point retained for all premium gates in the app.
///
/// The benefits now open as a full screen; pricing is a separate modal sheet.
/// The result still signals purchase/restore (true), an Android SBP browser
/// handoff (false), or dismissal (null) to existing callers.
/// [lockedGame] names the Premium-only game the player tapped, so the screen
/// says why it opened.
class PremiumPaywallSheet extends StatelessWidget {
  const PremiumPaywallSheet({super.key, this.lockedGame});

  final String? lockedGame;

  static Future<bool?> show(BuildContext context, {String? lockedGame}) {
    HapticFeedbackHelper.tap();
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        // Keep the staggered content live during the native route transition.
        allowSnapshotting: false,
        builder: (_) => PremiumPaywallSheet(lockedGame: lockedGame),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      PremiumBenefitsScreen(lockedGame: lockedGame);
}
