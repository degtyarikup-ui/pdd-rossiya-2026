import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PremiumTier {
  weekly,
  threeMonths,
}

class PremiumService extends ChangeNotifier {
  static final PremiumService instance = PremiumService._internal();
  PremiumService._internal();

  static const String _prefKeyIsPremium = 'premium_is_active';
  static const String _prefKeyExpiresAt = 'premium_expires_at';
  static const String _prefKeyDailyCards = 'premium_daily_cards_count';
  static const String _prefKeyDailyDate = 'premium_daily_cards_date';

  String? _currentUserId;

  /// Лимит бесплатных карточек в ленте в день: 5 для гостей, 10 для зарегистрированных
  int get dailyFreeLimit => _currentUserId != null ? 10 : 5;

  /// Лимит бесплатных сообщений/вопросов ИИ: 10 на аккаунт/гостя (не сбрасывается по дням)
  int get aiFreeLimit => 10;

  bool _isPremium = false;
  DateTime? _expiresAt;
  int _dailyCardsCount = 0;
  int _aiMessagesCount = 0;
  bool _isInitialized = false;

  final _premiumGrantedStreamController =
      StreamController<DateTime?>.broadcast();
  Stream<DateTime?> get onPremiumGrantedStream =>
      _premiumGrantedStreamController.stream;

  DateTime? _pendingGrantNotificationExpiresAt;
  DateTime? get pendingGrantNotificationExpiresAt =>
      _pendingGrantNotificationExpiresAt;

  void consumePendingGrantNotification() {
    _pendingGrantNotificationExpiresAt = null;
  }

