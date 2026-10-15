import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Network image for admin notices: never breaks the layout on errors.
class _NoticeImage extends StatelessWidget {
  final String url;
  final double? height, width;
  const _NoticeImage(this.url, {this.height, this.width});

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    height: height,
    width: width,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
    final colors = AppColors.of(context);
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
      backgroundColor: colors.cardBackground,
      child: Stack(
        children: [
          ConstrainedBox(
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
                        Padding(
                          padding: EdgeInsets.only(
                            right: hasImage && !compact ? 0 : 32,
                          ),
                          child: Text(
                            notice.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              color: colors.primaryText,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          notice.body,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                            color: colors.primaryText.withValues(alpha: .68),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: onAccent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppDimensions.buttonRadius,
                                ),
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
          Positioned(
            top: 8,
            right: 8,
            child: _NoticeCloseButton(
              onPressed: () => Navigator.of(context).pop(false),
              overImage: hasImage && !compact,
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-blocking card shown in place of the statistics block on the home screen.
class AppNoticeBanner extends StatelessWidget {
  final AppNotice notice;
  final VoidCallback onTap, onDismiss;

  /// Keep statistics visible until an image is available, including load errors.
  final Widget? imageFallback;
  const AppNoticeBanner({
    super.key,
    required this.notice,
    required this.onTap,
    required this.onDismiss,
    this.imageFallback,
  });

  Widget _surface(BuildContext context, Widget content, {bool image = false}) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: notice.tap == null ? null : onTap,
                child: notice.tap == null
                    ? null
                    : Semantics(
                        label: notice.isImageBanner
                            ? appL10n.noticeImageBanner
                            : notice.title,
                      ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: _NoticeCloseButton(onPressed: onDismiss, overImage: image),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final accent = notice.accent ?? colors.accent;
    if (notice.isImageBanner) {
      return Image.network(
        notice.imageUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        semanticLabel: notice.title.isNotEmpty
            ? notice.title
            : appL10n.noticeImageBanner,
        frameBuilder: (context, child, frame, _) =>
            frame == null && imageFallback != null
            ? imageFallback!
            : _surface(context, child, image: true),
        errorBuilder: (context, _, _) =>
            imageFallback ??
            _surface(context, const SizedBox.expand(), image: true),
      );
    }
    return _surface(
      context,
      Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (notice.imageUrl.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.smallRadius,
                      ),
                      child: _NoticeImage(
                        notice.imageUrl,
                        width: 64,
                        height: 64,
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacingM),
                  ],
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            flex: 2,
                            child: Text(
                              notice.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                letterSpacing: -0.25,
                                color: colors.primaryText,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Flexible(
                            flex: 3,
                            child: Text(
                              notice.body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                                height: 1.4,
                                color: colors.primaryText.withValues(alpha: .68),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (notice.tap != null) ...[
              const SizedBox(height: AppDimensions.spacingS),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: colors.isDark ? .18 : .08),
                  borderRadius: BorderRadius.circular(
                    AppDimensions.smallRadius,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        notice.buttonText.isNotEmpty
                            ? notice.buttonText
                            : appL10n.noticeOpen,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 12,
                          height: 1.2,
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 15, color: accent),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoticeCloseButton extends StatelessWidget {
  const _NoticeCloseButton({required this.onPressed, this.overImage = false});
  final VoidCallback onPressed;
  final bool overImage;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return IconButton(
      style: IconButton.styleFrom(
        backgroundColor: overImage ? Colors.black.withValues(alpha: .48) : null,
        minimumSize: const Size(36, 36),
        padding: const EdgeInsets.all(8),
      ),
      icon: Icon(
        Icons.close_rounded,
        size: 20,
        color: overImage ? Colors.white : colors.secondaryText,
      ),
      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      onPressed: onPressed,
    );
  }
}
