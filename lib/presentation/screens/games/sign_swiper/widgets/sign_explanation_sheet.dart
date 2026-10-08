import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Всплывающая карточка/шторка с официальным пояснением знака из базы ПДД.
class SignExplanationSheet extends StatelessWidget {
  final SignCardQuestion card;
  final bool? wasAnswerCorrect;
  final VoidCallback? onNext;

  const SignExplanationSheet({
    super.key,
    required this.card,
    this.wasAnswerCorrect,
    this.onNext,
  });

  static Future<void> show(
    BuildContext context, {
    required SignCardQuestion card,
    bool? wasAnswerCorrect,
    VoidCallback? onNext,
  }) async {
    HapticFeedbackHelper.tap();
    bool nextHandled = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SignExplanationSheet(
        card: card,
        wasAnswerCorrect: wasAnswerCorrect,
        onNext: onNext != null
            ? () {
                nextHandled = true;
                onNext();
              }
            : null,
      ),
    );
    if (!nextHandled && onNext != null) {
      onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final sign = card.sign;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Результат ответа (если указан)
          if (wasAnswerCorrect != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: wasAnswerCorrect!
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    wasAnswerCorrect! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: wasAnswerCorrect! ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      wasAnswerCorrect! ? appL10n.gameCorrect : appL10n.gameWrong,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: wasAnswerCorrect! ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Верхняя плашка: знак + название
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.homeScreenBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.divider),
                ),
                child: sign.image.endsWith('.svg')
                    ? SvgPicture.asset(sign.assetPath, fit: BoxFit.contain)
                    : Image.asset(sign.assetPath, fit: BoxFit.contain),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            sign.number,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: colors.accent,
                            ),
                          ),
                        ),
                        if (sign.folkName != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '«${sign.folkName}»',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      sign.title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sign.category,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Пояснение ответа карточки
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.homeScreenBackground.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              card.explanation,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Официальный текст ПДД
          if (sign.description.isNotEmpty) ...[
            Text(
              'ПДД РФ:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Text(
                  sign.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.primaryText.withValues(alpha: 0.85),
                    height: 1.35,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Кнопка закрытия / перехода дальше
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              onNext?.call();
            },
            child: Text(
              onNext != null ? appL10n.gameSignSwiperNext : 'Понятно',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
