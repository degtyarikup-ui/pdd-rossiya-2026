import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/game_situation.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';

enum GamePhase { ready, driving, situation, resolving, explanation, gameOver }

class GameState {
  /// Fuel: one unit per mistake; regenerates over time (see GameFuelService).
  /// Premium players have unlimited fuel.
  final int fuel;
  final bool fuelUnlimited;
  static const int maxFuel = 5;
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

  const GameState({
    this.fuel = maxFuel,
    this.fuelUnlimited = false,
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
  });

  double get timerProgress =>
      maxSeconds > 0 ? (remainingSeconds / maxSeconds).clamp(0.0, 1.0) : 0.0;
  bool get controlsEnabled =>
      (phase == GamePhase.driving || phase == GamePhase.resolving) &&
      !paused &&
      !recovering;

  GameState copyWith({
    int? fuel,
    bool? fuelUnlimited,
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
    bool clearSituation = false,
    bool clearViolation = false,
  }) {
    return GameState(
      fuel: fuel ?? this.fuel,
      fuelUnlimited: fuelUnlimited ?? this.fuelUnlimited,
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
    if (lane != 'left' && lane != 'right') return;
    state = state.copyWith(lane: lane, oncoming: oncoming);
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
        }.contains(type) ||
        episode < 0 ||
        !_violationEpisodes.add(episode)) {
      return;
    }
    // Violations cost points (a crash the most); the score never goes below zero.
    final penalty = type == 'collision' ? 100 : 50;
    state = state.copyWith(
      violationCount: state.violationCount + 1,
      lastViolation: type,
      score: (state.score - penalty).clamp(0, 1 << 30),
    );
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      state = state.copyWith(clearViolation: true);
    });
  }

  GameController() : super(const GameState());

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
      score: state.score + distance ~/ 2 - state.distanceM ~/ 2,
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
    state = state.copyWith(clearViolation: true);
    onStopGas?.call();
    _timer?.cancel();
    _lastTickSecond = -1;

    state = state.copyWith(
      currentSituation: situation,
      selectedAnswerIndex: null,
      isLastAnswerCorrect: null,
      phase: GamePhase.situation,
      remainingSeconds: 15.0,
      maxSeconds: 15.0,
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
    final newFuel = state.fuelUnlimited ? state.fuel : state.fuel - 1;

    SoundEffectsService.instance.playIncorrect();
    HapticFeedbackHelper.error();

    if (newFuel <= 0) {
      state = state.copyWith(
        fuel: 0,
        totalAnswered: state.totalAnswered + 1,
        totalMistakes: newMistakes,
        consecutiveCorrect: 0,
        isLastAnswerCorrect: false,
        phase: GamePhase.gameOver,
        remainingSeconds: 0,
      );
    } else {
      state = state.copyWith(
        fuel: newFuel,
        totalAnswered: state.totalAnswered + 1,
        totalMistakes: newMistakes,
        consecutiveCorrect: 0,
        isLastAnswerCorrect: false,
        phase: GamePhase.explanation,
        remainingSeconds: 0,
      );
    }
  }

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
      final addedScore = 100 + (newStreak * 25);

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
      final newFuel = state.fuelUnlimited ? state.fuel : state.fuel - 1;

      if (newFuel <= 0) {
        state = state.copyWith(
          selectedAnswerIndex: answerIndex,
          isLastAnswerCorrect: false,
          consecutiveCorrect: 0,
          totalAnswered: state.totalAnswered + 1,
          totalMistakes: newMistakes,
          fuel: 0,
          phase: GamePhase.gameOver,
        );
      } else {
        state = state.copyWith(
          selectedAnswerIndex: answerIndex,
          isLastAnswerCorrect: false,
          consecutiveCorrect: 0,
          totalAnswered: state.totalAnswered + 1,
          totalMistakes: newMistakes,
          fuel: newFuel,
          phase: GamePhase.explanation,
        );
      }
    }
  }

  void continueAfterExplanation() {
    if (state.phase == GamePhase.explanation && !state.paused) {
      state = state.copyWith(phase: GamePhase.resolving);
      onSituationResolvedToEngine?.call(false, state.currentSituation!.id);
    }
  }

  void onSituationClearedFromEngine(String situationId) {
    if (state.phase != GamePhase.resolving ||
        state.currentSituation?.id != situationId) {
      return;
    }
    state = state.copyWith(phase: GamePhase.driving, clearSituation: true);
  }

  /// Sets the fuel for a run: the persisted, time-regenerated amount for free
  /// players; unlimited for premium. Safe to call at any time.
  void configureFuel({required int fuel, required bool unlimited}) {
    state = state.copyWith(
      fuel: unlimited ? GameState.maxFuel : fuel.clamp(0, GameState.maxFuel),
      fuelUnlimited: unlimited,
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
    // A fresh run keeps the tank as it is (fuel is a resource, not a life bar).
    state = GameState(fuel: state.fuel, fuelUnlimited: state.fuelUnlimited);
  }
}

final gameControllerProvider =
    StateNotifierProvider.autoDispose<GameController, GameState>((ref) {
      return GameController();
    });
