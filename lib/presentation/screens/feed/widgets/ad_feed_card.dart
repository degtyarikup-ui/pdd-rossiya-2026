import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/ad_promo_item.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yandex_mobileads/mobile_ads.dart';

class AdFeedCard extends ConsumerStatefulWidget {
  final FeedItem item;
  final bool isCurrent;
  final VoidCallback onAutoNext;
  final VoidCallback onPrevious;

  const AdFeedCard({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.onAutoNext,
    required this.onPrevious,
  });

  @override
  ConsumerState<AdFeedCard> createState() => _AdFeedCardState();
}

class _AdFeedCardState extends ConsumerState<AdFeedCard>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  final ScrollController _scrollController = ScrollController();

  BannerAd? _yandexBanner;
  bool _isYandexLoaded = false;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: 0.0, end: -7.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    _initYandexAdIfNeeded();
  }

  void _initYandexAdIfNeeded() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    final adsRepo = ref.read(adsRepositoryProvider);
    final config = adsRepo.currentConfig;
    final adUnitId = config.yandexAdUnitId.isNotEmpty
        ? config.yandexAdUnitId
        : 'R-M-19816566-1';

    if (config.mode == 'yandex' && adUnitId.isNotEmpty) {
      try {
        final banner = BannerAd(
          adSize: const BannerAdSize.inline(width: 320, maxHeight: 300),
        );

        banner.loadStateStream.listen((state) {
          if (!mounted) return;
          if (state is BannerAdLoadStateLoaded) {
            setState(() {
              _isYandexLoaded = true;
            });
          }
        });

        banner.load(
          AdRequest(
            adUnitId: adUnitId,
          ),
        ).ignore();

        _yandexBanner = banner;
      } catch (e) {
        debugPrint('AdFeedCard: Yandex Ad init error: $e');
      }
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _scrollController.dispose();
    _yandexBanner?.destroy();
    super.dispose();
  }

  Future<void> _handleCtaTap(String url) async {
    HapticFeedbackHelper.tap();
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('AdFeedCard: could not launch url: $url ($e)');
      }
    }
  }

  IconData _resolveIcon(String iconKey) {
    switch (iconKey.toLowerCase()) {
      case 'car':
        return Icons.directions_car_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'gift':
        return Icons.card_giftcard_rounded;
      case 'tag':
        return Icons.local_offer_rounded;
      case 'shield':
      default:
        return Icons.verified_user_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AppColors.of(context);
    final promo = widget.item.adPromo ??
        const AdPromoItem(
          id: 'promo_default',
          badge: 'ПРОМО',
          title: 'Сравните цены на ОСАГО в 18 страховых',
          description:
              'Экономия до 3 500 ₽ при первом оформлении. Рассчитайте стоимость онлайн без визита в офис.',
          buttonText: 'Рассчитать полис →',
          buttonUrl: 'https://sravni.ru/osago/?utm_source=pdd_app',
          themeColor: 'blue',
          icon: 'shield',
        );

    final iconData = _resolveIcon(promo.icon);

    return Container(
      color: colors.homeScreenBackground,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // Top Bar with Badge
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.screenPadding,
                    vertical: AppDimensions.spacingM,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.lightAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _isYandexLoaded ? 'РЕКЛАМА' : (promo.badge.isNotEmpty ? promo.badge : 'ПРОМО'),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
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
                              _isYandexLoaded ? 'Яндекс Директ' : 'Партнёр',
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
                  ),
                ),

                // Main Promo / Yandex Body
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is OverscrollNotification) {
                        if (notification.overscroll > 10 && widget.isCurrent) {
                          widget.onAutoNext();
                          return true;
                        }
                        if (notification.overscroll < -10 && widget.isCurrent) {
                          widget.onPrevious();
                          return true;
                        }
                      } else if (notification is ScrollUpdateNotification) {
                        if (_scrollController.hasClients &&
                            _scrollController.position.pixels >=
                                _scrollController.position.maxScrollExtent &&
                            notification.scrollDelta != null &&
                            notification.scrollDelta! > 14 &&
                            widget.isCurrent) {
                          widget.onAutoNext();
                          return true;
                        }
                        if (_scrollController.hasClients &&
                            _scrollController.position.pixels <=
                                _scrollController.position.minScrollExtent &&
                            notification.scrollDelta != null &&
                            notification.scrollDelta! < -14 &&
                            widget.isCurrent) {
                          widget.onPrevious();
                          return true;
                        }
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.only(
                        left: AppDimensions.screenPadding,
                        right: AppDimensions.screenPadding,
                        bottom: 84,
                      ),
                      child: _isYandexLoaded && _yandexBanner != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: colors.cardBackground,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colors.black.withValues(alpha: 0.04),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: AdWidget(bannerAd: _yandexBanner!),
                                  ),
                                ),
                                const SizedBox(height: 32),
                              ],
                            )
                          : (widget.item.adPromo == null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(height: 48),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                                      decoration: BoxDecoration(
                                        color: colors.cardBackground,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: colors.black.withValues(alpha: 0.04),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: colors.accent,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Загрузка рекламы...',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: colors.secondaryText,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 16),

                                // Large Hero Icon Graphic
                                Center(
                                  child: Container(
                                    width: 100,
                                    height: 100,
                                    decoration: BoxDecoration(
                                      color: colors.lightAccent,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: colors.accent.withValues(alpha: 0.15),
                                          blurRadius: 24,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      iconData,
                                      size: 52,
                                      color: colors.accent,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 28),

                                // Promo Card Container
                                Container(
                                  padding: const EdgeInsets.all(AppDimensions.spacingXL),
                                  decoration: BoxDecoration(
                                    color: colors.cardBackground,
                                    borderRadius: BorderRadius.circular(
                                      AppDimensions.cardRadius,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colors.black.withValues(alpha: 0.04),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        promo.title,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: colors.primaryText,
                                          height: 1.3,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        promo.description,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: colors.secondaryText,
                                          height: 1.45,
                                        ),
                                      ),
                                      const SizedBox(height: 24),

                                      // Action Button
                                      SizedBox(
                                        width: double.infinity,
                                        height: 52,
                                        child: ElevatedButton(
                                          onPressed: () => _handleCtaTap(promo.buttonUrl),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: colors.accent,
                                            foregroundColor: AppColors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                promo.buttonText,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Icon(
                                                Icons.open_in_new_rounded,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 32),
                              ],
                            )),
                    ),
                  ),
                ),
              ],
            ),

            // Fixed Bottom Floating "Свайпай ↑" Pill
            Positioned(
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
                        widget.onAutoNext();
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
            ),
          ],
        ),
      ),
    );
  }
}
