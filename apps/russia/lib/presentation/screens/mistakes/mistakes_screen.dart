import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/layout/app_content_frame.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/safe_user_message.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/usage_reporter.dart';
import 'package:pdd_app/domain/services/mistakes_test_generator.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/app_loading_indicator.dart';

class MistakesScreen extends ConsumerStatefulWidget {
  const MistakesScreen({super.key});

  @override
  ConsumerState<MistakesScreen> createState() => _MistakesScreenState();
}

class _MistakesScreenState extends ConsumerState<MistakesScreen> {
  static const int _initialVisibleTopics = 4;
  bool _showAllTopics = false;

  void _openTraining(List<Question> questions, {required String title}) {
    if (questions.isEmpty) return;
    HapticFeedbackHelper.tap();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrainingScreen(
          questions: [for (final q in questions) q.toMap()],
          title: title,
          usageFeature: UsageFeature.mistakes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingsProvider.select((s) => s.ticketCategory));
    ref.watch(appSettingsProvider.select((s) => s.effectiveLanguageCode));
    final ticketsAsync = ref.watch(ticketsProvider);
    final progressAsync = ref.watch(trackedQuestionProgressProvider);
    final wrongIdsAsync = ref.watch(wrongQuestionIdsProvider);
    final colors = AppColors.of(context);

    return AppContentFrame(
      maxWidth: AppContentFrame.readingWidth,
      child: Scaffold(
        backgroundColor: colors.background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(AppDimensions.screenPadding),
                child: Row(
                  children: [
                    AppChromeIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () {
                        HapticFeedbackHelper.tap();
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: AppDimensions.spacingM),
                    Expanded(
                      child: Text(
                        appL10n.mistakesTitle,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _buildBody(
                context,
                ticketsAsync: ticketsAsync,
                progressAsync: progressAsync,
                wrongIdsAsync: wrongIdsAsync,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required AsyncValue<List<Map<String, dynamic>>> ticketsAsync,
    required AsyncValue<Map<String, dynamic>> progressAsync,
    required AsyncValue<List<String>> wrongIdsAsync,
  }) {
    final colors = AppColors.of(context);

    final tickets = ticketsAsync.valueOrNull;
    final wrongIds = wrongIdsAsync.valueOrNull;
    final progress = progressAsync.valueOrNull;

    final firstError = ticketsAsync.hasError && tickets == null
        ? ticketsAsync.error
        : wrongIdsAsync.hasError && wrongIds == null
        ? wrongIdsAsync.error
        : progressAsync.hasError && progress == null
        ? progressAsync.error
        : null;

    if (firstError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.screenPadding),
          child: Text(
            dataLoadErrorMessage(firstError),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: colors.secondaryText,
            ),
          ),
        ),
      );
    }

    if (tickets == null ||
        wrongIds == null ||
        (progress == null && progressAsync.isLoading)) {
      return const Center(child: AppLoadingIndicator());
    }

    final allQuestions = <Question>[
      for (final ticket in tickets)
        ...(ticket['questions'] as List).cast<Question>(),
    ];
    final analysis = MistakesAnalysis.build(
      allQuestions: allQuestions,
      progress: progress ?? const <String, dynamic>{},
      activeWrongIds: wrongIds,
    );

    if (!analysis.hasAnyHistory) {
      return _buildEmptyState(context);
    }

    final targetTestSize = CountryConfig.current.examRules.mainCount;
    final generalTestCount = math.min(
      targetTestSize,
      analysis.allUniqueQuestions.length,
    );
    final hardestCount = math.min(
      targetTestSize,
      analysis.frequentMistakes.length,
    );

    final hasActiveMistakes = analysis.activeMistakes.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const barVerticalPad = 12.0;
    const buttonHeight = 52.0;
    final listBottomPad = hasActiveMistakes
        ? barVerticalPad * 2 + buttonHeight + bottomInset + 8
        : AppDimensions.screenPadding + bottomInset;

    final visibleTopics = _showAllTopics
        ? analysis.weakTopics
        : analysis.weakTopics.take(_initialVisibleTopics).toList();
    final hasExtraTopics = analysis.weakTopics.length > _initialVisibleTopics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const PageStorageKey('mistakes-list'),
            padding: EdgeInsets.fromLTRB(
              AppDimensions.screenPadding,
              0,
              AppDimensions.screenPadding,
              listBottomPad,
            ),
            children: [
              _buildSectionHeader(
                context,
                title: appL10n.mistakesSmartSectionTitle,
              ),
              const SizedBox(height: AppDimensions.spacingS),
              _buildGeneralTestHeroCard(
                context,
                questionCount: generalTestCount,
                onTap: () {
                  final generated =
                      MistakesTestGenerator.generateFrequentMistakesTest(
                        analysis,
                        targetCount: targetTestSize,
                      );
                  _openTraining(
                    generated,
                    title: appL10n.frequentMistakesTestTitle,
                  );
                },
              ),
              if (analysis.hasDrillableFrequentMistakes) ...[
                const SizedBox(height: AppDimensions.spacingM),
                _buildHardestQuestionsCard(
                  context,
                  questionCount: hardestCount,
                  onTap: () {
                    final generated =
                        MistakesTestGenerator.generateHardestMistakesTest(
                          analysis,
                          maxQuestions: targetTestSize,
                        );
                    _openTraining(
                      generated,
                      title: appL10n.frequentMistakesDrillTitle,
                    );
                  },
                ),
              ],
              if (analysis.weakTopics.isNotEmpty) ...[
                const SizedBox(height: AppDimensions.spacingXL),
                _buildSectionHeader(
                  context,
                  title: appL10n.weakTopicsTitle,
                  subtitle: appL10n.weakTopicsSubtitle,
                ),
                const SizedBox(height: AppDimensions.spacingS),
                for (final topic in visibleTopics)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppDimensions.spacingM,
                    ),
                    child: _buildWeakTopicCard(
                      context,
                      topic: topic,
                      targetTestSize: targetTestSize,
                      onTap: () {
                        final generated =
                            MistakesTestGenerator.generateTopicTest(
                              analysis,
                              topic,
                              maxQuestions: targetTestSize,
                            );
                        _openTraining(generated, title: topic.name);
                      },
                    ),
                  ),
                if (hasExtraTopics)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        HapticFeedbackHelper.select();
                        setState(() => _showAllTopics = !_showAllTopics);
                      },
                      child: Text(
                        _showAllTopics
                            ? appL10n.hideExtraWeakTopics
                            : appL10n.showAllWeakTopics(
                                analysis.weakTopics.length,
                              ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: AppDimensions.spacingXL),
              _buildSectionHeader(
                context,
                title: appL10n.currentMistakesTitle,
                countBadge: hasActiveMistakes
                    ? '${analysis.activeMistakes.length}'
                    : null,
              ),
              const SizedBox(height: AppDimensions.spacingS),
              if (!hasActiveMistakes)
                _buildActiveMistakesClearedCard(context)
              else
                for (final entry in analysis.activeMistakes)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppDimensions.spacingM,
                    ),
                    child: _buildQuestionCard(context, entry),
                  ),
            ],
          ),
        ),
        if (hasActiveMistakes)
          _buildBottomRepeatBar(context, [
            for (final entry in analysis.activeMistakes) entry.question,
          ]),
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    String? subtitle,
    String? countBadge,
  }) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
            ),
            if (countBadge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.redLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  countBadge,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.red,
                  ),
                ),
              ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: colors.secondaryText),
          ),
        ],
      ],
    );
  }

  Widget _buildGeneralTestHeroCard(
    BuildContext context, {
    required int questionCount,
    required VoidCallback onTap,
  }) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.accent,
      borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('mistakes-general-test-card'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spacingL),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appL10n.frequentMistakesTestTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appL10n.frequentMistakesTestSubtitle(questionCount),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.86),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimensions.spacingS),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHardestQuestionsCard(
    BuildContext context, {
    required int questionCount,
    required VoidCallback onTap,
  }) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('mistakes-hardest-card'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spacingL),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.goldLightSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.bolt_rounded, color: colors.gold, size: 24),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appL10n.frequentMistakesDrillTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appL10n.frequentMistakesDrillSubtitle(questionCount),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.secondaryText,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimensions.spacingS),
              Icon(Icons.chevron_right_rounded, color: colors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeakTopicCard(
    BuildContext context, {
    required WeakTopicSummary topic,
    required int targetTestSize,
    required VoidCallback onTap,
  }) {
    final colors = AppColors.of(context);
    final hasActive = topic.activeMistakeCount > 0;
    final pillBg = hasActive ? colors.redLight : colors.goldLightSurface;
    final pillFg = hasActive ? colors.red : colors.gold;
    final testSize = math.min(targetTestSize, topic.totalQuestions);
    final metaLabel = testSize < topic.totalQuestions
        ? appL10n.weakTopicTestMeta(testSize, topic.totalQuestions)
        : appL10n.weakTopicFullTestMeta(testSize);

    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spacingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      topic.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingS),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.secondaryText,
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingS),
              Wrap(
                spacing: AppDimensions.spacingS,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      appL10n.weakTopicMistakeCount(topic.mistakeAttempts),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: pillFg,
                      ),
                    ),
                  ),
                  Text(
                    metaLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.secondaryText,
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

  Widget _buildActiveMistakesClearedCard(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.greenLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              color: colors.green,
              size: 24,
            ),
          ),
          const SizedBox(width: AppDimensions.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appL10n.activeMistakesClearedTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  appL10n.activeMistakesClearedHint,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.secondaryText,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.greenLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.check_circle_outline,
                size: 36,
                color: colors.green,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingL),
            Text(
              appL10n.noMistakesYet,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingS),
            Text(
              appL10n.mistakesEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Плашка на всю ширину экрана, закреплена у нижнего края (над home indicator).
  Widget _buildBottomRepeatBar(BuildContext context, List<Question> questions) {
    final colors = AppColors.of(context);
    return ColoredBox(
      color: colors.cardBackground,
      child: SafeArea(
        top: false,
        child: Material(
          color: colors.cardBackground,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.cardBackground,
              border: Border(top: BorderSide(color: colors.divider, width: 1)),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.screenPadding,
              12,
              AppDimensions.screenPadding,
              12,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () =>
                    _openTraining(questions, title: appL10n.mistakesTitle),
                child: Text(appL10n.repeatAllMistakes),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionCard(BuildContext context, MistakeQuestionEntry entry) {
    final colors = AppColors.of(context);
    final question = entry.question;
    final topicLabel = question.topic.isNotEmpty
        ? question.topic.first
        : appL10n.noTopic;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        onTap: () => _openTraining([question], title: appL10n.mistakeReview),
        child: Container(
          padding: const EdgeInsets.all(AppDimensions.spacingL),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.redLight,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            appL10n.mistakeLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.red,
                            ),
                          ),
                        ),
                        if (entry.wrongAttempts >= 2)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colors.goldLightSurface,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              appL10n.mistakeRepeatCount(entry.wrongAttempts),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.gold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingS),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      appL10n.ticketNumber(question.ticketNumber),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingM),
              Text(
                question.question,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingM),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      topicLabel,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.secondaryText,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
