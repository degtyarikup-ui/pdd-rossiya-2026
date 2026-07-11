import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/constants/question_swipe_motion.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/question_number_strip_scroll.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

class TrainingScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String title;
  final bool isExam;

  const TrainingScreen({
    super.key,
    required this.questions,
    required this.title,
    this.isExam = false,
  });

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends ConsumerState<TrainingScreen> {
  late List<int?> _savedChoices;
  int _currentIndex = 0;
  int? _selectedAnswerIndex;
  bool _isAnswerSubmitted = false;
  bool _isFavorite = false;
  final List<int> _correctIndices = [];
  final List<int> _wrongIndices = [];
  bool _showHint = false;
  String? _lastSpokenQuestionId;
  int _voiceScheduleGen = 0;
  late final PageController _pageController;
  final ScrollController _questionStripController = ScrollController();

  @override
  void initState() {
    super.initState();
    _savedChoices = List<int?>.filled(widget.questions.length, null);
    _pageController = PageController();
    _checkFavorite();
    scheduleScrollQuestionStripToCurrent(
      controller: _questionStripController,
      currentIndex: _currentIndex,
    );
  }

  void _onQuestionPageChanged(int i) {
    if (i < 0 || i >= widget.questions.length) return;
    _invalidateVoicePlayback();
    setState(() {
      _currentIndex = i;
      final saved = _savedChoices[i];
      _selectedAnswerIndex = saved;
      _isAnswerSubmitted = saved != null;
      _showHint = false;
    });
    _checkFavorite();
    scheduleScrollQuestionStripToCurrent(
      controller: _questionStripController,
      currentIndex: _currentIndex,
    );
  }

  Future<void> _checkFavorite() async {
    if (_currentIndex >= widget.questions.length) return;

    final question = widget.questions[_currentIndex];
    final dataSource = ref.read(progressDataSourceProvider);
    final TicketCategory category = ref.read(appSettingsProvider).ticketCategory;
    final favorite =
        await dataSource.isFavorite(question['id'] as String, category);

    if (mounted) {
      setState(() => _isFavorite = favorite);
    }
  }

  void _selectAnswer(int index, {required bool requireConfirmation}) {
    if (_isAnswerSubmitted) return;

    if (requireConfirmation) {
      // Только выбор варианта — лёгкий отклик выбора. Подтверждение придёт
      // отдельным действием.
      HapticFeedbackHelper.tap();
      setState(() => _selectedAnswerIndex = index);
      return;
    }

    // Прямая отправка: единственный отклик даёт _submitAnswer (success/error).
    // Дополнительный tap() здесь ощущался как «двойная вибрация».
    _submitAnswer(index);
  }

  void _submitSelectedAnswer() {
    if (_selectedAnswerIndex == null || _isAnswerSubmitted) return;

    // Отклик даёт _submitAnswer по результату; свой tap() убран, иначе двойной.
    _submitAnswer(_selectedAnswerIndex!);
  }

  void _submitAnswer(int index) {
    final question = widget.questions[_currentIndex];
    final answers = question['answers'] as List;
    final isCorrect = answers[index]['correct'] as bool;
    final dataSource = ref.read(progressDataSourceProvider);
    final TicketCategory category = ref.read(appSettingsProvider).ticketCategory;

    setState(() {
      _selectedAnswerIndex = index;
      _isAnswerSubmitted = true;
      _savedChoices[_currentIndex] = index;
    });

    dataSource.saveAnswer(
      questionId: question['id'] as String,
      isCorrect: isCorrect,
      selectedAnswerIndex: index,
      category: category,
    );
    ref.read(appDataRefreshProvider.notifier).state++;

    if (isCorrect) {
      setState(() => _correctIndices.add(_currentIndex));
      HapticFeedbackHelper.success();
      return;
    }

    setState(() => _wrongIndices.add(_currentIndex));
    HapticFeedbackHelper.error();
  }

  void _advanceQuestion() {
    if (_currentIndex >= widget.questions.length - 1) return;
    final next = _currentIndex + 1;
    _pageController.animateToPage(
      next,
      duration: QuestionSwipeMotion.duration,
      curve: QuestionSwipeMotion.curve,
    );
  }

  void _goToQuestion(int index) {
    if (index < 0 || index >= widget.questions.length) return;
    if (index == _currentIndex) return;
    HapticFeedbackHelper.tap();
    _invalidateVoicePlayback();
    _pageController.animateToPage(
      index,
      duration: QuestionSwipeMotion.duration,
      curve: QuestionSwipeMotion.curve,
    );
  }

  void _nextQuestion() {
    HapticFeedbackHelper.tap();
    _advanceQuestion();
  }

  Future<void> _toggleFavorite() async {
    HapticFeedbackHelper.select();
    final question = widget.questions[_currentIndex];
    final dataSource = ref.read(progressDataSourceProvider);
    final TicketCategory category = ref.read(appSettingsProvider).ticketCategory;

    await dataSource.toggleFavorite(question['id'] as String, category);
    ref.read(appDataRefreshProvider.notifier).state++;

    if (mounted) {
      setState(() => _isFavorite = !_isFavorite);
    }
  }

  void _toggleHint() {
    HapticFeedbackHelper.tap();
    setState(() => _showHint = !_showHint);
  }

  void _invalidateVoicePlayback() {
    _voiceScheduleGen++;
    unawaited(TtsService.instance.stop());
  }

  Future<void> _stopVoiceAndPop([Object? result]) async {
    _voiceScheduleGen++;
    await TtsService.instance.stop();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _syncVoicePlayback({
    required String questionId,
    required String questionText,
    required List answers,
    required bool enabled,
  }) {
    if (!enabled) {
      _lastSpokenQuestionId = null;
      _invalidateVoicePlayback();
      return;
    }

    if (_lastSpokenQuestionId == questionId) {
      return;
    }

    _lastSpokenQuestionId = questionId;
    final gen = ++_voiceScheduleGen;
    final capturedIndex = _currentIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _voiceScheduleGen) return;
      if (_currentIndex != capturedIndex) return;
      if (_isAnswerSubmitted || _selectedAnswerIndex != null) return;
      final q = widget.questions[_currentIndex];
      if ((q['id'] as String) != questionId) return;
      if (!ref.read(appSettingsProvider).voiceEnabled) return;

      final answerTexts = answers
          .map((answer) => (answer as Map)['text'] as String)
          .toList();
      TtsService.instance.speakQuestion(
        question: questionText,
        answers: answerTexts,
      );
    });
  }

  @override
  void dispose() {
    _voiceScheduleGen++;
    unawaited(TtsService.instance.stop());
    _questionStripController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) async {
          if (didPop) return;
          await _stopVoiceAndPop(result);
        },
        child: Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: const Center(child: Text('Нет вопросов')),
        ),
      );
    }

    final appSettings = ref.watch(appSettingsProvider);
    final question = widget.questions[_currentIndex];
    final questionId = question['id'] as String;
    final answers = question['answers'] as List;
    final questionText = question['question'] as String;
    final comment = question['comment'] as String? ?? '';
    final isAnswered = _isAnswerSubmitted;
    final hasHint = comment.isNotEmpty;
    final voiceEnabled = appSettings.voiceEnabled;
    final voiceShouldPlay =
        voiceEnabled && !isAnswered && _selectedAnswerIndex == null;

    _syncVoicePlayback(
      questionId: questionId,
      questionText: questionText,
      answers: answers,
      enabled: voiceShouldPlay,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _stopVoiceAndPop(result);
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            SizedBox(
              height: 36,
              width: double.infinity,
              child: ClipRect(
                child: _buildQuestionNumbers(),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.questions.length,
                onPageChanged: _onQuestionPageChanged,
                itemBuilder: (context, pageIndex) {
                  return _buildTrainingQuestionPage(
                    context,
                    pageIndex,
                    requireConfirmation: appSettings.confirmAnswerEnabled,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(
        requireConfirmation: appSettings.confirmAnswerEnabled,
        hasHint: hasHint,
      ),
      ),
    );
  }

  Widget _buildTrainingQuestionPage(
    BuildContext context,
    int pageIndex, {
    required bool requireConfirmation,
  }) {
    final question = widget.questions[pageIndex];
    final answers = question['answers'] as List;
    final questionText = question['question'] as String;
    final comment = question['comment'] as String? ?? '';
    final pddPoints = question['pddPoints'] as List? ?? [];
    final imagePath = question['image'] as String?;
    final hasImage =
        imagePath != null && imagePath.isNotEmpty && imagePath != 'no_image';
    final saved = _savedChoices[pageIndex];
    final pageAnswered = saved != null;
    final hasHint = comment.isNotEmpty;
    final showHintBlock =
        pageIndex == _currentIndex && _showHint && !pageAnswered && hasHint;
    final showCommentAfterAnswer = pageAnswered && hasHint;

    return SingleChildScrollView(
      key: ValueKey<int>(pageIndex),
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImage) ...[
            const SizedBox(height: AppDimensions.spacingM),
            ClipRRect(
              borderRadius: BorderRadius.circular(
                AppDimensions.smallRadius,
              ),
              child: Image.asset(
                imagePath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  color: AppColors.gray,
                  child: const Center(
                    child: Icon(
                      Icons.image,
                      size: 48,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppDimensions.spacingL),
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
            final index = entry.key;
            final answer = entry.value as Map;
            return Padding(
              padding: const EdgeInsets.only(
                bottom: AppDimensions.spacingM,
              ),
              child: _buildAnswerOption(
                questionIndex: pageIndex,
                index: index,
                text: answer['text'] as String,
                isCorrect: answer['correct'] as bool,
                requireConfirmation: requireConfirmation,
              ),
            );
          }),
          if (showHintBlock) ...[
            const SizedBox(height: AppDimensions.spacingL),
            _buildCommentCard(
              title: 'Подсказка',
              icon: Icons.lightbulb_outline,
              accentColor: AppColors.gold,
              comment: comment,
              pddPoints: pddPoints,
            ),
          ],
          if (showCommentAfterAnswer) ...[
            const SizedBox(height: AppDimensions.spacingL),
            _buildCommentCard(
              title: 'Комментарий',
              icon: Icons.lightbulb,
              accentColor: AppColors.gold,
              comment: comment,
              pddPoints: pddPoints,
            ),
          ],
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
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
              _stopVoiceAndPop();
            },
          ),
          const SizedBox(width: AppDimensions.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
                Text(
                  'Вопрос ${_currentIndex + 1} из ${widget.questions.length}',
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
    );
  }

  Widget _buildQuestionNumbers() {
    return ListView.builder(
        controller: _questionStripController,
        scrollDirection: Axis.horizontal,
        primary: false,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.screenPadding,
        ),
        itemCount: widget.questions.length,
        itemBuilder: (context, index) {
          final isCurrent = index == _currentIndex;
          final isCorrect = _correctIndices.contains(index);
          final isWrong = _wrongIndices.contains(index);

          final backgroundColor = isCurrent
              ? AppColors.accent
              : isCorrect
              ? AppColors.green
              : isWrong
              ? AppColors.red
              : AppColors.gray;

          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _goToQuestion(index),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
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
    );
  }

  Widget _buildAnswerOption({
    required int questionIndex,
    required int index,
    required String text,
    required bool isCorrect,
    required bool requireConfirmation,
  }) {
    final saved = _savedChoices[questionIndex];
    final isAnswered = saved != null;
    final isSelected = isAnswered
        ? (saved == index)
        : (questionIndex == _currentIndex && _selectedAnswerIndex == index);

    Color backgroundColor;
    Color textColor;
    Widget? trailingIcon;

    if (isAnswered) {
      if (isCorrect) {
        backgroundColor = AppColors.green;
        textColor = AppColors.white;
        trailingIcon = const Icon(
          Icons.check,
          color: AppColors.white,
          size: 20,
        );
      } else if (isSelected) {
        backgroundColor = AppColors.red;
        textColor = AppColors.white;
        trailingIcon = const Icon(
          Icons.close,
          color: AppColors.white,
          size: 20,
        );
      } else {
        backgroundColor = AppColors.gray;
        textColor = AppColors.secondaryText;
      }
    } else if (requireConfirmation && isSelected) {
      backgroundColor = AppColors.lightAccent;
      textColor = AppColors.primaryText;
    } else {
      backgroundColor = AppColors.cardBackground;
      textColor = AppColors.primaryText;
    }

    final canTap =
        !isAnswered && questionIndex == _currentIndex;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canTap
            ? () => _selectAnswer(
                index,
                requireConfirmation: requireConfirmation,
              )
            : null,
        borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(AppDimensions.spacingL),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isAnswered
                      ? (isCorrect || isSelected
                            ? AppColors.white.withOpacity(0.3)
                            : AppColors.gray)
                      : isSelected
                      ? AppColors.accent.withOpacity(0.12)
                      : AppColors.gray,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isAnswered
                          ? (isCorrect || isSelected
                                ? AppColors.white
                                : AppColors.secondaryText)
                          : isSelected
                          ? AppColors.accent
                          : AppColors.secondaryText,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                    height: 1.35,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                trailingIcon,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required String comment,
    required List<dynamic> pddPoints,
  }) {
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
              Icon(icon, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingS),
          Text(
            comment,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.primaryText,
              height: 1.45,
            ),
          ),
          if (pddPoints.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.spacingM),
            const Text(
              'Пункты ПДД',
              style: TextStyle(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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

  Widget _buildBottomBar({
    required bool requireConfirmation,
    required bool hasHint,
  }) {
    final isAnswered = _isAnswerSubmitted;
    final isLast = _currentIndex >= widget.questions.length - 1;
    final canConfirm =
        requireConfirmation && _selectedAnswerIndex != null && !isAnswered;

    return Container(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      color: AppColors.white,
      child: SafeArea(
        top: false,
        child: isAnswered
            ? SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isLast
                      ? () {
                          HapticFeedbackHelper.tap();
                          _stopVoiceAndPop();
                        }
                      : _nextQuestion,
                  child: Text(isLast ? 'Завершить' : 'Следующий вопрос'),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: hasHint ? _toggleHint : null,
                          style: ButtonStyle(
                            foregroundColor:
                                WidgetStateProperty.all(AppColors.gold),
                            overlayColor:
                                WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.pressed) ||
                                  states.contains(WidgetState.hovered) ||
                                  states.contains(WidgetState.focused)) {
                                return AppColors.goldLightSurface;
                              }
                              return Colors.transparent;
                            }),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          icon: Icon(
                            _showHint
                                ? Icons.lightbulb
                                : Icons.lightbulb_outline,
                            color: AppColors.gold,
                          ),
                          label: Text(
                            _showHint
                                ? 'Скрыть подсказку'
                                : 'Показать подсказку',
                            style: const TextStyle(color: AppColors.gold),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleFavorite,
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            _isFavorite ? Icons.star : Icons.star_border,
                            key: ValueKey(_isFavorite),
                            color: _isFavorite
                                ? AppColors.gold
                                : AppColors.secondaryText,
                          ),
                        ),
                        tooltip: 'Избранное',
                      ),
                    ],
                  ),
                  if (requireConfirmation) ...[
                    const SizedBox(height: AppDimensions.spacingM),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: canConfirm ? _submitSelectedAnswer : null,
                        child: const Text('Подтвердить ответ'),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
