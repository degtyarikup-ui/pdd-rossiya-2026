import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:yandex_mobileads/mobile_ads.dart';

/// Preloads and validates Yandex Banner Ads ahead of time in the background.
/// Ensures that unverified/empty/failed ad blocks are NEVER inserted into the feed.
class YandexAdPreloader {
  static final YandexAdPreloader instance = YandexAdPreloader._();
  YandexAdPreloader._();

  BannerAd? _readyBanner;
  bool _isLoading = false;
  DateTime? _lastErrorTime;
  String _currentAdUnitId = '';

  BannerAd? get readyBanner => _readyBanner;
  bool get hasReadyAd => _readyBanner != null;

  /// Consumes and returns the preloaded banner, transferring ownership to the UI card.
  /// Automatically triggers preloading of the next banner in the background.
  BannerAd? consumeReadyBanner() {
    final banner = _readyBanner;
    _readyBanner = null;
    if (_currentAdUnitId.isNotEmpty) {
      preloadNext(_currentAdUnitId).ignore();
    }
    return banner;
  }

  /// Starts loading a banner in the background if one is not already ready or loading.
  Future<void> preloadNext(String adUnitId, {int width = 340}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (adUnitId.isEmpty) return;
    if (_readyBanner != null || _isLoading) return;

    // Rate-limit retries if error occurred recently (backoff 20 seconds)
    if (_lastErrorTime != null &&
        DateTime.now().difference(_lastErrorTime!).inSeconds < 20) {
      return;
    }

    _currentAdUnitId = adUnitId;
    _isLoading = true;

    try {
      final banner = BannerAd(
        adSize: BannerAdSize.inline(width: width, maxHeight: 360),
      );

      StreamSubscription? sub;
      sub = banner.loadStateStream.listen((state) {
        if (state is BannerAdLoadStateLoaded) {
          debugPrint('YandexAdPreloader: Banner ad PRELOADED successfully (${state.width}x${state.height})');
          _readyBanner = banner;
          _isLoading = false;
          _lastErrorTime = null;
          sub?.cancel();
        } else if (state is BannerAdLoadStateError) {
          debugPrint('YandexAdPreloader: Preload error: ${state.error.description} (code: ${state.error.code})');
          _readyBanner = null;
          _isLoading = false;
          _lastErrorTime = DateTime.now();
          sub?.cancel();
        }
      });

      await banner.load(
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
      );
    } catch (e) {
      debugPrint('YandexAdPreloader: exception during preload: $e');
      _isLoading = false;
      _lastErrorTime = DateTime.now();
    }
  }
}
