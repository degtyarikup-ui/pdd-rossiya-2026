import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/theme/app_theme.dart';

/// Квадратная карточка результата экзамена для шеринга (1080×1080).
///
/// Зачем: раньше «Поделиться» отправляло голый текст, а текстом никто не
/// делится. Картинку кидают в чат автошколы и в сторис — это единственный
/// канал, где о приложении узнают бесплатно и без бэкенда.
///
/// Виджет НЕ показывается на экране: он рендерится офскрин в PNG
/// (см. [ShareCardRenderer]), поэтому размеры здесь абсолютные, в пикселях
/// итоговой картинки, а не в логических точках экрана.
class ShareResultCard extends StatelessWidget {
  const ShareResultCard({
    super.key,
    required this.passed,
    required this.correct,
    required this.wrong,
    required this.readinessPercent,
    required this.title,
    required this.correctLabel,
    required this.wrongLabel,
    required this.readinessLabel,
    required this.siteUrl,
  });

  /// Сдан ли экзамен — от этого зависит цвет и иконка.
  final bool passed;
  final int correct;
  final int wrong;

  /// Готовность к экзамену в процентах (нижняя плашка).
  final int readinessPercent;

  /// Заголовок («Экзамен сдан» / «Экзамен не сдан»).
  final String title;
  final String correctLabel;
  final String wrongLabel;
  final String readinessLabel;
  final String siteUrl;

  /// Сторона итоговой картинки в пикселях.
  static const double side = 1080;

  // Геометрия макета. Отступ между карточками статистики по горизонтали и
  // от них до плашки готовности по вертикали ОДИНАКОВЫЙ — 48; из-за этого
  // ширина карточки 406, а не круглые 400: 406 + 48 + 406 = 860 = ширина
  // за вычетом полей по 110.
  static const double _margin = 110;
  static const double _gap = 48;
  static const double _statWidth = 406;
  static const double _statHeight = 185;

  @override
  Widget build(BuildContext context) {
    final accentColor = passed ? AppColors.green : AppColors.red;

    // Шрифт задаём здесь явно, а не наследуем из темы: карточка рендерится
    // офскрин (см. ShareCardRenderer), вне дерева MaterialApp, поэтому
    // ThemeData.fontFamily до неё не доходит — без этого картинка уходила бы
    // в системном шрифте вместо фирменного.
    return DefaultTextStyle(
      style: const TextStyle(
        fontFamily: AppTheme.fontFamily,
        color: AppColors.primaryText,
        decoration: TextDecoration.none,
      ),
      child: SizedBox(
        width: side,
        height: side,
        child: Container(
          color: AppColors.background,
          child: Stack(
            children: [
              // Круг с галочкой / крестиком.
              Positioned(
                top: 128,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 204,
                    height: 204,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      passed ? Icons.check_rounded : Icons.close_rounded,
                      // Скруглённая иконка размером примерно в 40% круга —
                      // она не должна забивать собой всю плашку.
                      size: 108,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),

              // Заголовок.
              Positioned(
                top: 380,
                left: _margin,
                right: _margin,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 96,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                    height: 1.1,
                  ),
                ),
              ),

              // Две карточки статистики.
              Positioned(
                top: 575,
                left: _margin,
                child: _StatBox(
                  value: '$correct',
                  label: correctLabel,
                  color: AppColors.green,
                  background: AppColors.homeGreenSurface,
                ),
              ),
              Positioned(
                top: 575,
                left: _margin + _statWidth + _gap,
                child: _StatBox(
                  value: '$wrong',
                  label: wrongLabel,
                  color: AppColors.red,
                  background: AppColors.homeRedSurface,
                ),
              ),

              // Плашка готовности — тот же зазор 48 от карточек выше.
              Positioned(
                top: 575 + _statHeight + _gap,
                left: _margin,
                right: _margin,
                child: Container(
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.lightAccent,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Text(
                    '$readinessLabel — $readinessPercent%',
                    style: const TextStyle(
                      fontSize: 50,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),

              // Подпись сайта: тонкая, не спорит с содержимым.
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: Text(
                  siteUrl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w400,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.value,
    required this.label,
    required this.color,
    required this.background,
  });

  final String value;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ShareResultCard._statWidth,
      height: ShareResultCard._statHeight,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 66,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 36,
              // Подпись обычного начертания — жирный здесь только у цифры.
              fontWeight: FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
