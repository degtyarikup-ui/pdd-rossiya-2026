import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/data/models/ad_promo_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdsRepository {
  static const String _apiEndpoint =
      'https://pdd-install-notifier.sergei-pdd.workers.dev/api/ads/config';
  static const String _cacheKey = 'pdd_cached_ads_config';

  AdPromoConfig _currentConfig = AdPromoConfig.defaultFallback;
  int _cardRotationIndex = 0;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  AdPromoConfig get currentConfig => _currentConfig;

  Future<void> init() async {
    await _loadFromLocalCache();
    // Fire and forget or background refresh from remote
    fetchRemoteConfig().ignore();
  }

  Future<void> _loadFromLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
        _currentConfig = AdPromoConfig.fromJson(jsonMap);
        _isLoaded = true;
      }
    } catch (e) {
      debugPrint('AdsRepository: cache load error: $e');
    }
  }

  Future<AdPromoConfig> fetchRemoteConfig({String? storeOverride}) async {
    try {
      String platform = 'android';
      String store = 'rustore';

      if (kIsWeb) {
        platform = 'web';
        store = 'web';
      } else if (Platform.isIOS) {
        platform = 'ios';
        store = 'appstore';
      } else if (Platform.isAndroid) {
        platform = 'android';
        store = storeOverride ?? 'rustore';
      }

      final url = Uri.parse('$_apiEndpoint?platform=$platform&store=$store');
      final res = await http.get(url).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final jsonMap = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final newConfig = AdPromoConfig.fromJson(jsonMap);
        _currentConfig = newConfig;
        _isLoaded = true;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, res.body);
        return newConfig;
      }
    } catch (e) {
      debugPrint('AdsRepository: remote fetch failed ($e), using cached/fallback');
    }
    return _currentConfig;
  }

  AdPromoItem? getNextPromoCard() {
    if (!_currentConfig.isEnabled || _currentConfig.cards.isEmpty) {
      return null;
    }
    final activeCards = _currentConfig.cards.where((c) => c.isEnabled).toList();
    if (activeCards.isEmpty) return null;

    final card = activeCards[_cardRotationIndex % activeCards.length];
    _cardRotationIndex++;
    return card;
  }
}
