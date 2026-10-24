import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Four equal targets. Feedback never changes their size or position.
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
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppDimensions.spacingM;
        final side = math.max(
          0.0,
          (math.min(constraints.maxWidth, constraints.maxHeight) - gap) / 2,
        );
        return Center(
          child: SizedBox.square(
            dimension: side * 2 + gap,
            child: Column(
              children: [
                for (var row = 0; row < 2; row++) ...[
                  if (row > 0) const SizedBox(height: gap),
                  Row(
                    children: [
                      for (var column = 0; column < 2; column++) ...[
                        if (column > 0) const SizedBox(width: gap),
                        _card(row * 2 + column, side, colors, duration),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _card(
    int index,
    double side,
    AppThemeColors colors,
    Duration duration,
  ) {
    final answered = selectedIndex != null;
    final selected = selectedIndex == index;
    final correct = answered && correctIndex == index;
    final wrong = selected && isCorrect == false;
    final status = correct
        ? appL10n.gameCorrectAnswer
        : wrong
        ? appL10n.gameAnswerWrong
        : null;
    final surface = correct
        ? colors.greenLight
        : wrong
        ? colors.redLight
        : colors.cardBackground;
    final radius = BorderRadius.circular(AppDimensions.cardRadius);

    return Semantics(
      key: ValueKey('road-sign-option-$index'),
      button: true,
      onTap: isEnabled ? () => onSelectOption(index) : null,
      enabled: isEnabled,
      selected: selected,
      // Describe the choice without giving away its name before answering.
      label: appL10n.roadSignsOption(index + 1),
      value: status,
      child: SizedBox.square(
        dimension: side,
        child: Material(
          color: surface,
          animationDuration: duration,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isEnabled ? () => onSelectOption(index) : null,
            excludeFromSemantics: true,
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (isEnabled &&
                  (states.contains(WidgetState.focused) ||
                      states.contains(WidgetState.hovered))) {
                return colors.accent.withValues(alpha: 0.08);
              }
              return Colors.transparent;
            }),
            child: ExcludeSemantics(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: answered && !selected && !correct ? 0.45 : 1,
                      duration: duration,
                      child: Padding(
                        padding: EdgeInsets.all(side * 0.20),
                        child: SvgPicture.asset(
                          options[index].assetPath,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 14,
                    child: Text(
                      '${index + 1}',
                      // Like the corner icon, this decorative index must not
                      // grow over the sign; its accessible label is above.
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                  if (correct || wrong)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: correct ? colors.green : colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          correct ? Icons.check_rounded : Icons.close_rounded,
                          size: 18,
                          color: colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
