import 'package:pdd_app/data/services/device_region.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/services/payment_mode.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
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
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/data/services/pending_payment.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PremiumTier { weekly, threeMonths }

enum PurchaseVerificationFailure { unavailable, rejected, inactive }

class PremiumService extends ChangeNotifier {
  static final PremiumService instance = PremiumService._internal();
  PremiumService._internal();

  static const String _prefKeyIsPremium = 'premium_is_active';
  static const String _prefKeyOwner = 'premium_owner_id';
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
  String? _purchaseStore;
  String? get purchaseStore => _purchaseStore;
  int _dailyCardsCount = 0;
  int _aiMessagesCount = 0;
  bool _isInitialized = false;
  int _entitlementRevision = 0;
  PurchaseVerificationFailure? _purchaseVerificationFailure;
  PurchaseVerificationFailure? get purchaseVerificationFailure =>
      _purchaseVerificationFailure;

  final _premiumGrantedStreamController =
      StreamController<DateTime?>.broadcast();
  Stream<DateTime?> get onPremiumGrantedStream =>
      _premiumGrantedStreamController.stream;

  DateTime? _pendingGrantNotificationExpiresAt;
  bool _pendingGrant = false;
  DateTime? get pendingGrantNotificationExpiresAt =>
      _pendingGrantNotificationExpiresAt;

  /// A grant the user has not seen yet (also for lifetime Premium, which has
  /// no expiry date).
  bool get hasPendingGrant => _pendingGrant;

  /// The admin's text for the last grant notice («за победу в конкурсе»).
  String? _grantMessage;
  String? get grantMessage => _grantMessage;

  void consumePendingGrantNotification() {
    _pendingGrantNotificationExpiresAt = null;
    _pendingGrant = false;
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
        userId ??
        _currentUserId ??
        AuthService.instance.currentUser?.id ??
        'guest';
    return 'premium_daily_cards_$uid';
  }

  String _getDailyDateKey([String? userId]) {
    final uid =
        userId ??
        _currentUserId ??
        AuthService.instance.currentUser?.id ??
        'guest';
    return 'premium_daily_date_$uid';
  }

