import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/presentation/screens/feed/widgets/feed_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen>
    with WidgetsBindingObserver {
  static const String _prefKeyFeedSound = 'feed_sound_enabled';

  late PageController _pageController;
  int _currentIndex = 0;
  bool _isSoundEnabled = true;
  final List<FeedItem> _items = [];
  final Map<String, int> _answeredChoices = {};
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _loadSoundPreference();
  }

  Future<void> _loadSoundPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_prefKeyFeedSound);
      if (saved != null && mounted) {
        setState(() => _isSoundEnabled = saved);
      }
    } catch (_) {}
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
    super.dispose();
  }

  void _onPageChanged(int index) {
    HapticFeedbackHelper.select();
    setState(() => _currentIndex = index);

    // Auto-load more items when near end of list
    if (index >= _items.length - 4 && !_isLoadingMore) {
      _loadMoreItems();
    }
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

  void _autoNext() {
    if (_currentIndex < _items.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.fastOutSlowIn,
      );
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

    return Scaffold(
      backgroundColor: colors.homeScreenBackground,
      body: initialAsync.when(
        data: (initialItems) {
          if (_items.isEmpty && initialItems.isNotEmpty) {
            _items.addAll(initialItems);
          }

          if (_items.isEmpty) {
            return Center(
              child: Text(
                'Вопросы пока не загружены',
                style: TextStyle(color: colors.secondaryText),
              ),
            );
          }

          return PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            physics: const BouncingScrollPhysics(),
            onPageChanged: _onPageChanged,
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
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
              );
            },
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
}
