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
  final ValueChanged<String>? onFailed;

  const AdFeedCard({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.onAutoNext,
    required this.onPrevious,
    this.onFailed,
  });

  @override
  ConsumerState<AdFeedCard> createState() => _AdFeedCardState();
}

class _AdFeedCardState extends ConsumerState<AdFeedCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScrollController _scrollController = ScrollController();

  BannerAd? _yandexBanner;
  bool _isYandexLoaded = false;
  bool _isYandexError = false;
  int _calculatedWidth = 340;

  @override
  void initState() {
    super.initState();
    if (widget.item.preloadedBanner != null &&
        widget.item.preloadedBanner is BannerAd) {
      _yandexBanner = widget.item.preloadedBanner as BannerAd;
      _isYandexLoaded = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final screenW = MediaQuery.sizeOf(context).width;
    final w = (screenW - (AppDimensions.screenPadding * 2)).toInt().clamp(300, 500);
    _calculatedWidth = w;
    if (_yandexBanner == null) {
      _initYandexAdIfNeeded();
    }
  }

  void _initYandexAdIfNeeded() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (_yandexBanner != null) return;

    final adsRepo = ref.read(adsRepositoryProvider);
    final config = adsRepo.currentConfig;
    final adUnitId = config.yandexAdUnitId.isNotEmpty
        ? config.yandexAdUnitId
        : 'R-M-19816566-1';

    if (config.mode == 'yandex' && adUnitId.isNotEmpty) {
      try {
        final banner = BannerAd(
          adSize: BannerAdSize.inline(width: _calculatedWidth, maxHeight: 360),
        );

        banner.loadStateStream.listen((state) {
          if (!mounted) return;
          if (state is BannerAdLoadStateLoaded) {
            debugPrint('AdFeedCard: Yandex Banner loaded successfully (${state.width}x${state.height})');
            setState(() {
              _isYandexLoaded = true;
              _isYandexError = false;
            });
          } else if (state is BannerAdLoadStateError) {
            debugPrint('AdFeedCard: Yandex Banner load error: ${state.error.description} (code: ${state.error.code})');
            setState(() {
              _isYandexError = true;
            });
            if (widget.item.adPromo == null) {
              widget.onFailed?.call(widget.item.id);
            }
          }
        });

        banner.load(
          AdRequest(
            adUnitId: adUnitId,
            targeting: const AdTargeting(
              contextQuery: 'ПДД билеты автошкола вождение',
              contextTags: [
                'авто',
                'пдд',
                'автошкола',
                'осаго',
                'автострахование',
                'вождение',
                'гибдд',
                'автомобили',
              ],
            ),
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

    return NotificationListener<ScrollNotification>(
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
          top: 14,
          bottom: 84,
        ),
        child: (_yandexBanner != null && !_isYandexError)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: AdWidget(bannerAd: _yandexBanner!),
                        ),
                        if (!_isYandexLoaded)
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(minHeight: 180),
                            padding: const EdgeInsets.symmetric(
                              vertical: 48,
                              horizontal: 24,
                            ),
                            decoration: BoxDecoration(
                              color: colors.cardBackground,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
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
                                  'Загрузка рекламы Яндекс...',
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
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              )
            : (widget.item.adPromo != null)
                ? Column(
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
                          ),
                          child: Icon(
                            iconData,
                            size: 52,
                            color: colors.accent,
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Custom Promo Card Container
                      Container(
                        padding: const EdgeInsets.all(AppDimensions.spacingXL),
                        decoration: BoxDecoration(
                          color: colors.cardBackground,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.cardRadius,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.adPromo!.title,
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
                              widget.item.adPromo!.description,
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
                                onPressed: () {
                                  if (widget.item.adPromo!.buttonUrl.isNotEmpty) {
                                    _handleCtaTap(widget.item.adPromo!.buttonUrl);
                                  } else {
                                    HapticFeedbackHelper.tap();
                                    widget.onAutoNext();
                                  }
                                },
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
                                      widget.item.adPromo!.buttonText,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      widget.item.adPromo!.buttonUrl.isNotEmpty
                                          ? Icons.open_in_new_rounded
                                          : Icons.arrow_forward_rounded,
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
                  )
                : const SizedBox.shrink(),
      ),
    );
  }
}
