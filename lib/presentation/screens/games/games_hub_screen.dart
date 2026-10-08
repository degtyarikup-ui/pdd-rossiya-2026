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
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';

/// Акцент игры — фон обложки. Всё остальное — общие токены приложения.
const _signSwiperAccent = Color(0xFFEC4899);
const _roundaboutAccent = Color(0xFF6366F1);

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
            artBackground: colors.accentSurface10,
            title: appL10n.gameTrafficControllerTitle,
            summary: appL10n.gameTrafficControllerSubtitle,
            bestScore: traffic.bestScore,
            // Кто уже играл в блиц — сразу в блиц, новичок — в обучение.
            onTap: () => _open(
              context,
              TrafficControllerScreen(
                initialMode: traffic.bestScore > 0
                    ? GamePlayMode.arcade
                    : GamePlayMode.training,
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          _GameCard(
            art: const SignSwiperArt(),
            artBackground: _signSwiperAccent.withValues(alpha: 0.1),
            title: appL10n.gameSignSwiperTitle,
            summary: appL10n.gameSignSwiperSubtitle,
            bestScore: signs.bestScore,
            onTap: () => _open(
              context,
              SignSwiperScreen(
                initialMode: signs.bestScore > 0
                    ? SignSwiperMode.sprint
                    : SignSwiperMode.training,
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          _SoonTile(title: appL10n.gameRoundaboutTitle),
        ],
      ),
    );
  }
}

/// Карточка игры: обложка, название, одна-две строки о сути и рекорд.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.art,
    required this.artBackground,
    required this.title,
    required this.summary,
    required this.bestScore,
    required this.onTap,
  });

  final Widget art;
  final Color artBackground;
  final String title;
  final String summary;
  final int bestScore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final radius = BorderRadius.circular(AppDimensions.cardRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: radius,
        boxShadow: gameSoftShadow(colors),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 136,
                  child: ColoredBox(color: artBackground, child: art),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimensions.spacingL,
                    AppDimensions.spacingM,
                    AppDimensions.spacingL,
                    AppDimensions.spacingL,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: colors.primaryText,
                              ),
                            ),
                          ),
                          if (bestScore > 0) ...[
                            Icon(
                              Icons.star_rounded,
                              size: 18,
                              color: colors.gold,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              appL10n.gameBestScore(bestScore),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.secondaryText,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Игра, которая скоро появится: компактная строка, полупрозрачная и неактивная.
class _SoonTile extends StatelessWidget {
  const _SoonTile({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Opacity(
      opacity: 0.45,
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spacingM),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _roundaboutAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
              ),
              child: const RoundaboutArt(),
            ),
            const SizedBox(width: AppDimensions.spacingM),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
            ),
            Text(
              appL10n.gameSoonBadge,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(width: AppDimensions.spacingXS),
          ],
        ),
      ),
    );
  }
}
