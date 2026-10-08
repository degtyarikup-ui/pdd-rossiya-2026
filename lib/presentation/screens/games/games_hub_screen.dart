import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/sign_swiper_screen.dart';
import 'package:pdd_app/presentation/screens/games/traffic_controller/traffic_controller_screen.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_art.dart';

class GamesHubScreen extends ConsumerWidget {
  const GamesHubScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    HapticFeedbackHelper.tap();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final traffic = ref.watch(trafficControllerProgressProvider);
    final signs = ref.watch(signSwiperProgressProvider);
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: colors.background,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppDimensions.screenPadding,
          topInset + 16,
          AppDimensions.screenPadding,
          32,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppDimensions.spacingL),
            child: Text(
              appL10n.navGames,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
          ),
          _GameCard(
            art: const TrafficControllerArt(),
            title: appL10n.gameTrafficControllerTitle,
            bestScore: traffic.bestScore,
            onTap: () => _open(context, const TrafficControllerScreen()),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          _GameCard(
            art: const SignSwiperArt(),
            title: appL10n.gameSignSwiperTitle,
            bestScore: signs.bestScore,
            onTap: () => _open(context, const SignSwiperScreen()),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          _GameCard(
            art: const RoundaboutArt(),
            title: appL10n.gameRoundaboutTitle,
          ),
        ],
      ),
    );
  }
}

/// Общая обложка: название и рекорд либо отметка ещё недоступной игры.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.art,
    required this.title,
    this.bestScore,
    this.onTap,
  });

  final Widget art;
  final String title;
  final int? bestScore;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final radius = BorderRadius.circular(AppDimensions.cardRadius);
    final available = onTap != null;
    final status = bestScore == null
        ? appL10n.gameSoonBadge
        : appL10n.gameBestScore(bestScore!);
    final scaler = MediaQuery.textScalerOf(context);

    final card = Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Большой системный шрифт получает место, сохраняя обложку сверху.
            final height = math.max(
              constraints.maxWidth * 9 / 16,
              math.max(190.0, 112.0 + scaler.scale(22) * 2 + scaler.scale(13)),
            );
            return Semantics(
              button: true,
              enabled: available,
              label: '$title, $status',
              onTap: onTap,
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: radius,
                  child: SizedBox(
                    height: height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        art,
                        // Мягко вводим размытие только в нижней части фото.
                        ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.white],
                            stops: [0.58, 1],
                          ).createShader(rect),
                          child: ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                              sigmaX: 3,
                              sigmaY: 3,
                            ),
                            child: art,
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Color(0x18091121),
                                Color(0xD9091121),
                              ],
                              stops: [0.25, 0.45, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: AppDimensions.spacingL,
                          right: AppDimensions.spacingL,
                          bottom: AppDimensions.spacingL,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        height: 1.12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: AppDimensions.spacingS,
                                    ),
                                    Row(
                                      children: [
                                        Icon(
                                          available
                                              ? Icons.emoji_events_rounded
                                              : Icons.schedule_rounded,
                                          size: 16,
                                          color: available
                                              ? colors.gold
                                              : Colors.white,
                                        ),
                                        const SizedBox(
                                          width: AppDimensions.spacingXS,
                                        ),
                                        Flexible(
                                          child: Text(
                                            status,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              height: 1.2,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (available) ...[
                                const SizedBox(width: AppDimensions.spacingM),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 1),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 24,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (available)
                          Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              onTap: onTap,
                              borderRadius: radius,
                              splashColor: Colors.white24,
                              highlightColor: Colors.white10,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    if (available) return card;
    return Opacity(
      opacity: 0.55,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: card,
      ),
    );
  }
}
