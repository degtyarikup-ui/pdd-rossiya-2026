import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Эмблема игры «Знаки» для завершающего экрана результатов (GameResultOverlay).
/// Композиция из 4 дорожных знаков (Главная дорога, Уступи дорогу, Въезд запрещен, Пешеходный переход).
class RoadSignsEmblem extends StatelessWidget {
  const RoadSignsEmblem({super.key});

  static const _signAssets = [
    'assets/countries/ru/images/signs/c56c59646b12f56cc259a0c240446ddb.svg', // 2.1
    'assets/countries/ru/images/signs/cc8922782f1e3262ac4dfbb3fbe8cbe6.svg', // 2.4
    'assets/countries/ru/images/signs/9f77764c15a21428b8e6e7f5c75936e2.svg', // 3.1
    'assets/countries/ru/images/signs/5e5e79df8b8d44ac07e95737a9071eb1.svg', // 5.19.1
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(
          constraints.maxHeight * 0.75,
          constraints.maxWidth * 0.75,
        ).clamp(80.0, 180.0);
        final itemSize = size * 0.46;

        Widget signBox(String asset) {
          return SizedBox.square(
            dimension: itemSize,
            child: SvgPicture.asset(
              asset,
              fit: BoxFit.contain,
            ),
          );
        }

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Верхний левый знак (2.1)
              Transform.translate(
                offset: Offset(-size * 0.22, -size * 0.22),
                child: Transform.rotate(
                  angle: -0.08,
                  child: signBox(_signAssets[0]),
                ),
              ),
              // Верхний правый знак (2.4)
              Transform.translate(
                offset: Offset(size * 0.22, -size * 0.20),
                child: Transform.rotate(
                  angle: 0.08,
                  child: signBox(_signAssets[1]),
                ),
              ),
              // Нижний левый знак (3.1)
              Transform.translate(
                offset: Offset(-size * 0.20, size * 0.22),
                child: Transform.rotate(
                  angle: 0.06,
                  child: signBox(_signAssets[2]),
                ),
              ),
              // Нижний правый знак (5.19.1)
              Transform.translate(
                offset: Offset(size * 0.22, size * 0.20),
                child: Transform.rotate(
                  angle: -0.06,
                  child: signBox(_signAssets[3]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
