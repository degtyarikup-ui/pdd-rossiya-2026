import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';

/// Ограничитель ширины контента для широких экранов (планшеты, веб).
///
/// На телефонах (< [maxContentWidth]) — рендерим как есть, без изменений.
/// На широких — центруем контент в колонке заданной ширины, по бокам
/// нейтральный фон, чтобы UI выглядел как «телефон в окне», а не растянутая
/// мобильная вёрстка.
class AppMaxWidthFrame extends StatelessWidget {
  final Widget? child;

  /// Максимальная ширина контентной колонки. Подобрано с запасом —
  /// чуть шире типичного современного телефона (390-430), чтобы не было
  /// заметной разницы между мобильным и десктоп-вьюпортом.
  static const double maxContentWidth = 480;

  const AppMaxWidthFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    // На телефонах оставляем как есть — никаких накладных расходов на frame.
    if (width <= maxContentWidth) {
      return child ?? const SizedBox.shrink();
    }

    final colors = AppColors.of(context);
    return ColoredBox(
      color: colors.isDark ? Colors.black : colors.divider,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: ClipRect(
            child: Material(
              color: colors.background,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
