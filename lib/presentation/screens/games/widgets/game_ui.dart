import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdd_app/presentation/widgets/result_stage.dart';

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
  const GameLives({
    super.key,
    required this.lives,
    this.total = 3,
    this.compact = false,
  });

  final int lives;
  final int total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < (compact ? 1 : total); i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
            child: AnimatedScale(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              scale: i < lives ? 1 : 0.85,
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.5, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: Icon(
                  i < lives
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  key: ValueKey(i < lives),
                  size: total > 3 ? 15 : 22,
                  color: i < lives ? colors.red : colors.secondaryText,
                ),
              ),
            ),
          ),
        if (compact) ...[
          const SizedBox(width: 4),
          Text(
            '$lives',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
        ],
      ],
    );
  }
}

/// Счёт блица: число и множитель серии, если он есть.
class GameScoreLabel extends StatelessWidget {
  const GameScoreLabel({
    super.key,
    required this.score,
    this.streak = 0,
    this.shortCombo = false,
  });

  final int score;
  final int streak;
  final bool shortCombo;

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
        if (streak > 1) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.goldLightSurface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              shortCombo ? '×$streak' : appL10n.gameCurrentCombo(streak),
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
    this.inline = false,
  });

  final int secondsLeft;
  final int totalSeconds;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fraction = (secondsLeft / totalSeconds).clamp(0.0, 1.0);
    final urgent = secondsLeft <= 10;
    if (inline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_rounded,
            size: 18,
            color: urgent ? colors.red : colors.secondaryText,
          ),
          const SizedBox(width: 6),
          Text(
            appL10n.gameSecondsLeft(secondsLeft),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: urgent ? colors.red : colors.primaryText,
            ),
          ),
        ],
      );
    }
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
          width: MediaQuery.textScalerOf(context).scale(48),
          child: Text(
            appL10n.gameSecondsLeft(secondsLeft),
            maxLines: 1,
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

typedef GameResultStat = ResultStat;

/// Итог раунда в общем формате завершающих экранов ([ResultStage], как
/// `game_godot/scripts/mini_game_results.gd`): синий фон во весь экран,
/// эмблема игры, золотая плашка со счётом от нуля, две метрики, действия внизу.
class GameResultOverlay extends StatelessWidget {
  const GameResultOverlay({
    super.key,
    required this.emblem,
    required this.title,
    required this.score,
    required this.bestScore,
    required this.isNewRecord,
    required this.stats,
    required this.onRestart,
    required this.onExit,
    this.mistakesCount = 0,
    this.onMistakes,
    this.onShare,
  });

  final Widget emblem;
  final String title;
  final int score;

  /// Рекорд до этого раунда — показывается, если новый не поставлен.
  final int bestScore;
  final bool isNewRecord;

  /// Две метрики под очками; числовые значения считаются от нуля вместе с очками.
  final List<GameResultStat> stats;
  final VoidCallback onRestart;
  final VoidCallback onExit;
  final int mistakesCount;
  final VoidCallback? onMistakes;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return ResultStage(
      background: ResultStage.success,
      title: title,
      emblem: emblem,
      badge: ResultBadge(
        value: score,
        icon: Icons.star_rounded,
        color: AppThemeColors.light.gold,
        foreground: Colors.white,
        semanticsLabel: '${appL10n.gameScore}: $score',
      ),
      caption: isNewRecord
          ? appL10n.gameNewRecord
          : bestScore > 0
          ? appL10n.gameBestScore(bestScore)
          : null,
      captionStrong: isNewRecord,
      stats: stats,
      closeTooltip: appL10n.gameExit,
      onClose: onExit,
      actions: [
        if (mistakesCount > 0 && onMistakes != null)
          ResultButton(
            label: appL10n.gameRunMistakesButton(mistakesCount),
            icon: Icons.error_outline_rounded,
            primary: false,
            onPressed: onMistakes!,
          ),
        ResultButton(
          label: appL10n.share,
          icon: Icons.share_rounded,
          primary: false,
          onPressed: onShare ?? () => _defaultShare(context),
        ),
        ResultButton(
          label: appL10n.gameRestart,
          primary: true,
          onPressed: onRestart,
        ),
      ],
    );
  }

  Future<void> _defaultShare(BuildContext context) async {
    final config = CountryConfig.current;
    final statLines = stats.map((s) => '${s.label}: ${s.value}').join(' · ');
    final details = statLines.isNotEmpty
        ? statLines
        : appL10n.gameShareDetailsScoreOnly(score);
    final resultLine = appL10n.gameShareScore(title, score);
    final text = appL10n.gameShareText(
      resultLine,
      details,
      config.appTitle,
      config.webUrl,
    );
    try {
      final result = await SharePlus.instance.share(ShareParams(text: text));
      if (result.status != ShareResultStatus.unavailable) return;
    } catch (_) {}
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appL10n.copiedToClipboard)));
  }
}
