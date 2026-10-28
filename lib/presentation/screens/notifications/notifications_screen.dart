import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String? _selectedId;

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
        if (tap != null) {
          final remote = RemoteNotificationsService.instance;
          unawaited(remote.recordNoticeEvent(item.notice!.id, 'click'));
          remote.runTap(tap);
        }
      case InboxItemType.premiumEnded:
        await PremiumPaywallSheet.show(context);
      case InboxItemType.update:
        await AppUpdateService.instance.update(item.update!);
      case InboxItemType.premiumStarted:
        return;
    }
  }

  Widget _header(AppThemeColors colors, bool wide) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: wide ? 28 : AppDimensions.screenPadding,
      vertical: wide ? 24 : AppDimensions.spacingM,
    ),
    child: Row(
      children: [
        Tooltip(
          message: MaterialLocalizations.of(context).backButtonTooltip,
          child: AppChromeIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () {
              HapticFeedbackHelper.tap();
              Navigator.of(context).pop();
            },
          ),
        ),
        const SizedBox(width: AppDimensions.spacingM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                appL10n.inboxTitle,
                style: TextStyle(
                  fontSize: wide ? 28 : 22,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final items = _service.items;
    final largeText = MediaQuery.textScalerOf(context).scale(15) > 22;
    final selected = items.isEmpty
        ? null
        : items.firstWhere(
            (item) => item.id == _selectedId,
            orElse: () => items.first,
          );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.escape,
          includeRepeats: false,
        ): () {
          if (ModalRoute.of(context)?.isCurrent != false) {
            Navigator.of(context).maybePop();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: AppContentFrame(
          maxWidth: largeText
              ? AppContentFrame.readingWidth
              : AppContentFrame.desktopContentWidth,
          child: Scaffold(
            backgroundColor: colors.background,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900 && !largeText;
                  return Column(
                    children: [
                      _header(colors, wide),
                      Expanded(
                        child: items.isEmpty
                            ? _Empty(colors: colors)
                            : wide
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: 320,
                                      child: ListView.separated(
                                        key: const PageStorageKey(
                                          'desktop-inbox-list',
                                        ),
                                        padding: const EdgeInsets.only(
                                          right: 16,
                                          bottom: 24,
                                        ),
                                        itemCount: items.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(height: 8),
                                        itemBuilder: (_, i) => _InboxPreview(
                                          item: items[i],
                                          fresh: _fresh.contains(items[i].id),
                                          selected: items[i].id == selected!.id,
                                          onSelect: () => setState(
                                            () => _selectedId = items[i].id,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        key: PageStorageKey(
                                          'inbox-detail-${selected!.id}',
                                        ),
                                        primary: false,
                                        padding: const EdgeInsets.only(
                                          bottom: 24,
                                        ),
                                        child: _InboxCard(
                                          item: selected,
                                          fresh: _fresh.contains(selected.id),
                                          detail: true,
                                          onAction: () => _run(selected),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  AppDimensions.screenPadding,
                                  0,
                                  AppDimensions.screenPadding,
                                  32,
                                ),
                                itemCount: items.length,
                                separatorBuilder: (_, _) => const SizedBox(
                                  height: AppDimensions.spacingS,
                                ),
                                itemBuilder: (_, i) => _InboxCard(
                                  item: items[i],
                                  fresh: _fresh.contains(items[i].id),
                                  onAction: () => _run(items[i]),
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
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
      child: SingleChildScrollView(
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
    this.detail = false,
  });

  final InboxItem item;
  final bool fresh;
  final VoidCallback onAction;
  final bool detail;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final data = _inboxContent(item, colors);
    final icon = data.icon, tint = data.tint;
    final title = data.title, body = data.body, image = data.image;
    final action = data.action;

    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: detail || action == null ? null : onAction,
        child: Padding(
          padding: EdgeInsets.all(detail ? 24 : AppDimensions.spacingM),
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
                          // A picture-only message: the picture is the content.
                          child: title.isEmpty
                              ? const SizedBox.shrink()
                              : Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: detail ? 21 : 15,
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
                      if (title.isNotEmpty || body.isNotEmpty)
                        const SizedBox(height: AppDimensions.spacingS),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          image,
                          fit: detail ? BoxFit.contain : BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppDimensions.spacingS),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final date = Text(
                          _date(item.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.secondaryText,
                          ),
                        );
                        final label = action == null
                            ? null
                            : Text(
                                action,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: detail ? colors.white : colors.accent,
                                ),
                              );
                        if (detail ||
                            MediaQuery.textScalerOf(context).scale(14) > 19) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              date,
                              if (label != null) ...[
                                const SizedBox(height: 12),
                                if (detail)
                                  FilledButton(
                                    onPressed: onAction,
                                    child: label,
                                  )
                                else
                                  label,
                              ],
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: date),
                            ?label,
                          ],
                        );
                      },
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

String _date(DateTime value) =>
    DateFormat('d MMMM yyyy', appL10n.localeName).format(value);

({
  IconData icon,
  Color tint,
  String title,
  String body,
  String? action,
  String image,
})
_inboxContent(InboxItem item, AppThemeColors colors) {
  final notice = item.notice;
  final (IconData icon, Color tint) = switch (item.type) {
    InboxItemType.news => (Icons.campaign_rounded, colors.accent),
    InboxItemType.premiumStarted => (
      Icons.workspace_premium_rounded,
      colors.green,
    ),
    InboxItemType.premiumEnded => (Icons.timer_off_rounded, colors.red),
    InboxItemType.update => (Icons.system_update_rounded, colors.accent),
  };
  final title = switch (item.type) {
    InboxItemType.news => notice!.title.isNotEmpty ? notice.title : notice.body,
    InboxItemType.premiumStarted => appL10n.inboxPremiumStartedTitle,
    InboxItemType.premiumEnded => appL10n.inboxPremiumEndedTitle,
    InboxItemType.update => appL10n.inboxUpdateTitle(item.update!.version),
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
  };
  final image = notice?.imageUrl ?? '';

  return (
    icon: icon,
    tint: tint,
    title: title,
    body: body,
    action: action,
    image: image,
  );
}

class _InboxPreview extends StatelessWidget {
  const _InboxPreview({
    required this.item,
    required this.fresh,
    required this.selected,
    required this.onSelect,
  });
  final InboxItem item;
  final bool fresh, selected;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final data = _inboxContent(item, colors);
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? colors.accentSurface10 : colors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? colors.accent : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('inbox-preview-${item.id}'),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(data.icon, color: data.tint, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _date(item.date),
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.secondaryText,
                        ),
                      ),
                    ),
                    if (fresh)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  data.title.isEmpty ? appL10n.inboxPictureTitle : data.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: colors.primaryText,
                  ),
                ),
                if (data.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    data.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
