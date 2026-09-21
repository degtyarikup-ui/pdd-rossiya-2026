import 'package:pdd_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';

class GameQuestionCard extends StatelessWidget {
  final GameState state;
  final ValueChanged<int> onSelectAnswer;

  const GameQuestionCard({
    super.key,
    required this.state,
    required this.onSelectAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final situation = state.currentSituation;
    if (situation == null) return const SizedBox.shrink();

    final isAnswered =
        state.selectedAnswerIndex != null ||
        state.phase == GamePhase.explanation ||
        state.phase == GamePhase.resolving;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimensions.cardRadius),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.44,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header: Ticket label & Timer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accentSurface10,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.smallRadius,
                          ),
                        ),
                        child: Text(
                          situation.ticket,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 15,
                          color: state.remainingSeconds <= 3
                              ? colors.red
                              : colors.secondaryText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${state.remainingSeconds.toStringAsFixed(1)} ${appL10n.gameSeconds}',
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: state.remainingSeconds <= 3
                                ? colors.red
                                : colors.primaryText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Timer Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3.5,
                    child: LinearProgressIndicator(
                      value: state.timerProgress,
                      backgroundColor: colors.gray,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        state.remainingSeconds <= 3
                            ? colors.red
                            : (state.remainingSeconds <= 6
                                  ? colors.gold
                                  : colors.accent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Question Text
                Text(
                  situation.title,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),

                // Answer Options
                ...List.generate(situation.options.length, (index) {
                  final optionText = situation.options[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == situation.options.length - 1 ? 0 : 6,
                    ),
                    child: _OptionButton(
                      index: index,
                      text: optionText,
                      isAnswered: isAnswered,
                      isSelected: state.selectedAnswerIndex == index,
                      isCorrectOption: index == situation.correctAnswerIndex,
                      onTap: isAnswered ? null : () => onSelectAnswer(index),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final int index;
  final String text;
  final bool isAnswered;
  final bool isSelected;
  final bool isCorrectOption;
  final VoidCallback? onTap;

  const _OptionButton({
    required this.index,
    required this.text,
    required this.isAnswered,
    required this.isSelected,
    required this.isCorrectOption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    Color backgroundColor;
    Color textColor;

    if (isAnswered) {
      if (isCorrectOption) {
        backgroundColor = colors.green;
        textColor = AppColors.white;
      } else if (isSelected) {
        backgroundColor = colors.red;
        textColor = AppColors.white;
      } else {
        backgroundColor = colors.searchFieldFill;
        textColor = colors.secondaryText;
      }
    } else {
      backgroundColor = colors.searchFieldFill;
      textColor = colors.primaryText;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isAnswered
                      ? (isCorrectOption || isSelected
                            ? AppColors.white.withValues(alpha: 0.28)
                            : colors.gray)
                      : colors.gray,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isAnswered && isCorrectOption
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.white,
                          size: 16,
                        )
                      : isAnswered && isSelected
                      ? const Icon(
                          Icons.close_rounded,
                          color: AppColors.white,
                          size: 16,
                        )
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isAnswered
                                ? colors.secondaryText
                                : colors.primaryText,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                    height: 1.3,
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
