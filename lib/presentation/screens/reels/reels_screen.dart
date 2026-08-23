import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/reels/widgets/reel_player_card.dart';

class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key});

  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  int _currentPage = 0;
  bool _isMuted = false;
  bool _isAppInForeground = true;
  final Map<String, int> _sharesCounts = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isAppInForeground = state == AppLifecycleState.resumed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reelsAsync = ref.watch(reelsListProvider);
    final likedIdsAsync = ref.watch(reelsLikedIdsProvider);
    final savedIdsAsync = ref.watch(reelsSavedIdsProvider);
    final likedIds = likedIdsAsync.valueOrNull ?? <String>{};
    final savedIds = savedIdsAsync.valueOrNull ?? <String>{};

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            reelsAsync.when(
              data: (reels) {
                if (reels.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.video_library_outlined,
                            size: 64,
                            color: Colors.white38,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Видеоразборы скоро появятся',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Мы готовим новые полезные ролики с разборами сложных перекрестков и правил',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white60,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () =>
                                ref.invalidate(reelsListProvider),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Обновить'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: reels.length,
                  onPageChanged: (index) {
                    HapticFeedbackHelper.select();
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final reel = reels[index];
                    final isLiked = likedIds.contains(reel.id);
                    final isSaved = savedIds.contains(reel.id);
                    final sharesCount =
                        _sharesCounts[reel.id] ?? reel.sharesCount;

                    return ReelPlayerCard(
                      reel: reel,
                      isActive: index == _currentPage && _isAppInForeground,
                      isMuted: _isMuted,
                      isLiked: isLiked,
                      isSaved: isSaved,
                      sharesCount: sharesCount,
                      onToggleMute: () {
                        setState(() {
                          _isMuted = !_isMuted;
                        });
                      },
                      onToggleLike: () async {
                        final repo = ref.read(reelsRepositoryProvider);
                        await repo.toggleLike(reel.id);
                        ref.invalidate(reelsLikedIdsProvider);
                      },
                      onToggleSave: () async {
                        final repo = ref.read(reelsRepositoryProvider);
                        await repo.toggleSave(reel.id);
                        ref.invalidate(reelsSavedIdsProvider);
                      },
                      onShare: () async {
                        final repo = ref.read(reelsRepositoryProvider);
                        await repo.shareReel(reel);
                        final newShares = await repo.incrementShares(
                          reel.id,
                          reel.sharesCount,
                        );
                        if (mounted) {
                          setState(() {
                            _sharesCounts[reel.id] = newShares;
                          });
                        }
                      },
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                ),
              ),
              error: (err, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.white38,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Не удалось загрузить видео',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => ref.invalidate(reelsListProvider),
                      icon: const Icon(Icons.refresh, color: AppColors.accent),
                      label: const Text(
                        'Повторить',
                        style: TextStyle(color: AppColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Верхний заголовок над видео
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        appL10n.video,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 6,
                              color: Colors.black87,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white70,
                          size: 22,
                        ),
                        onPressed: () {
                          HapticFeedbackHelper.tap();
                          ref.invalidate(reelsListProvider);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
