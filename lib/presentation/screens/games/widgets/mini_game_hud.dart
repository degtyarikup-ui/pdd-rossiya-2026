import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/l10n/l10n.dart';

import 'game_ui.dart';

/// Flutter counterpart of Godot's MiniGameHud: close, score, time, lives.
class MiniGameHud extends StatelessWidget {
  const MiniGameHud({
    super.key,
    required this.score,
    required this.combo,
    required this.secondsLeft,
    required this.totalSeconds,
    required this.lives,
    required this.totalLives,
    required this.onExit,
  });

  final int score, combo, secondsLeft, totalSeconds, lives, totalLives;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double width(String text, double size, FontWeight weight) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(
            context,
          ).style.copyWith(fontSize: size, fontWeight: weight),
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      final result = painter.width;
      painter.dispose();
      return result;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 48,
            child: Center(
              child: IconButton(
                tooltip: appL10n.gameExit,
                onPressed: onExit,
                style: IconButton.styleFrom(
                  backgroundColor: colors.cardBackground,
                  minimumSize: const Size.square(40),
                  maximumSize: const Size.square(40),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: colors.primaryText,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scoreWidth =
                        26 + width('$score', 18, FontWeight.w800);
                    final timerWidth =
                        24 +
                        width(
                          appL10n.gameSecondsLeft(secondsLeft),
                          14,
                          FontWeight.w700,
                        );
                    final comboWidth = combo > 1
                        ? 18 + width('×$combo', 12, FontWeight.w800)
                        : 0;
                    final fullLivesWidth =
                        totalLives * 15.0 + math.max(0, totalLives - 1) * 3;
                    final compact =
                        scoreWidth +
                            comboWidth +
                            timerWidth +
                            fullLivesWidth +
                            16 >
                        constraints.maxWidth;
                    final livesWidth = compact
                        ? 19 + width('$totalLives', 14, FontWeight.w800)
                        : fullLivesWidth;
                    final twoRows =
                        scaler.scale(1) > 1.3 ||
                        scoreWidth + comboWidth + timerWidth + livesWidth + 16 >
                            constraints.maxWidth;
                    final scoreLabel = GameScoreLabel(
                      score: score,
                      streak: combo,
                      shortCombo: true,
                    );
                    final timer = GameTimeBar(
                      secondsLeft: secondsLeft,
                      totalSeconds: totalSeconds,
                      inline: true,
                    );
                    final hearts = Semantics(
                      label: appL10n.gameLives,
                      value: '$lives',
                      child: ExcludeSemantics(
                        child: GameLives(
                          lives: lives,
                          total: totalLives,
                          compact: compact,
                        ),
                      ),
                    );
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: math.max(24, scaler.scale(20)),
                          child: Row(
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: scoreLabel,
                                ),
                              ),
                              if (!twoRows) ...[
                                const Spacer(),
                                timer,
                                const SizedBox(width: 8),
                                hearts,
                              ],
                            ],
                          ),
                        ),
                        if (twoRows) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: timer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              hearts,
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A clear penalty mark: quick impact, readable hold, gentle upward fade.
/// Reduced motion keeps a stationary mark for the same answer feedback period.
class GameLifeLossBadge extends StatefulWidget {
  const GameLifeLossBadge({super.key});
  @override
  State<GameLifeLossBadge> createState() => _GameLifeLossBadgeState();
}

class _GameLifeLossBadgeState extends State<GameLifeLossBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _animation.forward();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: appL10n.gameLifeLost,
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _animation,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '−1',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colors.red,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.favorite_rounded, size: 24, color: colors.red),
            ],
          ),
          builder: (context, child) {
            final t = _animation.value;
            final scale = reduced
                ? 1.0
                : t < .25
                ? .65 + .5 * Curves.easeOutCubic.transform(t / .25)
                : t < .45
                ? 1.15 - .15 * Curves.easeInOut.transform((t - .25) / .2)
                : 1.0;
            final departure = ((t - .75) / .25).clamp(0.0, 1.0);
            return Opacity(
              opacity: reduced ? 1 : 1 - departure * .65,
              child: Transform.translate(
                offset: Offset(0, reduced ? 0 : -10 * departure),
                child: Transform.scale(scale: scale, child: child),
              ),
            );
          },
        ),
      ),
    );
  }
}
