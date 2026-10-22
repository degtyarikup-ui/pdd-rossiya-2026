import 'dart:async';
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
import 'package:pdd_app/domain/services/road_signs_engine.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_emblem.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_grid.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_modal.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';
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
  String? _streakBanner;
  Timer? _advanceTimer;

  final List<RoadSignAnswerResult> _mistakes = [];

  int _previousBest = 0;
  bool _isNewRecord = false;
  String _ratingRunId = '';

  @override
  void initState() {
    super.initState();
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
    _streakBanner = null;
    _mistakes.clear();
    _isNewRecord = false;
    _ratingRunId = GameLeaderboardService.newRunId();

    if (_engine != null && (widget.initialDeck == null || widget.initialDeck!.isEmpty)) {
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
          _endGame();
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
        if (_combo >= 2) {
          _streakBanner = '+ $points  •  ${appL10n.gameComboStreak(_combo)}';
        }
      } else {
        SoundEffectsService.instance.playIncorrect();
        HapticFeedbackHelper.warning();
        _combo = 0;
        _lives--;
        _streakBanner = null;
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
        await ref.read(roadSignsProgressProvider.notifier).recordGameResult(
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
            'Ошибка загрузки данных знаков',
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
                'Недостаточно знаков для викторины',
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
        child: Column(
          children: [
            _buildHeader(colors),
            const SizedBox(height: AppDimensions.spacingM),
            if (currentQuestion != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.screenPadding,
                ),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(
                    maxHeight: 120,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingL,
                    vertical: AppDimensions.spacingM,
                  ),
                  decoration: BoxDecoration(
                    color: colors.cardBackground,
                    borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
                    boxShadow: gameSoftShadow(colors),
                    border: Border.all(
                      color: colors.divider.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    currentQuestion.prompt,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: AppDimensions.spacingL),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimensions.screenPadding,
                    0,
                    AppDimensions.screenPadding,
                    AppDimensions.spacingXL,
                  ),
                  child: RoadSignsGrid(
                    options: currentQuestion.options,
                    onSelectOption: _onOptionSelected,
                    isEnabled: !_isProcessing && !_isGameOver,
                    selectedIndex: _selectedOptionIndex,
                    correctIndex: currentQuestion.correctAnswerIndex,
                    isCorrect: _answeredCorrectly,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        AppDimensions.spacingM,
        AppDimensions.screenPadding,
        0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded),
                color: colors.secondaryText,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => Navigator.of(context).pop(),
              ),
              GameLives(lives: _lives, total: widget.initialLives),
              GameScoreLabel(score: _score, streak: _combo),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingM),
          GameTimeBar(
            secondsLeft: _secondsLeft,
            totalSeconds: widget.initialSeconds,
          ),
          if (_streakBanner != null)
            Padding(
              padding: const EdgeInsets.only(top: AppDimensions.spacingS),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.goldLightSurface,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusExtraLarge),
                  border: Border.all(
                    color: colors.gold.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: Text(
                  _streakBanner!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.gold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultOverlay(AppThemeColors colors) {
    return GameResultOverlay(
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
                                  'Знак ${sign.number}',
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
