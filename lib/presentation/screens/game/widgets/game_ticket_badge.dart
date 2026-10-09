import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// The source ticket stays accessible in both the question and its explanation.
class GameTicketBadge extends StatelessWidget {
  const GameTicketBadge({
    super.key,
    required this.ticket,
    this.onTap,
    this.open = false,
  });

  final String ticket;
  final VoidCallback? onTap;

  /// The source photo is shown: the icon turns into a cross that closes it.
  final bool open;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final radius = BorderRadius.circular(AppDimensions.smallRadius);
    final badge = Material(
      color: colors.accentSurface10,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  ticket,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.accent,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    open ? Icons.close_rounded : Icons.photo_outlined,
                    key: ValueKey(open),
                    size: 15,
                    color: colors.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return onTap == null
        ? badge
        : Tooltip(message: appL10n.gameSourceImage, child: badge);
  }
}
