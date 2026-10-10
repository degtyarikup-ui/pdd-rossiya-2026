import 'package:pdd_app/core/config/game_economy.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/game_situation.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';

enum GamePhase { ready, driving, situation, resolving, explanation, gameOver }

class GameState {
  /// Runs left in stock for a free player (see GameRunsService); premium
  /// players have unlimited runs.
  final int runs;
  final bool runsUnlimited;
  static const int maxRuns = 3;

  /// A run ends after this many answered questions.
  static const int runQuestions = 20;
  final int score;
  final int distanceM;
  final int speedKmH;
  final int consecutiveCorrect;
  final int totalAnswered;
  final int totalCorrect;
  final int totalMistakes;
  final int violationCount;
  final int? limitKmH;
  final bool oncoming;
  final String lane;
  final bool paused;
  final bool recovering;
  final String? lastViolation;
  final GameSituation? currentSituation;
  final int? selectedAnswerIndex;
  final bool? isLastAnswerCorrect;
  final GamePhase phase;
  final double remainingSeconds;
  final double maxSeconds;

  /// Questions of this run answered wrong or left to time out, in order.
  final List<GameSituation> mistakes;

  /// Simple steering at a task junction: the exit chosen so far
  /// (straight/left/right/uturn) and the arrow the engine suggests for the
  /// task's manoeuvre until the player decides otherwise.
  final String? exitChoice;
  final String? exitHint;

  /// Simple steering: a U-turn can be chosen here (its button is shown).
  final bool exitUturn;

  const GameState({
    this.runs = maxRuns,
    this.runsUnlimited = false,
    this.score = 0,
    this.distanceM = 0,
    this.speedKmH = 0,
    this.consecutiveCorrect = 0,
    this.totalAnswered = 0,
    this.totalCorrect = 0,
    this.totalMistakes = 0,
    this.violationCount = 0,
    this.limitKmH,
    this.oncoming = false,
    this.lane = 'right',
    this.paused = false,
    this.recovering = false,
    this.lastViolation,
    this.currentSituation,
    this.selectedAnswerIndex,
    this.isLastAnswerCorrect,
    this.phase = GamePhase.ready,
    this.remainingSeconds = 15.0,
    this.maxSeconds = 15.0,
    this.mistakes = const [],
    this.exitChoice,
    this.exitHint,
    this.exitUturn = false,
  });

  double get timerProgress =>
      maxSeconds > 0 ? (remainingSeconds / maxSeconds).clamp(0.0, 1.0) : 0.0;
  bool get controlsEnabled =>
      (phase == GamePhase.driving || phase == GamePhase.resolving) &&
      !paused &&
      !recovering;

  GameState copyWith({
    int? runs,
    bool? runsUnlimited,
    int? score,
    int? distanceM,
    int? speedKmH,
    int? consecutiveCorrect,
    int? totalAnswered,
    int? totalCorrect,
    int? totalMistakes,
    int? violationCount,
    int? limitKmH,
    bool clearLimit = false,
    bool? oncoming,
    String? lane,
    bool? paused,
    bool? recovering,
    String? lastViolation,
    GameSituation? currentSituation,
    int? selectedAnswerIndex,
    bool? isLastAnswerCorrect,
    GamePhase? phase,
    double? remainingSeconds,
    double? maxSeconds,
    List<GameSituation>? mistakes,
    String? exitChoice,
    String? exitHint,
    bool? exitUturn,
    bool clearExit = false,
    bool clearSituation = false,
    bool clearViolation = false,
  }) {
    return GameState(
      runs: runs ?? this.runs,
      runsUnlimited: runsUnlimited ?? this.runsUnlimited,
      score: score ?? this.score,
      distanceM: distanceM ?? this.distanceM,
      speedKmH: speedKmH ?? this.speedKmH,
      consecutiveCorrect: consecutiveCorrect ?? this.consecutiveCorrect,
      totalAnswered: totalAnswered ?? this.totalAnswered,
      totalCorrect: totalCorrect ?? this.totalCorrect,
      totalMistakes: totalMistakes ?? this.totalMistakes,
      violationCount: violationCount ?? this.violationCount,
      limitKmH: clearLimit ? null : (limitKmH ?? this.limitKmH),
      oncoming: oncoming ?? this.oncoming,
      lane: lane ?? this.lane,
      paused: paused ?? this.paused,
      recovering: recovering ?? this.recovering,
      lastViolation: clearViolation
          ? null
          : lastViolation ?? this.lastViolation,
      currentSituation: clearSituation
          ? null
          : (currentSituation ?? this.currentSituation),
      selectedAnswerIndex: clearSituation
          ? null
          : (selectedAnswerIndex ?? this.selectedAnswerIndex),
      isLastAnswerCorrect: clearSituation
          ? null
          : (isLastAnswerCorrect ?? this.isLastAnswerCorrect),
      phase: phase ?? this.phase,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      maxSeconds: maxSeconds ?? this.maxSeconds,
      mistakes: mistakes ?? this.mistakes,
      exitChoice: clearExit ? exitChoice : (exitChoice ?? this.exitChoice),
      exitHint: clearExit ? exitHint : (exitHint ?? this.exitHint),
      exitUturn: clearExit
          ? (exitUturn ?? false)
          : (exitUturn ?? this.exitUturn),
    );
  }
}

