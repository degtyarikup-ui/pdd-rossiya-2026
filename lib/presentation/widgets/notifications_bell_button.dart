import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/notification_inbox_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/notifications/notifications_screen.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

/// Колокольчик уведомлений: красная точка, пока есть непрочитанное.
class NotificationsBellButton extends StatelessWidget {
  const NotificationsBellButton({super.key, this.service});

  final NotificationInboxService? service;

  @override
  Widget build(BuildContext context) {
    final inbox = service ?? NotificationInboxService.instance;
    final colors = AppColors.of(context);
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) {
        final unread = inbox.unreadCount;
        void open() {
          HapticFeedbackHelper.tap();
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => NotificationsScreen(service: service),
            ),
          );
        }

        return Semantics(
          button: true,
          onTap: open,
          label: unread > 0
              ? '${appL10n.inboxTitle}, ${appL10n.inboxUnread(unread)}'
              : appL10n.inboxTitle,
          excludeSemantics: true,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AppChromeIconButton(
                icon: unread > 0
                    ? Icons.notifications_rounded
                    : Icons.notifications_none_rounded,
                onTap: open,
              ),
              if (unread > 0)
                Positioned(
                  key: const ValueKey('inbox-unread-badge'),
                  top: 7,
                  right: 7,
                  child: IgnorePointer(
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
                ),
            ],
          ),
        );
      },
    );
  }
}
