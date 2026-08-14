import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';

/// Чип номера вопроса в верхней навигационной полоске.
///
/// Единый вид для экзамена и обучения (билеты/ошибки/избранное/темы) — форма,
/// размер и типографика живут здесь, чтобы экраны не расходились.
///
/// Цвет плашки задаёт вызывающий экран: семантика состояний у них разная
/// (экзамен прячет верность ответа, обучение показывает green/red). А правило
/// цвета ЦИФРЫ общее и зашито в виджете: на нейтральной («предстоящей»/серой)
/// плашке цифра приглушённая ([AppColors.secondaryText]), на любой цветной —
/// белая. Так «будущие» номера везде выглядят одинаково.
class QuestionNumberChip extends StatelessWidget {
  const QuestionNumberChip({
    super.key,
    required this.number,
    required this.backgroundColor,
    required this.muted,
    required this.onTap,
  });

  /// Отображаемый номер (1-based).
  final int number;

  /// Цвет плашки — решает экран по состоянию вопроса.
  final Color backgroundColor;

  /// true — нейтральный/предстоящий чип (серая цифра); false — белая.
  final bool muted;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: muted ? AppColors.secondaryText : AppColors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
