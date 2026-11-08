import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';

/// A recoverable loading failure stays next to the content and its retry action.
class InlineLoadError extends StatelessWidget {
  const InlineLoadError({super.key, required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spacingL),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: colors.secondaryText,
                  size: 22,
                ),
                const SizedBox(width: AppDimensions.spacingM),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.primaryText,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: AppDimensions.spacingS),
              Align(alignment: AlignmentDirectional.centerStart, child: action),
            ],
          ],
        ),
      ),
    );
  }
}
