import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/traffic_controller_progress.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/traffic_controller/traffic_controller_screen.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final progress = ref.watch(trafficControllerProgressProvider);

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
            // Заголовок раздела
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
                color: colors.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingL),

            // Главная карточка: Регулировщик 3D
            _buildTrafficControllerCard(context, colors, progress),

            const SizedBox(height: AppDimensions.spacingXL),

            // Раздел «Скоро»
            Text(
              'СКОРО В ИГРАХ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingM),

            _buildTeaserCard(
              colors: colors,
              title: 'Круговое движение 3D',
              subtitle: 'Въезд с любой полосы, съезд — только с крайней правой (п. 8.5 ПДД)',
              icon: Icons.rotate_right_rounded,
              color: const Color(0xFF6366F1),
            ),
            const SizedBox(height: AppDimensions.spacingM),

            _buildTeaserCard(
              colors: colors,
              title: 'Знак-Свайпер',
              subtitle: 'Быстрая сортировка 300+ дорожных знаков на скорость реакции',
              icon: Icons.swipe_rounded,
              color: const Color(0xFFEC4899),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficControllerCard(
    BuildContext context,
    AppThemeColors colors,
    TrafficControllerProgress progress,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.white12),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Бейдж и статус
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.view_in_ar_rounded, size: 14, color: AppColors.accent),
                        SizedBox(width: 4),
                        Text(
                          '3D WebGL',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (progress.bestScore > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.emoji_events_rounded, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            '${appL10n.gameBestScoreLabel}: ${progress.bestScore}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Название и описание
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.traffic_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appL10n.gameTrafficControllerTitle,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          appL10n.gameTrafficControllerSubtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Краткое описание пользы
              Text(
                appL10n.gameTrafficControllerDesc,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white60,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),

              // Статистика игрока
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCol(
                      label: appL10n.gameSolvedLabel,
                      value: '${progress.totalSolved}',
                    ),
                    Container(width: 1, height: 26, color: Colors.white12),
                    _buildStatCol(
                      label: appL10n.gameComboLabel,
                      value: 'x${progress.maxCombo}',
                    ),
                    Container(width: 1, height: 26, color: Colors.white12),
                    _buildStatCol(
                      label: appL10n.gameBestScoreLabel,
                      value: '${progress.bestScore}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Кнопки режимов
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.school_rounded, size: 18),
                      label: Text(
                        appL10n.gameModeTraining,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => _openTrafficController(context, GamePlayMode.training),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                      ),
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: Text(
                        appL10n.gameModeArcade,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed: () => _openTrafficController(context, GamePlayMode.arcade),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCol({required String label, required String value}) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildTeaserCard({
    required AppThemeColors colors,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.secondaryText.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'СКОРО',
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
                    color: colors.secondaryText,
                    height: 1.25,
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
