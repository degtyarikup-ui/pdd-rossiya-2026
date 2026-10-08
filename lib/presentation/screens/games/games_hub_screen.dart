import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/sign_swiper_screen.dart';
import 'package:pdd_app/presentation/screens/games/traffic_controller/traffic_controller_screen.dart';

/// Акценты игр — единственное, чем они отличаются друг от друга. Всё остальное
/// (поверхности, шрифты, отступы, радиусы) — токены приложения.
const _signSwiperAccent = Color(0xFFEC4899);
const _roundaboutAccent = Color(0xFF6366F1);

class GamesHubScreen extends ConsumerWidget {
  const GamesHubScreen({super.key});

  void _openTrafficController(BuildContext context, GamePlayMode mode) {
    HapticFeedbackHelper.tap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrafficControllerScreen(initialMode: mode),
      ),
    );
  }

  void _openSignSwiper(BuildContext context, SignSwiperMode mode) {
    HapticFeedbackHelper.tap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SignSwiperScreen(initialMode: mode),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final trafficProgress = ref.watch(trafficControllerProgressProvider);
    final signProgress = ref.watch(signSwiperProgressProvider);

    return Scaffold(
      backgroundColor: colors.homeScreenBackground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            AppDimensions.spacingM,
            AppDimensions.screenPadding,
            AppDimensions.spacingXL,
          ),
          children: [
            Text(
              appL10n.gamesHubTitle,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              appL10n.gamesHubSubtitle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingL),

            _GameCard(
              colors: colors,
              accent: colors.accent,
              icon: Icons.traffic_rounded,
              title: appL10n.gameTrafficControllerTitle,
              subtitle: appL10n.gameTrafficControllerSubtitle,
              description: appL10n.gameTrafficControllerDesc,
              stats: [
                _GameStat(appL10n.gameSolvedLabel, '${trafficProgress.totalSolved}'),
                _GameStat(appL10n.gameComboLabel, 'x${trafficProgress.maxCombo}'),
                _GameStat(appL10n.gameBestScoreLabel, '${trafficProgress.bestScore}'),
              ],
              onTraining: () => _openTrafficController(context, GamePlayMode.training),
              onArcade: () => _openTrafficController(context, GamePlayMode.arcade),
            ),
            const SizedBox(height: AppDimensions.spacingM),

            _GameCard(
              colors: colors,
              accent: _signSwiperAccent,
              icon: Icons.swipe_rounded,
              title: appL10n.gameSignSwiperTitle,
              subtitle: appL10n.gameSignSwiperSubtitle,
              description: appL10n.gameSignSwiperDesc,
              stats: [
                _GameStat(appL10n.gameSwipedLabel, '${signProgress.totalSwiped}'),
                _GameStat(appL10n.gameComboLabel, 'x${signProgress.maxCombo}'),
                _GameStat(appL10n.gameBestScoreLabel, '${signProgress.bestScore}'),
              ],
              onTraining: () => _openSignSwiper(context, SignSwiperMode.training),
              onArcade: () => _openSignSwiper(context, SignSwiperMode.sprint),
            ),
            const SizedBox(height: AppDimensions.spacingXL),

            Text(
              appL10n.gamesHubSoonSection.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingM),
            _TeaserCard(
              colors: colors,
              title: appL10n.gameRoundaboutTitle,
              subtitle: appL10n.gameRoundaboutSubtitle,
              icon: Icons.rotate_right_rounded,
              accent: _roundaboutAccent,
            ),
          ],
        ),
      ),
    );
  }
}

class _GameStat {
  const _GameStat(this.label, this.value);

  final String label;
  final String value;
}

/// Карточка игры: одна структура для всех игр, отличается только акцентом.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.colors,
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.stats,
    required this.onTraining,
    required this.onArcade,
  });

  final AppThemeColors colors;
  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final List<_GameStat> stats;
  final VoidCallback onTraining;
  final VoidCallback onArcade;

  @override
  Widget build(BuildContext context) {
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
    );

    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingM),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: colors.primaryText.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingM),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.homeScreenBackground,
              borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            ),
            child: Row(
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) Container(width: 1, height: 26, color: colors.divider),
                  Expanded(child: _StatCell(colors: colors, stat: stats[i])),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spacingM),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                    minimumSize: const Size.fromHeight(48),
                    shape: buttonShape,
                  ),
                  icon: const Icon(Icons.school_rounded, size: 18),
                  label: Text(
                    appL10n.gameModeTraining,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: onTraining,
                ),
              ),
              const SizedBox(width: AppDimensions.spacingS),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: colors.white,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(48),
                    shape: buttonShape,
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(
                    appL10n.gameModeArcade,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onPressed: onArcade,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.colors, required this.stat});

  final AppThemeColors colors;
  final _GameStat stat;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          stat.value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: colors.primaryText,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          stat.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.secondaryText,
          ),
        ),
      ],
    );
  }
}

class _TeaserCard extends StatelessWidget {
  const _TeaserCard({
    required this.colors,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final AppThemeColors colors;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: AppDimensions.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.homeScreenBackground,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        appL10n.gameSoonBadge.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: colors.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
