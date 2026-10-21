import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';

/// Виджет обратного вопроса викторины «Знаки»:
/// Сверху крупное изображение знака, снизу вертикальный список из 4 вариантов названий.
class RoadSignsReverseView extends StatelessWidget {
  final RoadSignQuizQuestion question;
  final ValueChanged<int> onSelectOption;
  final bool isEnabled;
  final int? selectedIndex;
  final int? correctIndex;
  final bool? isCorrect;

  const RoadSignsReverseView({
    super.key,
    required this.question,
    required this.onSelectOption,
    this.isEnabled = true,
    this.selectedIndex,
    this.correctIndex,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final sign = question.correctSign;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final compact = screenHeight < 520;
        final signHeight = compact ? 88.0 : 110.0;

        return Column(
          children: [
            // 1. Карточка с крупным изображением дорожного знака и вопросом
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: AppDimensions.spacingL,
                vertical: compact ? AppDimensions.spacingS : AppDimensions.spacingM,
              ),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
                boxShadow: gameSoftShadow(colors),
                border: Border.all(
                  color: colors.divider.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    appL10n.gameReverseSignPrompt,
                    style: TextStyle(
                      fontSize: compact ? 14 : 16,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: compact ? AppDimensions.spacingXS : AppDimensions.spacingS),
                  SizedBox(
                    height: signHeight,
                    child: Center(
                      child: SvgPicture.asset(
                        sign.assetPath,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? AppDimensions.spacingS : AppDimensions.spacingM),
            // 2. 4 вертикальные плашки вариантов ответа
            Expanded(
              child: Column(
                children: [
                  for (int i = 0; i < question.options.length; i++) ...[
                    if (i > 0)
                      SizedBox(height: compact ? AppDimensions.spacingXS : AppDimensions.spacingS),
                    Expanded(
                      child: _buildOptionTile(
                        index: i,
                        option: question.options[i],
                        colors: colors,
                        compact: compact,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOptionTile({
    required int index,
    required SignItem option,
    required AppThemeColors colors,
    required bool compact,
  }) {
    final isSelected = selectedIndex == index;
    final isTarget = correctIndex == index;

    Color borderColor = colors.divider.withValues(alpha: 0.5);
    Color backgroundColor = colors.cardBackground;
    double borderWidth = 1.0;

    if (selectedIndex != null) {
      if (isSelected) {
        if (isCorrect == true) {
          borderColor = colors.green;
          backgroundColor = colors.greenLight.withValues(alpha: 0.35);
          borderWidth = 2.0;
        } else {
          borderColor = colors.red;
          backgroundColor = colors.redLight.withValues(alpha: 0.35);
          borderWidth = 2.0;
        }
      } else if (isCorrect == false && isTarget) {
        borderColor = colors.green;
        backgroundColor = colors.greenLight.withValues(alpha: 0.35);
        borderWidth = 2.0;
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? () => onSelectOption(index) : null,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: double.infinity,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            boxShadow: gameSoftShadow(colors),
            border: Border.all(
              color: borderColor,
              width: borderWidth,
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingM,
            vertical: compact ? 6 : 10,
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Container(
                width: compact ? 22 : 26,
                height: compact ? 22 : 26,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isCorrect == true ? colors.green : colors.red)
                      : (isCorrect == false && isTarget ? colors.green : colors.lightAccent),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: compact ? 11 : 13,
                    fontWeight: FontWeight.w700,
                    color: (isSelected || (isCorrect == false && isTarget))
                        ? colors.white
                        : colors.accent,
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Text(
                  option.title.trim(),
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                    height: 1.25,
                  ),
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
