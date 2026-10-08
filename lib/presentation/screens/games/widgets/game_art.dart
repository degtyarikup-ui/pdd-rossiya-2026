import 'package:flutter/material.dart';

/// Игровые обложки в единой обработке: реальная сцена и карточки знаков.

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

/// Круговое движение; недоступное состояние задаёт сама карточка.
class RoundaboutArt extends StatelessWidget {
  const RoundaboutArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/games/roundabout_cover.webp',
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );
  }
}
