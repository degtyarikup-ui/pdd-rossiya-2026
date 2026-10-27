import 'package:pdd_app/data/services/achievement_award_service.dart';
import 'package:pdd_app/presentation/widgets/achievement_award_screen.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/core/config/game_economy.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/usage_reporter.dart';
import 'package:pdd_app/domain/services/road_signs_engine.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_emblem.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_grid.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_modal.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';
import 'package:pdd_app/presentation/screens/games/widgets/mini_game_hud.dart';
import 'package:pdd_app/presentation/widgets/app_loading_indicator.dart';

/// Главный экран игровой сессии «Знаки» (Road Signs Quiz).
class RoadSignsScreen extends ConsumerStatefulWidget {
  final List<RoadSignQuizQuestion>? initialDeck;
  final int initialSeconds;
  final int initialLives;

  const RoadSignsScreen({
    super.key,
    this.initialDeck,
    this.initialSeconds = GameEconomy.miniGameSeconds,
    this.initialLives = GameEconomy.miniGameLives,
  });

  @override
  ConsumerState<RoadSignsScreen> createState() => _RoadSignsScreenState();
}

class _RoadSignsScreenState extends ConsumerState<RoadSignsScreen> {
  RoadSignsEngine? _engine;
  List<RoadSignQuizQuestion> _deck = [];

  int _currentIndex = 0;
  int _score = 0;
  late int _lives;
  int _combo = 0;
  int _maxCombo = 0;
  int _correctAnswers = 0;
  int _totalAnswered = 0;

  late int _secondsLeft;
  Timer? _timer;
  bool _isTimerPaused = false;
  bool _timeUp = false;
  bool _isGameOver = false;
  bool _isProcessing = false;
  int? _selectedOptionIndex;
  bool? _answeredCorrectly;
  int _lastPoints = 0;
  Timer? _advanceTimer;

  final List<RoadSignAnswerResult> _mistakes = [];

  int _previousBest = 0;
  bool _isNewRecord = false;
  String _ratingRunId = '';

  late final _awardService = ref.read(achievementAwardServiceProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_awardService.prepare());
    _lives = widget.initialLives;
    _secondsLeft = widget.initialSeconds;
    _ratingRunId = GameLeaderboardService.newRunId();

