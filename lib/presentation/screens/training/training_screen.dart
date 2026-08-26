import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/constants/question_swipe_motion.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/question_number_strip_scroll.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/presentation/widgets/report_question_dialog.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/question_image.dart';
import 'package:pdd_app/presentation/widgets/question_number_chip.dart';
import 'package:pdd_app/presentation/widgets/pdd_comment_text.dart';
import 'package:pdd_app/presentation/screens/training/training_result_screen.dart';

class TrainingScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String title;
  final bool isExam;

  /// С какого вопроса открыть. Используется при возврате к незаконченной
  /// тренировке с главного экрана.
  final int startIndex;

  const TrainingScreen({
    super.key,
    required this.questions,
    required this.title,
    this.isExam = false,
    this.startIndex = 0,
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
    _currentIndex = widget.startIndex.clamp(0, widget.questions.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _checkFavorite();
    _rememberPosition();
    scheduleScrollQuestionStripToCurrent(
      controller: _questionStripController,
      currentIndex: _currentIndex,
    );
  }

  /// Запоминает, на каком вопросе человек сейчас — чтобы главный экран мог
  /// предложить «Продолжить». Экзамен не запоминаем: там своя логика с
  /// таймером, и вернуться в середину экзамена нельзя.
  void _rememberPosition() {
    if (widget.isExam) return;
    final ids = widget.questions
        .map((q) => q['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    // Запуск новой тренировки затирает прошлую сессию сам собой — отдельная
    // кнопка «сбросить старую» не нужна.
    unawaited(
      ref.read(progressDataSourceProvider).saveUnfinishedSession(
            title: widget.title,
            questionIds: ids,
            index: _currentIndex,
            category: ref.read(appSettingsProvider).ticketCategory,
          ),
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
    _rememberPosition();
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
      SoundEffectsService.instance.playCorrect();
      _clearSessionIfComplete();
      return;
    }

    setState(() => _wrongIndices.add(_currentIndex));
    HapticFeedbackHelper.error();
    SoundEffectsService.instance.playIncorrect();
    _clearSessionIfComplete();
  }

  /// Когда отвечены все вопросы, тренировка больше не «незаконченная» —
  /// убираем карточку «Продолжить» с главной, чтобы она не звала обратно
  /// в уже пройденный набор.
  void _clearSessionIfComplete() {
    if (widget.isExam) return;
    if (_savedChoices.any((c) => c == null)) return;
    unawaited(ref.read(progressDataSourceProvider).clearUnfinishedSession());
  }

  bool get _isAllAnswered => !_savedChoices.contains(null);

  /// Ищет следующий неотвеченный вопрос по кругу начиная от fromIndex
  int? _findNextUnansweredIndex([int? fromIndex]) {
    if (_isAllAnswered) return null;
    final start = fromIndex ?? _currentIndex;
    for (int i = 1; i <= widget.questions.length; i++) {
      final next = (start + i) % widget.questions.length;
      if (_savedChoices[next] == null) {
        return next;
      }
    }
    return null;
  }

  void _advanceQuestion() {
    final next = _findNextUnansweredIndex(_currentIndex);
    if (next != null) {
      _goToQuestion(next);
    } else if (_isAllAnswered) {
      _finishSession();
    }
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

  /// Завершение набора: показываем итог.
  ///
  /// Экран результата — только для набора из нескольких вопросов. Разбор
  /// одной ошибки из «Работы над ошибками» — это один вопрос, и подводить
  /// по нему итог было бы издевательством.
  void _finishSession() {
    _voiceScheduleGen++;
    // Озвучку останавливаем, но НЕ ждём: это обращение к плагину, и если он
    // не ответит, человек останется на последнем вопросе с нажатой кнопкой.
    // Прекращение речи — вспомогательное действие, переход от него зависеть
    // не должен.
    unawaited(TtsService.instance.stop());

    if (widget.questions.length < 2) {
      Navigator.of(context).pop();
      return;
    }

    final wrongQuestions = [
      for (final i in _wrongIndices) widget.questions[i],
    ];

    // pushReplacement: возвращаться из итога обратно в пройденные вопросы
    // незачем — «назад» должно вести к списку билетов или тем.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TrainingResultScreen(
          title: widget.title,
          total: widget.questions.length,
          correct: _correctIndices.length,
          wrongQuestions: wrongQuestions,
        ),
      ),
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

  /// Открывает форму жалобы на вопрос. Данные вопроса подставляются сами.
  Future<void> _reportQuestion(Map<String, dynamic> question) async {
    HapticFeedbackHelper.tap();
    final topics = question['topic'];
    await showReportQuestionDialog(
      context: context,
      questionId: question['id'] as String? ?? '',
      questionText: question['question'] as String?,
      ticketNumber: question['ticketNumber'] as int?,
      topic: topics is List && topics.isNotEmpty ? '${topics.first}' : null,
      mode: widget.title,
    );
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
        rawQuestionId: questionId,
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
          body: Center(child: Text(appL10n.noQuestions)),
        ),
      );
    }

    final colors = AppColors.of(context);
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
        backgroundColor: colors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              SizedBox(
                height: 36,
                width: double.infinity,
                child: ClipRect(
                  child: _buildQuestionNumbers(context),
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
          context,
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
    final colors = AppColors.of(context);
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
              child: QuestionImage(assetPath: imagePath),
            ),
          ],
          const SizedBox(height: AppDimensions.spacingL),
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
            final index = entry.key;
            final answer = entry.value as Map;
            return Padding(
              padding: const EdgeInsets.only(
                bottom: AppDimensions.spacingM,
              ),
              child: _buildAnswerOption(
                context,
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
              context,
              title: appL10n.hint,
              icon: Icons.lightbulb_outline,
              accentColor: colors.gold,
              comment: comment,
              pddPoints: pddPoints,
            ),
          ],
          if (showCommentAfterAnswer) ...[
            const SizedBox(height: AppDimensions.spacingL),
            _buildCommentCard(
              context,
              title: appL10n.comment,
              icon: Icons.lightbulb,
              accentColor: colors.gold,
              comment: comment,
              pddPoints: pddPoints,
            ),
          ],
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final colors = AppColors.of(context);
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                Text(
                  appL10n.questionOfTotal(
                    _currentIndex + 1,
                    widget.questions.length,
                  ),
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
    );
  }

  Widget _buildQuestionNumbers(BuildContext context) {
    final colors = AppColors.of(context);
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
              ? colors.accent
              : isCorrect
              ? colors.green
              : isWrong
              ? colors.red
              : colors.gray;

          return QuestionNumberChip(
            number: index + 1,
            backgroundColor: backgroundColor,
            muted: !isCurrent && !isCorrect && !isWrong,
            onTap: () => _goToQuestion(index),
          );
        },
    );
  }

  Widget _buildAnswerOption(
    BuildContext context, {
    required int questionIndex,
    required int index,
    required String text,
    required bool isCorrect,
    required bool requireConfirmation,
  }) {
    final colors = AppColors.of(context);
    final saved = _savedChoices[questionIndex];
    final isAnswered = saved != null;
    final isSelected = isAnswered
        ? (saved == index)
        : (questionIndex == _currentIndex && _selectedAnswerIndex == index);

    Color backgroundColor;
    Color textColor;

    if (isAnswered) {
      if (isCorrect) {
        backgroundColor = colors.green;
        textColor = AppColors.white;
      } else if (isSelected) {
        backgroundColor = colors.red;
        textColor = AppColors.white;
      } else {
        backgroundColor = colors.gray;
        textColor = colors.secondaryText;
      }
    } else if (requireConfirmation && isSelected) {
      backgroundColor = colors.accentSurface10;
      textColor = colors.primaryText;
    } else {
      backgroundColor = colors.cardBackground;
      textColor = colors.primaryText;
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isAnswered
                      ? (isCorrect || isSelected
                            ? AppColors.white.withValues(alpha: 0.28)
                            : colors.gray)
                      : isSelected
                      ? colors.accent.withValues(alpha: 0.12)
                      : colors.gray,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: isAnswered && isCorrect
                        ? const Icon(
                            Icons.check_rounded,
                            key: ValueKey('training_answer_check'),
                            color: AppColors.white,
                            size: 16,
                          )
                        : isAnswered && isSelected
                            ? const Icon(
                                Icons.close_rounded,
                                key: ValueKey('training_answer_close'),
                                color: AppColors.white,
                                size: 16,
                              )
                            : Text(
                                '${index + 1}',
                                key: ValueKey('training_answer_num_${index + 1}'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? colors.accent
                                      : colors.secondaryText,
                                ),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color accentColor,
    required String comment,
    required List<dynamic> pddPoints,
  }) {
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
              Icon(icon, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.goldLightSurface,
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

  Widget _buildBottomBar(
    BuildContext context, {
    required bool requireConfirmation,
    required bool hasHint,
  }) {
    final colors = AppColors.of(context);
    final isAnswered = _isAnswerSubmitted;
    final isAllComplete = _isAllAnswered;
    final canConfirm =
        requireConfirmation && _selectedAnswerIndex != null && !isAnswered;

    return Container(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      color: colors.cardBackground,
      child: SafeArea(
        top: false,
        child: isAnswered
            ? SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isAllComplete
                      ? () {
                          HapticFeedbackHelper.tap();
                          _finishSession();
                        }
                      : _nextQuestion,
                  child: Text(
                    isAllComplete ? appL10n.finishButton : appL10n.nextQuestion,
                  ),
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
                                WidgetStateProperty.all(colors.gold),
                            overlayColor:
                                WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.pressed) ||
                                  states.contains(WidgetState.hovered) ||
                                  states.contains(WidgetState.focused)) {
                                return colors.goldLightSurface;
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
                            color: colors.gold,
                          ),
                          label: Text(
                            _showHint ? appL10n.hideHint : appL10n.showHint,
                            style: TextStyle(color: colors.gold),
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
                                ? colors.gold
                                : colors.secondaryText,
                          ),
                        ),
                        tooltip: appL10n.favorites,
                      ),
                      IconButton(
                        onPressed: () =>
                            _reportQuestion(widget.questions[_currentIndex]),
                        icon: Icon(
                          Icons.flag_outlined,
                          color: colors.secondaryText,
                        ),
                        tooltip: appL10n.reportQuestionTooltip,
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
                        child: Text(appL10n.confirmAnswerButton),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
