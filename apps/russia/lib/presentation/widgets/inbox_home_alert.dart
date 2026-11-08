import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/notification_inbox_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/notifications/notifications_screen.dart';

/// Плашка на главной: пока человека не было, пришло уведомление. Нажатие
/// открывает список уведомлений, крестик скрывает плашку до следующего.
class InboxHomeAlert extends StatelessWidget {
  const InboxHomeAlert({super.key, required this.service});

  static const double height = 56;

  final NotificationInboxService service;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final count = service.homeAlertCount;
    return SizedBox(
      height: height,
      child: Material(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedbackHelper.tap();
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => NotificationsScreen(service: service),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(left: AppDimensions.spacingS),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.notifications_rounded,
                        color: colors.accent,
                        size: 20,
                      ),
                    ),
                    Positioned(
                      top: 1,
                      right: 1,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.cardBackground,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppDimensions.spacingM),
                Expanded(
                  child: Text(
                    appL10n.inboxHomeAlert(count),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.secondaryText),
                IconButton(
                  tooltip: appL10n.close,
                  onPressed: () {
                    HapticFeedbackHelper.tap();
                    service.dismissHomeAlert();
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
