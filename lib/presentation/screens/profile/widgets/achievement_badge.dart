import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/data/models/achievement.dart';

/// Стандартная luminance-матрица (0.2126 / 0.7152 / 0.0722) для перевода в оттенки серого.
const List<double> achievementGrayscaleMatrix = <double>[
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

String achievementAsset(AchievementId id, int level) =>
    'assets/images/achievements/${id.name}_$level.png';

class AchievementBadge extends StatelessWidget {
  final AchievementId id;
  final int imageLevel;
  final bool unlocked;
  final double size;

  const AchievementBadge({
    super.key,
    required this.id,
    required this.imageLevel,
    required this.unlocked,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final clampedLevel = imageLevel.clamp(1, 4);
    final assetPath = achievementAsset(id, clampedLevel);

    Widget badgeWidget = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colors.searchFieldFill,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.emoji_events_rounded,
            size: size * 0.48,
            color: colors.secondaryText,
          ),
        );
      },
    );

    if (!unlocked) {
      final opacity = isDark ? 0.25 : 0.35;
      badgeWidget = Opacity(
        opacity: opacity,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(achievementGrayscaleMatrix),
          child: badgeWidget,
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Center(child: badgeWidget),
    );
  }
}