  bool get isPremium {
    if (_isPremium) {
      if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
        _isPremium = false;
        _expiresAt = null;
        _saveState();
      }
    }
    return _isPremium;
  }

  DateTime? get expiresAt => _expiresAt;
  int get dailyCardsCount => _dailyCardsCount;
  int get remainingFreeCards =>
      isPremium ? 999999 : math.max(0, dailyFreeLimit - _dailyCardsCount);
  bool get canAccessFeed => isPremium || remainingFreeCards > 0;

  int get aiMessagesCount => _aiMessagesCount;
  int get remainingAiMessages =>
      isPremium ? 999999 : math.max(0, aiFreeLimit - _aiMessagesCount);
  bool get canSendAiMessage => isPremium || remainingAiMessages > 0;

  String _getDailyCardsKey([String? userId]) {
    final uid =
        userId ?? _currentUserId ?? AuthService.instance.currentUser?.id ?? 'guest';
    return 'premium_daily_cards_$uid';
  }

  String _getDailyDateKey([String? userId]) {
    final uid =
        userId ?? _currentUserId ?? AuthService.instance.currentUser?.id ?? 'guest';
    return 'premium_daily_date_$uid';
  }

  String _getAiMessagesKey([String? userId]) {
    final uid =
        userId ?? _currentUserId ?? AuthService.instance.currentUser?.id ?? 'guest';
    return 'premium_ai_messages_$uid';
  }

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isPremium = prefs.getBool(_prefKeyIsPremium) ?? false;
      final expMs = prefs.getInt(_prefKeyExpiresAt);
      if (expMs != null) {
        _expiresAt = DateTime.fromMillisecondsSinceEpoch(expMs);
      }

      _currentUserId = AuthService.instance.currentUser?.id;

      // Check daily reset for current user / guest
      final todayStr = _getTodayString();
      final dateKey = _getDailyDateKey();
      final cardsKey = _getDailyCardsKey();
      final lastDate =
          prefs.getString(dateKey) ?? prefs.getString(_prefKeyDailyDate);

      if (lastDate != todayStr) {
        _dailyCardsCount = 0;
        await prefs.setString(dateKey, todayStr);
        await prefs.setInt(cardsKey, 0);
      } else {
        _dailyCardsCount =
            prefs.getInt(cardsKey) ?? prefs.getInt(_prefKeyDailyCards) ?? 0;
      }

      // Load lifetime AI messages count for current user / guest
      _aiMessagesCount = prefs.getInt(_getAiMessagesKey()) ?? 0;

      _isInitialized = true;
      notifyListeners();

      // Sync with server in background if user is authenticated
      unawaited(syncWithServer());
    } catch (e) {
      debugPrint('PremiumService: init error: $e');
    }
  }

  /// Вызывается при авторизации, выходе или смене аккаунта,
  /// чтобы загрузить индивидуальный счетчик карточек, лимит ИИ и статус Premium.
  Future<void> onAuthChanged([UserProfile? user]) async {
    try {
      _currentUserId = user?.id;

      final prefs = await SharedPreferences.getInstance();
      final todayStr = _getTodayString();
      final uid = _currentUserId ?? 'guest';
      final dateKey = _getDailyDateKey(uid);
      final cardsKey = _getDailyCardsKey(uid);

      final lastDate = prefs.getString(dateKey);
      if (lastDate != todayStr) {
        _dailyCardsCount = 0;
        await prefs.setString(dateKey, todayStr);
        await prefs.setInt(cardsKey, 0);
      } else {
        _dailyCardsCount = prefs.getInt(cardsKey) ?? 0;
      }

      // Load AI messages count for this account / guest
      _aiMessagesCount = prefs.getInt(_getAiMessagesKey(uid)) ?? 0;

      if (user != null) {
        // Синхронизируем статус подписки аккаунта с сервером
        await syncWithServer();
      } else {
        // При выходе из аккаунта — сбрасываем премиум-состояние.
        // Гостевой режим не наследует подписку предыдущего пользователя.
        _isPremium = false;
        _expiresAt = null;
        await _saveState();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('PremiumService: onAuthChanged error: $e');
    }
  }

  static const String _syncEndpoint =
      '${BackendConfig.notifierUrl}/api/user/sync';

  Future<void> syncWithServer() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    if (!BackendConfig.hasNotifier) return;

    try {
      String appVersion = '';
      String platform = '';
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = '${info.version}+${info.buildNumber}';
        if (kIsWeb) {
          platform = 'web';
        } else if (Platform.isIOS) {
          platform = 'ios';
        } else if (Platform.isAndroid) {
          platform = 'android';
        }
      } catch (_) {}

      final payload = {
        'id': user.id,
        'email': user.email,
        'name': user.name,
        'avatarUrl': user.avatarUrl,
        'provider': user.provider.name,
        'country': CountryConfig.current.code,
        'app': 'ru',
        'isPremium': isPremium,
        'premiumExpiresAt': _expiresAt?.toIso8601String(),
        'createdAt': user.createdAt.toIso8601String(),
        if (platform.isNotEmpty) 'platform': platform,
        if (appVersion.isNotEmpty) 'appVersion': appVersion,
      };

      final resp = await http
          .post(
            Uri.parse(_syncEndpoint),
            headers: {
              'content-type': 'application/json',
              if (BackendConfig.notifierSecret.isNotEmpty)
                'x-install-secret': BackendConfig.notifierSecret,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final serverIsPremium = data['isPremium'] == true;
        final serverExpStr = data['premiumExpiresAt'] as String?;
        final serverExpiresAt =
            serverExpStr != null ? DateTime.tryParse(serverExpStr) : null;
        final serverGrantedAtStr = data['grantedAt'] as String?;
        final serverGrantedAt =
            serverGrantedAtStr != null ? DateTime.tryParse(serverGrantedAtStr) : null;

        // Проверка новой выдачи Premium для показа праздничного диалога
        if (serverIsPremium && serverGrantedAt != null) {
          final prefs = await SharedPreferences.getInstance();
          final grantKey = 'premium_last_seen_grant_${user.id}';
          final lastSeenStr = prefs.getString(grantKey);
          final lastSeen =
              lastSeenStr != null ? DateTime.tryParse(lastSeenStr) : null;

          if (lastSeen == null || serverGrantedAt.isAfter(lastSeen)) {
            await prefs.setString(grantKey, serverGrantedAt.toIso8601String());
            _pendingGrantNotificationExpiresAt = serverExpiresAt;
            _premiumGrantedStreamController.add(serverExpiresAt);
          }
        }

        // Сервер — единый источник правды для состояния подписки аккаунта
        _isPremium = serverIsPremium;
        _expiresAt = serverIsPremium ? serverExpiresAt : null;
        await _saveState();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('PremiumService: syncWithServer error: $e');
    }
  }

  String _getTodayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> recordCardCompleted() async {
    if (isPremium) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = _getTodayString();
      final cardsKey = _getDailyCardsKey();
      final dateKey = _getDailyDateKey();
      final lastDate = prefs.getString(dateKey);

      if (lastDate != todayStr) {
        _dailyCardsCount = 1;
        await prefs.setString(dateKey, todayStr);
      } else {
        _dailyCardsCount++;
      }
      await prefs.setInt(cardsKey, _dailyCardsCount);
      notifyListeners();
    } catch (e) {
      debugPrint('PremiumService: recordCardCompleted error: $e');
    }
  }

  Future<void> recordAiMessageSent() async {
    if (isPremium) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getAiMessagesKey();
      _aiMessagesCount++;
      await prefs.setInt(key, _aiMessagesCount);
      notifyListeners();
    } catch (e) {
      debugPrint('PremiumService: recordAiMessageSent error: $e');
    }
  }

  Future<bool> purchase(PremiumTier tier) async {
    return recordPurchase(
      tier: tier,
      price: tier == PremiumTier.threeMonths ? '290 ₽' : '99 ₽',
    );
  }

  Future<bool> recordPurchase({
    required PremiumTier tier,
    required String price,
    String? store,
    String? transactionId,
    String? productId,
  }) async {
    try {
      final now = DateTime.now();
      DateTime expiration;
      switch (tier) {
        case PremiumTier.weekly:
          expiration = now.add(const Duration(days: 7));
          break;
        case PremiumTier.threeMonths:
          expiration = now.add(const Duration(days: 90));
          break;
      }

      _isPremium = true;
      _expiresAt = expiration;
      await _saveState();
      notifyListeners();

      // Notify server about purchase
      if (BackendConfig.hasNotifier) {
        final user = AuthService.instance.currentUser;
        String appVersion = '';
        String platform = '';
        try {
          final info = await PackageInfo.fromPlatform();
          appVersion = '${info.version}+${info.buildNumber}';
          if (kIsWeb) {
            platform = 'web';
          } else if (Platform.isIOS) {
            platform = 'ios';
          } else if (Platform.isAndroid) {
            platform = 'android';
          }
        } catch (_) {}

        final payload = {
          'userId': user?.id ?? _currentUserId ?? 'guest',
          'name': user?.name ?? 'Пользователь',
          'email': user?.email,
          'provider': user?.provider.name ?? 'guest',
          'tier': tier.name,
          'tierName': tier == PremiumTier.threeMonths ? '3 месяца' : '1 неделя',
          'price': price,
          'store': store ?? (kIsWeb ? 'web' : Platform.isIOS ? 'appstore' : 'rustore'),
          'expiresAt': expiration.toIso8601String(),
          'country': CountryConfig.current.code,
          'app': 'ru',
          if (platform.isNotEmpty) 'platform': platform,
          if (appVersion.isNotEmpty) 'appVersion': appVersion,
          if (transactionId != null) 'transactionId': transactionId,
          if (productId != null) 'productId': productId,
        };

        try {
          await http
              .post(
                Uri.parse('${BackendConfig.notifierUrl}/api/user/purchase'),
                headers: {
                  'content-type': 'application/json',
                  if (BackendConfig.notifierSecret.isNotEmpty)
                    'x-install-secret': BackendConfig.notifierSecret,
                },
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 10));
        } catch (e) {
          debugPrint('PremiumService: recordPurchase server error: $e');
        }
      }

      unawaited(syncWithServer());
      return true;
    } catch (e) {
      debugPrint('PremiumService: recordPurchase error: $e');
      return false;
    }
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyIsPremium, _isPremium);
      if (_expiresAt != null) {
        await prefs.setInt(
            _prefKeyExpiresAt, _expiresAt!.millisecondsSinceEpoch);
      } else {
        await prefs.remove(_prefKeyExpiresAt);
      }
    } catch (e) {
      debugPrint('PremiumService: save error: $e');
    }
  }
}
