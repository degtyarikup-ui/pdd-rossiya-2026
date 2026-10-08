import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/domain/services/sign_swiper_engine.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/widgets/sign_explanation_sheet.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/widgets/swipe_card_view.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

enum SignSwiperMode {
  sprint,
  training,
}

class SignSwiperScreen extends ConsumerStatefulWidget {
  final SignSwiperMode initialMode;

  const SignSwiperScreen({
    super.key,
    this.initialMode = SignSwiperMode.sprint,
  });

  @override
  ConsumerState<SignSwiperScreen> createState() => _SignSwiperScreenState();
}

class _SignSwiperScreenState extends ConsumerState<SignSwiperScreen> {
  late SignSwiperMode _mode;
  SignSwiperEngine? _engine;

  final GlobalKey<SwipeCardViewState> _topCardKey = GlobalKey<SwipeCardViewState>();

  List<SignCardQuestion> _deck = [];
  int _currentIndex = 0;

  // Режим «Блиц-спринт»
  Timer? _timer;
  int _secondsLeft = 60;
  int _score = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _lives = 3;
  int _correctAnswers = 0;
  int _totalSwipedInRound = 0;
  bool _isGameOver = false;
  final List<SignCardQuestion> _mistakes = [];

  // Режим «Тренировка»
  String _selectedCategory = 'Все категории';
  int _trainingSolved = 0;

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

  void _initEngine(Map<String, dynamic> signsJson) {
    if (_engine != null) return;
    final signs = SignSwiperEngine.parseSignsJson(signsJson);
    _engine = SignSwiperEngine(allSigns: signs);
    _startRound();
  }

