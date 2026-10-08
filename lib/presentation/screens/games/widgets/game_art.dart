import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/config/country_config.dart';

/// Игровые обложки в единой обработке: реальная сцена и карточки знаков.

String _sign(String file) => '${CountryConfig.current.signImagesDir}/$file';

// Файл знака из signs.json.
final _roundaboutSign = _sign('58e7e696835bcc69857b61cf990b6151.svg'); // 4.3

/// Обложка на основе настоящего кадра «Регулировщика».
class TrafficControllerArt extends StatelessWidget {
  const TrafficControllerArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/games/traffic_controller_cover.webp',
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );
  }
}

/// Карточки со знаками и направлениями свайпа.
class SignSwiperArt extends StatelessWidget {
  const SignSwiperArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/games/sign_swiper_cover.webp',
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
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
