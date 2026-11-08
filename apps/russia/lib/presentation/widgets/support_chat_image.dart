import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Резервирует место для фото до декодирования первого кадра: история чата
/// не прыгает при загрузке, ошибка сети оставляет возможность повторить.
class SupportChatImage extends StatefulWidget {
  const SupportChatImage({super.key, required this.image, required this.onTap});

  final ImageProvider image;
  final VoidCallback onTap;

  @override
  State<SupportChatImage> createState() => _SupportChatImageState();
}

class _SupportChatImageState extends State<SupportChatImage> {
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ColoredBox(
            color: colors.divider.withValues(alpha: 0.2),
            child: Image(
              key: ValueKey(_attempt),
              image: widget.image,
              fit: BoxFit.contain,
              semanticLabel: appL10n.supportChatPhoto,
              frameBuilder: (context, child, frame, synchronouslyLoaded) {
                if (synchronouslyLoaded || frame != null) {
                  return GestureDetector(onTap: widget.onTap, child: child);
                }
                return Center(
                  child: SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.accent,
                      semanticsLabel: appL10n.appLoading,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        color: colors.secondaryText,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appL10n.supportChatImageLoadFailed,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.secondaryText),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => _attempt++),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(appL10n.supportChatRetry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
