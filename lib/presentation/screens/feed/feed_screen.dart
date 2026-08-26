import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/presentation/screens/feed/widgets/ad_feed_card.dart';
import 'package:pdd_app/presentation/screens/feed/widgets/feed_card.dart';
import 'package:pdd_app/presentation/screens/feed/widgets/tip_feed_card.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
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

  int _currentIndex = 0;
  bool _isSoundEnabled = true;
  int _swipeHintCount = 0;
  final List<FeedItem> _items = [];
  final Map<String, int> _answeredChoices = {};
  bool _isLoadingMore = false;
  bool _isRefreshing = false;

  final ValueNotifier<double> _timerProgressNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<int> _remainingSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _isCurrentAnsweredNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isCurrentCorrectNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isCurrentFavoriteNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
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
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sound = prefs.getBool(_prefKeyFeedSound);
      final swipeCount = prefs.getInt(_prefKeySwipeHintCount) ?? 0;
      if (mounted) {
        setState(() {
          if (sound != null) _isSoundEnabled = sound;
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
    _isCurrentFavoriteNotifier.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    HapticFeedbackHelper.select();
    TtsService.instance.stop().ignore();

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
      _checkCurrentFavorite();
    }

    if (index >= _items.length - 4 && !_isLoadingMore) {
      _loadMoreItems();
    }
  }

  Future<void> _checkCurrentFavorite() async {
    if (_currentIndex >= _items.length) return;
    final item = _items[_currentIndex];
    final rawId = item.rawQuestionId;
    if (rawId == null) {
      _isCurrentFavoriteNotifier.value = false;
      return;
    }
    try {
      final category = ref.read(appSettingsProvider).ticketCategory;
      final ds = ref.read(progressDataSourceProvider);
      final isFav = await ds.isFavorite(rawId, category);
      if (mounted) _isCurrentFavoriteNotifier.value = isFav;
    } catch (_) {}
  }

  Future<void> _toggleCurrentFavorite() async {
    if (_currentIndex >= _items.length) return;
    final item = _items[_currentIndex];
    final rawId = item.rawQuestionId;
    if (rawId == null) return;
    HapticFeedbackHelper.success();
    final category = ref.read(appSettingsProvider).ticketCategory;
    final ds = ref.read(progressDataSourceProvider);
    await ds.toggleFavorite(rawId, category);
    final isFav = await ds.isFavorite(rawId, category);
    if (mounted) _isCurrentFavoriteNotifier.value = isFav;
  }

  Future<void> _loadMoreItems() async {
    _isLoadingMore = true;
    try {
      final category = ref.read(appSettingsProvider).ticketCategory;
      final repo = ref.read(feedRepositoryProvider);
      final newItems = await repo.generateFeedItems(category: category, count: 40);
      if (mounted) {
        setState(() {
          _items.addAll(newItems);
        });
      }
    } catch (_) {} finally {
      _isLoadingMore = false;
    }
  }

  void _onAdLoadFailed(String itemId) {
    if (!mounted) return;
    final itemIndex = _items.indexWhere((it) => it.id == itemId);
    if (itemIndex == -1) return;

    setState(() {
      _items.removeAt(itemIndex);
      if (_currentIndex >= _items.length && _items.isNotEmpty) {
        _currentIndex = _items.length - 1;
      }
    });
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
        _checkCurrentFavorite();

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

  Future<void> _toggleSound() async {
    HapticFeedbackHelper.tap();
    final newVal = !_isSoundEnabled;
    setState(() => _isSoundEnabled = newVal);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyFeedSound, newVal);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final initialAsync = ref.watch(feedItemsProvider);
    final topPadding = MediaQuery.paddingOf(context).top;
    final topHeaderHeight = topPadding + 52.0;

    return Scaffold(
      backgroundColor: colors.homeScreenBackground,
      body: initialAsync.when(
        data: (initialItems) {
          if (_items.isEmpty && initialItems.isNotEmpty) {
            _items.addAll(initialItems);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _checkCurrentFavorite();
            });
          }

          if (_items.isEmpty) {
            return Center(
              child: Text(
                'Вопросы пока не загружены',
                style: TextStyle(color: colors.secondaryText),
              ),
            );
          }

          final currentItem = _currentIndex < _items.length
              ? _items[_currentIndex]
              : _items.first;

          return Stack(
            children: [
              // 1. Full-screen PageView with top padding to clear the fixed header
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(top: topHeaderHeight),
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
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        if (item.isAd) {
                          return AdFeedCard(
                            key: ValueKey('${item.id}_$index'),
                            item: item,
                            isCurrent: index == _currentIndex,
                            onAutoNext: _autoNext,
                            onPrevious: _previousPage,
                            onFailed: _onAdLoadFailed,
                          );
                        }
                        if (item.isTip) {
                          return TipFeedCard(
                            key: ValueKey('${item.id}_$index'),
                            item: item,
                            isCurrent: index == _currentIndex,
                            onAutoNext: _autoNext,
                            onPrevious: _previousPage,
                          );
                        }
                        return FeedCard(
                          key: ValueKey('${item.id}_$index'),
                          item: item,
                          isCurrent: index == _currentIndex,
                          isSoundEnabled: _isSoundEnabled,
                          initialSelectedAnswerIndex: _answeredChoices[item.id],
                          onAnswerRecorded: (selectedIdx) {
                            _answeredChoices[item.id] = selectedIdx;
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
                          onFavoriteChanged: (isFav) {
                            _isCurrentFavoriteNotifier.value = isFav;
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),

              // 2. Top Smooth Gradient Dissolve Mask (Questions gracefully fade into background color as they fly away)
              Positioned(
                top: topHeaderHeight,
                left: 0,
                right: 0,
                height: 28,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.homeScreenBackground,
                          colors.homeScreenBackground.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Bottom Smooth Gradient Dissolve Mask (New questions smoothly fade in from bottom)
              Positioned(
                bottom: 4,
                left: 0,
                right: 0,
                height: 28,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          colors.homeScreenBackground,
                          colors.homeScreenBackground.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 4. Fixed Top Header Bar (Controls stay firmly in place; contents update smoothly)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    color: colors.homeScreenBackground,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.screenPadding,
                      vertical: 8,
                    ),
                    child: _buildTopHeader(context, currentItem, colors),
                  ),
                ),
              ),

              // 5. Fixed Bottom Countdown Timing Line (Firmly pinned at bottom)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomTimingBar(colors, currentItem),
              ),

              // 6. Floating "Свайпай ↑" Hint (Shown maximum 3 times)
              ValueListenableBuilder<bool>(
                valueListenable: _isCurrentAnsweredNotifier,
                builder: (context, isAnswered, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _isCurrentCorrectNotifier,
                    builder: (context, isCorrect, _) {
                      final shouldShowHint =
                          _swipeHintCount < 3 && isAnswered && !isCorrect;
                      if (!shouldShowHint) return const SizedBox.shrink();

                      return Positioned(
                        left: 0,
                        right: 0,
                        bottom: 16,
                        child: Center(
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
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(color: colors.accent),
        ),
        error: (err, _) => Center(
          child: Text(
            'Ошибка загрузки ленты: $err',
            style: TextStyle(color: colors.secondaryText),
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(
    BuildContext context,
    FeedItem currentItem,
    AppThemeColors colors,
  ) {
    if (currentItem.isTip) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final yellowBadgeBg =
          isDark ? const Color(0xFF422006) : const Color(0xFFFEF08A);
      final yellowBadgeText =
          isDark ? const Color(0xFFFACC15) : const Color(0xFFCA8A04);
      final tip = currentItem.driverTip;
      final categoryName = tip != null ? tip.category : 'СОВЕТЫ';

      return Row(
        key: ValueKey('tip_header_${currentItem.id}'),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: yellowBadgeBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lightbulb_rounded,
                  size: 14,
                  color: yellowBadgeText,
                ),
                const SizedBox(width: 5),
                Text(
                  'СОВЕТ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: yellowBadgeText,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: colors.secondaryText,
                ),
                const SizedBox(width: 4),
                Text(
                  categoryName,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (currentItem.isAd) {
      return Row(
        key: ValueKey('ad_header_${currentItem.id}'),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.lightAccent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'РЕКЛАМА',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.accent,
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: colors.secondaryText,
                ),
                const SizedBox(width: 4),
                Text(
                  'Яндекс Директ',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Standard Question Header
    return Row(
      key: ValueKey('question_header_${currentItem.id}'),
      children: [
        if (currentItem.badgeText != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.lightAccent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              currentItem.badgeText!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],

        // Digital countdown badge (shows remaining seconds or completion status)
        ValueListenableBuilder<bool>(
          valueListenable: _isCurrentAnsweredNotifier,
          builder: (context, isAnswered, _) {
            if (isAnswered) {
              return ValueListenableBuilder<bool>(
                valueListenable: _isCurrentCorrectNotifier,
                builder: (context, isCorrect, _) {
                  final badgeBg = isCorrect ? colors.greenLight : colors.redLight;
                  final badgeText = isCorrect ? colors.green : colors.red;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          size: 14,
                          color: badgeText,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isCorrect ? 'Верно' : 'Ошибка',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: badgeText,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            }

            return ValueListenableBuilder<int>(
              valueListenable: _remainingSecondsNotifier,
              builder: (context, remainingSec, _) {
                final isUrgent = remainingSec <= 4 && remainingSec > 0;
                final timerBg = isUrgent
                    ? colors.redLight
                    : (remainingSec > 5 ? colors.lightAccent : colors.goldLightSurface);
                final timerText = isUrgent
                    ? colors.red
                    : (remainingSec > 5 ? colors.accent : colors.gold);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: timerBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: timerText,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$remainingSec с',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: timerText,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),

        const Spacer(),

        // Sound Voiceover Toggle Button
        AppChromeIconButton(
          icon: _isSoundEnabled
              ? Icons.volume_up_rounded
              : Icons.volume_off_rounded,
          backgroundColor: _isSoundEnabled
              ? colors.lightAccent
              : colors.cardBackground,
          iconColor: _isSoundEnabled
              ? colors.accent
              : colors.primaryText.withValues(alpha: 0.65),
          onTap: _toggleSound,
        ),
        const SizedBox(width: 8),

        // Favorite Star Button
        ValueListenableBuilder<bool>(
          valueListenable: _isCurrentFavoriteNotifier,
          builder: (context, isFav, _) {
            return AppChromeIconButton(
              icon: isFav ? Icons.star_rounded : Icons.star_outline_rounded,
              backgroundColor: isFav
                  ? colors.goldLightSurface
                  : colors.cardBackground,
              iconColor: isFav
                  ? colors.gold
                  : colors.primaryText.withValues(alpha: 0.65),
              onTap: _toggleCurrentFavorite,
            );
          },
        ),
      ],
    );
  }

  Widget _buildBottomTimingBar(AppThemeColors colors, FeedItem currentItem) {
    if (currentItem.isTip || currentItem.isAd) {
      return const SizedBox.shrink();
    }

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
                  if (isAnswered) {
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
                      value: isAnswered ? 1.0 : progress,
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
