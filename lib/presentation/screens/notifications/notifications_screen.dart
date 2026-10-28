import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/layout/app_content_frame.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/app_update_service.dart';
import 'package:pdd_app/data/services/notification_inbox_service.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';

/// Новости приложения и сообщения о подписке. Открытие экрана отмечает всё
/// прочитанным; новые записи этого захода выделены точкой.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.service});

  final NotificationInboxService? service;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  NotificationInboxService get _service =>
      widget.service ?? NotificationInboxService.instance;

  /// Unread when the screen opened: stays highlighted until it is closed.
  late final Set<String> _fresh = {
    for (final item in _service.items)
      if (!_service.isRead(item.id)) item.id,
  };

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    unawaited(_service.refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_service.markAllRead());
    });
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // Entries that arrive while the screen is open are new too.
    for (final item in _service.items) {
      if (!_service.isRead(item.id)) _fresh.add(item.id);
    }
    setState(() {});
    unawaited(_service.markAllRead());
  }

  Future<void> _run(InboxItem item) async {
    HapticFeedbackHelper.tap();
    switch (item.type) {
      case InboxItemType.news:
        final tap = item.notice?.tap;
        if (tap != null) RemoteNotificationsService.instance.runTap(tap);
      case InboxItemType.premiumEnded || InboxItemType.sbp:
        await PremiumPaywallSheet.show(context);
      case InboxItemType.update:
        await AppUpdateService.instance.update(item.update!);
      case InboxItemType.premiumStarted:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final items = _service.items;
    return AppContentFrame(
      maxWidth: AppContentFrame.readingWidth,
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.screenPadding,
                  AppDimensions.spacingM,
                  AppDimensions.screenPadding,
                  AppDimensions.spacingM,
                ),
                child: Row(
                  children: [
                    AppChromeIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () {
                        HapticFeedbackHelper.tap();
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: AppDimensions.spacingM),
                    Expanded(
                      child: Text(
                        appL10n.inboxTitle,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? _Empty(colors: colors)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimensions.screenPadding,
                          0,
                          AppDimensions.screenPadding,
                          32,
                        ),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppDimensions.spacingS),
                        itemBuilder: (_, i) => _InboxCard(
                          item: items[i],
                          fresh: _fresh.contains(items[i].id),
                          onAction: () => _run(items[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.colors});

  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 48,
              color: colors.secondaryText,
            ),
            const SizedBox(height: AppDimensions.spacingM),
            Text(
              appL10n.inboxEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: colors.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.item,
    required this.fresh,
    required this.onAction,
  });

  final InboxItem item;
  final bool fresh;
  final VoidCallback onAction;

  String _date(DateTime value) =>
      DateFormat('d MMMM yyyy', appL10n.localeName).format(value);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final notice = item.notice;
    final (IconData icon, Color tint) = switch (item.type) {
      InboxItemType.news => (Icons.campaign_rounded, colors.accent),
      InboxItemType.premiumStarted => (
        Icons.workspace_premium_rounded,
        colors.green,
      ),
      InboxItemType.premiumEnded => (Icons.timer_off_rounded, colors.red),
      InboxItemType.update => (Icons.system_update_rounded, colors.accent),
      InboxItemType.sbp => (Icons.account_balance_rounded, colors.gold),
    };
    final title = switch (item.type) {
      InboxItemType.news =>
        notice!.title.isNotEmpty ? notice.title : notice.body,
      InboxItemType.premiumStarted => appL10n.inboxPremiumStartedTitle,
      InboxItemType.premiumEnded => appL10n.inboxPremiumEndedTitle,
      InboxItemType.update => appL10n.inboxUpdateTitle(item.update!.version),
      InboxItemType.sbp => appL10n.inboxSbpTitle,
    };
    final body = switch (item.type) {
      InboxItemType.news => notice!.title.isNotEmpty ? notice.body : '',
      InboxItemType.premiumStarted =>
        item.premiumUntil == null
            ? appL10n.inboxPremiumStartedForever
            : appL10n.inboxPremiumStartedBody(_date(item.premiumUntil!)),
      InboxItemType.premiumEnded => appL10n.inboxPremiumEndedBody(
        _date(item.premiumUntil ?? item.date),
      ),
      InboxItemType.update =>
        item.update!.notes.isNotEmpty
            ? item.update!.notes
            : appL10n.inboxUpdateBody,
      InboxItemType.sbp => appL10n.inboxSbpBody,
    };
    final action = switch (item.type) {
      InboxItemType.news =>
        notice!.tap == null
            ? null
            : (notice.buttonText.isNotEmpty
                  ? notice.buttonText
                  : appL10n.inboxOpen),
      InboxItemType.premiumStarted => null,
      InboxItemType.premiumEnded => appL10n.inboxRenew,
      InboxItemType.update => appL10n.inboxUpdateAction,
      InboxItemType.sbp => appL10n.inboxSbpAction,
    };
    final image = notice?.imageUrl ?? '';

    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action == null ? null : onAction,
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spacingM),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tint, size: 22),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: colors.primaryText,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (fresh)
                          Container(
                            key: const ValueKey('inbox-fresh-dot'),
                            margin: const EdgeInsets.only(
                              left: AppDimensions.spacingS,
                              top: 5,
                            ),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.primaryText.withValues(alpha: 0.75),
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (image.isNotEmpty) ...[
                      const SizedBox(height: AppDimensions.spacingS),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppDimensions.spacingS),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _date(item.date),
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.secondaryText,
                            ),
                          ),
                        ),
                        if (action != null)
                          Text(
                            action,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.accent,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
