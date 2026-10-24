import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/celebration_screen.dart';
import 'package:pdd_app/presentation/widgets/flame_icon.dart';

Future<void> showStreakCelebrationDialog({
  required BuildContext context,
  required Streak streak,
}) => showGeneralDialog<void>(
  context: context,
  transitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (context, _, _) => StreakCelebrationView(streak: streak),
);

/// Same full-screen frame and motion as an achievement; only completion queues
/// decide when it may appear. Opening the home screen never presents it.
class StreakCelebrationView extends StatelessWidget {
  const StreakCelebrationView({
    super.key,
    required this.streak,
    this.today,
    this.onContinue,
    this.onClose,
    this.position = 1,
    this.total = 1,
  });
  final Streak streak;
  final DateTime? today;
  final VoidCallback? onContinue, onClose;
  final int position, total;
  @override
  Widget build(BuildContext context) => CelebrationScreen(
    heading: appL10n.streakTitle,
    title: '${streak.current}',
    titleWidget: TweenAnimationBuilder<double>(
      tween: Tween(
        begin: (streak.current - 1).clamp(0, streak.current).toDouble(),
        end: streak.current.toDouble(),
      ),
      duration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 650,
      ),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Text(
        '${value.round()}',
        style: const TextStyle(
          fontSize: 64,
          fontWeight: FontWeight.w800,
          height: 1,
          color: AppColors.white,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
    description: appL10n.streakDaysWord(streak.current),
    label: streak.current > 1 && streak.current >= streak.longest
        ? appL10n.streakNewRecord
        : appL10n.streakToday,
    heroBuilder: (size) => _BreathingFlame(size: size),
    onContinue: onContinue ?? () => Navigator.of(context).pop(),
    onClose: onClose ?? () => Navigator.of(context).pop(),
    position: position,
    total: total,
    isStreak: true,
  );
}

class _BreathingFlame extends StatefulWidget {
  const _BreathingFlame({required this.size});
  final double size;
  @override
  State<_BreathingFlame> createState() => _BreathingFlameState();
}

class _BreathingFlameState extends State<_BreathingFlame>
    with SingleTickerProviderStateMixin {
  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _breath,
    builder: (context, child) => Transform.scale(
      scale: 1 + .035 * Curves.easeInOut.transform(_breath.value),
      child: child,
    ),
    child: FlameIcon(size: widget.size, color: AppColors.gold),
  );
}
