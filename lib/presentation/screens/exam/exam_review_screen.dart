import 'package:flutter/material.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/constants/question_swipe_motion.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/question_number_strip_scroll.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/question_image.dart';
import 'package:pdd_app/presentation/widgets/pdd_comment_text.dart';

/// Разбор после экзамена: все вопросы по порядку, верность ответов и комментарий.
class ExamReviewScreen extends ConsumerStatefulWidget {
  const ExamReviewScreen({
    super.key,
    required this.questions,
    required this.savedAnswers,
  });

  final List<Map<String, dynamic>> questions;
  final List<int?> savedAnswers;

  @override
  ConsumerState<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ExamReviewScreenState extends ConsumerState<ExamReviewScreen> {
  late int _currentPos;
  late List<int> _order;
  final ScrollController _stripController = ScrollController();
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _order = List.generate(widget.questions.length, (i) => i);
    _currentPos = 0;
    _pageController = PageController();
    scheduleScrollQuestionStripToCurrent(
      controller: _stripController,
      currentIndex: _currentPos,
    );
  }

  @override
  void dispose() {
    _stripController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onReviewPageChanged(int pos) {
    if (pos < 0 || pos >= _order.length) return;
    setState(() => _currentPos = pos);
    scheduleScrollQuestionStripToCurrent(
      controller: _stripController,
      currentIndex: _currentPos,
    );
  }

  void _goToStripIndex(int pos) {
    if (pos < 0 || pos >= _order.length) return;
    if (pos == _currentPos) return;
    HapticFeedbackHelper.tap();
    _pageController.animateToPage(
      pos,
      duration: QuestionSwipeMotion.duration,
      curve: QuestionSwipeMotion.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (widget.questions.isEmpty || _order.isEmpty) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          elevation: 0,
          leading: AppChromeIconButton(
            icon: Icons.close_rounded,
            onTap: () => Navigator.pop(context),
          ),
          title: Text(appL10n.myMistakes),
        ),
        body: Center(
          child: Text(
            appL10n.noQuestionsToReview,
            style: TextStyle(color: colors.secondaryText),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.screenPadding,
                vertical: AppDimensions.spacingM,
              ),
              child: Row(
                children: [
                  AppChromeIconButton(
                    icon: Icons.close_rounded,
                    onTap: () {
                      HapticFeedbackHelper.tap();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: AppDimensions.spacingM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appL10n.examReview,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.primaryText,
                          ),
                        ),
                        Text(
                          appL10n.questionOfTotal(
                            _currentPos + 1,
                            _order.length,
                          ),
                          key: ValueKey<int>(_currentPos),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView.builder(
                controller: _stripController,
                scrollDirection: Axis.horizontal,
                primary: false,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.screenPadding,
                ),
                itemCount: _order.length,
                itemBuilder: (context, pos) {
                  final isCurrent = pos == _currentPos;
                  final idx = _order[pos];
                  final qMap = widget.questions[idx];
                  final ansList = qMap['answers'] as List;
                  final selI = widget.savedAnswers[idx];
                  final correct = selI != null &&
                      (ansList[selI]['correct'] as bool);

                  Color bg;
                  if (isCurrent) {
                    bg = colors.accent;
                  } else if (selI == null) {
                    bg = colors.red;
                  } else if (correct) {
                    bg = colors.green;
                  } else {
                    bg = colors.red;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _goToStripIndex(pos),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _order.length,
                onPageChanged: _onReviewPageChanged,
                itemBuilder: (context, pos) => _buildReviewPage(context, pos),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        color: colors.cardBackground,
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _currentPos >= _order.length - 1
                  ? () {
                      HapticFeedbackHelper.tap();
                      Navigator.pop(context);
                    }
                  : () {
                      HapticFeedbackHelper.tap();
                      _pageController.animateToPage(
                        _currentPos + 1,
                        duration: QuestionSwipeMotion.duration,
                        curve: QuestionSwipeMotion.curve,
                      );
                    },
              child: Text(
                _currentPos >= _order.length - 1
                    ? appL10n.close
                    : appL10n.next,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewPage(BuildContext context, int pos) {
    final colors = AppColors.of(context);
    final idx = _order[pos];
    final q = widget.questions[idx];
    final answers = q['answers'] as List;
    final questionText = q['question'] as String;
    final comment = q['comment'] as String? ?? '';
    final pddPoints = q['pddPoints'] as List? ?? [];
    final imagePath = q['image'] as String?;
    final hasImage =
        imagePath != null && imagePath.isNotEmpty && imagePath != 'no_image';
    final selected = widget.savedAnswers[idx];
    final isUnanswered = selected == null;

    return SingleChildScrollView(
      key: ValueKey<int>(pos),
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isUnanswered)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDimensions.spacingM),
              margin: const EdgeInsets.only(bottom: AppDimensions.spacingM),
              decoration: BoxDecoration(
                color: colors.redLight,
                borderRadius: BorderRadius.circular(
                  AppDimensions.smallRadius,
                ),
              ),
              child: Text(
                appL10n.notAnsweredThisQuestion,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.red,
                ),
              ),
            ),
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(
                AppDimensions.smallRadius,
              ),
              child: QuestionImage(assetPath: imagePath),
            ),
            const SizedBox(height: AppDimensions.spacingL),
          ],
          Text(
            questionText,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          ...answers.asMap().entries.map((entry) {
            final i = entry.key;
            final answer = entry.value as Map;
            final isCorrect = answer['correct'] as bool;
            final isSelected = selected == i;
            Color bg;
            Color tc;
            if (isCorrect) {
              bg = colors.green;
              tc = AppColors.white;
            } else if (isSelected) {
              bg = colors.red;
              tc = AppColors.white;
            } else {
              bg = colors.gray;
              tc = colors.secondaryText;
            }
            return Padding(
              padding: const EdgeInsets.only(
                bottom: AppDimensions.spacingM,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppDimensions.spacingL),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(
                    AppDimensions.smallRadius,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isCorrect || isSelected
                            ? AppColors.white.withValues(alpha: 0.28)
                            : colors.gray,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: isCorrect
                            ? const Icon(
                                Icons.check_rounded,
                                color: AppColors.white,
                                size: 16,
                              )
                            : isSelected
                                ? const Icon(
                                    Icons.close_rounded,
                                    color: AppColors.white,
                                    size: 16,
                                  )
                                : Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: colors.secondaryText,
                                    ),
                                  ),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacingM),
                    Expanded(
                      child: Text(
                        answer['text'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: tc,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.spacingL),
            _commentBlock(context, comment, pddPoints),
          ],
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _commentBlock(BuildContext context, String comment, List<dynamic> pddPoints) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, color: colors.gold, size: 20),
              const SizedBox(width: 8),
              Text(
                appL10n.comment,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingS),
          PddCommentText(comment),
          if (pddPoints.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.spacingM),
            Text(
              appL10n.pddPoints,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingXS),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: pddPoints.map((point) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    point.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.gold,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
