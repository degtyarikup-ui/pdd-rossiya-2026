import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/config/country_config.dart';

/// Обложки игр. Только настоящий контент: кадр из 3D-сцены регулировщика
/// и знаки из базы — никаких нарисованных «по мотивам» картинок.

String _sign(String file) => '${CountryConfig.current.signImagesDir}/$file';

// Файлы знаков из signs.json.
final _stopSign = _sign('2bc0f81810c66f9af28b7a7ba506aa56.svg'); // 2.5
final _noEntrySign = _sign('9f77764c15a21428b8e6e7f5c75936e2.svg'); // 3.1
final _yieldSign = _sign('cc8922782f1e3262ac4dfbb3fbe8cbe6.svg'); // 2.4
final _roundaboutSign = _sign('58e7e696835bcc69857b61cf990b6151.svg'); // 4.3

/// Кадр из сцены «Регулировщика» с места водителя.
class TrafficControllerArt extends StatelessWidget {
  const TrafficControllerArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/games/traffic_controller.webp',
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );
  }
}

/// Веер из трёх знаков — как колода карточек «Знак-Свайпера».
class SignSwiperArt extends StatelessWidget {
  const SignSwiperArt({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(
          constraints.maxHeight * 0.6,
          constraints.maxWidth * 0.22,
        );
        Widget sign(String path, double angle, double dx) =>
            Transform.translate(
              offset: Offset(dx * side, 0),
              child: Transform.rotate(
                angle: angle,
                child: SvgPicture.asset(path, width: side, height: side),
              ),
            );
        return Stack(
          alignment: Alignment.center,
          children: [
            sign(_noEntrySign, -0.22, -1.05),
            sign(_yieldSign, 0.22, 1.05),
            sign(_stopSign, 0, 0),
          ],
        );
      },
    );
  }
}

/// Знак 4.3 «Круговое движение» для игры, которая скоро появится.
class RoundaboutArt extends StatelessWidget {
  const RoundaboutArt({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            math.min(constraints.maxHeight, constraints.maxWidth) * 0.6;
        return Center(
          child: SvgPicture.asset(_roundaboutSign, width: side, height: side),
        );
      },
    );
  }
}