class GameController extends StateNotifier<GameState> {
  static int _sessionSequence = 0;
  Timer? _timer;
  Timer? _noticeTimer;
  int _lastTickSecond = -1;
  void Function(bool isCorrect, String situationId)?
  onSituationResolvedToEngine;
  void Function(String situationId)? onTrafficReleaseToEngine;
  void Function()? onStopGas;
  final Set<int> _violationEpisodes = {};
  String? _lastSituationId;
  String sessionId =
      '${DateTime.now().microsecondsSinceEpoch}-${_sessionSequence++}';

  bool acceptsSession(Object? id) => id == sessionId;

  void setRecovering(bool recovering) {
    if (state.phase == GamePhase.ready || state.phase == GamePhase.gameOver) {
      return;
    }
    state = state.copyWith(recovering: recovering);
  }

  void setPaused(bool paused) {
    if (paused) onStopGas?.call();
    state = state.copyWith(paused: paused);
  }

  void updateLane(String lane, bool oncoming) {
    if (state.phase == GamePhase.ready || state.phase == GamePhase.gameOver) {
      return;
    }
    // 'against': any lane of a one-way road, driven against its flow.
    if (lane != 'left' && lane != 'right' && lane != 'against') return;
    state = state.copyWith(lane: lane, oncoming: oncoming);
  }

  /// The engine's exit choice and hint (both null away from a junction).
  void updateExit(String? choice, String? hint, {bool uturn = false}) {
    const exits = {'straight', 'left', 'right', 'uturn'};
    if (choice != null && !exits.contains(choice)) return;
    if (hint != null && !exits.contains(hint)) return;
    state = state.copyWith(
      exitChoice: choice,
      exitHint: hint,
      exitUturn: uturn,
      clearExit: true,
    );
  }

