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

/// Две колонки — карточка шире, номер билета и «12/20» помещаются без обрезки.
int _ticketGridCrossAxisCount(double gridWidth) {
  return 2;
}

/// Ширина/высота ячейки: больше → ниже карточка (горизонтальная полоса).
double _ticketGridAspectRatio(int crossAxisCount) {
  switch (crossAxisCount) {
    case 2:
      return 2.05;
    case 3:
      return 1.88;
    default:
      return 1.72;
  }
}

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  int _refreshKey = 0;
  Map<int, ({int answered, int correct})>? _cachedProgress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshProgress());
  }

  Future<void> _refreshProgress() async {
    final tickets = await ref.read(ticketsProvider.future);
    final dataSource = ref.read(progressDataSourceProvider);
    final category = ref.read(appSettingsProvider).ticketCategory;
    final progressMap = await dataSource.getAllQuestionProgress(category);
    final Map<int, ({int answered, int correct})> progress = {};

    for (final ticket in tickets) {
      final ticketNum = ticket['number'] as int;
      final questions = ticket['questions'] as List;
      int answeredCount = 0;
      int correctCount = 0;

      for (final q in questions) {
        final snapshot = progressMap[q.id as String];
        if (snapshot is Map<String, dynamic>) {
          answeredCount++;
          if (snapshot['isCorrect'] == true) {
            correctCount++;
          }
        }
      }

      progress[ticketNum] = (answered: answeredCount, correct: correctCount);
    }

    if (mounted) {
      setState(() {
        _cachedProgress = progress;
        _refreshKey++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ticketsProvider, (prev, next) {
      next.whenData((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refreshProgress();
        });
      });
    });
    final ticketsAsync = ref.watch(ticketsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: ticketsAsync.when(
                data: (tickets) {
                  final progress = _cachedProgress ?? {};
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final gridWidth = constraints.maxWidth;
                      final crossAxisCount = _ticketGridCrossAxisCount(gridWidth);
                      final gridPad = gridWidth < 400
                          ? AppDimensions.spacingS
                          : AppDimensions.screenPadding;
                      return GridView.builder(
                        key: ValueKey(_refreshKey),
                        padding: EdgeInsets.all(gridPad),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: AppDimensions.spacingM,
                          crossAxisSpacing: AppDimensions.spacingM,
                          childAspectRatio: _ticketGridAspectRatio(crossAxisCount),
                        ),
                        itemCount: tickets.length,
                    itemBuilder: (context, index) {
                      final ticket = tickets[index];
                      final ticketNum = ticket['number'] as int;
                      final questions = ticket['questions'] as List;
                      final progressSnapshot =
                          progress[ticketNum] ?? (answered: 0, correct: 0);
                      final answeredCount = progressSnapshot.answered;
                      final correctCount = progressSnapshot.correct;
                      final isCompleted = answeredCount == questions.length;
                      final isPassed = isCompleted && correctCount >= 18;
                      return _buildTicketCard(
                        context: context,
                        number: ticketNum,
                        totalQuestions: questions.length,
                        correctCount: correctCount,
                        isCompleted: isCompleted,
                        isPassed: isPassed,
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
                              'topic': q.topic ?? [],
                              'ticketNumber': q.ticketNumber,
                            },
                          ),
                        ),
                      );
                    },
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
          const Text(
            AppStrings.tickets,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketCard({
    required BuildContext context,
    required int number,
    required int totalQuestions,
    required int correctCount,
    required bool isCompleted,
    required bool isPassed,
    required List<Map<String, dynamic>> questions,
  }) {
    final isFailed = isCompleted && !isPassed;
    final hasCorrectProgress = correctCount > 0 && !isCompleted;

    final backgroundColor = isPassed
        ? AppColors.greenLight
        : isFailed
        ? AppColors.redLight
        : AppColors.cardBackground;
    final accentColor = isPassed
        ? AppColors.green
        : isFailed
        ? AppColors.red
        : hasCorrectProgress
        ? AppColors.accent
        : AppColors.secondaryText;
    final progressPillLabel = '$correctCount/$totalQuestions';

    return GestureDetector(
      onTap: () async {
        HapticFeedbackHelper.tap();
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TrainingScreen(
              questions: questions,
              title: '${AppStrings.ticket} $number',
              isExam: false,
            ),
          ),
        );
        _refreshProgress();
      },
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingM,
          vertical: 6,
        ),
        child: Center(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '№$number',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  progressPillLabel,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
