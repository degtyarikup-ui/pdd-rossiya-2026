import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_over_dialog.dart';

/// Общие элементы мини-игр. Только токены темы, без обводок; лёгкая тень —
/// лишь там, где белая карточка иначе теряется на светлом фоне.

/// Мягкая тень для белых карточек в светлой теме (в тёмной не видна и не нужна).
List<BoxShadow> gameSoftShadow(AppThemeColors colors) => colors.isDark
    ? const []
    : const [
        BoxShadow(
          color: Color(0x14101828),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ];

/// Жизни сердцами: оставшиеся красные, потерянные приглушены.
class GameLives extends StatelessWidget {
  const GameLives({super.key, required this.lives, this.total = 3});

  final int lives;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              scale: i < lives ? 1 : 0.85,
              child: Icon(
                i < lives
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 22,
                color: i < lives ? colors.red : colors.secondaryText,
              ),
            ),
          ),
      ],
    );
  }
}

/// Счёт блица: число и множитель серии, если он есть.
class GameScoreLabel extends StatelessWidget {
  const GameScoreLabel({super.key, required this.score, this.multiplier = 1});

  final int score;
  final int multiplier;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.star_rounded, size: 22, color: colors.gold),
        const SizedBox(width: 4),
        Text(
          '$score',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: colors.primaryText,
          ),
        ),
        if (multiplier > 1) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.goldLightSurface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'x$multiplier',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colors.gold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Полоса оставшегося времени: убывает плавно, к концу краснеет.
class GameTimeBar extends StatelessWidget {
  const GameTimeBar({
    super.key,
    required this.secondsLeft,
    required this.totalSeconds,
  });

  final int secondsLeft;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fraction = (secondsLeft / totalSeconds).clamp(0.0, 1.0);
    final urgent = secondsLeft <= 10;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 6,
              color: colors.gray,
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 950),
                curve: Curves.linear,
                widthFactor: fraction,
                heightFactor: 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  color: urgent ? colors.red : colors.accent,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppDimensions.spacingS),
        SizedBox(
          width: 40,
          child: Text(
            appL10n.gameSecondsLeft(secondsLeft),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: urgent ? colors.red : colors.secondaryText,
            ),
          ),
        ),
      ],
    );
  }
}

/// Кнопка действия на всю ширину: заливка и цвет текста задаёт состояние.
class GameActionButton extends StatelessWidget {
  const GameActionButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
    this.icon,
    this.iconColor,
    this.height = AppDimensions.answerOptionHeight,
  });

  final String label;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final Color? iconColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: iconColor ?? foreground),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: foreground,
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

/// Круглая кнопка ответа с подписью: «нет» слева, «да» справа.
class GameRoundButton extends StatefulWidget {
  const GameRoundButton({
    super.key,
    required this.icon,
    required this.color,
    required this.surface,
    required this.onTap,
    this.iconColor,
    this.label,
    this.size = 76,
  });

  final IconData icon;
  final String? label;
  final Color color;
  final Color surface;
  final Color? iconColor;
  final VoidCallback onTap;
  final double size;

  @override
  State<GameRoundButton> createState() => _GameRoundButtonState();
}

class _GameRoundButtonState extends State<GameRoundButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: Material(
            color: widget.surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: widget.onTap,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Icon(
                  widget.icon,
                  size: widget.size * 0.46,
                  color: widget.iconColor ?? widget.color,
                ),
              ),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: AppDimensions.spacingS),
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: widget.color,
            ),
          ),
        ],
      ],
    );
  }
}

class GameResultStat {
  const GameResultStat(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;
}

/// Итог раунда — в том же формате, что и итог основной игры
/// ([GameOverDialog]): обложка, заголовок, счёт со звездой, рекорд, три цифры,
/// «Попробовать снова», ошибки и «Выйти». Кладётся на весь экран поверх игры.
class GameResultOverlay extends StatelessWidget {
  const GameResultOverlay({
    super.key,
    required this.art,
    required this.title,
    required this.score,
    required this.bestScore,
    required this.isNewRecord,
    required this.stats,
    required this.onRestart,
    required this.onExit,
    this.mistakesCount = 0,
    this.onMistakes,
  });

  final Widget art;
  final String title;
  final int score;

  /// Рекорд до этого раунда — показывается, если новый не поставлен.
  final int bestScore;
  final bool isNewRecord;
  final List<GameResultStat> stats;
  final VoidCallback onRestart;
  final VoidCallback onExit;
  final int mistakesCount;
  final VoidCallback? onMistakes;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      color: const Color(0x80000000),
      child: Center(
        child: Dialog(
          backgroundColor: colors.cardBackground,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusExtraLarge),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          clipBehavior: Clip.antiAlias,
          constraints: const BoxConstraints(maxWidth: 420),
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppDimensions.buttonRadius,
                        ),
                        child: AspectRatio(aspectRatio: 16 / 9, child: art),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Semantics(
                        label: '${appL10n.gameScore}: $score',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 40,
                              color: colors.gold,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$score',
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                color: colors.gold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isNewRecord) ...[
                        const SizedBox(height: 6),
                        Center(child: GameRecordBadge(color: colors.gold)),
                      ] else if (bestScore > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          appL10n.gameBestScore(bestScore),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.secondaryText,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          for (final stat in stats)
                            Expanded(
                              child: GameMiniStat(
                                value: stat.value,
                                label: stat.label,
                                color: stat.color,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton(
                        onPressed: () {
                          HapticFeedbackHelper.tap();
                          onRestart();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.accent,
                          foregroundColor: colors.white,
                          elevation: 0,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppDimensions.radiusMedium,
                            ),
                          ),
                        ),
                        child: Text(
                          appL10n.gameRestart,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (mistakesCount > 0 && onMistakes != null) ...[
                        const SizedBox(height: 8),
                        GameSecondaryButton(
                          icon: Icons.error_outline_rounded,
                          label: appL10n.gameRunMistakesButton(mistakesCount),
                          color: colors.red,
                          onPressed: onMistakes!,
                        ),
                      ],
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () {
                          HapticFeedbackHelper.tap();
                          onExit();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: colors.secondaryText,
                          minimumSize: const Size.fromHeight(44),
                        ),
                        child: Text(
                          appL10n.gameExit,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isNewRecord)
                const Positioned.fill(
                  child: IgnorePointer(child: ConfettiBurst()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