  void recordViolation(String type, int episode) {
    if (state.phase == GamePhase.ready ||
        state.phase == GamePhase.gameOver ||
        !{
          'oncoming',
          'collision',
          'offroad',
          'priority',
          'wrong_maneuver',
          'speeding',
          'overtaking',
          'pedestrian',
          'one_way',
          'roadworks',
          'railway',
          'stop',
          'red_light',
        }.contains(type) ||
        episode < 0 ||
        !_violationEpisodes.add(episode)) {
      return;
    }
    // Keep the warning and counter; earned knowledge points are protected.
    state = state.copyWith(
      violationCount: state.violationCount + 1,
      lastViolation: type,
    );
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      state = state.copyWith(clearViolation: true);
    });
  }

  GameController() : super(const GameState());

  /// Driving feedback does not erase already earned knowledge points.
  static int penaltyFor(String type) => 0;

  /// Seconds to answer: 15 for a short question, one more for every 16
  /// characters of question and options beyond 160, at most 30 — the longest
  /// tickets (divided roads, overtaking steps) are otherwise unreadable in time.
  static double answerSeconds(GameSituation situation) {
    final length =
        situation.title.length +
        situation.options.fold<int>(0, (sum, o) => sum + o.length);
    return (15 + ((length - 160) / 16).ceil()).clamp(15, 30).toDouble();
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _timer?.cancel();
    onStopGas?.call();
    onSituationResolvedToEngine = null;
    onTrafficReleaseToEngine = null;
    onStopGas = null;
    super.dispose();
  }

  void onEngineReady() {
    if (state.phase == GamePhase.ready) {
      state = state.copyWith(phase: GamePhase.driving);
    }
  }

  void updateTelemetry({
    required int speedKmH,
    required int distanceM,
    int? limitKmH,
  }) {
    if (state.phase == GamePhase.ready ||
        state.phase == GamePhase.gameOver ||
        state.paused) {
      return;
    }
    final distance = distanceM < state.distanceM ? state.distanceM : distanceM;
    state = state.copyWith(
      speedKmH: speedKmH.clamp(0, 400),
      distanceM: distance,

      limitKmH: limitKmH,
      clearLimit: limitKmH == null,
    );
  }

  void onApproachSituation(GameSituation situation) {
    if (state.phase != GamePhase.driving ||
        !situation.isValid ||
        _lastSituationId == situation.id) {
      return;
    }
    _lastSituationId = situation.id;
    // A new question closes any crash recovery still open: its end signal
    // must not be the only thing that can re-enable the controls.
    state = state.copyWith(clearViolation: true, recovering: false);
    onStopGas?.call();
    _timer?.cancel();
    _lastTickSecond = -1;

    final seconds = answerSeconds(situation);
    state = state.copyWith(
      currentSituation: situation,
      selectedAnswerIndex: null,
      isLastAnswerCorrect: null,
      phase: GamePhase.situation,
      remainingSeconds: seconds,
      maxSeconds: seconds,
    );

    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (state.paused) return;
      if (state.phase != GamePhase.situation) {
        timer.cancel();
        return;
      }

      final nextSec = state.remainingSeconds - 0.1;
      if (nextSec <= 0) {
        timer.cancel();
        _onTimeout();
      } else {
        final currentIntSec = nextSec.ceil();
        if (currentIntSec <= 3 && currentIntSec != _lastTickSecond) {
          _lastTickSecond = currentIntSec;
          SoundEffectsService.instance.playTick();
        }
        state = state.copyWith(remainingSeconds: nextSec);
      }
    });
  }

  void _onTimeout() {
    onTrafficReleaseToEngine?.call(state.currentSituation!.id);
    final newMistakes = state.totalMistakes + 1;

    SoundEffectsService.instance.playIncorrect();
    HapticFeedbackHelper.error();

    state = state.copyWith(
      totalAnswered: state.totalAnswered + 1,
      totalMistakes: newMistakes,
      consecutiveCorrect: 0,
      isLastAnswerCorrect: false,
      phase: GamePhase.explanation,
      remainingSeconds: 0,
      mistakes: [...state.mistakes, state.currentSituation!],
    );
  }

  /// The run is over once [GameState.runQuestions] questions are answered.
  bool get _runComplete => state.totalAnswered >= GameState.runQuestions;

  void submitAnswer(int answerIndex) {
    if (state.phase != GamePhase.situation || state.paused) return;
    if (answerIndex < 0 ||
        answerIndex >= state.currentSituation!.options.length) {
      return;
    }
    _timer?.cancel();

    final sit = state.currentSituation;
    if (sit == null) return;

    final isCorrect = (answerIndex == sit.correctAnswerIndex);

    if (isCorrect) {
      SoundEffectsService.instance.playCorrect();
      HapticFeedbackHelper.softSuccess();

      final newStreak = state.consecutiveCorrect + 1;
      final addedScore = GameEconomy.city(newStreak);

      state = state.copyWith(
        selectedAnswerIndex: answerIndex,
        isLastAnswerCorrect: true,
        consecutiveCorrect: newStreak,
        totalAnswered: state.totalAnswered + 1,
        totalCorrect: state.totalCorrect + 1,
        score: state.score + addedScore,
        phase: GamePhase.resolving,
      );

      // Notify 3D engine to animate vehicles
      onSituationResolvedToEngine?.call(true, sit.id);
    } else {
      SoundEffectsService.instance.playIncorrect();
      onTrafficReleaseToEngine?.call(sit.id);
      HapticFeedbackHelper.error();

      final newMistakes = state.totalMistakes + 1;

      state = state.copyWith(
        selectedAnswerIndex: answerIndex,
        isLastAnswerCorrect: false,
        consecutiveCorrect: 0,
        totalAnswered: state.totalAnswered + 1,
        totalMistakes: newMistakes,
        phase: GamePhase.explanation,
        mistakes: [...state.mistakes, sit],
      );
    }
  }

  void continueAfterExplanation() {
    if (state.phase == GamePhase.explanation && !state.paused) {
      if (_runComplete) {
        state = state.copyWith(phase: GamePhase.gameOver);
        return;
      }
      state = state.copyWith(phase: GamePhase.resolving);
      onSituationResolvedToEngine?.call(false, state.currentSituation!.id);
    }
  }

  void onSituationClearedFromEngine(String situationId) {
    if (state.phase != GamePhase.resolving ||
        state.currentSituation?.id != situationId) {
      return;
    }
    state = state.copyWith(
      phase: _runComplete ? GamePhase.gameOver : GamePhase.driving,
      clearSituation: true,
    );
  }

  /// Sets the runs in stock: the persisted, time-refilled count for free
  /// players; unlimited for premium. Safe to call at any time.
  void configureRuns({required int runs, required bool unlimited}) {
    state = state.copyWith(
      runs: unlimited ? GameState.maxRuns : runs.clamp(0, GameState.maxRuns),
      runsUnlimited: unlimited,
    );
  }

  /// The engine document was replaced mid-run (the OS dropped its WebView):
  /// the run goes on with its score, answers and mistakes. Only the question
  /// on screen is dropped, and the new engine drives from the start.
  void engineReloaded() {
    _noticeTimer?.cancel();
    _timer?.cancel();
    onStopGas?.call();
    _lastTickSecond = -1;
    _lastSituationId = null;
    sessionId =
        '${DateTime.now().microsecondsSinceEpoch}-${_sessionSequence++}';
    if (state.phase == GamePhase.gameOver) return;
    state = state.copyWith(
      phase: GamePhase.ready,
      clearSituation: true,
      clearExit: true,
      recovering: false,
      oncoming: false,
      speedKmH: 0,
    );
  }

  void restartGame() {
    _noticeTimer?.cancel();
    _timer?.cancel();
    onStopGas?.call();
    _lastTickSecond = -1;
    _violationEpisodes.clear();
    _lastSituationId = null;
    sessionId =
        '${DateTime.now().microsecondsSinceEpoch}-${_sessionSequence++}';
    // A fresh run keeps the stock of runs as it is.
    state = GameState(runs: state.runs, runsUnlimited: state.runsUnlimited);
  }
}

final gameControllerProvider =
    StateNotifierProvider.autoDispose<GameController, GameState>((ref) {
      return GameController();
    });
