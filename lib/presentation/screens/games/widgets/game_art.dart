import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Карточки используют подготовленный blur; результаты — чёткий оригинал.
class TrafficControllerArt extends StatelessWidget {
  const TrafficControllerArt({super.key, this.forCard = false});

  final bool forCard;

  @override
  Widget build(BuildContext context) => _GameCoverImage(
    asset:
        'assets/images/games/traffic_controller_${forCard ? 'card' : 'cover'}.webp',
  );
}

class SignSwiperArt extends StatelessWidget {
  const SignSwiperArt({super.key, this.forCard = false});

  final bool forCard;

  @override
  Widget build(BuildContext context) => _GameCoverImage(
    asset: 'assets/images/games/sign_swiper_${forCard ? 'card' : 'cover'}.webp',
  );
}

class CrossroadsArt extends StatelessWidget {
  const CrossroadsArt({super.key, this.forCard = false});

  final bool forCard;

  @override
  Widget build(BuildContext context) => _GameCoverImage(
    asset: 'assets/images/games/crossroads_${forCard ? 'card' : 'cover'}.webp',
  );
}

class CityArt extends StatelessWidget {
  const CityArt({super.key, this.forCard = false});
  final bool forCard;
  @override
  Widget build(BuildContext context) => _GameCoverImage(
    asset: 'assets/images/games/city_${forCard ? 'card' : 'cover'}.webp',
  );
}

/// Неактивная карточка уже обесцвечена при подготовке ассета.
class RoundaboutArt extends StatelessWidget {
  const RoundaboutArt({super.key, this.forCard = false});

  final bool forCard;

  @override
  Widget build(BuildContext context) => _GameCoverImage(
    asset: 'assets/images/games/roundabout_${forCard ? 'card' : 'cover'}.webp',
  );
}

class _GameCoverImage extends StatelessWidget {
  const _GameCoverImage({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 480.0;
        final heightWidth = constraints.hasBoundedHeight
            ? constraints.maxHeight * 16 / 9
            : width;
        final pixels =
            math.max(width, heightWidth) *
            MediaQuery.devicePixelRatioOf(context);
        // Три стабильных размера сохраняют общий image cache между экранами.
        // На обычном телефоне — 480/720 px, на плотном дисплее — не более 960.
        final decodeWidth = pixels <= 480 ? 480 : (pixels <= 720 ? 720 : 960);
        return Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          cacheWidth: decodeWidth,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        );
      },
    );
  }
}
