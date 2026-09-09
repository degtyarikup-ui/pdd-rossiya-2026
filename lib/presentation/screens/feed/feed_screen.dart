import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/presentation/screens/feed/widgets/feed_card.dart';
import 'package:pdd_app/presentation/screens/feed/widgets/feed_streak_dialog.dart';
import 'package:pdd_app/presentation/screens/feed/widgets/tip_feed_card.dart';
import 'package:pdd_app/presentation/widgets/ai_explanation_sheet.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const String _prefKeyFeedSound = 'feed_sound_enabled';
  static const String _prefKeySwipeHintCount = 'feed_swipe_hint_count';

  late PageController _pageController;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  static bool? _cachedSoundEnabled;

  int _currentIndex = 0;
  bool _isSoundEnabled = true;
  bool _isAiSheetOpen = false;
  int _swipeHintCount = 0;
  int _correctStreak = 0;
  final List<FeedItem> _items = [];
  final Map<String, int> _answeredChoices = {};
  final Set<int> _viewedIndices = {0};
  bool _isLoadingMore = false;
  bool _isRefreshing = false;

  final ValueNotifier<double> _timerProgressNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<int> _remainingSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _isCurrentAnsweredNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isCurrentCorrectNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    if (_cachedSoundEnabled != null) {
      _isSoundEnabled = _cachedSoundEnabled!;
    }
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: 0.0, end: -7.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    _loadPreferences();
    _initFeed();
  }

  Future<void> _initFeed() async {
    try {
      final category = ref.read(appSettingsProvider).ticketCategory;
      final repo = ref.read(feedRepositoryProvider);
      debugPrint('FEED_DEBUG: _initFeed starting for category $category');
      final initial = await repo.generateFeedItems(category: category, count: 60);
      debugPrint('FEED_DEBUG: _initFeed generated ${initial.length} items');
      if (mounted) {
        setState(() {
          _items.clear();
          _items.addAll(initial);
        });
      }
    } catch (e, stack) {
      debugPrint('FEED_DEBUG: Feed initialization failed: $e\n$stack');
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sound = prefs.getBool(_prefKeyFeedSound);
      final swipeCount = prefs.getInt(_prefKeySwipeHintCount) ?? 0;
      if (mounted) {
        setState(() {
          if (sound != null) {
            _cachedSoundEnabled = sound;
            _isSoundEnabled = sound;
          }
          _swipeHintCount = swipeCount;
        });
      }
    } catch (_) {}
  }

  Future<void> _incrementSwipeHintCount() async {
    if (_swipeHintCount < 3) {
      _swipeHintCount++;
      if (mounted) setState(() {});
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_prefKeySwipeHintCount, _swipeHintCount);
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      TtsService.instance.stop();
    }
  }

  @override
  void deactivate() {
    TtsService.instance.stop();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TtsService.instance.stop();
    _pageController.dispose();
    _bounceController.dispose();
    _timerProgressNotifier.dispose();
    _remainingSecondsNotifier.dispose();
    _isCurrentAnsweredNotifier.dispose();
    _isCurrentCorrectNotifier.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    HapticFeedbackHelper.select();
    TtsService.instance.stop().ignore();

    if (index > _currentIndex && !_viewedIndices.contains(index)) {
      if (!PremiumService.instance.canAccessFeed) {
        _pageController.jumpToPage(_currentIndex);
        PremiumPaywallSheet.show(context);
        return;
      }
      _viewedIndices.add(index);
    }

    if (_isCurrentAnsweredNotifier.value && !_isCurrentCorrectNotifier.value) {
      _incrementSwipeHintCount();
    }

    setState(() => _currentIndex = index);

    if (index < _items.length) {
      final item = _items[index];
      if (_answeredChoices.containsKey(item.id)) {
        final chosen = _answeredChoices[item.id]!;
        _isCurrentAnsweredNotifier.value = true;
        _isCurrentCorrectNotifier.value = (chosen == item.correctAnswerIndex);
        _timerProgressNotifier.value = 1.0;
      } else {
        _isCurrentAnsweredNotifier.value = false;
        _isCurrentCorrectNotifier.value = false;
        _timerProgressNotifier.value = 1.0;
      }
    }

    if (index >= _items.length - 4 && !_isLoadingMore) {
      _loadMoreItems();
    }
  }

  Future<void> _loadMoreItems() async {
    _isLoadingMore = true;
    try {
      final category = ref.read(appSettingsProvider).ticketCategory;
      final repo = ref.read(feedRepositoryProvider);
      final currentIds = _items
          .map((i) => i.rawQuestionId ?? i.id)
          .where((id) => id.isNotEmpty)
          .toSet();
      final newItems = await repo.generateFeedItems(
        category: category,
        count: 40,
        excludeQuestionIds: currentIds,
      );
      if (mounted && newItems.isNotEmpty) {
        setState(() {
          _items.addAll(newItems);
        });
      }
    } catch (_) {} finally {
      _isLoadingMore = false;
    }
  }

  Future<void> _refreshFeed() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    HapticFeedbackHelper.success();

    try {
      final category = ref.read(appSettingsProvider).ticketCategory;
      final repo = ref.read(feedRepositoryProvider);
      final newItems = await repo.generateFeedItems(category: category, count: 50);

      if (mounted) {
        setState(() {
          _items.clear();
          _answeredChoices.clear();
          _items.addAll(newItems);
          _currentIndex = 0;
        });

        _isCurrentAnsweredNotifier.value = false;
        _isCurrentCorrectNotifier.value = false;
        _timerProgressNotifier.value = 1.0;

        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      }
    } catch (e) {
      debugPrint('FeedScreen: refresh error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _autoNext() {
    if (_isCurrentAnsweredNotifier.value && !_isCurrentCorrectNotifier.value) {
      _incrementSwipeHintCount();
    }
    if (!PremiumService.instance.canAccessFeed) {
      PremiumPaywallSheet.show(context);
      return;
    }
    if (_currentIndex < _items.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  void _previousPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.fastOutSlowIn,
      );
    } else if (_currentIndex == 0) {
      _refreshFeed();
    }
  }

  void _checkStreakMilestone(int streak) {
    final milestone = FeedStreakMilestone.forCount(streak);
    if (milestone != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FeedStreakDialog.show(context, milestone);
        }
      });
    }
  }

  Future<void> _toggleSound() async {
    HapticFeedbackHelper.tap();
    final newVal = !_isSoundEnabled;
    _cachedSoundEnabled = newVal;
    if (!newVal) {
      TtsService.instance.stop().ignore();
    }
    setState(() => _isSoundEnabled = newVal);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyFeedSound, newVal);
    } catch (_) {}
  }

  Future<void> _openAiChatForCurrentItem(FeedItem currentItem) async {
    HapticFeedbackHelper.tap();
    TtsService.instance.stop();
    setState(() {
      _isAiSheetOpen = true;
    });

    final qId = currentItem.rawQuestionId ?? currentItem.id;
    await AiExplanationSheet.show(
      context: context,
      questionId: qId,
      questionText: currentItem.questionText,
      answers: currentItem.answers,
      correctAnswerIndex: currentItem.correctAnswerIndex,
      officialExplanation: currentItem.explanation,
    );

    if (mounted) {
      setState(() {
        _isAiSheetOpen = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final feedAsync = ref.watch(feedItemsProvider);

    if (_items.isEmpty) {
      return feedAsync.when(
        loading: () => Scaffold(
          backgroundColor: colors.homeScreenBackground,
          body: Center(
            child: CircularProgressIndicator(color: colors.accent),
          ),
        ),
        error: (err, stack) => Scaffold(
          backgroundColor: colors.homeScreenBackground,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Не удалось загрузить вопросы',
                  style: TextStyle(color: colors.secondaryText, fontSize: 16),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    _initFeed();
                    final _ = ref.refresh(feedItemsProvider);
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Scaffold(
              backgroundColor: colors.homeScreenBackground,
              body: Center(
                child: Text(
                  'Нет вопросов для отображения',
                  style: TextStyle(color: colors.secondaryText),
                ),
              ),
            );
          }
          if (_items.isEmpty) {
            _items.addAll(items);
          }
          return _buildFeedContent(context, _items, colors);
        },
      );
    }

    return _buildFeedContent(context, _items, colors);
  }

  Widget _buildFeedContent(
    BuildContext context,
    List<FeedItem> displayItems,
    AppThemeColors colors,
  ) {
    final currentItem = _currentIndex < displayItems.length
        ? displayItems[_currentIndex]
        : displayItems.first;

    return Scaffold(
      backgroundColor: colors.homeScreenBackground,
      body: Stack(
        children: [
          // 1. Full-screen PageView (Cards and their top controls swipe together)
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (_currentIndex == 0 && !_isRefreshing) {
                  if (notification is OverscrollNotification &&
                      notification.overscroll < -15) {
                    _refreshFeed();
                    return true;
                  }
                }
                return false;
              },
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                onPageChanged: _onPageChanged,
                itemCount: displayItems.length,
                itemBuilder: (context, index) {
                  final item = displayItems[index];
                  if (item.isTip) {
                    return TipFeedCard(
                      key: ValueKey('${item.id}_$index'),
                      item: item,
                      isCurrent: index == _currentIndex,
                      onAutoNext: _autoNext,
                      onPrevious: _previousPage,
                      onTimerTick: (progress, remainingSec) {
                        _timerProgressNotifier.value = progress;
                        _remainingSecondsNotifier.value = remainingSec;
                      },
                    );
                  }
                  return FeedCard(
                    key: ValueKey('${item.id}_$index'),
                    item: item,
                    isCurrent: index == _currentIndex,
                    isSoundEnabled: _isSoundEnabled,
                    isPaused: _isAiSheetOpen,
                    initialSelectedAnswerIndex: _answeredChoices[item.id],
                    onAnswerRecorded: (selectedIdx) {
                      _answeredChoices[item.id] = selectedIdx;
                      if (selectedIdx == item.correctAnswerIndex) {
                        _correctStreak++;
                        _checkStreakMilestone(_correctStreak);
                      } else {
                        _correctStreak = 0;
                      }
                    },
                    onToggleSound: _toggleSound,
                    onAutoNext: _autoNext,
                    onPrevious: _previousPage,
                    onTimerTick: (progress, remainingSec) {
                      _timerProgressNotifier.value = progress;
                      _remainingSecondsNotifier.value = remainingSec;
                    },
                    onAnswerStateChanged: (isAnswered, isCorrect) {
                      _isCurrentAnsweredNotifier.value = isAnswered;
                      _isCurrentCorrectNotifier.value = isCorrect;
                    },
                  );
                },
              ),
            ),
          ),

          // 2. Fixed Bottom Countdown Timing Line (Firmly pinned to bottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomTimingBar(colors, currentItem),
          ),

          // 3. Floating "Свайпай ↑" Hint (Shown maximum 3 times)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: ValueListenableBuilder<bool>(
              valueListenable: _isCurrentAnsweredNotifier,
              builder: (context, isAnswered, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _isCurrentCorrectNotifier,
                  builder: (context, isCorrect, _) {
                    final shouldShowHint =
                        _swipeHintCount < 3 && isAnswered && !isCorrect;
                    if (!shouldShowHint) return const SizedBox.shrink();

                    return Center(
                      child: AnimatedBuilder(
                        animation: _bounceAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, _bounceAnimation.value),
                            child: child,
                          );
                        },
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              HapticFeedbackHelper.tap();
                              _incrementSwipeHintCount();
                              _autoNext();
                            },
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: colors.accent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Свайпай',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(
                                    Icons.arrow_upward_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 4. Floating AI, Sound & Favorite controls (bottom right corner, above bottom nav bar)
          Positioned(
            right: AppDimensions.screenPadding,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. AI Chat Button (Brand Green #10B981, visible even before answering)
                _buildFloatingActionButton(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: Colors.white,
                  backgroundColor: colors.green,
                  onTap: () {
                    final currentItem = _currentIndex < displayItems.length
                        ? displayItems[_currentIndex]
                        : null;
                    if (currentItem != null && !currentItem.isTip) {
                      _openAiChatForCurrentItem(currentItem);
                    }
                  },
                  colors: colors,
                ),
                const SizedBox(height: 10),

                // 2. Sound Toggle Button
                _buildFloatingActionButton(
                  icon: _isSoundEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  iconColor: _isSoundEnabled
                      ? colors.primaryText
                      : colors.secondaryText,
                  onTap: _toggleSound,
                  colors: colors,
                ),
                const SizedBox(height: 10),

                // 3. Favorite Toggle Button
                Consumer(
                  builder: (context, ref, _) {
                    final currentItem = _currentIndex < displayItems.length
                        ? displayItems[_currentIndex]
                        : null;
                    final qId = currentItem?.rawQuestionId;
                    if (qId == null) return const SizedBox.shrink();

                    final isFavAsync =
                        ref.watch(favoriteQuestionProvider(qId));
                    final isFav = isFavAsync.value ?? false;

                    return _buildFloatingActionButton(
                      icon: isFav
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      iconColor: isFav ? Colors.white : colors.primaryText,
                      backgroundColor: isFav ? colors.gold : null,
                      onTap: () async {
                        HapticFeedbackHelper.tap();
                        final category =
                            ref.read(appSettingsProvider).ticketCategory;
                        final ds = ref.read(progressDataSourceProvider);
                        await ds.toggleFavorite(qId, category);
                        ref.read(appDataRefreshProvider.notifier).state++;
                      },
                      colors: colors,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton({
    required IconData icon,
    required Color iconColor,
    Color? backgroundColor,
    required VoidCallback onTap,
    required AppThemeColors colors,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: backgroundColor ?? colors.cardBackground,
          shape: BoxShape.circle,
          border: Border.all(
            color: backgroundColor != null ? Colors.transparent : colors.divider,
            width: 1,
          ),
        ),
        child: Center(
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }

  Widget _buildBottomTimingBar(AppThemeColors colors, FeedItem currentItem) {
    return IgnorePointer(
      child: ValueListenableBuilder<bool>(
        valueListenable: _isCurrentAnsweredNotifier,
        builder: (context, isAnswered, _) {
          return ValueListenableBuilder<bool>(
            valueListenable: _isCurrentCorrectNotifier,
            builder: (context, isCorrect, _) {
              return ValueListenableBuilder<double>(
                valueListenable: _timerProgressNotifier,
                builder: (context, progress, _) {
                  Color barColor;
                  if (!currentItem.isTip && isAnswered) {
                    barColor = isCorrect ? colors.green : colors.red;
                  } else if (progress > 0.3) {
                    barColor = colors.accent;
                  } else if (progress > 0.15) {
                    barColor = colors.gold;
                  } else {
                    barColor = colors.red;
                  }

                  return SizedBox(
                    height: 3.5,
                    child: LinearProgressIndicator(
                      value: (!currentItem.isTip && isAnswered) ? 1.0 : progress,
                      backgroundColor:
                          colors.cardBackground.withValues(alpha: 0.5),
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      minHeight: 3.5,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
