import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// A compact comparison and the official explanation, with a pinned action.
class RoadSignsModal extends StatefulWidget {
  final RoadSignAnswerResult result;
  final VoidCallback onContinue;

  const RoadSignsModal({
    super.key,
    required this.result,
    required this.onContinue,
  });

  static Future<void> show(
    BuildContext context, {
    required RoadSignAnswerResult result,
    required VoidCallback onContinue,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => RoadSignsModal(result: result, onContinue: onContinue),
    );
  }

  @override
  State<RoadSignsModal> createState() => _RoadSignsModalState();
}

class _RoadSignsModalState extends State<RoadSignsModal> {
  bool _continued = false;

  void _triggerContinue() {
    if (_continued) return;
    _continued = true;
    Navigator.of(context, rootNavigator: true).pop();
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final result = widget.result;
    final question = result.question;
    final correct = result.isCorrect;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_continued) {
          _continued = true;
          widget.onContinue();
        }
      },
      child: Dialog(
        elevation: 0,
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusExtraLarge),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appL10n.gameAnswerDetails,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: appL10n.close,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: colors.secondaryText,
                      onPressed: _triggerContinue,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          question.prompt,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                            color: colors.primaryText,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            for (
                              var i = 0;
                              i < question.options.length;
                              i++
                            ) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(child: _miniSign(i, colors)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(
                              correct
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              size: 20,
                              color: correct ? colors.green : colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                correct
                                    ? appL10n.gameAnswerCorrectStatus
                                    : appL10n.gameAnswerWrongStatus,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: colors.primaryText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!correct) ...[
                          const SizedBox(height: 8),
                          Text(
                            appL10n.gameYourChoiceSign(
                              result.selectedSign.number,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.background,
                            borderRadius: BorderRadius.circular(
                              AppDimensions.cardRadius,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appL10n.gameCorrectAnswerSection,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: colors.secondaryText,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${result.correctSign.number} «${result.correctSign.title}»',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                  color: colors.primaryText,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                question.officialRuleQuote,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: colors.primaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _triggerContinue,
                  child: Text(appL10n.continueButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniSign(int index, AppThemeColors colors) {
    final result = widget.result;
    final correct = index == result.question.correctAnswerIndex;
    final wrong = !result.isCorrect && index == result.selectedIndex;
    return Semantics(
      label: appL10n.roadSignsSignNumber(result.question.options[index].number),
      value: correct
          ? appL10n.gameCorrectAnswer
          : wrong
          ? appL10n.gameAnswerWrong
          : null,
      child: Container(
        key: ValueKey('road-sign-review-$index'),
        height: 76,
        decoration: BoxDecoration(
          color: correct
              ? colors.greenLight
              : wrong
              ? colors.redLight
              : colors.background,
          borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SvgPicture.asset(
                  result.question.options[index].assetPath,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ),
            ),
            if (correct || wrong)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 16,
                  color: correct ? colors.green : colors.red,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