  void _startRound() {
    _timer?.cancel();
    setState(() {
      _currentIndex = 0;
      _score = 0;
      _combo = 0;
      _maxCombo = 0;
      _lives = 3;
      _secondsLeft = 60;
      _correctAnswers = 0;
      _totalSwipedInRound = 0;
      _isGameOver = false;
      _mistakes.clear();

      final categoryFilter = _mode == SignSwiperMode.training && _selectedCategory != 'Все категории'
          ? _selectedCategory
          : null;
      _deck = _engine?.generateDeck(categoryFilter: categoryFilter, count: 30) ?? [];
    });

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
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
          if (_secondsLeft <= 5 && _secondsLeft > 0) {
            SoundEffectsService.instance.playTick();
          }
        } else {
          _endGame();
        }
      });
    });
  }

  void _endGame() {
    _timer?.cancel();
    _isGameOver = true;

    // Сохраняем результат
    ref.read(signSwiperProgressProvider.notifier).recordGameResult(
          score: _score,
          combo: _maxCombo,
          swiped: _totalSwipedInRound,
        );
  }

  void _onCardSwiped(bool userRightSwipe) {
    if (_currentIndex >= _deck.length || _isGameOver) return;

    final card = _deck[_currentIndex];
    final isCorrect = (userRightSwipe == card.isCorrect);

    _totalSwipedInRound++;

    if (isCorrect) {
      SoundEffectsService.instance.playCorrect();
      HapticFeedbackHelper.softSuccess();

      if (_mode == SignSwiperMode.sprint) {
        _correctAnswers++;
        _combo++;
        if (_combo > _maxCombo) _maxCombo = _combo;

        final multiplier = 1 + (_combo ~/ 3).clamp(0, 3);
        _score += 100 * multiplier;
        _secondsLeft = (_secondsLeft + 2).clamp(1, 60);

        if (_combo == 5 || _combo == 10 || _combo == 20) {
          SoundEffectsService.instance.playStreak();
        }
      } else {
        _trainingSolved++;
        ref.read(signSwiperProgressProvider.notifier).incrementTraining(swiped: 1);
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
        // В тренировке сразу показываем разбор знака
        SignExplanationSheet.show(
          context,
          card: card,
          wasAnswerCorrect: false,
          onNext: () {
            _advanceToNextCard();
          },
        );
        return;
      }
    }

    _advanceToNextCard();
  }

  void _advanceToNextCard() {
    setState(() {
      _currentIndex++;
      // Подгрузка следующей пачки, если колода подходит к концу
      if (_deck.length - _currentIndex < 6 && _engine != null) {
        final categoryFilter = _mode == SignSwiperMode.training && _selectedCategory != 'Все категории'
            ? _selectedCategory
            : null;
        final nextBatch = _engine!.generateDeck(categoryFilter: categoryFilter, count: 20);
        _deck.addAll(nextBatch);
      }
    });
  }

  void _switchMode(SignSwiperMode newMode) {
    if (_mode == newMode) return;
    HapticFeedbackHelper.tap();
    setState(() {
      _mode = newMode;
      _startRound();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final signsAsync = ref.watch(signsProvider);

    return Scaffold(
      backgroundColor: colors.homeScreenBackground,
      body: SafeArea(
        child: signsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator.adaptive()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(
                    'Не удалось загрузить знаки',
                    style: TextStyle(fontSize: 16, color: colors.primaryText, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref.refresh(signsProvider),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
          data: (signsJson) {
            _initEngine(signsJson);

            return Stack(
              children: [
                Column(
                  children: [
                    // Верхняя панель
                    _buildTopHeader(colors),

                    // Переключатель режимов
                    _buildModeTabs(colors),

                    // Статусная строка текущего режима
                    if (_mode == SignSwiperMode.sprint)
                      _buildSprintStatusBar(colors)
                    else
                      _buildTrainingStatusBar(colors),

                    // Центр: колода карточек
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: _buildCardStack(colors),
                      ),
                    ),

                    // Нижние кнопки управления
                    _buildBottomButtons(colors),
                  ],
                ),

                // Оверлей окончания игры (Game Over)
                if (_isGameOver) _buildGameOverOverlay(colors),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopHeader(AppThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          AppChromeIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () {
              HapticFeedbackHelper.tap();
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appL10n.gameSignSwiperTitle,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
                Text(
                  appL10n.gameSignSwiperSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка рестарта
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: colors.primaryText,
            tooltip: 'Начать сначала',
            onPressed: () {
              HapticFeedbackHelper.tap();
              _startRound();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabs(AppThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildTabButton(
                colors: colors,
                title: appL10n.gameSignSwiperModeSprint,
                icon: Icons.bolt_rounded,
                isSelected: _mode == SignSwiperMode.sprint,
                onTap: () => _switchMode(SignSwiperMode.sprint),
              ),
            ),
            Expanded(
              child: _buildTabButton(
                colors: colors,
                title: appL10n.gameSignSwiperModeTraining,
                icon: Icons.school_rounded,
                isSelected: _mode == SignSwiperMode.training,
                onTap: () => _switchMode(SignSwiperMode.training),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required AppThemeColors colors,
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : colors.secondaryText,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSprintStatusBar(AppThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Таймер
            Row(
              children: [
                Icon(
                  Icons.timer_rounded,
                  size: 20,
                  color: _secondsLeft <= 10 ? const Color(0xFFEF4444) : colors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  '$_secondsLeft с',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _secondsLeft <= 10 ? const Color(0xFFEF4444) : colors.primaryText,
                  ),
                ),
              ],
            ),

            // Жизни
            Row(
              children: List.generate(3, (index) {
                final isAlive = index < _lives;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    isAlive ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 20,
                    color: isAlive ? const Color(0xFFEF4444) : colors.secondaryText.withValues(alpha: 0.3),
                  ),
                );
              }),
            ),

            // Счёт и Комбо
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$_score',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: colors.primaryText,
                  ),
                ),
                if (_combo > 1)
                  Text(
                    'x${1 + (_combo ~/ 3)} 🔥',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.amber,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrainingStatusBar(AppThemeColors colors) {
    final categories = ['Все категории', ...?_engine?.availableCategories];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.divider),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down_rounded, color: colors.secondaryText),
                  dropdownColor: colors.cardBackground,
                  items: categories.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(
                        cat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (newCat) {
                    if (newCat != null && newCat != _selectedCategory) {
                      setState(() {
                        _selectedCategory = newCat;
                        _startRound();
                      });
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
                const SizedBox(width: 6),
                Text(
                  '$_trainingSolved',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardStack(AppThemeColors colors) {
    if (_currentIndex >= _deck.length) {
      return Center(
        child: CircularProgressIndicator.adaptive(
          valueColor: AlwaysStoppedAnimation(colors.accent),
        ),
      );
    }

    final topCard = _deck[_currentIndex];
    final nextCard = (_currentIndex + 1 < _deck.length) ? _deck[_currentIndex + 1] : null;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Нижняя фоновая карточка для ощущения колоды
        if (nextCard != null)
          Transform.scale(
            scale: 0.94,
            child: Transform.translate(
              offset: const Offset(0, 16),
              child: Opacity(
                opacity: 0.65,
                child: SwipeCardView(
                  key: ValueKey(nextCard.id),
                  card: nextCard,
                  isTopCard: false,
                  onSwiped: (_) {},
                ),
              ),
            ),
          ),

        // Верхняя активная карточка
        SwipeCardView(
          key: _topCardKey,
          card: topCard,
          isTopCard: true,
          onSwiped: _onCardSwiped,
          onCardTap: _mode == SignSwiperMode.training
              ? () {
                  SignExplanationSheet.show(
                    context,
                    card: topCard,
                  );
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildBottomButtons(AppThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Кнопка НЕТ / ВЛЕВО
          _buildActionButton(
            colors: colors,
            icon: Icons.close_rounded,
            color: const Color(0xFFEF4444),
            label: appL10n.gameSignSwiperSwipeLeft,
            onTap: () {
              HapticFeedbackHelper.tap();
              _topCardKey.currentState?.triggerSwipe(false);
            },
          ),

          // Кнопка ПОЯСНЕНИЕ (в режиме обучения)
          if (_mode == SignSwiperMode.training && _currentIndex < _deck.length) ...[
            GestureDetector(
              onTap: () {
                SignExplanationSheet.show(
                  context,
                  card: _deck[_currentIndex],
                );
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.divider),
                ),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: colors.secondaryText,
                  size: 22,
                ),
              ),
            ),
          ],

          // Кнопка ДА / ВПРАВО
          _buildActionButton(
            colors: colors,
            icon: Icons.check_rounded,
            color: const Color(0xFF10B981),
            label: appL10n.gameSignSwiperSwipeRight,
            onTap: () {
              HapticFeedbackHelper.tap();
              _topCardKey.currentState?.triggerSwipe(true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required AppThemeColors colors,
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(36),
            child: Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 34),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _buildGameOverOverlay(AppThemeColors colors) {
    final progress = ref.watch(signSwiperProgressProvider);
    final isNewRecord = _score > 0 && _score >= progress.bestScore;
    final accuracy = _totalSwipedInRound > 0
        ? ((_correctAnswers / _totalSwipedInRound) * 100).round()
        : 0;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Иконка кубка / завершения
                Center(
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: isNewRecord
                          ? Colors.amber.withValues(alpha: 0.2)
                          : colors.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isNewRecord ? Icons.emoji_events_rounded : Icons.flag_rounded,
                      color: isNewRecord ? Colors.amber : colors.accent,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  appL10n.gameOverTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: colors.primaryText,
                  ),
                ),
                if (isNewRecord) ...[
                  const SizedBox(height: 4),
                  Text(
                    appL10n.gameOverNewRecord,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.amber,
                    ),
                  ),
                ],
                const SizedBox(height: 18),

                // Статистика
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.homeScreenBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildGameOverStat(label: appL10n.gameScore, value: '$_score'),
                      Container(width: 1, height: 28, color: colors.divider),
                      _buildGameOverStat(label: appL10n.gameComboLabel, value: 'x$_maxCombo'),
                      Container(width: 1, height: 28, color: colors.divider),
                      _buildGameOverStat(label: appL10n.gameAccuracyLabel, value: '$accuracy%'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Ошибки (если есть)
                if (_mistakes.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${appL10n.gameMistakesReview} (${_mistakes.length}):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _mistakes.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final mistakeCard = _mistakes[i];
                        return InkWell(
                          onTap: () {
                            SignExplanationSheet.show(
                              context,
                              card: mistakeCard,
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: colors.cardBackground,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: colors.divider),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${mistakeCard.sign.number} ${mistakeCard.sign.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: colors.primaryText,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // Кнопки
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: colors.divider),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          HapticFeedbackHelper.tap();
                          Navigator.of(context).pop();
                        },
                        child: Text(
                          appL10n.gameExit,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          HapticFeedbackHelper.tap();
                          _startRound();
                        },
                        child: Text(
                          appL10n.gamePlayAgain,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameOverStat({required String label, required String value}) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