  String _getAiMessagesKey([String? userId]) {
    final uid =
        userId ??
        _currentUserId ??
        AuthService.instance.currentUser?.id ??
        'guest';
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

      _currentUserId = prefs.getString(_prefKeyOwner);
      _purchaseStore = prefs.getString('premium_purchase_store');

      // Check daily reset for current user / guest
      final todayStr = _getTodayString();
      final dateKey = _getDailyDateKey();
      final cardsKey = _getDailyCardsKey();
      final lastDate =
          prefs.getString(dateKey) ?? prefs.getString(_prefKeyDailyDate);

      if (lastDate != todayStr) {
        _dailyCardsCount = 0;
        unawaited(prefs.setString(dateKey, todayStr));
        unawaited(prefs.setInt(cardsKey, 0));
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
  Future<void> onAuthChanged(
    UserProfile? user, {
    bool waitForSync = true,
  }) async {
    try {
      final changedAccount = _currentUserId != user?.id;
      _currentUserId = user?.id;
      if (changedAccount) {
        _purchaseStore = null;
        _isPremium = false;
        _expiresAt = null;
        _pendingGrantNotificationExpiresAt = null;
        await _saveState();
      }

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
        if (waitForSync) {
          await syncWithServer();
        } else {
          // Restoring a valid local session must not wait for the network.
          unawaited(syncWithServer());
        }
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
    if (user == null || !AuthService.instance.hasServerSession) return;
    if (!BackendConfig.hasNotifier) return;
    final revision = AuthService.instance.accountRevision;
    final entitlementRevision = _entitlementRevision;

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
        ...await InstallReporter.clientMetadata(),
        'id': user.id,
        'email': user.email,
        'name': user.name,
        'avatarUrl': user.avatarUrl,
        'provider': user.provider.name,
        'country': CountryConfig.current.code,
        'app': CountryConfig.current.code,
        'isPremium': isPremium,
        'premiumExpiresAt': _expiresAt?.toIso8601String(),
        'createdAt': user.createdAt.toIso8601String(),
        if (platform.isNotEmpty) 'platform': platform,
        if (appVersion.isNotEmpty) 'appVersion': appVersion,
      };

      final resp = await http
          .post(
            Uri.parse(_syncEndpoint),
            headers: AuthService.instance.serverHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 &&
          revision == AuthService.instance.accountRevision &&
          entitlementRevision == _entitlementRevision) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final serverIsPremium = data['isPremium'] == true;
        final serverExpStr = data['premiumExpiresAt'] as String?;
        final serverExpiresAt = serverExpStr != null
            ? DateTime.tryParse(serverExpStr)
            : null;
        await _handleGrantNotice(
          data,
          user.id,
          serverIsPremium,
          serverExpiresAt,
        );
        if (revision != AuthService.instance.accountRevision ||
            entitlementRevision != _entitlementRevision) {
          return;
        }

        // Сервер — единый источник правды для состояния подписки аккаунта
        _purchaseStore = data['premiumSource'] as String?;
        _isPremium = serverIsPremium;
        _expiresAt = serverIsPremium ? serverExpiresAt : null;
        await _saveState();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('PremiumService: syncWithServer error: $e');
    }
  }

  /// A new «Premium granted» notice from the admin panel: shown once, with
  /// the admin's reason as its text. Silent grants carry no new notice.
  Future<void> _handleGrantNotice(
    Map<String, dynamic> data,
    String userId,
    bool serverIsPremium,
    DateTime? serverExpiresAt,
  ) async {
    final notice = data['grantNotice'];
    if (!serverIsPremium || notice is! Map) return;
    final at = DateTime.tryParse(notice['at'] as String? ?? '');
    if (at == null) return;
    final prefs = await SharedPreferences.getInstance();
    final grantKey = 'premium_last_seen_grant_$userId';
    final lastSeen = DateTime.tryParse(prefs.getString(grantKey) ?? '');
    if (lastSeen != null && !at.isAfter(lastSeen)) return;
    await prefs.setString(grantKey, at.toIso8601String());
    final message = (notice['message'] as String? ?? '').trim();
    _grantMessage = message.isEmpty ? null : message;
    _pendingGrantNotificationExpiresAt = serverExpiresAt;
    _pendingGrant = true;
    _premiumGrantedStreamController.add(serverExpiresAt);
  }

  static const String _statusEndpoint =
      '${BackendConfig.notifierUrl}/api/user/status';

  /// Picks up administrative grants and store renewals while the app is open.
  Future<void> checkForGrant() async {
    final user = AuthService.instance.currentUser;
    if (user == null || !AuthService.instance.hasServerSession) return;
    if (!BackendConfig.hasNotifier) return;
    final revision = AuthService.instance.accountRevision;
    final entitlementRevision = _entitlementRevision;
    try {
      final resp = await http
          .get(
            Uri.parse(_statusEndpoint),
            headers: AuthService.instance.serverHeaders,
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200 ||
          revision != AuthService.instance.accountRevision ||
          entitlementRevision != _entitlementRevision) {
        return;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final serverIsPremium = data['isPremium'] == true;
      final serverExpiresAt = DateTime.tryParse(
        data['premiumExpiresAt'] as String? ?? '',
      );
      await _handleGrantNotice(data, user.id, serverIsPremium, serverExpiresAt);
      if (revision != AuthService.instance.accountRevision ||
          entitlementRevision != _entitlementRevision) {
        return;
      }
      if (serverIsPremium != _isPremium ||
          serverExpiresAt != _expiresAt ||
          data['premiumSource'] != _purchaseStore) {
        _purchaseStore = data['premiumSource'] as String?;
        _isPremium = serverIsPremium;
        _expiresAt = serverIsPremium ? serverExpiresAt : null;
        await _saveState();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('PremiumService: checkForGrant error: $e');
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

  /// Both purchases and restores use the store's verified expiry. Replaying a
  /// receipt never starts a new local 7/90-day period.
  Future<bool> recordPurchase({
    required PremiumTier tier,
    required String price,
    required String store,
    required String productId,
    required String purchaseToken,
    String? transactionId,
  }) async {
    _purchaseVerificationFailure = PurchaseVerificationFailure.unavailable;
    final auth = AuthService.instance;
    final user = auth.currentUser;
    if (user == null || !auth.hasServerSession || !BackendConfig.hasNotifier) {
      return false;
    }
    final revision = auth.accountRevision;
    try {
      final response = await http
          .post(
            Uri.parse('${BackendConfig.notifierUrl}/api/user/purchase'),
            headers: auth.serverHeaders,
            body: jsonEncode({
              'userId': user.id,
              'tier': tier.name,
              'price': price,
              'store': store,
              'productId': productId,
              'purchaseToken': purchaseToken,
              'transactionId': ?transactionId,
              'country': CountryConfig.current.code,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        if ([400, 403, 422].contains(response.statusCode)) {
          _purchaseVerificationFailure = PurchaseVerificationFailure.rejected;
        }
        return false;
      }
      if (revision != auth.accountRevision) {
        return false;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final expiry = DateTime.tryParse(
        data['premiumExpiresAt'] as String? ?? '',
      );
      if (data['ok'] != true ||
          data['isPremium'] != true ||
          expiry == null ||
          !expiry.isAfter(DateTime.now())) {
        if (data['ok'] == true && data['isPremium'] == false) {
          _purchaseVerificationFailure = PurchaseVerificationFailure.inactive;
        } else {
          ErrorReporter.report(
            ErrorCategory.purchase,
            'premium.verify',
            code: 'invalid_response',
            provider: store,
          );
        }
        return false;
      }
      _isPremium = true;
      _purchaseStore = data['premiumSource'] as String? ?? store;
      _expiresAt = expiry;
      _entitlementRevision++;
      _purchaseVerificationFailure = null;
      await _saveState();
      notifyListeners();
      return true;
    } catch (error) {
      ErrorReporter.report(
        ErrorCategory.purchase,
        'premium.verify',
        error: error,
        provider: store,
      );
      return false;
    }
  }

  /// Включена ли оплата на сайте (у воркера есть ключи платёжки). Пока нет —
  /// веб-пейвол показывает заглушку «СБП скоро» и только собирает почту.
  Future<bool> webPaymentsAvailable() async {
    if (!BackendConfig.hasNotifier) return false;
    try {
      final response = await http
          .get(Uri.parse('${BackendConfig.notifierUrl}/api/pay/status'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['available'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Оплата на сайте: сервер записывает выбор (аккаунт, тариф, почта для
  /// чека) и, если платёжка подключена, создаёт платёж. null — ошибка;
  /// `url == null` — платёжка ещё не подключена (заглушка). Премиум этим
  /// не выдаётся: только после подтверждения оплаты платёжным сервисом.
  Future<({String? url, String? order})?> startWebPayment({
    required PremiumTier tier,
    required String email,
    String method = 'sbp',
  }) async {
    if (!kIsWeb) {
      if (defaultTargetPlatform != TargetPlatform.android) return null;
      final store = StoreConfig.current;
      final country = store == AppStore.rustore
          ? null
          : await DeviceRegion.countryCode();
      if (androidPaymentMode(store: store, deviceCountry: country) !=
          PaymentMode.sbp) {
        return null;
      }
    }
    final auth = AuthService.instance;
    if (!auth.hasServerSession || !BackendConfig.hasNotifier) return null;
    try {
      final response = await http
          .post(
            Uri.parse('${BackendConfig.notifierUrl}/api/user/pay-intent'),
            headers: auth.serverHeaders,
            body: jsonEncode({
              'tier': tier.name,
              'email': email.trim(),
              'method': method,
              'app': CountryConfig.current.code,
              // Android возвращает человека в приложение, а не на сайт.
              'client': kIsWeb ? 'web' : 'android',
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final url = data['available'] == true ? data['url'] as String? : null;
      if (url != null && !url.startsWith('https://')) {
        ErrorReporter.report(
          ErrorCategory.purchase,
          'web_payment.start',
          code: 'invalid_response',
          provider: 'platega',
        );
        return null;
      }
      return (url: url, order: data['order'] as String?);
    } catch (error) {
      ErrorReporter.report(
        ErrorCategory.purchase,
        'web_payment.start',
        error: error,
        provider: 'platega',
      );
      return null;
    }
  }

  /// Возврат с формы оплаты: сервер перепроверяет платёж у платёжного
  /// сервиса и, если он оплачен, начисляет срок. Возвращает статус заказа
  /// (`confirmed`, `pending`, `canceled`, …) или null при ошибке сети.
  Future<String?> checkWebPayment(String order) async {
    final auth = AuthService.instance;
    if (!auth.hasServerSession || !BackendConfig.hasNotifier) return null;
    try {
      final response = await http
          .post(
            Uri.parse('${BackendConfig.notifierUrl}/api/user/pay-check'),
            headers: auth.serverHeaders,
            body: jsonEncode({'order': order}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final status =
          (jsonDecode(response.body) as Map<String, dynamic>)['status']
              as String?;
      if (status == 'confirmed') await syncWithServer();
      return status;
    } catch (error) {
      ErrorReporter.report(
        ErrorCategory.purchase,
        'web_payment.check',
        error: error,
        provider: 'platega',
      );
      return null;
    }
  }

  /// Android: оплата, которую человек начал в браузере. Проверяется при
  /// возврате в приложение; заказ закрывается, когда сервер получил
  /// окончательный статус (подтверждён, отменён, возврат).
  Future<String?> checkPendingPayment() async {
    final order = await PendingPayment.current();
    if (order == null) return null;
    final status = await checkWebPayment(order);
    if (status != null && status != 'pending') await PendingPayment.clear();
    return status;
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_currentUserId != null) {
        await prefs.setString(_prefKeyOwner, _currentUserId!);
      } else {
        await prefs.remove(_prefKeyOwner);
      }
      if (_purchaseStore != null) {
        await prefs.setString('premium_purchase_store', _purchaseStore!);
      } else {
        await prefs.remove('premium_purchase_store');
      }
      await prefs.setBool(_prefKeyIsPremium, _isPremium);
      if (_expiresAt != null) {
        await prefs.setInt(
          _prefKeyExpiresAt,
          _expiresAt!.millisecondsSinceEpoch,
        );
      } else {
        await prefs.remove(_prefKeyExpiresAt);
      }
    } catch (e) {
      debugPrint('PremiumService: save error: $e');
    }
  }
}
