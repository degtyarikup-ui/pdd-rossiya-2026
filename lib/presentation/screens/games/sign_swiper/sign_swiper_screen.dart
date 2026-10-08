import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/domain/services/sign_swiper_engine.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/widgets/sign_explanation_sheet.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/widgets/swipe_card_view.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_art.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

enum SignSwiperMode { sprint, training }

class SignSwiperScreen extends ConsumerStatefulWidget {
  final SignSwiperMode initialMode;

  const SignSwiperScreen({
    super.key,
    this.initialMode = SignSwiperMode.training,
  });

  @override
  ConsumerState<SignSwiperScreen> createState() => _SignSwiperScreenState();
}

class _SignSwiperScreenState extends ConsumerState<SignSwiperScreen> {
  late SignSwiperMode _mode;
  SignSwiperEngine? _engine;

  final SwipeCardController _cardController = SwipeCardController();

  List<SignCardQuestion> _deck = [];
  int _currentIndex = 0;
  bool _isProcessingSwipe = false;

  // Блиц
  Timer? _timer;
  int _secondsLeft = 60;
  int _score = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _lives = 3;
  int _correctAnswers = 0;
  int _totalSwipedInRound = 0;
  bool _isGameOver = false;
  bool _isNewRecord = false;
  bool _timeUp = false;
  int _previousBest = 0;
  final List<SignCardQuestion> _mistakes = [];

  // Обучение: null — все категории
  String? _selectedCategory;
  int _trainingSolved = 0;

  /// Множитель очков за комбо: каждые 3 верных ответа +1, не выше x4.
  static int _multiplierFor(int combo) => 1 + (combo ~/ 3).clamp(0, 3);

