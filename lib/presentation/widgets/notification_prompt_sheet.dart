import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Explicit opt-in shown before the system permission dialog: one consent
/// covers streak reminders and app news (App Store 4.5.4, Russian ad law).
/// Returns `true` when the user chose to enable notifications.
class NotificationPromptSheet extends StatelessWidget {
  const NotificationPromptSheet({super.key});

  static Future<bool> show(BuildContext context) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.of(context).cardBackground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const NotificationPromptSheet(),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active_rounded,
              size: 48,
              color: colors.accent,
            ),
            const SizedBox(height: 16),
            Text(
              appL10n.notificationPromptTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appL10n.notificationPromptBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppDimensions.buttonRadius,
                    ),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(appL10n.notificationPromptEnable),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(appL10n.notificationPromptLater),
            ),
          ],
        ),
      ),
    );
  }
}
