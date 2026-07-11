import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/constants/question_swipe_motion.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/question_number_strip_scroll.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/presentation/screens/exam/exam_review_screen.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

class ExamScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> allQuestions;

  /// Правила экзамена. По умолчанию — правила страны сборки;
  /// параметр нужен тестам, чтобы проверять RU и BY на одном коде.
  final ExamRules? rules;

  const ExamScreen({super.key, required this.allQuestions, this.rules});

  @override
  ConsumerState<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends ConsumerState<ExamScreen> {
  late final ExamRules _rules =
      widget.rules ?? CountryConfig.current.examRules;

  /// Размер основного блока экзамена (страно-зависимый).
  int get _mainCount => _rules.mainCount;

  late List<Map<String, dynamic>> _examQuestions;
  late List<int?> _savedAnswers;
  int _currentIndex = 0;
  int? _selectedAnswerIndex;
  bool _isAnswerSubmitted = false;
  final List<int> _wrongAnswers = [];
  final List<int> _correctAnswers = [];
  int _unansweredTotal = 0;
  late int _remainingTime = _rules.totalSeconds;
  late int _totalTimeSeconds = _rules.totalSeconds;
  Timer? _timer;
  bool _examFinished = false;
  bool _examPassed = false;
  bool _additionalPhase = false;
  int _additionalQuestionsCount = 0;
  int _initialWrongCount = 0;
  bool _timedOut = false;
  String? _lastSpokenQuestionId;
  int _voiceScheduleGen = 0;
  PageController? _pageController;
  final ScrollController _questionStripController = ScrollController();

  /// Кэш сервиса озвучки: ref нельзя использовать в dispose,
  /// а озвучку там нужно останавливать.
  late final TtsService _ttsService;

  @override
  void initState() {
    super.initState();
    _ttsService = ref.read(ttsServiceProvider);
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
    // Страховка от «зависших» состояний: если к этому моменту фаза уже
    // завершена по правилам (всё отвечено / лимит ошибок), доводим экзамен
    // до перехода или результатов. Без advance — навигацией управляет юзер.
    _evaluateExamState(advance: false);
  }

  void _prepareExam() {
    final random = Random();
    final shuffled = List<Map<String, dynamic>>.from(widget.allQuestions)
      ..shuffle(random);
    _examQuestions = shuffled.take(_mainCount).toList();
    // ВАЖНО: growable — при переходе к доп. вопросам список расширяется.
    // List.filled по умолчанию фиксированной длины, addAll на нём бросает
    // UnsupportedError и оставляет экзамен в полусломанном состоянии.
    _savedAnswers =
        List<int?>.filled(_examQuestions.length, null, growable: true);
    _startTimer();
  }

  bool _isAnswerWrongAt(int i) {
    final s = _savedAnswers[i];
    if (s == null) return false;
    return !((_examQuestions[i]['answers'] as List)[s]['correct'] as bool);
  }

  /// Ошибки основного блока; неотвеченные вопросы считаются ошибками.
  /// Используется только при подведении итогов (таймаут / досрочное завершение).
  int _mainWrongTotal() {
    final end = _examQuestions.length < _mainCount
        ? _examQuestions.length
        : _mainCount;
    var w = 0;
    for (var i = 0; i < end; i++) {
      if (_savedAnswers[i] == null || _isAnswerWrongAt(i)) w++;
    }
    return w;
  }

  /// Ошибки доп. блока; неотвеченные считаются ошибками (для итогов).
  int _additionalWrongTotal() {
    var w = 0;
    for (var i = _mainCount; i < _examQuestions.length; i++) {
      if (_savedAnswers[i] == null || _isAnswerWrongAt(i)) w++;
    }
    return w;
  }

  /// Ошибки среди уже отвеченных вопросов основного блока.
  /// Используется по ходу экзамена (правило «3 ошибки — не сдал»).
  int _mainAnsweredWrongCount() {
    final end = _examQuestions.length < _mainCount
        ? _examQuestions.length
        : _mainCount;
    var w = 0;
    for (var i = 0; i < end; i++) {
      if (_isAnswerWrongAt(i)) w++;
    }
    return w;
  }

  /// Ошибки среди отвеченных доп. вопросов (правило «ошибка в доп. блоке — не сдал»).
  int _additionalAnsweredWrongCount() {
    var w = 0;
    for (var i = _mainCount; i < _examQuestions.length; i++) {
      if (_isAnswerWrongAt(i)) w++;
    }
    return w;
  }

  void _recomputeScoreLists() {
    _correctAnswers.clear();
    _wrongAnswers.clear();
    _unansweredTotal = 0;
    for (var i = 0; i < _examQuestions.length; i++) {
      final s = _savedAnswers[i];
      if (s == null) {
        _unansweredTotal++;
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

  /// Ближайший неотвеченный вопрос в диапазоне [start, end): сначала вперёд
  /// от [from]+1, затем с начала диапазона (обход по кругу). Так автопереход
  /// работает при ответах в любом порядке.
  int? _firstUnansweredInRange(int start, int end, {required int from}) {
    for (var i = from + 1; i < end; i++) {
      if (i >= start && _savedAnswers[i] == null) return i;
    }
    for (var i = start; i <= from && i < end; i++) {
      if (_savedAnswers[i] == null) return i;
    }
    return null;
  }

  int? _firstUnansweredMainIndex({required int from}) {
    final end = _examQuestions.length < _mainCount
        ? _examQuestions.length
        : _mainCount;
    return _firstUnansweredInRange(0, end, from: from);
  }

  int? _firstUnansweredAdditionalIndex({required int from}) {
    return _firstUnansweredInRange(_mainCount, _examQuestions.length,
        from: from);
  }

  void _goToQuestion(int index) {
    if (index < 0 || index >= _examQuestions.length) return;
    if (index == _currentIndex) return;
    final c = _pageController;
    if (c == null) return;
    if (!c.hasClients) {
      // PageView ещё не приаттачен (например, сразу после ребилда со сменой
      // количества страниц) — повторяем попытку в следующем кадре.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _examFinished) return;
        _goToQuestion(index);
      });
      return;
    }
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
    _submitAnswer(index);
  }

  void _submitAnswer(int index) {
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evaluateExamState(advance: true);
    });
  }

  /// Центральная точка принятия решений по ходу экзамена.
  ///
  /// Вызывается после каждого ответа (и как страховка — при смене страницы),
  /// поэтому переход к доп. вопросам и завершение экзамена не зависят от того,
  /// на какой странице находится пользователь и в каком порядке он отвечал.
  ///
  /// Правила задаются [ExamRules] страны:
  /// - ошибок больше [ExamRules.maxMistakes] — экзамен прекращается, не сдан;
  /// - РФ: за каждую ошибку +[ExamRules.additionalPerMistake] доп. вопросов
  ///   (и добавка времени); любая ошибка в доп. блоке — не сдан;
  /// - РБ: механики доп. вопросов нет — при допустимом числе ошибок
  ///   экзамен просто завершается сдачей.
  void _evaluateExamState({required bool advance}) {
    if (_examFinished || !mounted) return;

    if (!_additionalPhase) {
      final mainWrong = _mainAnsweredWrongCount();
      if (mainWrong > _rules.maxMistakes) {
        _finishExam();
        return;
      }

      final pending = _firstUnansweredMainIndex(from: _currentIndex);
      if (pending == null) {
        if (mainWrong == 0 || !_rules.hasAdditionalPhase) {
          _finishExam();
          return;
        }
        _startAdditionalPhase(mainWrong * _rules.additionalPerMistake);
        return;
      }

      if (advance) _goToQuestion(pending);
      return;
    }

    if (_additionalAnsweredWrongCount() > 0) {
      _finishExam();
      return;
    }

    final pendingAdd = _firstUnansweredAdditionalIndex(from: _currentIndex);
    if (pendingAdd == null) {
      _finishExam();
      return;
    }

    if (advance) _goToQuestion(pendingAdd);
  }

  void _startAdditionalPhase(int count) {
    if (_additionalPhase) return;

    final random = Random();
    final usedIds = _examQuestions.map((q) => q['id'] as String).toSet();
    final available =
        widget.allQuestions.where((q) => !usedIds.contains(q['id'])).toList()
          ..shuffle(random);
    final additional = available.take(count).toList();

    // Вырожденный случай: в базе не нашлось доп. вопросов — завершаем как есть.
    if (additional.isEmpty) {
      _finishExam();
      return;
    }

    // Каждый доп. блок добавляет фиксированное время (РФ: 5 минут за блок из 5).
    final per = _rules.additionalPerMistake;
    final blocks = (additional.length + per - 1) ~/ per;
    final extraSeconds = blocks * _rules.additionalSecondsPerBlock;

    setState(() {
      _initialWrongCount = _mainAnsweredWrongCount();
      // Сначала расширяем ответы, затем вопросы: если что-то бросит исключение,
      // не останется состояния «вопросов больше, чем слотов под ответы».
      _savedAnswers.addAll(List<int?>.filled(additional.length, null));
      _examQuestions.addAll(additional);
      _additionalPhase = true;
      _additionalQuestionsCount = additional.length;
      _remainingTime += extraSeconds;
      _totalTimeSeconds += extraSeconds;
    });

    // Навигацию к первому доп. вопросу выполняем после ребилда PageView
    // с новым количеством страниц; _currentIndex обновит _onExamPageChanged.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _examFinished) return;
      _goToQuestion(_mainCount);
    });
  }

  void _finishExam() {
    if (_examFinished) return;

    _lastSpokenQuestionId = null;
    _invalidateVoicePlayback();

    _timer?.cancel();

    _recomputeScoreLists();
    // Сдан, если не вышло время И:
    // - в доп. фазе (РФ) — ни одной ошибки/неотвеченного в доп. блоке;
    // - в основном блоке — не больше допуска. При наличии механики доп.
    //   вопросов чистый финал основного блока возможен только с 0 ошибок
    //   (1-2 уводят в доп. фазу); без механики (РБ) допуск = maxMistakes.
    // Неотвеченные считаются ошибками — досрочный выход не даёт «сдал».
    final mainAllowed = _rules.hasAdditionalPhase ? 0 : _rules.maxMistakes;
    final passed = !_timedOut &&
        (_additionalPhase
            ? _additionalWrongTotal() == 0
            : _mainWrongTotal() <= mainAllowed);
    _examPassed = passed;

    final dataSource = ref.read(progressDataSourceProvider);
    final TicketCategory category = ref.read(appSettingsProvider).ticketCategory;
    dataSource.saveExamResult(
      ticketNumber: 0,
      correctAnswers: _correctAnswers.length,
      wrongAnswers: _wrongAnswers.length,
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

  /// Крестик во время экзамена: подтверждение с выбором — продолжить или
  /// завершить с показом результатов (и доступным разбором ошибок).
  /// Если ни одного ответа ещё нет — просто выходим без записи результата.
  Future<void> _confirmLeaveExam() async {
    HapticFeedbackHelper.tap();

    final answeredCount = _savedAnswers.where((s) => s != null).length;
    if (answeredCount == 0) {
      _timer?.cancel();
      Navigator.pop(context);
      return;
    }

    final finish = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Прервать экзамен?'),
        content: const Text(
          'Экзамен будет завершён, неотвеченные вопросы засчитаются как ошибки. '
          'После завершения можно посмотреть разбор ответов.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Продолжить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Завершить',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );

    if (finish == true && mounted) {
      _finishExam();
    }
  }

  void _invalidateVoicePlayback() {
    _voiceScheduleGen++;
    _ttsService.stop();
  }

  void _syncVoicePlayback({
    required String questionId,
    required String questionText,
    required List answers,
    required bool enabled,
  }) {
    final ttsService = _ttsService;

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

    // Системный «назад» (кнопка/жест Android, свайп iOS, back браузера) идёт
    // через тот же диалог подтверждения, что и крестик, — иначе экзамен
    // молча пропадает без результатов и разбора ошибок.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _confirmLeaveExam();
      },
      child: Scaffold(
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
                    onTap: _confirmLeaveExam,
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
                          _currentIndex >= _mainCount
                              ? 'Доп. вопрос ${_currentIndex - _mainCount + 1} из $_additionalQuestionsCount'
                              : 'Вопрос ${_currentIndex + 1} из ${_examQuestions.length}',
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
    final passed = _examPassed;
    final timeSpent = _totalTimeSeconds - _remainingTime;

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
                    if (_unansweredTotal > 0) ...[
                      const SizedBox(height: AppDimensions.spacingM),
                      _buildResultCard(
                        icon: Icons.remove_circle_outline,
                        label: 'Без ответа',
                        value: '$_unansweredTotal',
                        color: AppColors.secondaryText,
                      ),
                    ],
                    if (_additionalPhase) ...[
                      const SizedBox(height: AppDimensions.spacingM),
                      _buildResultCard(
                        icon: Icons.help_outline,
                        label: 'Дополнительный блок',
                        value:
                            '$_additionalQuestionsCount вопросов, ошибок: ${_additionalAnsweredWrongCount()}',
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
        final isAdditional = index >= _mainCount;
        final backgroundColor = isCurrent
            ? AppColors.accent
            : answered
                ? AppColors.accent.withValues(alpha: 0.42)
                : isAdditional
                    ? AppColors.gold.withValues(alpha: 0.5)
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
