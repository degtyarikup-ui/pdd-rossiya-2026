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
                    ? colors.green.withValues(alpha: 0.15)
                    : colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    wasAnswerCorrect! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: wasAnswerCorrect! ? colors.green : colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      wasAnswerCorrect! ? appL10n.gameCorrect : appL10n.gameWrong,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: wasAnswerCorrect! ? colors.green : colors.red,
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
                              color: colors.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '«${sign.folkName}»',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.gold,
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
            Row(
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  size: 15,
                  color: colors.secondaryText,
                ),
                const SizedBox(width: 6),
                Text(
                  appL10n.gamePddOfficialText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.homeScreenBackground.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.divider),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(
                    _formatPddDescription(sign.description),
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.primaryText.withValues(alpha: 0.9),
                      height: 1.45,
                    ),
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
              onNext != null ? appL10n.gameSignSwiperNext : appL10n.gameUnderstood,
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

  static String _formatPddDescription(String raw) {
    if (raw.isEmpty) return raw;

    // 1. Нормализация неразрывных пробелов и переводов строк
    var text = raw.replaceAll('\u00a0', ' ').replaceAll('\r', '').trim();

    // 2. Исправление склеенных предложений (точка/скобка перед заглавной буквой)
    text = text.replaceAllMapped(
      RegExp(r'(\))\.(?=[А-ЯЁ])'),
      (m) => '). ',
    );
    text = text.replaceAllMapped(
      RegExp(r'(?<=[а-яё\w])\.(?=[А-ЯЁ])'),
      (m) => '. ',
    );
    text = text.replaceAllMapped(
      RegExp(r':(?=[а-яА-Я0-9])'),
      (m) => ': ',
    );

    // 3. Выделение стандартных смысловых разделов ПДД с новой строки
    const sections = [
      'Зона действия знака:',
      'Зона действия:',
      'От действия знака отступают:',
      'Запрещается:',
      'Разрешается:',
      'Особенности:',
      'Наказание за нарушение требований знака:',
      'Наказание:',
      'КоАП РФ',
    ];
    for (final s in sections) {
      if (text.contains(s)) {
        text = text.replaceAll(s, '\n\n$s\n');
      }
    }

    // 4. Разделение нумерованных пунктов (1. 2. 3. ...)
    text = text.replaceAllMapped(
      RegExp(r'(?<=\S)\s*(\d+\.\s+)'),
      (m) => '\n\n${m[1]}',
    );

    // 5. Разделение подпунктов (а) б) в) г) ...) на маркированные строки
    text = text.replaceAllMapped(
      RegExp(r'(?<=[:;\n])\s*([а-иa-d])\)\s*'),
      (m) => '\n  • ',
    );
    text = text.replaceAllMapped(
      RegExp(r';\s*([а-иa-d])\)\s*'),
      (m) => ';\n  • ',
    );

    // 6. Очистка лишних повторяющихся пустых строк
    final lines = text.split('\n').map((l) => l.trimRight()).toList();
    final cleaned = <String>[];
    for (final line in lines) {
      if (line.isNotEmpty) {
        cleaned.add(line);
      } else if (cleaned.isNotEmpty && cleaned.last.isNotEmpty) {
        cleaned.add('');
      }
    }

    return cleaned.join('\n').trim();
  }
}
