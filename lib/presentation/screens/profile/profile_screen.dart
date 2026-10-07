import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/profile/widgets/achievement_badge.dart';
import 'package:pdd_app/presentation/screens/settings/settings_screen.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/presentation/widgets/premium_banner_card.dart';
import 'package:pdd_app/presentation/widgets/profile_modal_sheet.dart';

String _getAchievementTitle(AchievementId id) {
  switch (id) {
    case AchievementId.streak:
      return appL10n.achievementTitleStreak;
    case AchievementId.coverage:
      return appL10n.achievementTitleCoverage;
    case AchievementId.tickets:
      return appL10n.achievementTitleTickets;
    case AchievementId.attempts:
      return appL10n.achievementTitleAttempts;
    case AchievementId.exams:
      return appL10n.achievementTitleExams;
    case AchievementId.flawless:
      return appL10n.achievementTitleFlawless;
    case AchievementId.mistakes:
      return appL10n.achievementTitleMistakes;
    case AchievementId.game:
      return appL10n.achievementTitleGame;
  }
}

String _getAchievementDescription(AchievementId id) {
  switch (id) {
    case AchievementId.streak:
      return appL10n.achievementDescStreak;
    case AchievementId.coverage:
      return appL10n.achievementDescCoverage;
    case AchievementId.tickets:
      return appL10n.achievementDescTickets;
    case AchievementId.attempts:
      return appL10n.achievementDescAttempts;
    case AchievementId.exams:
      return appL10n.achievementDescExams;
    case AchievementId.flawless:
      return appL10n.achievementDescFlawless;
    case AchievementId.mistakes:
      return appL10n.achievementDescMistakes;
    case AchievementId.game:
      return appL10n.achievementDescGame;
  }
}

