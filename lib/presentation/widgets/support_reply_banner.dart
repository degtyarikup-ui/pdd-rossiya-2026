import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// A short banner from the top of the screen with an operator reply: the manager's picture,
/// the name and the start of the text. A tap opens the support chat; it hides by itself.
class SupportReplyBanner {
  SupportReplyBanner._();

  static const Duration visibleFor = Duration(seconds: 5);
  static const String avatarAsset = 'assets/images/support_manager.webp';

  static OverlayEntry? _entry;
  static Timer? _hideTimer;

  static void show(
    OverlayState overlay,
    SupportChatMessage reply, {
    required VoidCallback onTap,
  }) {
    hide();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _BannerView(
        text: reply.text,
        onTap: () {
          hide();
          onTap();
        },
        onDismiss: hide,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _hideTimer = Timer(visibleFor, hide);
  }

  static void hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _BannerView extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _BannerView({
    required this.text,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final top = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: -1.0, end: 0.0),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Transform.translate(
          offset: Offset(0, value * 120),
          child: child,
        ),
        child: Dismissible(
          key: const ValueKey('support-reply-banner'),
          direction: DismissDirection.up,
          onDismissed: (_) => onDismiss(),
          child: Material(
            color: colors.cardBackground,
            elevation: 6,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        SupportReplyBanner.avatarAsset,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            appL10n.supportManagerName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.accent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
