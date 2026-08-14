import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/constants/app_strings.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/safe_user_message.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

class TopicsScreen extends ConsumerStatefulWidget {
  const TopicsScreen({super.key});

  @override
  ConsumerState<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends ConsumerState<TopicsScreen> {
  int _refreshKey = 0;
  Map<int, int> _progress = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshProgress());
  }

  Future<void> _refreshProgress() async {
    final topics = await ref.read(topicsProvider.future);
    final dataSource = ref.read(progressDataSourceProvider);
    final category = ref.read(appSettingsProvider).ticketCategory;
    final progressMap = await dataSource.getAllQuestionProgress(category);
    final Map<int, int> progress = {};
    for (int i = 0; i < topics.length; i++) {
      final questions = topics[i]['questions'] as List;
      var correctCount = 0;
      for (final q in questions) {
        final snap = progressMap[q.id];
        if (snap is Map && snap['isCorrect'] == true) {
          correctCount++;
        }
      }
      progress[i] = correctCount;
    }
    if (mounted) {
      setState(() {
        _progress = progress;
        _refreshKey++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(topicsProvider, (prev, next) {
      next.whenData((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refreshProgress();
        });
      });
    });
    final topicsAsync = ref.watch(topicsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: topicsAsync.when(
                data: (topics) {
                  return ListView.builder(
                    key: ValueKey(_refreshKey),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.screenPadding,
                    ),
                    itemCount: topics.length,
                    itemBuilder: (context, index) {
                      final topic = topics[index];
                      final name = topic['name'] as String;
                      final questions = topic['questions'] as List;
                      final totalQuestions = questions.length;
                      final correctCount = _progress[index] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppDimensions.spacingM,
                        ),
                        child: _buildTopicCard(
                          context: context,
                          name: name,
                          totalQuestions: totalQuestions,
                          correctCount: correctCount,
                          questions: List<Map<String, dynamic>>.from(
                            questions.map(
                              (q) => {
                                'id': q.id,
                                'question': q.question,
                                'answers': q.answers
                                    .map(
                                      (a) => {
                                        'text': a.text,
                                        'correct': a.isCorrect,
                                      },
                                    )
                                    .toList(),
                                'comment': q.comment ?? '',
                                'pddPoints': q.pddPoints ?? [],
                                'image': q.image,
                                'topic': q.topic ?? [name],
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(dataLoadErrorMessage(e))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
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
          Text(
            AppStrings.topics,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicCard({
    required BuildContext context,
    required String name,
    required int totalQuestions,
    required int correctCount,
    required List<Map<String, dynamic>> questions,
  }) {
    final notStarted = totalQuestions == 0 || correctCount == 0;
    final completed = !notStarted && correctCount >= totalQuestions;

    late final Color pillBg;
    late final Color pillTextColor;
    late final String progressLabel;

    if (notStarted) {
      pillBg = AppColors.secondaryText.withOpacity(0.12);
      pillTextColor = AppColors.secondaryText;
    } else if (completed) {
      pillBg = AppColors.green.withOpacity(0.12);
      pillTextColor = AppColors.green;
    } else {
      pillBg = AppColors.accent.withOpacity(0.12);
      pillTextColor = AppColors.accent;
    }
    progressLabel = '$correctCount/$totalQuestions';

    return GestureDetector(
      onTap: () async {
        HapticFeedbackHelper.tap();
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TrainingScreen(
              questions: questions,
              title: name,
              isExam: false,
            ),
          ),
        );
        _refreshProgress();
      },
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spacingL),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primaryText,
                ),
              ),
            ),
            const SizedBox(width: AppDimensions.spacingM),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                progressLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: pillTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
