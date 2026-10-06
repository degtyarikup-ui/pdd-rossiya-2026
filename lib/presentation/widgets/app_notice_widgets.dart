import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Network image for admin notices: never breaks the layout on errors.
class _NoticeImage extends StatelessWidget {
  final String url;
  final double? height, width;
  final Widget? fallback;
  const _NoticeImage(this.url, {this.height, this.width, this.fallback});

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    height: height,
    width: width,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : SizedBox(
            height: height,
            width: width,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.05)),
          ),
  );
}

/// Modal admin message. Returns `true` when the primary button was pressed.
class AppNoticeDialog extends StatelessWidget {
  final AppNotice notice;
  const AppNoticeDialog({super.key, required this.notice});

  static Future<bool> show(BuildContext context, AppNotice notice) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AppNoticeDialog(notice: notice),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = notice.accent ?? theme.colorScheme.primary;
    final onAccent = accent.computeLuminance() > 0.55
        ? Colors.black87
        : Colors.white;
    final hasImage = notice.imageUrl.isNotEmpty;
    final compact = notice.layout == 'compact';
    final primary = notice.buttonText.isNotEmpty
        ? notice.buttonText
        : notice.tap == null
        ? appL10n.noticeAcknowledge
        : appL10n.noticeOpen;
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: size.height * .85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasImage && !compact)
                AspectRatio(
                  aspectRatio: notice.layout == 'cover' ? 4 / 3 : 16 / 9,
                  child: _NoticeImage(notice.imageUrl),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasImage && compact)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _NoticeImage(
                            notice.imageUrl,
                            width: 64,
                            height: 64,
                          ),
                        ),
                      ),
                    if (notice.emoji.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          notice.emoji,
                          style: const TextStyle(fontSize: 36, height: 1),
                        ),
                      ),
                    Text(
                      notice.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(notice.body, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: onAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(primary),
                      ),
                    ),
                    if (notice.dismissText.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(notice.dismissText),
                        ),
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

/// Non-blocking card shown in place of the statistics block on the home screen.
class AppNoticeBanner extends StatelessWidget {
  final AppNotice notice;
  final VoidCallback onTap, onDismiss;
  const AppNoticeBanner({
    super.key,
    required this.notice,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final accent = notice.accent ?? theme.colorScheme.primary;
    final hasImage = notice.imageUrl.isNotEmpty;
    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: notice.tap == null ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 5)),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.spacingL,
                  AppDimensions.spacingL,
                  36,
                  AppDimensions.spacingL,
                ),
                child: Center(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        child: hasImage
                            ? _NoticeImage(
                                notice.imageUrl,
                                width: 84,
                                height: 84,
                                fallback: Text(
                                  notice.emoji.isEmpty ? '🔔' : notice.emoji,
                                  style: const TextStyle(fontSize: 38),
                                ),
                              )
                            : Text(
                                notice.emoji.isEmpty ? '🔔' : notice.emoji,
                                style: const TextStyle(fontSize: 38),
                              ),
                      ),
                      const SizedBox(width: AppDimensions.spacingL),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasImage && notice.emoji.isNotEmpty
                                  ? '${notice.emoji} ${notice.title}'
                                  : notice.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                                color: colors.primaryText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Flexible(
                              child: Text(
                                notice.body,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 13.5,
                                  height: 1.35,
                                  color: colors.secondaryText,
                                ),
                              ),
                            ),
                            if (notice.tap != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${notice.buttonText.isNotEmpty ? notice.buttonText : appL10n.noticeOpen} →',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: colors.secondaryText,
                  ),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onDismiss,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
