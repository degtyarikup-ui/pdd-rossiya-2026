import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';

/// Модальное окно «Детали ответа» викторины «Знаки», в точности соответствующее
/// референсу (reference_signs_modal.png).
class RoadSignsModal extends StatefulWidget {
  final RoadSignAnswerResult result;
  final VoidCallback onContinue;

  const RoadSignsModal({
    super.key,
    required this.result,
    required this.onContinue,
  });

  /// Открытие модального окна с гарантией вызова [onContinue] ровно один раз.
  static Future<void> show(
    BuildContext context, {
    required RoadSignAnswerResult result,
    required VoidCallback onContinue,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return RoadSignsModal(
          result: result,
          onContinue: onContinue,
        );
      },
    );
  }

  @override
  State<RoadSignsModal> createState() => _RoadSignsModalState();
}

class _RoadSignsModalState extends State<RoadSignsModal> {
  bool _continued = false;

  void _triggerContinue() {
    if (!_continued) {
      _continued = true;
      Navigator.of(context, rootNavigator: true).pop();
      widget.onContinue();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final question = widget.result.question;
    final isCorrect = widget.result.isCorrect;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_continued) {
          _continued = true;
          widget.onContinue();
        }
      },
      child: Dialog(
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusExtraLarge),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Шапка: Иконка документа, «Детали ответа», крестик закрытия
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.lightAccent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.assignment_outlined,
                        size: 20,
                        color: colors.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        appL10n.gameAnswerDetails,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: colors.secondaryText,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: _triggerContinue,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Текст вопроса
                Text(
                  question.prompt,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Горизонтальный ряд из 4 миниатюр вариантов ответа
                Row(
                  children: [
                    for (int i = 0; i < question.options.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                          child: _buildMiniSignCard(
                            sign: question.options[i],
                            isCorrectOption: i == question.correctAnswerIndex,
                            isUserSelectedWrong: !isCorrect && i == widget.result.selectedIndex,
                            colors: colors,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4. Индикатор статуса ответа
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      isCorrect
                          ? '✓ ${appL10n.gameAnswerCorrectStatus}'
                          : '✕ ${appL10n.gameAnswerWrongStatus}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isCorrect ? colors.green : colors.red,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // 5. Карточка ошибочного выбора игрока (только если неверно)
                if (!isCorrect) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: colors.redLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 64,
                          child: SvgPicture.asset(
                            widget.result.selectedSign.assetPath,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '✕ ${appL10n.gameYourChoiceSign(widget.result.selectedSign.number)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 6. Блок правильного ответа
                Text(
                  appL10n.gameCorrectAnswerSection,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: colors.gray,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 76,
                        child: SvgPicture.asset(
                          widget.result.correctSign.assetPath,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.result.correctSign.number} «${widget.result.correctSign.title}»',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 7. Дословная официальная цитата правил ПДД РФ
                Text(
                  question.officialRuleQuote,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: 20),

                // 8. Кнопка «Продолжить»
                GameActionButton(
                  onTap: _triggerContinue,
                  label: appL10n.continueButton,
                  background: colors.accent,
                  foreground: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniSignCard({
    required SignItem sign,
    required bool isCorrectOption,
    required bool isUserSelectedWrong,
    required AppThemeColors colors,
  }) {
    final Color bgColor;
    final Border border;

    if (isCorrectOption) {
      bgColor = colors.greenLight;
      border = Border.all(color: colors.green, width: 2);
    } else if (isUserSelectedWrong) {
      bgColor = colors.redLight;
      border = Border.all(color: colors.red, width: 2);
    } else {
      bgColor = colors.gray;
      border = Border.all(color: colors.divider.withValues(alpha: 0.4), width: 1);
    }

    return Container(
      height: 60,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: Center(
        child: SvgPicture.asset(
          sign.assetPath,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
