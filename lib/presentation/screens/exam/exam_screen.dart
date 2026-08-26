import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/constants/question_swipe_motion.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/question_number_strip_scroll.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/share_card_renderer.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/presentation/screens/exam/exam_review_screen.dart';
import 'package:pdd_app/presentation/widgets/share_result_card.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/question_image.dart';
import 'package:pdd_app/presentation/widgets/question_number_chip.dart';

class ExamScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> allQuestions;

  /// Правила экзамена. По умолчанию — правила страны сборки;
  /// параметр нужен тестам, чтобы проверять RU и BY на одном коде.
  final ExamRules? rules;

  /// Состояние прерванного экзамена (из [unfinishedSessionProvider]): набор
  /// вопросов, ответы, остаток времени, доп. фаза. null — новый экзамен.
  final Map<String, dynamic>? resume;

  const ExamScreen({
    super.key,
    required this.allQuestions,
    this.rules,
    this.resume,
  });

  @override
  ConsumerState<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends ConsumerState<ExamScreen> {
  late final ExamRules _rules =
      widget.rules ?? CountryConfig.current.examRules;

  /// Размер основного блока экзамена (страно-зависимый).
  int get _mainCount => _rules.mainCount;

  /// Балльная модель подсчёта (Сербия): вопрос весит 1/2/3, доп. фазы нет.
  bool get _isPointsScoring => _rules.scoring == ExamScoring.points;

  /// Вес вопроса в баллах (по умолчанию 1). Для моделей «по ошибкам» не важен.
  int _questionPoints(int i) => _examQuestions[i]['points'] as int? ?? 1;

  /// Максимум баллов за весь билет.
  int _maxPoints() {
    var sum = 0;
    for (var i = 0; i < _examQuestions.length; i++) {
      sum += _questionPoints(i);
    }
    return sum;
  }

  /// Набранные баллы: сумма весов верно отвеченных вопросов.
  int _earnedPoints() {
    var sum = 0;
    for (var i = 0; i < _examQuestions.length; i++) {
      final s = _savedAnswers[i];
      if (s == null) continue;
      if ((_examQuestions[i]['answers'] as List)[s]['correct'] as bool) {
        sum += _questionPoints(i);
      }
    }
    return sum;
  }

  /// Процент набранных баллов (0..100), округление вниз.
  int _scorePercent() {
    final max = _maxPoints();
    if (max == 0) return 0;
    return _earnedPoints() * 100 ~/ max;
  }

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
  /// Экзамен провален именно по блочному правилу (две ошибки в одном
  /// тематическом блоке). Нужен, чтобы на экране результата объяснить причину:
  /// без объяснения «две ошибки, но не сдал» читается как баг приложения.
  bool _failedByBlock = false;
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
      // initialPage обязателен: при возврате к прерванному экзамену индекс
      // уже восстановлен, а PageView без него открылся бы на первом вопросе
      // и тут же сбросил позицию через onPageChanged.
      _pageController = PageController(initialPage: _currentIndex);
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
    final resume = widget.resume;
    if (resume != null && _restoreExam(resume)) return;

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

  /// Разворачивает сохранённый экзамен. false — запись не подошла
  /// (например, вопросов меньше, чем ответов), тогда начинаем заново.
  bool _restoreExam(Map<String, dynamic> resume) {
    final questions =
        (resume['questions'] as List?)?.cast<Map<String, dynamic>>();
    final answers = (resume['answers'] as List?)?.map((e) => e as int?).toList();
    if (questions == null || answers == null) return false;
    if (questions.isEmpty || questions.length != answers.length) return false;

    _examQuestions = List<Map<String, dynamic>>.from(questions);
    _savedAnswers = List<int?>.from(answers, growable: true);
    _currentIndex =
        (resume['index'] as int? ?? 0).clamp(0, _examQuestions.length - 1);
    _selectedAnswerIndex = _savedAnswers[_currentIndex];
    _isAnswerSubmitted = _selectedAnswerIndex != null;
    _additionalPhase = resume['additionalPhase'] as bool? ?? false;
    _additionalQuestionsCount = resume['additionalQuestionsCount'] as int? ?? 0;
    _initialWrongCount = resume['initialWrongCount'] as int? ?? 0;
    _totalTimeSeconds = resume['totalSeconds'] as int? ?? _rules.totalSeconds;
    _remainingTime = resume['remainingSeconds'] as int? ?? _totalTimeSeconds;
    // Нулевой остаток означал бы мгновенный провал сразу после возврата —
    // такую запись считаем негодной и начинаем экзамен заново.
    if (_remainingTime <= 0) return false;

    _startTimer();
    return true;
  }

  /// Сохраняет прерванный экзамен, чтобы вернуться к нему с главного экрана.
  Future<void> _saveUnfinishedExam() {
    return ref.read(progressDataSourceProvider).saveUnfinishedExam(
          questionIds: _examQuestions
              .map((q) => q['id'] as String? ?? '')
              .toList(),
          answers: _savedAnswers,
          index: _currentIndex,
          remainingSeconds: _remainingTime,
          totalSeconds: _totalTimeSeconds,
          additionalPhase: _additionalPhase,
          additionalQuestionsCount: _additionalQuestionsCount,
          initialWrongCount: _initialWrongCount,
          category: ref.read(appSettingsProvider).ticketCategory,
        );
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

  /// Ошибки основной части, разложенные по тематическим блокам:
  /// номер блока → сколько в нём ошибок.
  ///
  /// [countUnanswered] — считать ли неотвеченные вопросы ошибками. По ходу
  /// экзамена false (человек ещё может ответить), при подведении итогов true.
  Map<int, int> _mistakesByBlock({bool countUnanswered = false}) {
    final end = _examQuestions.length < _mainCount
        ? _examQuestions.length
        : _mainCount;
    final byBlock = <int, int>{};
    for (var i = 0; i < end; i++) {
      final isMistake = countUnanswered
          ? (_savedAnswers[i] == null || _isAnswerWrongAt(i))
          : _isAnswerWrongAt(i);
      if (!isMistake) continue;
      final block = _rules.blockIndexOf(i);
      byBlock[block] = (byBlock[block] ?? 0) + 1;
    }
    return byBlock;
  }

  /// Провал по блочному правилу: набралось [ExamRules.maxMistakesPerBlock]
  /// ошибок внутри одного тематического блока (РФ: две ошибки в одном блоке).
  ///
  /// Срабатывает РАНЬШЕ общего лимита ошибок: на реальном экзамене две ошибки
  /// в одном блоке валят сразу, хотя суммарно ошибок всего две и по общему
  /// лимиту экзамен ещё продолжался бы.
  bool _failedByBlockRule({bool countUnanswered = false}) {
    if (!_rules.hasBlockRule) return false;
    return _mistakesByBlock(countUnanswered: countUnanswered).values.any(
      (count) => count >= _rules.maxMistakesPerBlock,
    );
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

  void _goToQuestion(int index, {bool withHaptic = true}) {
    if (index < 0 || index >= _examQuestions.length) return;
    if (index == _currentIndex) return;
    final c = _pageController;
    if (c == null) return;
    if (!c.hasClients) {
      // PageView ещё не приаттачен (например, сразу после ребилда со сменой
      // количества страниц) — повторяем попытку в следующем кадре.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _examFinished) return;
        _goToQuestion(index, withHaptic: withHaptic);
      });
      return;
    }
    // Вибрируем только при ручной навигации (тап по номеру сверху). При
    // авто-переходе после ответа отклик уже дал _selectAnswer — иначе «двойная».
    if (withHaptic) HapticFeedbackHelper.tap();
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

    // Балльная модель (Сербия): досрочного провала и доп. фазы нет —
    // отвечаем на все вопросы, затем подводим итог по сумме баллов.
    if (_isPointsScoring) {
      final pending = _firstUnansweredMainIndex(from: _currentIndex);
      if (pending == null) {
        _finishExam();
        return;
      }
      if (advance) _goToQuestion(pending, withHaptic: false);
      return;
    }

    if (!_additionalPhase) {
      // Блочное правило проверяем ПЕРВЫМ: две ошибки в одном тематическом
      // блоке валят экзамен сразу, хотя по общему лимиту ошибок он ещё
      // продолжался бы.
      if (_failedByBlockRule()) {
        _finishExam();
        return;
      }

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

      if (advance) _goToQuestion(pending, withHaptic: false);
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

    if (advance) _goToQuestion(pendingAdd, withHaptic: false);
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
      _goToQuestion(_mainCount, withHaptic: false);
    });
  }

  void _finishExam() {
    if (_examFinished) return;

    // Экзамен дошёл до результата — предлагать «продолжить» его больше нельзя.
    ref.read(progressDataSourceProvider).clearUnfinishedSession();

    _lastSpokenQuestionId = null;
    _invalidateVoicePlayback();

    _timer?.cancel();

    _recomputeScoreLists();
    // Сдан, если не вышло время И:
    // - балльная модель (Сербия) — набрано ≥ passPercent% от максимума баллов;
    // - в доп. фазе (РФ) — ни одной ошибки/неотвеченного в доп. блоке;
    // - в основном блоке — не больше допуска. При наличии механики доп.
    //   вопросов чистый финал основного блока возможен только с 0 ошибок
    //   (1-2 уводят в доп. фазу); без механики (РБ) допуск = maxMistakes.
    // Неотвеченные считаются ошибками — досрочный выход не даёт «сдал».
    final bool passed;
    if (_isPointsScoring) {
      // Балльная модель (Сербия): время лишь ограничивает длительность.
      // При истечении экзамен НЕ проваливается автоматически — оценивается
      // по набранным баллам (неотвеченные = 0), как на реальном тесте MUP.
      // Иначе «ответил верно на 40 из 41, но не успел последний» = провал,
      // хотя баллов уже сильно выше порога.
      passed = _earnedPoints() * 100 >= _rules.passPercent * _maxPoints();
    } else {
      final mainAllowed = _rules.hasAdditionalPhase ? 0 : _rules.maxMistakes;
      // Блочное правило считаем и здесь: экзамен мог закончиться досрочным
      // выходом или таймаутом, а не через _evaluateExamState.
      _failedByBlock = _failedByBlockRule(countUnanswered: true);
      passed = !_timedOut &&
          !_failedByBlock &&
          (_additionalPhase
              ? _additionalWrongTotal() == 0
              : _mainWrongTotal() <= mainAllowed);
    }
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
    _timer?.cancel();

    // Выход больше не подводит итог. Экзамен запоминается целиком и ждёт
    // на главном экране кнопкой «Продолжить»: показывать результат за
    // недорешённый билет — значит сообщать провал там, где человек всего
    // лишь отвлёкся.
    final answeredCount = _savedAnswers.where((s) => s != null).length;
    if (answeredCount > 0) {
      await _saveUnfinishedExam();
    }
    if (!mounted) return;
    ref.read(appDataRefreshProvider.notifier).state++;
    Navigator.pop(context);
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
      ttsService.speakQuestion(
        rawQuestionId: questionId,
        question: questionText,
        answers: answerTexts,
      );
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

    final colors = AppColors.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _confirmLeaveExam();
      },
      child: Scaffold(
      backgroundColor: colors.background,
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
                              ? appL10n.examAdditionalTitle
                              : appL10n.exam,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.primaryText,
                          ),
                        ),
                        Text(
                          _currentIndex >= _mainCount
                              ? appL10n.examAdditionalQuestionOfTotal(
                                  _currentIndex - _mainCount + 1,
                                  _additionalQuestionsCount,
                                )
                              : appL10n.questionOfTotal(
                                  _currentIndex + 1,
                                  _examQuestions.length,
                                ),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.secondaryText,
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
                          ? colors.redLight
                          : colors.accentSurface10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 18,
                          color: _remainingTime < 120
                              ? colors.red
                              : colors.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(_remainingTime),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _remainingTime < 120
                                ? colors.red
                                : colors.accent,
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
    final colors = AppColors.of(context);
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

  /// Делится результатом экзамена системным диалогом «Поделиться»
  /// (share_plus: Android/iOS — нативный лист, web — Web Share API).
  /// Собирает картинку результата и кладёт во временный файл.
  ///
  /// Возвращает null на вебе (там нет файловой системы под share_plus и
  /// картинку всё равно не приложить) и при любой ошибке рендера — тогда
  /// вызывающий код делится обычным текстом.
  Future<XFile?> _buildShareImage() async {
    if (kIsWeb) return null;
    try {
      // Готовность — тот же показатель, что на главной: доля верно решённых
      // вопросов от всей базы категории.
      final stats = await ref.read(statsProvider.future);
      final correctTotal = stats['correctAnswers'] ?? 0;
      final totalQuestions = stats['totalQuestions'] ?? 0;
      final readiness = totalQuestions > 0
          ? (correctTotal / totalQuestions * 100).round()
          : 0;

      final correctCount = _correctAnswers.length;
      final wrongCount = _wrongAnswers.length + _unansweredTotal;

      final png = await ShareCardRenderer.renderToPng(
        size: const Size(ShareResultCard.side, ShareResultCard.side),
        widget: ShareResultCard(
          passed: _examPassed,
          correct: correctCount,
          wrong: wrongCount,
          readinessPercent: readiness,
          title: _examPassed ? appL10n.examPassed : appL10n.examFailed,
          // Короткие формы со склонением: на карточке подпись стоит прямо
          // под числом, и «6 ошибка» из обычного ярлыка выглядело бы
          // безграмотно — а картинку увидят посторонние люди.
          correctLabel: appL10n.shareCardCorrectWord(correctCount),
          wrongLabel: appL10n.shareCardWrongWord(wrongCount),
          readinessLabel: appL10n.examReadiness,
          siteUrl: CountryConfig.current.webUrl
              .replaceFirst(RegExp(r'^https?://'), ''),
        ),
      );
      if (png == null) return null;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/exam_result.png');
      await file.writeAsBytes(png, flush: true);
      return XFile(file.path, mimeType: 'image/png');
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareResult() async {
    final config = CountryConfig.current;
    final resultLine = _examPassed ? appL10n.examPassed : appL10n.examFailed;
    final text = appL10n.examShareText(
      resultLine,
      _correctAnswers.length,
      _examQuestions.length,
      config.appTitle,
      config.webUrl,
    );

    // Сначала пробуем поделиться картинкой: текстом никто не делится, а
    // квадрат 1080×1080 уходит в сторис и чаты автошкол. Если рендер или
    // сохранение не удались — молча откатываемся на прежний текстовый путь.
    final imageFile = await _buildShareImage();
    if (imageFile != null) {
      try {
        final result = await SharePlus.instance.share(
          ShareParams(text: text, files: [imageFile]),
        );
        if (result.status != ShareResultStatus.unavailable) return;
      } catch (_) {
        // Ниже — обычный текстовый шеринг.
      }
    }

    try {
      final result = await SharePlus.instance.share(ShareParams(text: text));
      // На web системный «Поделиться» (navigator.share) есть не везде — на
      // десктопе/без HTTPS он недоступен, и share_plus вернёт unavailable.
      // Тогда — запасной путь: копируем текст в буфер и уведомляем.
      if (result.status != ShareResultStatus.unavailable) return;
    } catch (_) {
      // navigator.share бросил (нет Web Share API) — идём в запасной путь.
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(appL10n.copiedToClipboard)),
    );
  }

  Widget _buildResultsScreen() {
    final colors = AppColors.of(context);
    final totalWrong = _wrongAnswers.length;
    final totalQuestions = _examQuestions.length;
    final passed = _examPassed;
    final timeSpent = _totalTimeSeconds - _remainingTime;

    const double kBarTop = AppDimensions.screenPadding;
    const double kBarHeight = 40;
    const double kFadeHeight = kBarTop + kBarHeight + 80;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                kFadeHeight,
                AppDimensions.screenPadding,
                AppDimensions.screenPadding,
              ),
              child: Column(
                children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: passed ? colors.green : colors.red,
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
                      passed ? appL10n.examPassed : appL10n.examFailed,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: passed ? colors.green : colors.red,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingS),
                    Text(
                      // «Время вышло» показываем только когда таймаут привёл к
                      // провалу. В балльной модели можно набрать проходной балл
                      // и при истечении времени — тогда это сдача, не таймаут.
                      (_timedOut && !passed)
                          ? appL10n.examResultTimeout
                          : passed
                          ? appL10n.examResultPassed
                          : appL10n.examResultFailed,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: colors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingXXL),
                    if (_isPointsScoring) ...[
                      _buildResultCard(
                        icon: Icons.stars_outlined,
                        label: appL10n.examPointsLabel,
                        value: appL10n.valueOfTotal(
                          _earnedPoints(),
                          _maxPoints(),
                        ),
                        color: colors.accent,
                      ),
                      const SizedBox(height: AppDimensions.spacingM),
                      _buildResultCard(
                        icon: Icons.percent_rounded,
                        label: appL10n.examScoreLabel,
                        value: appL10n.examScorePercent(_scorePercent()),
                        color: passed ? colors.green : colors.red,
                      ),
                      const SizedBox(height: AppDimensions.spacingM),
                    ],
                    _buildResultCard(
                      icon: Icons.check_circle_outline,
                      label: appL10n.correctAnswers,
                      value: appL10n.valueOfTotal(
                        _correctAnswers.length,
                        totalQuestions,
                      ),
                      color: colors.green,
                    ),
                    const SizedBox(height: AppDimensions.spacingM),
                    _buildResultCard(
                      icon: Icons.cancel_outlined,
                      label: appL10n.wrongAnswers,
                      value: '$totalWrong',
                      color: colors.red,
                    ),
                    if (_additionalPhase) ...[
                      const SizedBox(height: AppDimensions.spacingM),
                      _buildResultCard(
                        icon: Icons.help_outline,
                        label: appL10n.examAdditionalBlock,
                        value: appL10n.examAdditionalBlockValue(
                          _additionalQuestionsCount,
                          _additionalAnsweredWrongCount(),
                        ),
                        color: colors.gold,
                      ),
                    ],
                    const SizedBox(height: AppDimensions.spacingM),
                    _buildResultCard(
                      icon: Icons.timer_outlined,
                      label: appL10n.examTimeSpent,
                      value: _formatTime(timeSpent),
                      color: colors.accent,
                    ),
                    if (_additionalPhase) ...[
                      const SizedBox(height: AppDimensions.spacingM),
                      _buildResultCard(
                        icon: Icons.rule_folder_outlined,
                        label: appL10n.examMainBlockErrors,
                        value: '$_initialWrongCount',
                        color: colors.primaryText,
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
                        child: Text(appL10n.myMistakes),
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
                        child: Text(appL10n.backToTraining),
                      ),
                    ),
                    const SizedBox(height: 100),
                ],
              ),
            ),
            // Градиент затухания: фон (непрозрачный под кнопками) → прозрачный.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: kFadeHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.background,
                        colors.background,
                        colors.background.withValues(alpha: 0.0),
                      ],
                      stops: const [
                        0.0,
                        (kBarTop + kBarHeight) / kFadeHeight,
                        1.0,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Закреплённая панель: закрыть + поделиться.
            Positioned(
              top: kBarTop,
              left: AppDimensions.screenPadding,
              right: AppDimensions.screenPadding,
              child: Row(
                children: [
                  AppChromeIconButton(
                    icon: Icons.close_rounded,
                    onTap: () {
                      HapticFeedbackHelper.tap();
                      Navigator.pop(context);
                    },
                  ),
                  const Spacer(),
                  if (_failedByBlock) ...[
                    AppChromeIconButton(
                      icon: Icons.info_outline_rounded,
                      onTap: () {
                        HapticFeedbackHelper.tap();
                        _showBlockRuleExplanation();
                      },
                    ),
                    const SizedBox(width: AppDimensions.spacingM),
                  ],
                  AppChromeIconButton(
                    icon: Icons.ios_share_rounded,
                    backgroundColor: colors.accent,
                    iconColor: AppColors.white,
                    onTap: () {
                      HapticFeedbackHelper.tap();
                      _shareResult();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Почему экзамен не сдан при двух ошибках — по кнопке-иконке, а не полотном
  /// на экране результата.
  Future<void> _showBlockRuleExplanation() {
    final colors = AppColors.of(context);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        icon: Icon(
          Icons.info_outline_rounded,
          color: colors.red,
          size: 28,
        ),
        title: Text(
          appL10n.examFailed,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
        ),
        content: Text(
          appL10n.examFailedByBlock(_rules.maxMistakesPerBlock),
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: colors.primaryText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(appL10n.close),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: AppDimensions.spacingM),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: colors.secondaryText,
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
    final colors = AppColors.of(context);
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
            ? colors.accent
            : answered
                ? colors.accent.withValues(alpha: 0.42)
                : isAdditional
                    ? colors.gold.withValues(alpha: 0.5)
                    : colors.gray;

        return QuestionNumberChip(
          number: index + 1,
          backgroundColor: backgroundColor,
          muted: !isCurrent && !answered && !isAdditional,
          onTap: () => _goToQuestion(index),
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
    final colors = AppColors.of(context);
    final saved = _savedAnswers[questionIndex];
    final isAnswered = saved != null;
    final isSelected = isAnswered
        ? (saved == index)
        : (questionIndex == _currentIndex && _selectedAnswerIndex == index);

    Color backgroundColor;
    Color textColor;

    if (isAnswered) {
      if (isSelected) {
        backgroundColor = colors.accentSurface10;
        textColor = colors.primaryText;
      } else {
        backgroundColor = colors.cardBackground;
        textColor = colors.secondaryText;
      }
    } else if (isSelected) {
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
                            ? colors.accent.withValues(alpha: 0.2)
                            : colors.gray)
                      : isSelected
                          ? colors.accent.withValues(alpha: 0.12)
                          : colors.gray,
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
                                ? colors.accent
                                : colors.secondaryText)
                          : isSelected
                              ? colors.accent
                              : colors.secondaryText,
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
