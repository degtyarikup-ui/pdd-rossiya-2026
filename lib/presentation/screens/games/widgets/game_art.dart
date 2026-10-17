import 'dart:math';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Чёткие WebP-обложки; декодирование ограничено размером карточки.
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
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        );
      },
    );
  }
}

/// Эмблема свайпа знаков для итогового экрана: три настоящих знака
/// (2.4, 2.5, 3.1) веером, без подложек — над синим экраном результатов.
class SignSwiperEmblem extends StatelessWidget {
  const SignSwiperEmblem({super.key});

  static const _signs = [
    'assets/countries/ru/images/signs/cc8922782f1e3262ac4dfbb3fbe8cbe6.svg',
    'assets/countries/ru/images/signs/2bc0f81810c66f9af28b7a7ba506aa56.svg',
    'assets/countries/ru/images/signs/9f77764c15a21428b8e6e7f5c75936e2.svg',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final card = min(
          box.maxHeight * 0.66,
          box.maxWidth / 3.0,
        ).clamp(70.0, 170.0);
        Widget face(String asset, double size) => SizedBox.square(
          dimension: size,
          child: SvgPicture.asset(asset, fit: BoxFit.contain),
        );
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: Offset(-card * 0.9, card * 0.1),
              child: Transform.rotate(
                angle: -0.2,
                child: face(_signs[0], card * 0.82),
              ),
            ),
            Transform.translate(
              offset: Offset(card * 0.9, card * 0.1),
              child: Transform.rotate(
                angle: 0.2,
                child: face(_signs[2], card * 0.82),
              ),
            ),
            face(_signs[1], card),
          ],
        );
      },
    );
  }
}
