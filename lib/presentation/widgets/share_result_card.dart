import 'package:flutter/material.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/presentation/widgets/result_stage.dart';

/// Квадратная карточка результата для шеринга (1080×1080): экзамена, билета,
/// темы.
///
/// Зачем: раньше «Поделиться» отправляло голый текст, а текстом никто не
/// делится. Картинку кидают в чат автошколы и в сторис — это единственный
/// канал, где о приложении узнают бесплатно и без бэкенда.
///
/// Оформление — как у завершающего экрана ([ResultStage]): синий фон с лучами
/// при успехе, красный без лучей при неудаче, эмблема, белая плашка «19/20»,
/// две метрики и готовность к экзамену.
///
/// Виджет НЕ показывается на экране: он рендерится офскрин в PNG
/// (см. ShareCardRenderer), поэтому размеры здесь абсолютные, в пикселях
/// итоговой картинки, а не в логических точках экрана.
class ShareResultCard extends StatelessWidget {
  const ShareResultCard({
    super.key,
    required this.passed,
    required this.correct,
    required this.total,
    required this.wrong,
    required this.readinessPercent,
    required this.title,
    required this.correctLabel,
    required this.wrongLabel,
    required this.readinessLabel,
    required this.siteUrl,
  });

  /// Сдан ли экзамен (пройден ли набор) — от этого зависит фон и эмблема.
  final bool passed;
  final int correct;
  final int total;
  final int wrong;

  /// Готовность к экзамену в процентах (нижняя плашка).
  final int readinessPercent;

  /// Заголовок: «Экзамен сдан!», «Билет 1», название темы.
  final String title;
  final String correctLabel;
  final String wrongLabel;
  final String readinessLabel;
  final String siteUrl;

  /// Сторона итоговой картинки в пикселях.
  static const double side = 1080;

  static const double _margin = 96;
  static const double _emblemTop = 196;
  static const double _emblem = 320;
  static const double _pillTop = 556;
  static const double _pillHeight = 140;

  @override
  Widget build(BuildContext context) {
    final background = passed ? ResultStage.success : ResultStage.failure;
    const dim = Color(0xB3FFFFFF);

    // Шрифт задаём здесь явно, а не наследуем из темы: карточка рендерится
    // офскрин, вне дерева MaterialApp, поэтому ThemeData.fontFamily до неё не
    // доходит — без этого картинка уходила бы в системном шрифте.
    return DefaultTextStyle(
      style: const TextStyle(
        fontFamily: AppTheme.fontFamily,
        color: Colors.white,
        decoration: TextDecoration.none,
      ),
      child: SizedBox(
        width: side,
        height: side,
        child: ColoredBox(
          color: background,
          child: Stack(
            children: [
              if (passed)
                Positioned.fill(
                  child: CustomPaint(
                    painter: ResultRaysPainter(
                      const Offset(side / 2, _pillTop + _pillHeight / 2),
                      -0.1,
                    ),
                  ),
                ),

              // Заголовок в одну строку: длинное название темы ужимается.
              Positioned(
                top: 72,
                left: _margin,
                right: _margin,
                height: 96,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

              // Эмблема со свечением.
              Positioned(
                top: _emblemTop - 60,
                left: 0,
                right: 0,
                height: _emblem + 120,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: _emblemTop,
                left: 0,
                right: 0,
                child: Center(
                  child: ResultVerdictEmblem(passed: passed, size: _emblem),
                ),
              ),

              // Белая плашка «19/20».
              Positioned(
                top: _pillTop,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    height: _pillHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 64),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(_pillHeight / 2),
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        '$correct/$total',
                        style: TextStyle(
                          fontSize: 100,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: background,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Две метрики.
              Positioned(
                top: 744,
                left: _margin,
                right: _margin,
                child: Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        value: '$correct',
                        label: correctLabel,
                        dim: dim,
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        value: '$wrong',
                        label: wrongLabel,
                        dim: dim,
                      ),
                    ),
                  ],
                ),
              ),

              // Готовность — полупрозрачная плашка, как вторичная кнопка экрана.
              Positioned(
                top: 900,
                left: _margin,
                right: _margin,
                child: Container(
                  height: 88,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: const Color(0x2EFFFFFF),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$readinessLabel — $readinessPercent%',
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

              // Подпись сайта: тонкая, не спорит с содержимым.
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Text(
                  siteUrl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w500,
                    color: dim,
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.dim});

  final String value;
  final String label;
  final Color dim;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 76,
            fontWeight: FontWeight.w800,
            height: 1.1,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w500,
              color: dim,
            ),
          ),
        ),
      ],
    );
  }
}
