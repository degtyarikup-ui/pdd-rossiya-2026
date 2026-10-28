import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/exam_hero_card.dart';
import 'package:pdd_app/presentation/widgets/progress_panel_card.dart';

/// Desktop presentation only. Sessions, progress and navigation belong to Home.
class DesktopStudyDashboard extends StatelessWidget {
  const DesktopStudyDashboard({
    super.key,
    required this.progress,
    required this.category,
    required this.onExam,
    required this.onTopics,
    required this.onTickets,
    required this.onMistakes,
    required this.onFavorites,
    required this.onMarathon,
    required this.onRate,
    this.resume,
    this.inboxAlert,
    this.marathonBusy = false,
  });
  final Widget progress;
  final Widget? resume, inboxAlert;
  final String category;
  final VoidCallback onExam,
      onTopics,
      onTickets,
      onMistakes,
      onFavorites,
      onMarathon,
      onRate;
  final bool marathonBusy;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final twoColumns = constraints.maxWidth >= 760 && scale <= 1.35;
        final modes = [
          (
            title: appL10n.topics,
            description: appL10n.desktopTopicsDescription,
            asset: 'topics',
            onTap: onTopics,
          ),
          (
            title: appL10n.tickets,
            description: appL10n.desktopTicketsDescription,
            asset: 'tickets',
            onTap: onTickets,
          ),
          (
            title: appL10n.mistakes,
            description: appL10n.desktopMistakesDescription,
            asset: 'errors',
            onTap: onMistakes,
          ),
          (
            title: appL10n.favorites,
            description: appL10n.desktopFavoritesDescription,
            asset: 'favorites',
            onTap: onFavorites,
          ),
        ];
        final exam = _DesktopExamCard(category: category, onStart: onExam);
        return SingleChildScrollView(
          key: const PageStorageKey('desktop-study-scroll'),
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appL10n.training,
                          style: TextStyle(
                            fontSize: 30,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.7,
                            color: colors.primaryText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          appL10n.desktopStudyIntro,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: colors.primaryText.withValues(alpha: .62),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${appL10n.category}: $category',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText.withValues(alpha: .62),
                      ),
                    ),
                  ),
                ],
              ),
              if (inboxAlert != null) ...[
                const SizedBox(height: 24),
                inboxAlert!,
              ],
              if (resume != null) ...[const SizedBox(height: 20), resume!],
              const SizedBox(height: 28),
              if (twoColumns)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: exam),
                    const SizedBox(width: 20),
                    Expanded(flex: 4, child: progress),
                  ],
                )
              else ...[
                exam,
                const SizedBox(height: 20),
                progress,
              ],
              const SizedBox(height: 28),
              Text(
                appL10n.desktopPracticeTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, box) {
                  final columns = twoColumns ? 2 : 1;
                  final width = (box.maxWidth - (columns - 1) * 16) / columns;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final mode in modes)
                        SizedBox(
                          width: width,
                          child: _StudyModeCard(
                            title: mode.title,
                            description: mode.description,
                            asset: mode.asset,
                            onTap: mode.onTap,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Material(
                color: colors.accentSurface10,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  leading: Icon(
                    Icons.route_rounded,
                    color: colors.accent,
                    size: 28,
                  ),
                  title: Text(
                    appL10n.marathon,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      appL10n.desktopMarathonDescription,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: colors.primaryText.withValues(alpha: .62),
                      ),
                    ),
                  ),
                  trailing: marathonBusy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.arrow_forward_rounded, color: colors.accent),
                  onTap: marathonBusy ? null : onMarathon,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onRate,
                  icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                  label: Text(appL10n.rateUs),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.primaryText.withValues(alpha: .62),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DesktopExamCard extends StatelessWidget {
  const _DesktopExamCard({required this.category, required this.onStart});
  final String category;
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) {
    final rules = CountryConfig.current.examRules;
    return Container(
      constraints: const BoxConstraints(minHeight: 320),
      padding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1685FF), Color(0xFF0758D8)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final artwork =
              constraints.maxWidth >= 380 &&
              MediaQuery.textScalerOf(context).scale(16) <= 22;
          return Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appL10n.exam,
                      style: const TextStyle(
                        fontSize: 30,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.6,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      appL10n.desktopExamDescription,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: .85),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final label in [
                          appL10n.examQuestionsBadge(rules.mainCount),
                          appL10n.examMinutesBadge(rules.totalMinutes),
                          category,
                        ])
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      key: const ValueKey('desktop-start-exam'),
                      onPressed: onStart,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0758D8),
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      iconAlignment: IconAlignment.end,
                      label: Text(
                        appL10n.desktopStartExam,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              if (artwork) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: (constraints.maxWidth * .3).clamp(110, 185),
                  height: 200,
                  child: const ExcludeSemantics(child: ExamHeroArtwork()),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StudyModeCard extends StatelessWidget {
  const _StudyModeCard({
    required this.title,
    required this.description,
    required this.asset,
    required this.onTap,
  });
  final String title, description, asset;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.accentSurface10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(
                  'assets/images/home_icon_$asset.png',
                  width: 28,
                  height: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: colors.primaryText.withValues(alpha: .62),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: colors.primaryText.withValues(alpha: .62),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DesktopProgressCard extends StatelessWidget {
  const DesktopProgressCard({super.key, required this.stats});
  final Map<String, int> stats;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final total = stats['totalQuestions'] ?? 0;
    final correct = stats['correctAnswers'] ?? 0;
    final remaining = math.max(0, total - correct);
    final percent = total > 0 ? (correct / total * 100).round() : 0;
    Widget metric(String value, String label, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: color ?? colors.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.primaryText.withValues(alpha: .62),
            ),
          ),
        ],
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 320),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            appL10n.examReadiness,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              ReadinessGauge(percent: percent),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  remaining > 0
                      ? appL10n.progressRemaining(remaining)
                      : appL10n.progressAllDone,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: colors.primaryText.withValues(alpha: .62),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Divider(height: 1, color: colors.divider),
          const SizedBox(height: 18),
          Row(
            children: [
              metric(
                '${stats['answeredQuestions'] ?? 0}',
                appL10n.progressDone,
              ),
              metric(
                '${stats['passedTickets'] ?? 0}/${stats['totalTickets'] ?? 0}',
                appL10n.progressTickets,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              metric('$correct', appL10n.progressCorrect, color: colors.green),
              metric(
                '${stats['wrongQuestions'] ?? 0}',
                appL10n.progressWrong,
                color: colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
