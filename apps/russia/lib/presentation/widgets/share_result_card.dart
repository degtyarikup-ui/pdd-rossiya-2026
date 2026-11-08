import 'package:flutter/material.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/presentation/widgets/result_stage.dart';

/// Квадратная карточка результата для шеринга (1080×1080): экзамена, билета,
/// темы, игры.
///
/// Зачем: раньше «Поделиться» отправляло голый текст, а текстом никто не
/// делится. Картинку кидают в чат автошколы и в сторис — это единственный
/// канал, где о приложении узнают бесплатно и без бэкенда.
///
/// Оформление — как у завершающего экрана ([ResultStage]): синий фон с лучами
/// при успехе, красный без лучей при неудаче, эмблема, белая плашка («19/20»
/// или очки игры), две метрики и строка внизу (готовность, рекорд).
///
/// Виджет НЕ показывается на экране: он рендерится офскрин в PNG
/// (см. ShareCardRenderer), поэтому размеры здесь абсолютные, в пикселях
/// итоговой картинки, а не в логических точках экрана.
class ShareResultCard extends StatelessWidget {
  const ShareResultCard({
    super.key,
    required this.passed,
    required this.title,
    required this.badge,
    required this.stats,
    required this.siteUrl,
    this.footer,
    this.emblem,
  });

  /// Успех (синий, лучи) или неудача (красный, без лучей).
  final bool passed;

  /// Заголовок: «Экзамен сдан!», «Билет 1», название игры.
  final String title;

  /// Текст белой плашки: «19/20» или очки.
  final String badge;

  /// Две метрики: число и короткая подпись под ним.
  final List<({String value, String label})> stats;

  /// Полупрозрачная строка внизу: готовность к экзамену, рекорд.
  final String? footer;
  final String siteUrl;

  /// Эмблема игры; по умолчанию — галочка или крестик итога учёбы.
  final Widget? emblem;

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
                  child: SizedBox.square(
                    dimension: _emblem,
                    child:
                        emblem ??
                        ResultVerdictEmblem(passed: passed, size: _emblem),
                  ),
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
                        badge,
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
                    for (final stat in stats)
                      Expanded(
                        child: _Stat(
                          value: stat.value,
                          label: stat.label,
                          dim: dim,
                        ),
                      ),
                  ],
                ),
              ),

              // Готовность или рекорд — полупрозрачная плашка, как вторичная
              // кнопка экрана.
              if (footer != null)
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
                        footer!,
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
