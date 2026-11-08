import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/data/services/app_update_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

class AppUpdateDialog extends StatelessWidget {
  final AppUpdateOffer offer;
  const AppUpdateDialog({super.key, required this.offer});

  static Future<bool> show(BuildContext context, AppUpdateOffer offer) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AppUpdateDialog(offer: offer),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AlertDialog(
      scrollable: true,
      backgroundColor: colors.cardBackground,
      icon: Icon(Icons.system_update_rounded, color: colors.accent, size: 32),
      title: Text(
        offer.readyToInstall
            ? appL10n.appUpdateReadyTitle
            : appL10n.appUpdateTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (offer.version.isNotEmpty) ...[
            Text(
              appL10n.appUpdateVersion(offer.version),
              style: TextStyle(color: colors.secondaryText),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            offer.readyToInstall
                ? appL10n.appUpdateReadyBody
                : offer.notes.isNotEmpty
                ? offer.notes
                : appL10n.appUpdateBody,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(appL10n.appUpdateLater),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            offer.readyToInstall
                ? appL10n.appUpdateRestart
                : appL10n.appUpdateAction,
          ),
        ),
      ],
    );
  }
}
