import 'package:flutter/material.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/safe_user_message.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

class MistakesScreen extends ConsumerWidget {
  const MistakesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wrongIdsAsync = ref.watch(wrongQuestionIdsProvider);
    final colors = AppColors.of(context);

    return Scaffold(
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
            child: wrongIdsAsync.when(
              data: (wrongIds) {
                if (wrongIds.isEmpty) {
                  return _buildEmptyState(context);
                }

                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadWrongQuestions(ref, wrongIds),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final questions = snapshot.data!;

                    if (questions.isEmpty) {
                      return _buildEmptyState(context);
                    }

                    final bottomInset = MediaQuery.paddingOf(context).bottom;
                    const barVerticalPad = 12.0;
                    const buttonHeight = 52.0;
                    final listBottomPad =
                        barVerticalPad * 2 + buttonHeight + bottomInset + 8;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(
                              AppDimensions.screenPadding,
                              0,
                              AppDimensions.screenPadding,
                              listBottomPad,
                            ),
                            children: [
                              ...questions.map((question) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppDimensions.spacingM,
                                  ),
                                  child: _buildQuestionCard(
                                    context,
                                    question,
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        _buildBottomRepeatBar(context, questions),
                      ],
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text(dataLoadErrorMessage(error))),
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

  Future<List<Map<String, dynamic>>> _loadWrongQuestions(
    WidgetRef ref,
    List<String> wrongIds,
  ) async {
    final dataSource = ref.read(questionsDataSourceProvider);
    final category = ref.read(appSettingsProvider).ticketCategory;
    final allQuestions = await dataSource.loadTickets(category);
    final wrongIdSet = wrongIds.toSet();

    return allQuestions
        .where((question) => wrongIdSet.contains(question.id))
        .map(
          (question) => {
            'id': question.id,
            'question': question.question,
            'answers': question.answers
                .map(
                  (answer) => {
                    'text': answer.text,
                    'correct': answer.isCorrect,
                  },
                )
                .toList(),
            'comment': question.comment ?? '',
            'pddPoints': question.pddPoints,
            'image': question.image,
            'topic': question.topic,
            'ticketNumber': question.ticketNumber,
          },
        )
        .toList();
  }

  /// Плашка на всю ширину экрана, закреплена у нижнего края (над home indicator).
  Widget _buildBottomRepeatBar(
    BuildContext context,
    List<Map<String, dynamic>> questions,
  ) {
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
              border: Border(
                top: BorderSide(color: colors.divider, width: 1),
              ),
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
                onPressed: () {
                  HapticFeedbackHelper.tap();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrainingScreen(
                        questions: questions,
                        title: appL10n.mistakesTitle,
                      ),
                    ),
                  );
                },
                child: Text(appL10n.repeatAllMistakes),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionCard(
    BuildContext context,
    Map<String, dynamic> question,
  ) {
    final colors = AppColors.of(context);
    final topics = (question['topic'] as List?)?.cast<String>() ?? const [];
    final topicLabel = topics.isNotEmpty ? topics.first : appL10n.noTopic;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        onTap: () {
          HapticFeedbackHelper.tap();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  TrainingScreen(questions: [question], title: appL10n.mistakeReview),
            ),
          );
        },
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
                  const Spacer(),
                  Text(
                    appL10n.ticketNumber(question['ticketNumber']),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingM),
              Text(
                question['question'] as String,
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
