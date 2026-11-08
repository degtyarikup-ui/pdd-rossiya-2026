import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/services/notification_inbox_service.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_notice_widgets.dart';

/// Inline profile placements share the profile's scroll view and natural height.
class ProfileNoticeBanners extends StatelessWidget {
  const ProfileNoticeBanners({super.key, this.service});

  final RemoteNotificationsService? service;

  @override
  Widget build(BuildContext context) {
    final notifications = service ?? RemoteNotificationsService.instance;
    return ValueListenableBuilder<List<AppNotice>>(
      valueListenable: notifications.profileBanners,
      builder: (context, notices, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final notice in notices)
            ProfileNoticeBanner(
              key: ValueKey(notice.id),
              notice: notice,
              margin: const EdgeInsets.only(top: AppDimensions.spacingM),
              onViewed: () {
                unawaited(notifications.recordNoticeEvent(notice.id, 'view'));
                unawaited(
                  NotificationInboxService.instance.markNoticeRead(notice.id),
                );
              },
              onDismiss: () => notifications.dismissBanner(notice.id),
              onTap: () {
                final tap = notice.tap;
                if (tap == null) return;
                unawaited(notifications.recordNoticeEvent(notice.id, 'click'));
                unawaited(
                  NotificationInboxService.instance.markNoticeRead(notice.id),
                );
                notifications.runTap(tap);
              },
            ),
        ],
      ),
    );
  }
}

/// Independent optional image, text and action. No fixed content height or crop.
class ProfileNoticeBanner extends StatefulWidget {
  const ProfileNoticeBanner({
    super.key,
    required this.notice,
    required this.onTap,
    required this.onDismiss,
    this.onViewed,
    this.margin = EdgeInsets.zero,
  });

  final AppNotice notice;
  final VoidCallback onTap, onDismiss;
  final VoidCallback? onViewed;
  final EdgeInsetsGeometry margin;

  @override
  State<ProfileNoticeBanner> createState() => _ProfileNoticeBannerState();
}

class _ProfileNoticeBannerState extends State<ProfileNoticeBanner> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _image;
  bool _imageFailed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(ProfileNoticeBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notice.imageUrl != widget.notice.imageUrl) {
      _stopImage();
      _image?.dispose();
      _image = null;
      _imageFailed = false;
      _resolveImage();
    }
  }

  void _resolveImage() {
    if (widget.notice.imageUrl.isEmpty || _stream != null) return;
    _stream = NetworkImage(
      widget.notice.imageUrl,
    ).resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener(
      (image, _) {
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
        });
      },
      onError: (Object error, StackTrace? stack) {
        if (mounted) setState(() => _imageFailed = true);
      },
      // The banner handles image failures. A request that fails after the
      // profile closes must not become an unhandled framework error.
      reportErrors: false,
    );
    _stream!.addListener(_listener!);
  }

  void _stopImage() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stopImage();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    final colors = AppColors.of(context);
    final hasImage = notice.imageUrl.isNotEmpty && !_imageFailed;
    final hasTitle = notice.title.isNotEmpty;
    final hasBody = notice.body.isNotEmpty;
    final hasButton = notice.button && notice.tap != null;
    final hasContent = hasTitle || hasBody || hasButton;
    if (!hasImage && !hasContent) return const SizedBox.shrink();
    final accent = notice.accent ?? colors.accent;
    final onAccent = accent.computeLuminance() > .55
        ? Colors.black87
        : Colors.white;
    final wholeCardTap = !hasButton && notice.tap != null;
    final imageRatio = _image == null
        ? notice.imageAspectRatio ?? 16 / 9
        : _image!.image.width / _image!.image.height;

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasImage)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Semantics(
              image: true,
              label: appL10n.noticeImageBanner,
              child: AspectRatio(
                aspectRatio: imageRatio,
                child: _image == null
                    ? ColoredBox(color: colors.accent.withValues(alpha: .05))
                    : RawImage(image: _image!.image, fit: BoxFit.contain),
              ),
            ),
          ),
        if (hasContent)
          Padding(
            padding: const EdgeInsets.all(AppDimensions.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasTitle)
                  Padding(
                    padding: EdgeInsets.only(right: hasImage ? 0 : 36),
                    child: Text(
                      notice.title,
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                if (hasTitle && hasBody)
                  const SizedBox(height: AppDimensions.spacingS),
                if (hasBody)
                  Padding(
                    padding: EdgeInsets.only(
                      right: hasImage || hasTitle ? 0 : 36,
                    ),
                    child: Text(
                      notice.body,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: colors.primaryText.withValues(alpha: .72),
                      ),
                    ),
                  ),
                if (hasButton) ...[
                  if (hasTitle || hasBody)
                    const SizedBox(height: AppDimensions.spacingL),
                  Padding(
                    padding: EdgeInsets.only(
                      right: !hasImage && !hasTitle && !hasBody ? 36 : 0,
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: onAccent,
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.buttonRadius,
                          ),
                        ),
                      ),
                      onPressed: widget.onTap,
                      child: Text(
                        notice.buttonText.isEmpty
                            ? appL10n.noticeOpen
                            : notice.buttonText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
    if (wholeCardTap) {
      content = InkWell(onTap: widget.onTap, child: content);
    }
    final card = Padding(
      padding: widget.margin,
      child: Material(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            content,
            Positioned(
              top: 4,
              right: 4,
              child: NoticeCloseButton(
                onPressed: widget.onDismiss,
                overImage: hasImage,
              ),
            ),
          ],
        ),
      ),
    );
    // A tall loading picture may push all copy off-screen. Wait for its first
    // frame (or fallback after failure) before counting a campaign impression.
    if (hasImage && _image == null) return card;
    return NoticeViewObserver(
      key: ValueKey('profile-view-${notice.id}'),
      onViewed: widget.onViewed,
      child: card,
    );
  }
}