  String? get _categoryFilter =>
      _mode == SignSwiperMode.training ? _selectedCategory : null;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Вызывается из build при первой загрузке знаков: состояние выставляем
  /// без setState (нельзя перерисовывать во время build), таймер — после кадра.
  void _initEngine(Map<String, dynamic> signsJson) {
    if (_engine != null) return;
    final signs = SignSwiperEngine.parseSignsJson(signsJson);
    _engine = SignSwiperEngine(allSigns: signs);
    _resetRoundState();
    if (_mode == SignSwiperMode.sprint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mode == SignSwiperMode.sprint && !_isGameOver) {
          _startSprintTimer();
        }
      });
    }
  }

  void _resetRoundState() {
    _isProcessingSwipe = false;
    _currentIndex = 0;
    _score = 0;
    _combo = 0;
    _maxCombo = 0;
    _lives = 3;
    _secondsLeft = 60;
    _correctAnswers = 0;
    _totalSwipedInRound = 0;
    _isGameOver = false;
    _isNewRecord = false;
    _timeUp = false;
    _mistakes.clear();
    _deck =
        _engine?.generateDeck(categoryFilter: _categoryFilter, count: 30) ?? [];
  }

  void _startRound() {
    _timer?.cancel();
    setState(_resetRoundState);

    if (_mode == SignSwiperMode.sprint) {
      _startSprintTimer();
    }
  }

  void _startSprintTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 5 && _secondsLeft > 0) {
          SoundEffectsService.instance.playTick();
        }
      } else {
        _timeUp = true;
        _endGame();
      }
    });
  }

  /// Конец раунда. Вызывается и из таймера, и из свайпа — поэтому сам делает
  /// setState. Рекорд сравниваем ДО записи, иначе он всегда «побит».
  void _endGame() {
    _timer?.cancel();
    final previousBest = ref.read(signSwiperProgressProvider).bestScore;
    ref
        .read(signSwiperProgressProvider.notifier)
        .recordGameResult(
          score: _score,
          combo: _maxCombo,
          swiped: _totalSwipedInRound,
        );
    setState(() {
      _previousBest = previousBest;
      _isNewRecord = _score > 0 && _score > previousBest;
      _isGameOver = true;
      _isProcessingSwipe = false;
    });
  }

  void _onCardSwiped(bool userRightSwipe) {
    if (_currentIndex >= _deck.length || _isGameOver || _isProcessingSwipe) {
      return;
    }
    _isProcessingSwipe = true;

    final card = _deck[_currentIndex];
    final isCorrect = userRightSwipe == card.isCorrect;

    _totalSwipedInRound++;

    if (isCorrect) {
      SoundEffectsService.instance.playCorrect();
      HapticFeedbackHelper.softSuccess();

      if (_mode == SignSwiperMode.sprint) {
        _correctAnswers++;
        _combo++;
        if (_combo > _maxCombo) _maxCombo = _combo;
        _score += 100 * _multiplierFor(_combo);
        _secondsLeft = (_secondsLeft + 2).clamp(1, 60);

        if (_combo == 5 || _combo == 10 || _combo == 20) {
          SoundEffectsService.instance.playStreak();
        }
      } else {
        _trainingSolved++;
        ref
            .read(signSwiperProgressProvider.notifier)
            .incrementTraining(swiped: 1);
      }
    } else {
      SoundEffectsService.instance.playIncorrect();
      HapticFeedbackHelper.error();

      if (_mode == SignSwiperMode.sprint) {
        _combo = 0;
        _lives--;
        _secondsLeft = (_secondsLeft - 3).clamp(0, 60);
        _mistakes.add(card);

        if (_lives <= 0 || _secondsLeft <= 0) {
          _endGame();
          return;
        }
      } else {
        // В обучении сразу разбираем знак.
        SignExplanationSheet.show(
          context,
          card: card,
          wasAnswerCorrect: false,
          onNext: _advanceToNextCard,
        );
        return;
      }
    }

    _advanceToNextCard();
  }

  void _advanceToNextCard() {
    if (!mounted) return;
    setState(() {
      _isProcessingSwipe = false;
      _currentIndex++;
      // Подгружаем следующую пачку, пока колода не кончилась.
      if (_deck.length - _currentIndex < 6 && _engine != null) {
        _deck.addAll(
          _engine!.generateDeck(categoryFilter: _categoryFilter, count: 20),
        );
      }
    });
  }

  void _switchMode(SignSwiperMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    _startRound();
  }

  Future<void> _pickCategory() async {
    final categories = _engine?.availableCategories ?? const <String>[];
    HapticFeedbackHelper.tap();
    final picked = await showModalBottomSheet<_CategoryChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _CategorySheet(categories: categories, selected: _selectedCategory),
    );
    if (picked == null || !mounted || picked.value == _selectedCategory) return;
    _selectedCategory = picked.value;
    _startRound();
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final signsAsync = ref.watch(signsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: signsAsync.when(
          loading: () =>
              Center(child: CircularProgressIndicator(color: colors.accent)),
          error: (error, _) => _buildError(colors),
          data: (signsJson) {
            _initEngine(signsJson);
            final sprint = _mode == SignSwiperMode.sprint;

            return Stack(
              children: [
                Column(
                  children: [
                    _buildHeader(colors, sprint),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.screenPadding,
                      ),
                      child: GameModeSwitch(
                        labels: [
                          appL10n.gameSignSwiperModeTraining,
                          appL10n.gameSignSwiperModeSprint,
                        ],
                        selected: sprint ? 1 : 0,
                        onChanged: (i) => _switchMode(
                          i == 1
                              ? SignSwiperMode.sprint
                              : SignSwiperMode.training,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimensions.screenPadding,
                          AppDimensions.spacingXL,
                          AppDimensions.screenPadding,
                          AppDimensions.spacingXXXL,
                        ),
                        child: _buildCardStack(colors),
                      ),
                    ),
                    _buildAnswerButtons(colors),
                  ],
                ),
                if (_isGameOver) Positioned.fill(child: _buildResult(colors)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildError(AppThemeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              appL10n.gameSignsLoadError,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: colors.secondaryText),
            ),
            const SizedBox(height: AppDimensions.spacingL),
            SizedBox(
              width: 200,
              child: GameActionButton(
                label: appL10n.gameRetry,
                background: colors.accent,
                foreground: colors.white,
                onTap: () => ref.invalidate(signsProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Шапка. Блиц: закрыть · счёт · жизни, под ними полоса времени.
  /// Обучение: закрыть · выбор категории · сколько верно.
  Widget _buildHeader(AppThemeColors colors, bool sprint) {
    final close = AppChromeIconButton(
      icon: Icons.close_rounded,
      onTap: () {
        HapticFeedbackHelper.tap();
        Navigator.of(context).pop();
      },
    );

    if (sprint) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimensions.screenPadding,
          AppDimensions.spacingM,
          AppDimensions.screenPadding,
          AppDimensions.spacingL,
        ),
        child: Column(
          children: [
            Row(
              children: [
                close,
                Expanded(
                  child: Center(
                    child: GameScoreLabel(
                      score: _score,
                      multiplier: _multiplierFor(_combo),
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: GameLives(lives: _lives),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingM),
            GameTimeBar(secondsLeft: _secondsLeft, totalSeconds: 60),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        AppDimensions.spacingM,
        AppDimensions.screenPadding,
        AppDimensions.spacingL,
      ),
      child: Row(
        children: [
          close,
          const SizedBox(width: AppDimensions.spacingM),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickCategory,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _selectedCategory ?? appL10n.gameSignSwiperCategoryAll,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 22,
                    color: colors.secondaryText,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppDimensions.spacingS),
          Icon(Icons.check_circle_rounded, size: 20, color: colors.green),
          const SizedBox(width: 4),
          Text(
            '$_trainingSolved',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardStack(AppThemeColors colors) {
    if (_currentIndex >= _deck.length) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }

    final topCard = _deck[_currentIndex];
    final training = _mode == SignSwiperMode.training;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Следующая карточка: край колоды, без содержимого.
            Positioned.fill(
              child: Transform.translate(
                offset: const Offset(0, 22),
                child: Transform.scale(
                  scale: 0.92,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.cardBackground.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(
                        AppDimensions.radiusExtraLarge,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SwipeCardView(
              key: ValueKey(topCard.id),
              controller: _cardController,
              card: topCard,
              onSwiped: _onCardSwiped,
              onCardTap: training
                  ? () => SignExplanationSheet.show(context, card: topCard)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerButtons(AppThemeColors colors) {
    final card = _currentIndex < _deck.length ? _deck[_currentIndex] : null;
    final training = _mode == SignSwiperMode.training;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        0,
        AppDimensions.screenPadding,
        AppDimensions.spacingXL,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GameRoundButton(
            icon: Icons.close_rounded,
            label: card?.leftActionLabel ?? appL10n.gameSignNo,
            color: colors.red,
            surface: colors.redLight,
            onTap: () {
              HapticFeedbackHelper.tap();
              _cardController.swipeLeft();
            },
          ),
          // В обучении — разбор знака до ответа.
          if (training && card != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GameRoundButton(
                icon: Icons.menu_book_rounded,
                color: colors.secondaryText,
                surface: colors.cardBackground,
                size: 52,
                onTap: () => SignExplanationSheet.show(context, card: card),
              ),
            ),
          GameRoundButton(
            icon: Icons.check_rounded,
            label: card?.rightActionLabel ?? appL10n.gameSignYes,
            color: colors.green,
            surface: colors.greenLight,
            onTap: () {
              HapticFeedbackHelper.tap();
              _cardController.swipeRight();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResult(AppThemeColors colors) {
    final accuracy = _totalSwipedInRound > 0
        ? ((_correctAnswers / _totalSwipedInRound) * 100).round()
        : 0;

    return GameResultOverlay(
      art: const SignSwiperArt(),
      title: _timeUp ? appL10n.gameTimeUp : appL10n.gameOverTitle,
      score: _score,
      bestScore: _previousBest,
      isNewRecord: _isNewRecord,
      stats: [
        GameResultStat(
          appL10n.gameCorrectShort,
          '$_correctAnswers',
          color: colors.green,
        ),
        GameResultStat(appL10n.gameAccuracyLabel, '$accuracy%'),
        GameResultStat(appL10n.gameComboLabel, 'x$_maxCombo'),
      ],
      mistakesCount: _mistakes.length,
      onMistakes: _showMistakes,
      onRestart: _startRound,
      onExit: () => Navigator.of(context).pop(),
    );
  }

  void _showMistakes() {
    HapticFeedbackHelper.tap();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MistakesSheet(mistakes: List.of(_mistakes)),
    );
  }
}

/// Результат выбора в листе категорий: `value == null` — «все категории».
class _CategoryChoice {
  const _CategoryChoice(this.value);

  final String? value;
}

class _CategorySheet extends StatelessWidget {
  const _CategorySheet({required this.categories, required this.selected});

  final List<String> categories;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final options = <String?>[null, ...categories];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusExtraLarge),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AppDimensions.spacingS),
          itemCount: options.length,
          itemBuilder: (context, i) {
            final option = options[i];
            final isSelected = option == selected;
            return InkWell(
              onTap: () => Navigator.of(context).pop(_CategoryChoice(option)),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.screenPadding,
                ),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option ?? appL10n.gameSignSwiperCategoryAll,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? colors.accent
                              : colors.primaryText,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_rounded, size: 20, color: colors.accent),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Ошибки раунда: строка на знак, тап — разбор.
class _MistakesSheet extends StatelessWidget {
  const _MistakesSheet({required this.mistakes});

  final List<SignCardQuestion> mistakes;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
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
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: AppDimensions.spacingM),
                itemCount: mistakes.length,
                itemBuilder: (context, i) {
                  final card = mistakes[i];
                  return InkWell(
                    onTap: () => SignExplanationSheet.show(context, card: card),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.screenPadding,
                        vertical: AppDimensions.spacingM,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: card.sign.image.endsWith('.svg')
                                ? SvgPicture.asset(card.sign.assetPath)
                                : Image.asset(card.sign.assetPath),
                          ),
                          const SizedBox(width: AppDimensions.spacingM),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  card.sign.number,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.accent,
                                  ),
                                ),
                                Text(
                                  card.sign.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
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
