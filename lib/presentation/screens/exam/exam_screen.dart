import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/constants/question_swipe_motion.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/question_number_strip_scroll.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/presentation/screens/exam/exam_review_screen.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

class ExamScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> allQuestions;

  const ExamScreen({super.key, required this.allQuestions});

  @override
  ConsumerState<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends ConsumerState<ExamScreen> {
  late List<Map<String, dynamic>> _examQuestions;
  late List<int?> _savedAnswers;
  int _currentIndex = 0;
  int? _selectedAnswerIndex;
  bool _isAnswerSubmitted = false;
  final List<int> _wrongAnswers = [];
  final List<int> _correctAnswers = [];
  int _remainingTime = 20 * 60;
  Timer? _timer;
  bool _examFinished = false;
  bool _additionalPhase = false;
  int _additionalQuestionsCount = 0;
  int _initialWrongCount = 0;
  bool _timedOut = false;
  String? _lastSpokenQuestionId;
  int _voiceScheduleGen = 0;
  PageController? _pageController;
  final ScrollController _questionStripController = ScrollController();

  @override
  void initState() {
    super.initState();
    _prepareExam();
    if (_examQuestions.isNotEmpty) {
      _pageController = PageController();
    }
    scheduleScrollQuestionStripToCurrent(
      controller: _questionStripController,
      currentIndex: _currentIndex,
    );
  }

  void _onExamPageChanged(int i) {
    if (i < 0 || i >= _examQuestions.length) return;
    _lastSpokenQuestionId = null;
    _invalidateVoicePlayback();
    setState(() {
      _currentIndex = i;
      final saved = _savedAnswers[i];
      _selectedAnswerIndex = saved;
      _isAnswerSubmitted = saved != null;
    });
    scheduleScrollQuestionStripToCurrent(
      controller: _questionStripController,
      currentIndex: _currentIndex,
    );
  }

  void _prepareExam() {
    final random = Random();
    final shuffled = List<Map<String, dynamic>>.from(widget.allQuestions)
      ..shuffle(random);
    _examQuestions = shuffled.take(20).toList();
    _savedAnswers = List<int?>.filled(_examQuestions.length, null);
    _startTimer();
  }

  int _mainWrongTotal() {
    final end = _examQuestions.length < 20 ? _examQuestions.length : 20;
    var w = 0;
    for (var i = 0; i < end; i++) {
      final s = _savedAnswers[i];
      if (s == null) {
        w++;
        continue;
      }
      final ok = (_examQuestions[i]['answers'] as List)[s]['correct'] as bool;
      if (!ok) w++;
    }
    return w;
  }

  int _additionalWrongTotal() {
    var w = 0;
    for (var i = 20; i < _examQuestions.length; i++) {
      final s = _savedAnswers[i];
      if (s == null) {
        w++;
        continue;
      }
      final ok = (_examQuestions[i]['answers'] as List)[s]['correct'] as bool;
      if (!ok) w++;
    }
    return w;
  }

  void _recomputeScoreLists() {
    _correctAnswers.clear();
    _wrongAnswers.clear();
    for (var i = 0; i < _examQuestions.length; i++) {
      final s = _savedAnswers[i];
      if (s == null) {
        _wrongAnswers.add(i);
        continue;
      }
      final ok = (_examQuestions[i]['answers'] as List)[s]['correct'] as bool;
      if (ok) {
        _correctAnswers.add(i);
      } else {
        _wrongAnswers.add(i);
      }
    }
  }

  /// Первый неотвеченный вопрос основного блока (0..19), если есть.
  int? _firstUnansweredMainIndex() {
    final end = _examQuestions.length < 20 ? _examQuestions.length : 20;
    for (var i = 0; i < end; i++) {
      if (_savedAnswers[i] == null) return i;
    }
    return null;
  }

  /// Первый неотвеченный в дополнительной фазе (индексы с 20).
  int? _firstUnansweredAdditionalIndex() {
    for (var i = 20; i < _examQuestions.length; i++) {
      if (_savedAnswers[i] == null) return i;
    }
    return null;
  }

  void _goToQuestion(int index) {
    if (index < 0 || index >= _examQuestions.length) return;
    if (index == _currentIndex) return;
    final c = _pageController;
    if (c == null) return;
    HapticFeedbackHelper.tap();
    _lastSpokenQuestionId = null;
    _invalidateVoicePlayback();
    c.animateToPage(
      index,
      duration: QuestionSwipeMotion.duration,
      curve: QuestionSwipeMotion.curve,
    );
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _examFinished) return;

      if (_remainingTime <= 1) {
        _timedOut = true;
        _remainingTime = 0;
        _finishExam();
        return;
      }

      setState(() => _remainingTime--);
    });
  }

  void _selectAnswer(int index) {
    if (_isAnswerSubmitted) return;

    HapticFeedbackHelper.tap();
    _submitAnswer(index, advanceToNextAfterSubmit: true);
  }

  void _submitAnswer(int index, {bool advanceToNextAfterSubmit = false}) {
    final question = _examQuestions[_currentIndex];
    final answers = question['answers'] as List;
    final isCorrect = answers[index]['correct'] as bool;
    final dataSource = ref.read(progressDataSourceProvider);
    final TicketCategory category = ref.read(appSettingsProvider).ticketCategory;

    setState(() {
      _selectedAnswerIndex = index;
      _isAnswerSubmitted = true;
      _savedAnswers[_currentIndex] = index;
    });

    dataSource.saveAnswer(
      questionId: question['id'] as String,
      isCorrect: isCorrect,
      selectedAnswerIndex: index,
      category: category,
    );
    ref.read(appDataRefreshProvider.notifier).state++;

    if (isCorrect) {
      _correctAnswers.add(_currentIndex);
    } else {
      _wrongAnswers.add(_currentIndex);
    }

    if (advanceToNextAfterSubmit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _nextQuestion();
      });
    }
  }

  void _moveToNextQuestion() {
    final c = _pageController;
    if (c == null) return;
    final next = _currentIndex + 1;
    c.animateToPage(
      next,
      duration: QuestionSwipeMotion.duration,
      curve: QuestionSwipeMotion.curve,
    );
  }

  void _nextQuestion() {
    if (!_additionalPhase) {
      final mainLast = _examQuestions.length - 1;
      if (mainLast >= 0 && _currentIndex >= mainLast) {
        final pending = _firstUnansweredMainIndex();
        if (pending != null) {
          _goToQuestion(pending);
          return;
        }

        final mainWrong = _mainWrongTotal();
        if (mainWrong == 0) {
          _finishExam();
          return;
        }

        if (mainWrong == 1) {
          _startAdditionalPhase(5);
          return;
        }

        if (mainWrong == 2) {
          _startAdditionalPhase(10);
          return;
        }

        _finishExam();
        return;
      }

      _moveToNextQuestion();
      return;
    }

    if (_currentIndex < _examQuestions.length - 1) {
      _moveToNextQuestion();
      return;
    }

    final pendingAdd = _firstUnansweredAdditionalIndex();
    if (pendingAdd != null) {
      _goToQuestion(pendingAdd);
      return;
    }

    _finishExam();
  }

  void _startAdditionalPhase(int count) {
    final random = Random();
    final usedIds = _examQuestions.map((q) => q['id'] as String).toSet();
    final available =
        widget.allQuestions.where((q) => !usedIds.contains(q['id'])).toList()
          ..shuffle(random);
    final additional = available.take(count).toList();

    setState(() {
      _initialWrongCount = _mainWrongTotal();
      _examQuestions.addAll(additional);
      _savedAnswers.addAll(List<int?>.filled(count, null));
      _additionalPhase = true;
      _additionalQuestionsCount = count;
      _currentIndex++;
      _selectedAnswerIndex = _savedAnswers[_currentIndex];
      _isAnswerSubmitted = _savedAnswers[_currentIndex] != null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _pageController;
      if (c != null && c.hasClients) {
        c.jumpToPage(_currentIndex);
      }
      scheduleScrollQuestionStripToCurrent(
        controller: _questionStripController,
        currentIndex: _currentIndex,
      );
    });
  }

  void _finishExam() {
    if (_examFinished) return;

    _lastSpokenQuestionId = null;
    _invalidateVoicePlayback();

    _timer?.cancel();

    _recomputeScoreLists();
    final totalWrong = _wrongAnswers.length;
    final passed = !_timedOut &&
        (_additionalPhase
            ? _additionalWrongTotal() == 0
            : _mainWrongTotal() <= 2);

    final dataSource = ref.read(progressDataSourceProvider);
    final TicketCategory category = ref.read(appSettingsProvider).ticketCategory;
    dataSource.saveExamResult(
      ticketNumber: 0,
      correctAnswers: _correctAnswers.length,
      wrongAnswers: totalWrong,
      passed: passed,
      category: category,
    );
    ref.read(appDataRefreshProvider.notifier).state++;

    setState(() {
      _examFinished = true;
    });

    if (passed) {
      HapticFeedbackHelper.success();
    } else {
      HapticFeedbackHelper.error();
    }
  }

  void _invalidateVoicePlayback() {
    _voiceScheduleGen++;
    ref.read(ttsServiceProvider).stop();
  }

  void _syncVoicePlayback({
    required String questionId,
    required String questionText,
    required List answers,
    required bool enabled,
  }) {
    final ttsService = ref.read(ttsServiceProvider);

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
      if (_examFinished) return;
      if (_currentIndex != capturedIndex) return;
      if (_isAnswerSubmitted || _selectedAnswerIndex != null) return;
      final q = _examQuestions[_currentIndex];
      if ((q['id'] as String) != questionId) return;
      if (!ref.read(appSettingsProvider).voiceEnabled) return;

      final answerTexts = answers
          .map((answer) => (answer as Map)['text'] as String)
          .toList();
      ttsService.speakQuestion(question: questionText, answers: answerTexts);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _invalidateVoicePlayback();
    _questionStripController.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_examFinished) {
      return _buildResultsScreen();
    }

    if (_examQuestions.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final appSettings = ref.watch(appSettingsProvider);
    final question = _examQuestions[_currentIndex];
    final questionId = question['id'] as String;
    final answers = question['answers'] as List;
    final questionText = question['question'] as String;
    final isAnswered = _isAnswerSubmitted;
    final voiceEnabled = appSettings.voiceEnabled;
    final voiceShouldPlay =
        voiceEnabled && !isAnswered && _selectedAnswerIndex == null;

    _syncVoicePlayback(
      questionId: questionId,
      questionText: questionText,
      answers: answers,
      enabled: voiceShouldPlay,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
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
                      _timer?.cancel();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: AppDimensions.spacingM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _additionalPhase
                              ? 'Дополнительные вопросы'
                              : 'Экзамен',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryText,
                          ),
                        ),
                        Text(
                          'Вопрос ${_currentIndex + 1} из ${_examQuestions.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _remainingTime < 120
                          ? AppColors.redLight
                          : AppColors.lightAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 18,
                          color: _remainingTime < 120
                              ? AppColors.red
                              : AppColors.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(_remainingTime),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _remainingTime < 120
                                ? AppColors.red
                                : AppColors.accent,
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
              width: double.infinity,
              child: ClipRect(
                child: _buildQuestionNumbers(),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController!,
                itemCount: _examQuestions.length,
                onPageChanged: _onExamPageChanged,
                itemBuilder: (context, pageIndex) {
                  return _buildExamQuestionPage(pageIndex);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamQuestionPage(int pageIndex) {
    final question = _examQuestions[pageIndex];
    final answers = question['answers'] as List;
    final questionText = question['question'] as String;
    final imagePath = question['image'] as String?;
    final hasImage =
        imagePath != null && imagePath.isNotEmpty && imagePath != 'no_image';

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
              child: _buildExamAnswerOption(
                questionIndex: pageIndex,
                index: index,
                text: answer['text'] as String,
              ),
            );
          }),
          const SizedBox(height: AppDimensions.spacingXXL),
        ],
      ),
    );
  }

  Widget _buildResultsScreen() {
    final totalWrong = _wrongAnswers.length;
    final totalQuestions = _examQuestions.length;
    final passed = !_timedOut &&
        (_additionalPhase
            ? _additionalWrongTotal() == 0
            : _mainWrongTotal() <= 2);
    final timeSpent = 20 * 60 - _remainingTime;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppDimensions.screenPadding),
              child: Row(
                children: [
                  AppChromeIconButton(
                    icon: Icons.close_rounded,
                    onTap: () {
                      HapticFeedbackHelper.tap();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDimensions.screenPadding),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: passed ? AppColors.green : AppColors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        passed ? Icons.check_circle : Icons.cancel,
                        size: 60,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingL),
                    Text(
                      passed ? 'Экзамен сдан!' : 'Экзамен не сдан',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: passed ? AppColors.green : AppColors.red,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingS),
                    Text(
                      _timedOut
                          ? 'Время вышло. Попробуйте снова в спокойном темпе.'
                          : passed
                          ? 'Отличный результат. Можно закрепить его билетами.'
                          : 'Разберите ошибки и повторите слабые места.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingXXL),
                    _buildResultCard(
                      icon: Icons.check_circle_outline,
                      label: 'Правильных ответов',
                      value: '${_correctAnswers.length} из $totalQuestions',
                      color: AppColors.green,
                    ),
                    const SizedBox(height: AppDimensions.spacingM),
                    _buildResultCard(
                      icon: Icons.cancel_outlined,
                      label: 'Неправильных ответов',
                      value: '$totalWrong',
                      color: AppColors.red,
                    ),
                    if (_additionalPhase) ...[
                      const SizedBox(height: AppDimensions.spacingM),
                      _buildResultCard(
                        icon: Icons.help_outline,
                        label: 'Дополнительный блок',
                        value:
                            '$_additionalQuestionsCount вопросов, ошибок: ${_additionalWrongTotal()}',
                        color: AppColors.gold,
                      ),
                    ],
                    const SizedBox(height: AppDimensions.spacingM),
                    _buildResultCard(
                      icon: Icons.timer_outlined,
                      label: 'Затраченное время',
                      value: _formatTime(timeSpent),
                      color: AppColors.accent,
                    ),
                    if (_additionalPhase) ...[
                      const SizedBox(height: AppDimensions.spacingM),
                      _buildResultCard(
                        icon: Icons.rule_folder_outlined,
                        label: 'Ошибок в основном блоке',
                        value: '$_initialWrongCount',
                        color: AppColors.primaryText,
                      ),
                    ],
                    const SizedBox(height: AppDimensions.spacingXXL),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () {
                          HapticFeedbackHelper.tap();
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (ctx) => ExamReviewScreen(
                                questions: List<Map<String, dynamic>>.from(
                                  _examQuestions,
                                ),
                                savedAnswers: List<int?>.from(_savedAnswers),
                              ),
                            ),
                          );
                        },
                        child: const Text('Мои ошибки'),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingM),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedbackHelper.tap();
                          Navigator.pop(context);
                        },
                        child: const Text('Вернуться к обучению'),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: AppDimensions.spacingM),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: color,
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
      itemCount: _examQuestions.length,
      itemBuilder: (context, index) {
        final isCurrent = index == _currentIndex;
        final answered = _savedAnswers[index] != null;
        final backgroundColor = isCurrent
            ? AppColors.accent
            : answered
                ? AppColors.accent.withOpacity(0.42)
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

  /// Во время экзамена не показываем верность ответа и не подсвечиваем правильный вариант.
  Widget _buildExamAnswerOption({
    required int questionIndex,
    required int index,
    required String text,
  }) {
    final saved = _savedAnswers[questionIndex];
    final isAnswered = saved != null;
    final isSelected = isAnswered
        ? (saved == index)
        : (questionIndex == _currentIndex && _selectedAnswerIndex == index);

    Color backgroundColor;
    Color textColor;

    if (isAnswered) {
      if (isSelected) {
        backgroundColor = AppColors.lightAccent;
        textColor = AppColors.primaryText;
      } else {
        backgroundColor = AppColors.cardBackground;
        textColor = AppColors.secondaryText;
      }
    } else if (isSelected) {
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
        onTap: canTap ? () => _selectAnswer(index) : null,
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
                      ? (isSelected
                            ? AppColors.accent.withOpacity(0.2)
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
                          ? (isSelected
                                ? AppColors.accent
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
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
