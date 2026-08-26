import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';

class FeedStreakMilestone {
  final int count;
  final String badgeText;
  final String title;
  final String subtitle;
  final String? imagePath;
  final IconData fallbackIcon;
  final Color accentColor;

  const FeedStreakMilestone({
    required this.count,
    required this.badgeText,
    required this.title,
    required this.subtitle,
    this.imagePath,
    required this.fallbackIcon,
    required this.accentColor,
  });

  static FeedStreakMilestone? forCount(int count) {
    switch (count) {
      case 5:
        return const FeedStreakMilestone(
          count: 5,
          badgeText: '5 ПОДРЯД! 🔥',
          title: 'Старт идеальный!',
          subtitle: 'Мотор прогрет, жми дальше!',
          imagePath: 'assets/images/streaks/streak_5.png',
          fallbackIcon: Icons.local_fire_department_rounded,
          accentColor: Color(0xFFF97316),
        );
      case 10:
        return const FeedStreakMilestone(
          count: 10,
          badgeText: '10 ПОДРЯД! ⚡',
          title: 'В потоке без ошибок!',
          subtitle: 'Ты отлично чувствуешь дорогу!',
          imagePath: 'assets/images/streaks/streak_10.png',
          fallbackIcon: Icons.bolt_rounded,
          accentColor: Color(0xFFEAB308),
        );
      case 20:
        return const FeedStreakMilestone(
          count: 20,
          badgeText: '20 ПОДРЯД! 🏎️',
          title: 'Огненный форсаж!',
          subtitle: 'Билет за билетом! Инспектор в шоке!',
          imagePath: 'assets/images/streaks/streak_20.png',
          fallbackIcon: Icons.speed_rounded,
          accentColor: Color(0xFFEF4444),
        );
      case 50:
        return const FeedStreakMilestone(
          count: 50,
          badgeText: '50 ПОДРЯД! 💥',
          title: 'Легенда автошколы!',
          subtitle: 'Тебя уже ничто не остановит на дороге!',
          imagePath: 'assets/images/streaks/streak_50.png',
          fallbackIcon: Icons.whatshot_rounded,
          accentColor: Color(0xFF8B5CF6),
        );
      case 100:
        return const FeedStreakMilestone(
          count: 100,
          badgeText: '100 ПОДРЯД! 🌌',
          title: 'Космический уровень!',
          subtitle: 'Экзамен сдашь даже с закрытыми глазами!',
          imagePath: 'assets/images/streaks/streak_100.png',
          fallbackIcon: Icons.rocket_launch_rounded,
          accentColor: Color(0xFF06B6D4),
        );
      default:
        return null;
    }
  }
}

class FeedStreakDialog extends StatelessWidget {
  final FeedStreakMilestone milestone;
  final VoidCallback onContinue;

  const FeedStreakDialog({
    super.key,
    required this.milestone,
    required this.onContinue,
  });

  static Future<void> show(
    BuildContext context,
    FeedStreakMilestone milestone,
  ) {
    HapticFeedbackHelper.success();
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => FeedStreakDialog(
        milestone: milestone,
        onContinue: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: milestone.accentColor.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: milestone.accentColor.withValues(alpha: isDark ? 0.25 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      milestone.fallbackIcon,
                      size: 16,
                      color: milestone.accentColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      milestone.badgeText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: milestone.accentColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Visual Image / Fallback Icon Box
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: milestone.accentColor.withValues(alpha: isDark ? 0.2 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: milestone.imagePath != null
                      ? Image.asset(
                          milestone.imagePath!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            milestone.fallbackIcon,
                            size: 48,
                            color: milestone.accentColor,
                          ),
                        )
                      : Icon(
                          milestone.fallbackIcon,
                          size: 48,
                          color: milestone.accentColor,
                        ),
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Text(
                milestone.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                milestone.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.secondaryText,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),

              // Action Button (Flat clean style, no shadow)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedbackHelper.tap();
                    onContinue();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: milestone.accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
                    ),
                  ),
                  child: const Text(
                    'Продолжить',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
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
