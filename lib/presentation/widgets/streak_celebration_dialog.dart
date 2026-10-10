import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/flame_icon.dart';
import 'package:pdd_app/presentation/widgets/streak_widgets.dart';

/// Поздравление за засчитанный сегодня день.
///
/// Показывается один раз в день, когда пользователь впервые после полуночи
/// ответил на вопрос. Открывается из главного экрана при возврате
/// с тренировки (см. home_screen.dart → _maybeShowStreakCelebration).
///
/// Содержание сведено к тому, что человек действительно считывает за
/// секунду: число дней, отметка «сегодня засчитано» в неделе и сколько
/// осталось до ближайшей цели. Без мотивационных абзацев, лучей и искр:
/// яркость даёт один тёплый цвет шапки, движение — огонёк, который
/// загорается, и число, которое прибавляет единицу.
Future<void> showStreakCelebrationDialog({
  required BuildContext context,
  required Streak streak,
}) async {
  HapticFeedbackHelper.success();
  SoundEffectsService.instance.playStreak();
  await showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    barrierDismissible: true,
    barrierLabel: appL10n.streakBarrierLabel,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) => StreakCelebrationView(streak: streak),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Тёплая шапка: один цвет на светлой и тёмной теме, она и есть «яркость».
const _heatTop = Color(0xFFFFB13D);
const _heatBottom = Color(0xFFFF7A1A);

class StreakCelebrationView extends StatelessWidget {
  const StreakCelebrationView({super.key, required this.streak, this.today});

  final Streak streak;

  /// Для тестов; по умолчанию — сейчас.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final s = streak;
    // «Рекорд» — только если серия длиннее одного дня и не ниже лучшей.
    final isNewRecord = s.current > 1 && s.current >= s.longest;
    final now = today ?? DateTime.now();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Material(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(current: s.current, isNewRecord: isNewRecord),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StreakWeekStrip(
                        streak: s,
                        today: now,
                        size: 36,
                        highlightToday: true,
                      ),
                      const SizedBox(height: AppDimensions.spacingXL),
                      StreakGoalBar(current: s.current),
                      const SizedBox(height: AppDimensions.spacingXL),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDimensions.buttonRadius,
                              ),
                            ),
                          ),
                          onPressed: () {
                            HapticFeedbackHelper.tap();
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            appL10n.continueButton,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.current, required this.isNewRecord});

  final int current;
  final bool isNewRecord;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_heatTop, _heatBottom],
        ),
      ),
      child: Column(
        children: [
          const _IgnitingFlame(),
          const SizedBox(height: 10),
          _CountUp(value: current),
          const SizedBox(height: 2),
          Text(
            appL10n.streakDaysWord(current),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isNewRecord
                      ? Icons.emoji_events_rounded
                      : Icons.check_circle_rounded,
                  size: 15,
                  color: AppColors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  isNewRecord ? appL10n.streakNewRecord : appL10n.streakToday,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Огонёк загорается: появляется с отскоком и один раз «вспыхивает»
/// светлым кругом позади. Дальше спокойно дышит — без искр и лучей.
class _IgnitingFlame extends StatefulWidget {
  const _IgnitingFlame();

  @override
  State<_IgnitingFlame> createState() => _IgnitingFlameState();
}

class _IgnitingFlameState extends State<_IgnitingFlame>
    with TickerProviderStateMixin {
  late final AnimationController _ignite = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ignite.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: AnimatedBuilder(
        animation: Listenable.merge([_ignite, _breath]),
        builder: (context, _) {
          final t = _ignite.value;
          final pop = Curves.elasticOut.transform((t / 0.8).clamp(0.0, 1.0));
          final glow = Curves.easeOut.transform(t);
          final breath = 1 + 0.035 * Curves.easeInOut.transform(_breath.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              // Один светлый круг: вспыхивает и оседает подложкой огонька.
              Transform.scale(
                scale: 0.6 + 0.4 * glow,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.white.withValues(
                      alpha: 0.18 + 0.22 * (1 - glow),
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: pop * breath,
                alignment: Alignment.bottomCenter,
                child: const FlameIcon(size: 56, color: AppColors.white),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Число дней прибавляет единицу на глазах: вчерашнее → сегодняшнее.
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final from = value > 0 ? value - 1 : 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: from.toDouble(), end: value.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: const Interval(0.3, 1, curve: Curves.easeOutCubic),
      builder: (context, v, _) => Text(
        '${v.round()}',
        style: const TextStyle(
          fontSize: 64,
          fontWeight: FontWeight.w800,
          letterSpacing: -2,
          height: 1,
          color: AppColors.white,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