String _getAchievementTargetLabel(AchievementId id, int target) {
  switch (id) {
    case AchievementId.streak:
      return appL10n.achievementTargetStreak(target);
    case AchievementId.coverage:
      return appL10n.achievementTargetCoverage(target);
    case AchievementId.tickets:
      return appL10n.achievementTargetTickets(target);
    case AchievementId.attempts:
      return appL10n.achievementTargetAttempts(target);
    case AchievementId.exams:
      return appL10n.achievementTargetExams(target);
    case AchievementId.flawless:
      return appL10n.achievementTargetFlawless(target);
    case AchievementId.mistakes:
      return appL10n.achievementTargetMistakes(target);
    case AchievementId.game:
      return appL10n.achievementTargetGame(target);
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _showAchievementDetails(
    BuildContext context,
    AchievementProgress achievement,
  ) {
    final colors = AppColors.of(context);
    final title = _getAchievementTitle(achievement.id);
    final description = _getAchievementDescription(achievement.id);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.cardBackground,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            0,
            AppDimensions.screenPadding,
            AppDimensions.spacingXL,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppDimensions.spacingS),
              Center(
                child: AchievementBadge(
                  id: achievement.id,
                  imageLevel: achievement.level == 0 ? 1 : achievement.level,
                  unlocked: achievement.isUnlocked,
                  size: 140,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(fontSize: 14, color: colors.secondaryText),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 12.0;
                  final itemWidth = (constraints.maxWidth - spacing) / 2;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: 20.0,
                    children: [
                      for (int i = 0; i < achievement.levels.length; i++)
                        SizedBox(
                          width: itemWidth,
                          child: _AchievementLevelItem(
                            achievement: achievement,
                            levelIndex: i,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double topInset = MediaQuery.paddingOf(context).top;
    final currentUser = ref.watch(currentUserProvider);
    final streakAsync = ref.watch(streakProvider);
    final statsAsync = ref.watch(statsProvider);
    final achievementsAsync = ref.watch(achievementsProvider);

    final achievements = achievementsAsync.valueOrNull ?? const [];
    final unlockedCount = achievements.where((a) => a.isUnlocked).length;
    final totalCount = achievements.length;

    return Scaffold(
      backgroundColor: colors.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarColor: colors.cardBackground,
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            topInset + 16,
            AppDimensions.screenPadding,
            32,
          ),
          children: [
            // Шапка: заголовок слева, кнопка-шестерёнка справа
            Padding(
              padding: const EdgeInsets.only(bottom: AppDimensions.spacingL),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      appL10n.profile,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  AppChromeIconButton(
                    icon: Icons.settings_outlined,
                    onTap: () {
                      HapticFeedbackHelper.tap();
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Карточка аккаунта
            if (currentUser != null) ...[
              _UserProfileCard(profile: currentUser),
              const SizedBox(height: AppDimensions.spacingM),
            ] else ...[
              const _SignInCard(),
              const SizedBox(height: AppDimensions.spacingM),
            ],

            // Премиум-баннер
            const PremiumBannerCard(),
            const SizedBox(height: AppDimensions.spacingM),

            // Короткая статистика
            _ShortStatsCard(
              streakAsync: streakAsync,
              statsAsync: statsAsync,
              achievementsAsync: achievementsAsync,
            ),
            const SizedBox(height: AppDimensions.spacingXL),

            // Раздел «Достижения»
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppDimensions.spacingXS,
                    bottom: AppDimensions.spacingS,
                  ),
                  child: Text(
                    appL10n.achievements,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.secondaryText,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    right: AppDimensions.spacingXS,
                    bottom: AppDimensions.spacingS,
                  ),
                  child: Text(
                    appL10n.achievementsEarnedCount(unlockedCount, totalCount),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingS),

            // Сетка значков (3 колонки через LayoutBuilder + Wrap)
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                final itemWidth = (constraints.maxWidth - 2 * spacing) / 3;
                return Wrap(
                  spacing: spacing,
                  runSpacing: AppDimensions.spacingXL,
                  children: [
                    for (final achievement in achievements)
                      SizedBox(
                        width: itemWidth,
                        child: _AchievementGridCell(
                          achievement: achievement,
                          onTap: () {
                            HapticFeedbackHelper.tap();
                            _showAchievementDetails(context, achievement);
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _UserProfileCard extends StatelessWidget {
  final UserProfile profile;

  const _UserProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: () => ProfileModalSheet.show(context, profile),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.lightAccent,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child:
                    profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty
                    ? Image.network(
                        profile.avatarUrl!,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Text(
                            profile.name.isNotEmpty
                                ? profile.name[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: colors.accent,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          profile.name.isNotEmpty
                              ? profile.name[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                  if (profile.email.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      profile.email,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.secondaryText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInCard extends StatelessWidget {
  const _SignInCard();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: () => AuthModalSheet.show(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.searchFieldFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_circle_outlined,
                color: colors.secondaryText,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appL10n.signInCardTitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    appL10n.signInCardSubtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.secondaryText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortStatsCard extends StatelessWidget {
  final AsyncValue<Streak> streakAsync;
  final AsyncValue<Map<String, int>> statsAsync;
  final AsyncValue<List<AchievementProgress>> achievementsAsync;

  const _ShortStatsCard({
    required this.streakAsync,
    required this.statsAsync,
    required this.achievementsAsync,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    final String streakValue;
    final String streakLabel;
    if (streakAsync.isLoading && !streakAsync.hasValue) {
      streakValue = '—';
      streakLabel = appL10n.profileStatStreakDays(0);
    } else {
      final current = streakAsync.valueOrNull?.current ?? 0;
      streakValue = '$current';
      streakLabel = appL10n.profileStatStreakDays(current);
    }

    final String questionsValue;
    if (statsAsync.isLoading && !statsAsync.hasValue) {
      questionsValue = '—';
    } else {
      final stats = statsAsync.valueOrNull;
      final answered = stats?['answeredQuestions'] ?? 0;
      final total = stats?['totalQuestions'] ?? 0;
      questionsValue = '$answered / $total';
    }

    final String examsValue;
    if (achievementsAsync.isLoading && !achievementsAsync.hasValue) {
      examsValue = '—';
    } else {
      final achievements = achievementsAsync.valueOrNull ?? const [];
      final examsAch = achievements
          .where((a) => a.id == AchievementId.exams)
          .firstOrNull;
      examsValue = '${examsAch?.value ?? 0}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatColumn(value: streakValue, label: streakLabel),
          ),
          Expanded(
            child: _StatColumn(
              value: questionsValue,
              label: appL10n.profileStatQuestions,
            ),
          ),
          Expanded(
            child: _StatColumn(
              value: examsValue,
              label: appL10n.profileStatExams,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String label;

  const _StatColumn({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // «800 / 800» при крупном системном шрифте не влезает в треть
        // ширины — уменьшаем, а не обрезаем.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12.5, color: colors.secondaryText),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _AchievementGridCell extends StatelessWidget {
  final AchievementProgress achievement;
  final VoidCallback onTap;

  const _AchievementGridCell({required this.achievement, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final title = _getAchievementTitle(achievement.id);
    final semanticsLabel = appL10n.achievementSemanticsLabel(
      title,
      achievement.level,
      achievement.levels.length,
    );

    return Semantics(
      label: semanticsLabel,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AchievementBadge(
              id: achievement.id,
              imageLevel: achievement.level == 0 ? 1 : achievement.level,
              unlocked: achievement.isUnlocked,
              size: 72,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: achievement.isUnlocked
                    ? colors.primaryText
                    : colors.secondaryText,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              appL10n.achievementLevelFormat(
                achievement.level,
                achievement.levels.length,
              ),
              style: TextStyle(fontSize: 12, color: colors.secondaryText),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementLevelItem extends StatelessWidget {
  final AchievementProgress achievement;
  final int levelIndex;

  const _AchievementLevelItem({
    required this.achievement,
    required this.levelIndex,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final levelNum = levelIndex + 1;
    final target = achievement.levels[levelIndex];
    final isLevelUnlocked = achievement.level >= levelNum;
    final current = math.min(achievement.value, target);
    final targetLabel = _getAchievementTargetLabel(achievement.id, target);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AchievementBadge(
          id: achievement.id,
          imageLevel: levelNum,
          unlocked: isLevelUnlocked,
          size: 72,
        ),
        const SizedBox(height: 8),
        Text(
          targetLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isLevelUnlocked ? colors.primaryText : colors.secondaryText,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          appL10n.achievementProgressFormat(current, target),
          style: TextStyle(fontSize: 12, color: colors.secondaryText),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
            color: colors.accent,
            backgroundColor: colors.searchFieldFill,
          ),
        ),
      ],
    );
  }
}
