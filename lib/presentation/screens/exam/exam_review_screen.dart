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
    if (widget.questions.isEmpty || _order.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
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
            style: const TextStyle(color: AppColors.secondaryText),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryText,
                          ),
                        ),
                        Text(
                          appL10n.questionOfTotal(
                            _currentPos + 1,
                            _order.length,
                          ),
                          key: ValueKey<int>(_currentPos),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.secondaryText,
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
                    bg = AppColors.accent;
                  } else if (selI == null) {
                    bg = AppColors.red;
                  } else if (correct) {
                    bg = AppColors.green;
                  } else {
                    bg = AppColors.red;
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
                itemBuilder: (context, pos) => _buildReviewPage(pos),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        color: AppColors.white,
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

  Widget _buildReviewPage(int pos) {
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
                color: AppColors.redLight,
                borderRadius: BorderRadius.circular(
                  AppDimensions.smallRadius,
                ),
              ),
              child: Text(
                appL10n.notAnsweredThisQuestion,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.red,
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
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
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
            Widget? icon;
            if (isCorrect) {
              bg = AppColors.green;
              tc = AppColors.white;
              icon = const Icon(Icons.check, color: AppColors.white, size: 20);
            } else if (isSelected) {
              bg = AppColors.red;
              tc = AppColors.white;
              icon = const Icon(Icons.close, color: AppColors.white, size: 20);
            } else {
              bg = AppColors.gray;
              tc = AppColors.secondaryText;
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
                    Text(
                      '${i + 1}.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tc,
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
                    if (icon != null) icon,
                  ],
                ),
              ),
            );
          }),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.spacingL),
            _commentBlock(comment, pddPoints),
          ],
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _commentBlock(String comment, List<dynamic> pddPoints) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb, color: AppColors.gold, size: 20),
              const SizedBox(width: 8),
              Text(
                appL10n.comment,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
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
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
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
                    color: AppColors.gold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    point.toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.gold,
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
