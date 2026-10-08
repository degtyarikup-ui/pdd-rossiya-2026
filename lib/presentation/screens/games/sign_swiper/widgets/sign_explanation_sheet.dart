import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';

/// Шторка с разбором знака: что он значит и что говорит ПДД.
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

  /// Закрытие шторки жестом или тапом по фону тоже ведёт к [onNext] —
  /// иначе игра осталась бы ждать ответа.
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
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusExtraLarge),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        AppDimensions.spacingM,
        AppDimensions.screenPadding,
        MediaQuery.paddingOf(context).bottom + AppDimensions.screenPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.gray,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          if (wasAnswerCorrect != null) ...[
            Text(
              wasAnswerCorrect! ? appL10n.gameCorrect : appL10n.gameAnswerWrong,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: wasAnswerCorrect! ? colors.green : colors.red,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingM),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: sign.image.endsWith('.svg')
                    ? SvgPicture.asset(sign.assetPath, fit: BoxFit.contain)
                    : Image.asset(sign.assetPath, fit: BoxFit.contain),
              ),
              const SizedBox(width: AppDimensions.spacingL),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sign.folkName != null
                          ? '${sign.number} · «${sign.folkName}»'
                          : sign.number,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sign.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: colors.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingL),
          Text(
            card.explanation,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: colors.primaryText,
            ),
          ),
          if (sign.description.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.spacingL),
            Text(
              appL10n.gamePddOfficialText,
              style: TextStyle(fontSize: 12, color: colors.secondaryText),
            ),
            const SizedBox(height: AppDimensions.spacingS),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(
                  _formatPddDescription(sign.description),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: colors.primaryText.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppDimensions.spacingXL),
          GameActionButton(
            label: onNext != null
                ? appL10n.gameSignSwiperNext
                : appL10n.gameUnderstood,
            background: colors.accent,
            foreground: colors.white,
            onTap: () {
              Navigator.of(context).pop();
              onNext?.call();
            },
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
    text = text.replaceAllMapped(RegExp(r'(\))\.(?=[А-ЯЁ])'), (m) => '). ');
    text = text.replaceAllMapped(
      RegExp(r'(?<=[а-яё\w])\.(?=[А-ЯЁ])'),
      (m) => '. ',
    );
    text = text.replaceAllMapped(RegExp(r':(?=[а-яА-Я0-9])'), (m) => ': ');

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
