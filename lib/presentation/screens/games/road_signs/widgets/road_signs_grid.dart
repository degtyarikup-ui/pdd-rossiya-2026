import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';

/// Сетка из 4 карточек дорожных знаков (2x2) для выбора ответа.
class RoadSignsGrid extends StatelessWidget {
  final List<SignItem> options;
  final ValueChanged<int> onSelectOption;
  final bool isEnabled;
  final int? selectedIndex;
  final int? correctIndex;
  final bool? isCorrect;

  const RoadSignsGrid({
    super.key,
    required this.options,
    required this.onSelectOption,
    this.isEnabled = true,
    this.selectedIndex,
    this.correctIndex,
    this.isCorrect,
  }) : assert(options.length == 4, 'RoadSignsGrid requires exactly 4 options');

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        // Определяем размер карточки, чтобы 2x2 идеально помещались
        const gap = AppDimensions.spacingM; // 12px
        final itemWidth = (availableWidth - gap) / 2;
        final itemHeight = (availableHeight - gap) / 2;
        final side = itemWidth < itemHeight ? itemWidth : itemHeight;

        return Center(
          child: SizedBox(
            width: side * 2 + gap,
            height: side * 2 + gap,
            child: Column(
              children: [
                Row(
                  children: [
                    _buildCard(0, side, colors),
                    const SizedBox(width: gap),
                    _buildCard(1, side, colors),
                  ],
                ),
                const SizedBox(height: gap),
                Row(
                  children: [
                    _buildCard(2, side, colors),
                    const SizedBox(width: gap),
                    _buildCard(3, side, colors),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(int index, double side, AppThemeColors colors) {
    final sign = options[index];
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
          borderWidth = 2.5;
        } else {
          borderColor = colors.red;
          backgroundColor = colors.redLight.withValues(alpha: 0.35);
          borderWidth = 2.5;
        }
      } else if (isCorrect == false && isTarget) {
        borderColor = colors.green;
        backgroundColor = colors.greenLight.withValues(alpha: 0.35);
        borderWidth = 2.5;
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
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            boxShadow: gameSoftShadow(colors),
            border: Border.all(
              color: borderColor,
              width: borderWidth,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.spacingL),
            child: Center(
              child: SvgPicture.asset(
                sign.assetPath,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