    if (widget.initialDeck != null && widget.initialDeck!.isNotEmpty) {
      _deck = List.of(widget.initialDeck!);
      _startRound();
    }
    _loadPreviousBest();
  }

  Future<void> _loadPreviousBest() async {
    try {
      final best = ref.read(roadSignsProgressProvider).bestScore;
      if (best > 0) {
        if (mounted) {
          setState(() => _previousBest = best);
        }
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _previousBest = prefs.getInt('roadSignsBest') ?? best;
        });
      }
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (mounted) {
          setState(() {
            _previousBest = prefs.getInt('roadSignsBest') ?? 0;
          });
        }
      } catch (_) {}
    }
  }

  void _initEngine(Map<String, dynamic> rawJson) {
    if (_engine != null) return;
    final signs = RoadSignsEngine.parseSignsJson(rawJson);
    if (signs.length < 4) return;
    _engine = RoadSignsEngine(allSigns: signs);
    if (_deck.isEmpty) {
      _deck = _engine!.generateDeck(count: 25);
      _startRound();
    }
  }

  void _startRound() {
    UsageReporter.track(UsageFeature.roadSigns);
    unawaited(_awardService.startActivity());
    _timer?.cancel();
    _advanceTimer?.cancel();
    _score = 0;
    _lives = widget.initialLives;
    _combo = 0;
    _maxCombo = 0;
    _correctAnswers = 0;
    _totalAnswered = 0;
    _currentIndex = 0;
    _secondsLeft = widget.initialSeconds;
    _isTimerPaused = false;
    _timeUp = false;
    _isGameOver = false;
    _isProcessing = false;
    _selectedOptionIndex = null;
    _answeredCorrectly = null;
    _lastPoints = 0;
    _mistakes.clear();
    _isNewRecord = false;
    _ratingRunId = GameLeaderboardService.newRunId();

    if (_engine != null &&
        (widget.initialDeck == null || widget.initialDeck!.isEmpty)) {
      _deck = _engine!.generateDeck(count: 25);
    }

    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_isTimerPaused && !_isGameOver) {
        if (_secondsLeft > 0) {
          setState(() => _secondsLeft--);
          if (_secondsLeft <= 5 && _secondsLeft > 0) {
            SoundEffectsService.instance.playTick();
          }
        }
        if (_secondsLeft <= 0) {
          _timeUp = true;
          if (!_isProcessing) _endGame();
        }
      }
    });
  }

  void _onOptionSelected(int index) {
    if (_isGameOver || _isProcessing || _currentIndex >= _deck.length) {
      return;
    }

    _isProcessing = true;
    final question = _deck[_currentIndex];
    final isCorrect = index == question.correctAnswerIndex;
    final result = RoadSignAnswerResult(
      question: question,
      selectedIndex: index,
      isCorrect: isCorrect,
    );

    setState(() {
      _selectedOptionIndex = index;
      _answeredCorrectly = isCorrect;
      _totalAnswered++;
      if (isCorrect) {
        SoundEffectsService.instance.playCorrect();
        HapticFeedbackHelper.tap();
        _combo++;
        if (_combo > _maxCombo) {
          _maxCombo = _combo;
        }
        if (_combo > 2) {
          SoundEffectsService.instance.playStreak();
        }
        final points = GameEconomy.signs(_combo);
        _score += points;
        _correctAnswers++;
        _lastPoints = points;
      } else {
        SoundEffectsService.instance.playIncorrect();
        HapticFeedbackHelper.warning();
        _combo = 0;
        _lives--;
        _lastPoints = 0;
        _mistakes.add(result);
      }
    });

    final delay = isCorrect
        ? const Duration(milliseconds: 450)
        : const Duration(milliseconds: 800);

    _advanceTimer?.cancel();
    _advanceTimer = Timer(delay, () {
      if (!mounted) return;

      if (_lives <= 0 || _secondsLeft <= 0) {
        _endGame();
        return;
      }

      setState(() {
        _isProcessing = false;
        _selectedOptionIndex = null;
        _answeredCorrectly = null;
        _currentIndex++;
        if (_deck.length - _currentIndex < 5 && _engine != null) {
          _deck.addAll(_engine!.generateDeck(count: 20));
        }
      });
    });
  }

  void _endGame() {
    if (_isGameOver) return;
    _timer?.cancel();
    _advanceTimer?.cancel();

    final currentBest = _previousBest;
    final isRecord = _score > 0 && _score > currentBest;

    // Сохранение рекорда и прогресса в провайдер и хранилище
    unawaited(() async {
      try {
        await ref
            .read(roadSignsProgressProvider.notifier)
            .recordGameResult(
              score: _score,
              combo: _maxCombo,
              totalAnswered: _totalAnswered,
              totalCorrect: _correctAnswers,
            );
        final prefs = await SharedPreferences.getInstance();
        if (isRecord) {
          await prefs.setInt('roadSignsBest', _score);
        }
        await ProgressSyncService.instance.syncWithServer();
      } catch (_) {}
    }());

    // Отправка в лидерборд
    unawaited(
      GameLeaderboardService.instance
          .submitRun(
            GameEconomy.rankedScore(
              _score,
              correct: _correctAnswers,
              wrong: _totalAnswered - _correctAnswers,
            ),
            runId: _ratingRunId,
          )
          .catchError((_) => null),
    );

    setState(() {
      _isNewRecord = isRecord;
      _isGameOver = true;
      _isProcessing = false;
      _isTimerPaused = true;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _advanceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // Если колода передана извне (например, в виджет-тестах)
    if (widget.initialDeck != null && widget.initialDeck!.isNotEmpty) {
      return _buildGameScaffold(colors);
    }

    final signsAsync = ref.watch(signsProvider);
    return signsAsync.when(
      loading: () => Scaffold(
        backgroundColor: colors.background,
        body: const Center(child: AppLoadingIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: colors.background,
        body: Center(
          child: Text(
            appL10n.gameSignsLoadError,
            style: TextStyle(color: colors.primaryText),
          ),
        ),
      ),
      data: (signsJson) {
        _initEngine(signsJson);
        if (_engine == null) {
          return Scaffold(
            backgroundColor: colors.background,
            body: Center(
              child: Text(
                appL10n.gameSignsLoadError,
                style: TextStyle(color: colors.primaryText),
              ),
            ),
          );
        }
        return _buildGameScaffold(colors);
      },
    );
  }

  Widget _buildGameScaffold(AppThemeColors colors) {
    if (_isGameOver) {
      return Scaffold(
        backgroundColor: colors.background,
        body: _buildResultOverlay(colors),
      );
    }

    final hasQuestion = _currentIndex < _deck.length;
    final currentQuestion = hasQuestion ? _deck[_currentIndex] : null;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.screenPadding,
              ),
              child: Column(
                children: [
                  _buildHeader(colors),
                  if (currentQuestion != null)
                    Expanded(child: _buildQuestion(currentQuestion, colors)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestion(RoadSignQuizQuestion question, AppThemeColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.5);
        if (constraints.maxWidth >= 480 && constraints.maxHeight < 400) {
          final side = math.min(
            (constraints.maxWidth - 24) / 2,
            math.max(212.0, constraints.maxHeight - 16),
          );
          return SingleChildScrollView(
            child: SizedBox(
              height: math.max(side + 16, constraints.maxHeight),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      key: ValueKey('road-signs-prompt-$_currentIndex'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          Text(
                            question.prompt,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: colors.primaryText,
                            ),
                          ),
                          SizedBox(
                            height: 64 * scale,
                            child: _buildFeedback(colors),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox.square(dimension: side, child: _buildGrid(question)),
                ],
              ),
            ),
          );
        }
        final compact = constraints.maxHeight < 520;
        final questionHeight = (compact ? 96.0 : 124.0) * scale;
        final feedbackHeight = 64.0 * scale;
        // Preserve usable sign targets on short screens; scroll the group when
        // large accessibility text needs more room than the viewport allows.
        final gridSide = math.min(
          math.min(constraints.maxWidth, 420.0),
          math.max(
            240.0,
            constraints.maxHeight - questionHeight - feedbackHeight - 32,
          ),
        );
        return SingleChildScrollView(
          key: const ValueKey('road-signs-question-scroll'),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: questionHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          question.prompt,
                          style: TextStyle(
                            fontSize: compact ? 20 : 22,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: colors.primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: gridSide, child: _buildGrid(question)),
                SizedBox(height: feedbackHeight, child: _buildFeedback(colors)),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid(RoadSignQuizQuestion question) {
    return RoadSignsGrid(
      options: question.options,
      onSelectOption: _onOptionSelected,
      isEnabled: !_isProcessing && !_isGameOver,
      selectedIndex: _selectedOptionIndex,
      correctIndex: question.correctAnswerIndex,
      isCorrect: _answeredCorrectly,
    );
  }

  Widget _buildFeedback(AppThemeColors colors) {
    final correct = _answeredCorrectly == true;
    final answered = _answeredCorrectly != null;
    if (!answered) return const SizedBox.shrink();
    if (!correct) {
      return Center(
        child: GameLifeLossBadge(key: ValueKey('life-loss-$_currentIndex')),
      );
    }
    final text = appL10n.roadSignsCorrectPoints(_lastPoints);
    return Semantics(
      liveRegion: answered,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (answered) ...[
            Icon(
              correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 18,
              color: correct ? colors.green : colors.red,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: answered ? FontWeight.w600 : FontWeight.w400,
                color: answered ? colors.primaryText : colors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppThemeColors colors) {
    return MiniGameHud(
      score: _score,
      combo: _combo,
      secondsLeft: _secondsLeft,
      totalSeconds: widget.initialSeconds,
      lives: _lives,
      totalLives: widget.initialLives,
      onExit: () => Navigator.of(context).pop(),
    );
  }

  Widget _buildResultOverlay(AppThemeColors colors) {
    return CompletionAchievementAwards(
      key: ValueKey(_ratingRunId),
      service: _awardService,
      resultBuilder: (_) => GameResultOverlay(
        emblem: const RoadSignsEmblem(),
        title: _timeUp ? appL10n.gameTimeUp : appL10n.gameOverTitle,
        score: _score,
        bestScore: _previousBest,
        isNewRecord: _isNewRecord,
        stats: [
          GameResultStat(
            appL10n.gameCorrectAnswers,
            '$_correctAnswers/$_totalAnswered',
          ),
          GameResultStat(appL10n.gameComboLabel, 'x$_maxCombo'),
        ],
        mistakesCount: _mistakes.length,
        onMistakes: _mistakes.isNotEmpty ? _showMistakes : null,
        onRestart: () => setState(_startRound),
        onExit: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _showMistakes() {
    HapticFeedbackHelper.tap();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RoadSignsMistakesSheet(
        mistakes: List.of(_mistakes),
        onSelectMistake: (result) {
          RoadSignsModal.show(context, result: result, onContinue: () {});
        },
      ),
    );
  }
}

/// Нижняя шторка для разбора ошибок раунда.
class _RoadSignsMistakesSheet extends StatelessWidget {
  final List<RoadSignAnswerResult> mistakes;
  final ValueChanged<RoadSignAnswerResult> onSelectMistake;

  const _RoadSignsMistakesSheet({
    required this.mistakes,
    required this.onSelectMistake,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusExtraLarge),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                AppDimensions.spacingXL,
                AppDimensions.screenPadding,
                AppDimensions.spacingS,
              ),
              child: Text(
                appL10n.gameMistakesReview,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.screenPadding,
                  vertical: AppDimensions.spacingM,
                ),
                itemCount: mistakes.length,
                separatorBuilder: (context, index) => Divider(
                  color: colors.divider.withValues(alpha: 0.4),
                  height: 1,
                ),
                itemBuilder: (context, i) {
                  final mistake = mistakes[i];
                  final sign = mistake.correctSign;

                  return InkWell(
                    onTap: () => onSelectMistake(mistake),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: SvgPicture.asset(
                              sign.assetPath,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: AppDimensions.spacingM),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appL10n.roadSignsSignNumber(sign.number),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.accent,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  sign.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: colors.primaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: colors.secondaryText,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
