import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_notice_widgets.dart';
import 'package:pdd_app/presentation/widgets/premium_motion.dart';
import 'package:url_launcher/url_launcher.dart';

ButtonStyle paywallButtonStyle({
  required Color background,
  required Color foreground,
  Color? disabledBackground,
  Color? disabledForeground,
}) => ElevatedButton.styleFrom(
  backgroundColor: background,
  foregroundColor: foreground,
  disabledBackgroundColor: disabledBackground,
  disabledForegroundColor: disabledForeground,
  minimumSize: const Size(double.infinity, 56),
  padding: const EdgeInsets.all(AppDimensions.spacingL),
  elevation: 0,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
  ),
);

class PaywallNoticeButton extends StatelessWidget {
  const PaywallNoticeButton({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final notifications = RemoteNotificationsService.instance;
    return ValueListenableBuilder<AppNotice?>(
      valueListenable: notifications.paywallButton,
      builder: (context, notice, _) {
        final tap = notice?.tap;
        if (notice == null || tap == null) return const SizedBox.shrink();
        final accent = notice.accent ?? AppColors.white;
        final foreground = notice.accent == null
            ? AppColors.accent
            : accent.computeLuminance() > .179
            ? Colors.black
            : Colors.white;
        final label = notice.buttonText;

        Future<void> open() async {
          unawaited(notifications.recordNoticeEvent(notice.id, 'click'));
          try {
            await launchUrl(
              Uri.parse(tap.url),
              mode: LaunchMode.externalApplication,
            );
          } catch (_) {
            // The configured link may be unavailable on this device.
          }
        }

        Widget button({Widget? image}) {
          if (image == null && label.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: AppDimensions.spacingS),
            child: NoticeViewObserver(
              key: ValueKey('paywall-notice-${notice.id}'),
              onViewed: () =>
                  unawaited(notifications.recordNoticeEvent(notice.id, 'view')),
              child: PremiumPressFeedback(
                enabled: enabled,
                child: ElevatedButton(
                  onPressed: enabled ? open : null,
                  style: paywallButtonStyle(
                    background: accent,
                    foreground: foreground,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (image != null) Flexible(child: image),
                      if (image != null && label.isNotEmpty)
                        const SizedBox(width: AppDimensions.spacingS),
                      if (label.isNotEmpty)
                        Flexible(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        if (notice.imageUrl.isEmpty) return button();
        return Image.network(
          notice.imageUrl,
          width: label.isEmpty ? null : 24,
          height: 24,
          fit: BoxFit.contain,
          semanticLabel: label.isEmpty ? appL10n.noticeOpen : null,
          excludeFromSemantics: label.isNotEmpty,
          frameBuilder: (context, image, frame, _) =>
              button(image: frame == null ? null : image),
          errorBuilder: (context, error, stack) => button(),
        );
      },
    );
  }
}
