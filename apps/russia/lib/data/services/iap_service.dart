import 'package:pdd_app/data/services/diagnostic_context.dart';
import 'package:pdd_app/data/services/iap_offer.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart'
    show SK2Product;

export 'package:pdd_app/data/services/iap_offer.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:crypto/crypto.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/device_region.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:pdd_app/data/services/notifier_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ProductLoadPhase { background, paywall, purchase }

enum PurchaseResult {
  success,
  canceled,
  error,
  productNotFound,
  offerChanged,
  storeUnavailable,
}

/// Почему покупка закончилась ошибкой — для понятного текста пользователю.
/// Сырой текст магазина или исключения человеку не показывается.
enum PurchaseFailure {
  /// Причина не уточнена (общий случай).
  other,

  /// Магазин не смог провести оплату (способ оплаты, отказ банка и т.п.).
  storeRefused,

  /// Оплата прошла, но доступ пока не подтверждён — повторно платить не нужно.
  verificationPending,

  /// A legacy Apple transaction needs ownership evidence from support.
  legacyOwnerRequired,

  /// An unfinished store payment belongs to another app account.
  accountMismatch,

  /// The store is waiting for approval or completion of a pending payment.
  paymentPending,
}

typedef NativeOfferPolicy = ({bool standard, bool trial});
typedef _PendingVerification = (PurchaseDetails, String?, bool);

class _StoreProductQuery {
  _StoreProductQuery(this.ids);

  final Set<String> ids;
  final Map<String, dynamic> context = {};
  late final Future<String?> result;
}

class IapService extends ChangeNotifier {
  static final IapService instance = IapService._internal();
  IapService._internal()
    : _onProductDiagnostic = null,
      _queryPlayPurchases = null,
      _readPolicy = _publishedPolicy,
      _appleEligible = SK2Product.isIntroductoryOfferEligible;
  @visibleForTesting
  IapService.forTesting({
    void Function(String, Map<String, dynamic>)? onProductDiagnostic,
    Future<QueryPurchaseDetailsResponse> Function()? queryPlayPurchases,
    Future<NativeOfferPolicy> Function(String store)? readPolicy,
    Future<bool> Function(String productId)? appleEligible,
  }) : _onProductDiagnostic = onProductDiagnostic,
       _queryPlayPurchases = queryPlayPurchases,
       _readPolicy = readPolicy,
       _appleEligible = appleEligible ?? SK2Product.isIntroductoryOfferEligible;

  final Future<NativeOfferPolicy> Function(String)? _readPolicy;
  final Future<bool> Function(String) _appleEligible;
  static const _legacyPolicy = (standard: false, trial: false);
  NativeOfferPolicy _policy = _legacyPolicy;
  IapOffer? _trialOffer;

  static Future<NativeOfferPolicy> _publishedPolicy(String store) async {
    final catalog = await PremiumService.instance.loadPremiumCatalog();
    return (
      standard: catalog?.nativeQuarterMode(store) == 'standard',
      trial: catalog?.trialEnabled(store) == true,
    );
  }

  Future<NativeOfferPolicy> _loadPolicy() async {
    if (_readPolicy == null) return _legacyPolicy;
    try {
      final policy = await _readPolicy(
        _store,
      ).timeout(const Duration(seconds: 3));
      if (policy.trial && defaultTargetPlatform == TargetPlatform.android) {
        final country = await DeviceRegion.playCountry();
        return (
          standard: policy.standard,
          trial: country != null && country != 'RU',
        );
      }
      return policy;
    } catch (_) {
      return _legacyPolicy;
    }
  }

  final Future<QueryPurchaseDetailsResponse> Function()? _queryPlayPurchases;
  final void Function(String, Map<String, dynamic>)? _onProductDiagnostic;

  // RuStore distributes the app with SBP payments only. Keep the guard at the
  // store boundary: startup, paywall and restore can all call this service.
  bool get supportsStoreBilling =>
      !kIsWeb &&
      (defaultTargetPlatform != TargetPlatform.android ||
          StoreConfig.current == AppStore.googlePlay);

  late final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _purchaseQueue = Future.value();
  final Map<String, _PendingVerification> _pendingVerification = {};
  final Map<String, String> _pendingStoreOwners = {};
  final Set<String> _pendingOnboarding = {};
  static const _onboardingKey = '_onboarding';
  final Set<String> _pendingProducts = {};
  static const _ownersKey = 'iap_pending_owners_v1';
  bool _ownersLoaded = false;

  Future<void> _loadOwners() async {
    if (_ownersLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ownersKey);
    if (raw != null) {
      final data = jsonDecode(raw);
      if (data is Map) {
        final onboarding = data[_onboardingKey];
        if (onboarding is List) {
          _pendingOnboarding.addAll(onboarding.whereType<String>());
        }
        for (final entry in data.entries) {
          if (entry.key is String && entry.value is String) {
            _pendingStoreOwners[entry.key as String] = entry.value as String;
          }
        }
      }
    }
    _ownersLoaded = true;
  }

  Future<void> _saveOwners() async {
    final prefs = await SharedPreferences.getInstance();
    final reservations = {
      ..._pendingStoreOwners,
      // Older clients still read the product-to-owner entries.
      if (_pendingOnboarding.isNotEmpty)
        _onboardingKey: _pendingOnboarding.toList(),
    };
    if (!await prefs.setString(_ownersKey, jsonEncode(reservations))) {
      throw StateError('purchase ownership storage unavailable');
    }
  }

  Future<void> _clearOwner(String product) async {
    _pendingStoreOwners.remove(product);
    _pendingOnboarding.remove(product);
    await _saveOwners();
  }

  Future<String?> _appleAccountToken() async {
    final response = await sendWithRetry(
      (host) => http.get(
        Uri.parse('$host/api/user/store/account-token'),
        headers: AuthService.instance.serverHeaders,
      ),
      hosts: BackendConfig.notifierHosts,
    );
    if (response.statusCode != 200) return null;
    final value = jsonDecode(response.body)['accountToken'];
    return value is String &&
            RegExp(
              r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-5[a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$',
            ).hasMatch(value)
        ? value
        : null;
  }

  Timer? _retryTimer;
  bool _observingAuth = false;
  Future<void>? _initializing;

  static String get productIdWeek =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? 'u.pdd.pddApp.premium.week'
      : 'ru.pdd.pddapp.sub.week';

  static String get productId3Months =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? 'ru.pdd.pddApp.sub.3months'
      : 'ru.pdd.pddapp.sub.3months';

  // Query only the products sold by this storefront and accepted by our
  // verification server. Guessing aliases can display an unpurchasable product.
  // Restored transactions are handled independently from this sales catalogue.
  static String get productIdQuarterStandard => '$productId3Months.v2';
  static String get productIdQuarterTrial => '$productId3Months.trial3d';

  static String get productIdQuarterLegacyTrial =>
      '$productIdQuarterTrial.legacy';

  String get _selectedTrialId =>
      _policy.standard ? productIdQuarterTrial : productIdQuarterLegacyTrial;

  static bool _isTrialProduct(String id) =>
      id == productIdQuarterTrial || id == productIdQuarterLegacyTrial;

  Set<String> get _productIds => {
    productIdWeek,
    productId3Months,
    if (_policy.standard) productIdQuarterStandard,
    if (_policy.trial) _selectedTrialId,
  };

  final Map<String, ProductDetails> _products = {};
  bool _isAvailable = false;
  String _lastErrorMessage = '';

  bool get isAvailable => _isAvailable;
  Map<String, ProductDetails> get products => _products;
  String get lastErrorMessage => _lastErrorMessage;

  PurchaseFailure _lastFailure = PurchaseFailure.other;
  PurchaseFailure get lastFailure => _lastFailure;

  void _report(
    String operation, {
    String? code,
    Object? error,
    Map<String, dynamic>? context,
    StackTrace? stack,
  }) => ErrorReporter.report(
    ErrorCategory.purchase,
    operation,
    code: code,
    error: error,
    provider: _store,
    context: context,
    stack: stack,
  );

  Completer<PurchaseResult>? _currentPurchaseCompleter;
  String? _currentPurchaseOwner;
  String? _currentPurchaseProductId;
  Completer<bool>? _restoreCompleter;
  String? _restoreOwner;

  Future<void> init() => _initializing ??= _init().whenComplete(() {
    _initializing = null;
  });

  Future<void> _init() async {
    try {
      if (!supportsStoreBilling) return;
      await _loadPriceCache();
      await _loadOwners();
      if (!_observingAuth) {
        AuthService.instance.addListener(_onAuthChanged);
        _observingAuth = true;
      }
      // Subscribe before querying availability: StoreKit may replay an
      // unfinished payment as soon as its platform is initialized.
      _subscription ??= _iap.purchaseStream.listen(
        _enqueuePurchases,
        onDone: () => _subscription?.cancel(),
        onError: (error) {
          _report('iap.stream', error: error);
          debugPrint('IapService: stream error: $error');
          _lastErrorMessage = error.toString();
          _safeCompletePurchase(PurchaseResult.error);
          _safeCompleteRestore(false);
        },
      );

      _isAvailable = await _iap.isAvailable().timeout(productQueryTimeout);
      if (!_isAvailable) return;
      // Страна аккаунта Play нужна пейволлу: узнаём заранее, чтобы он не ждал.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        unawaited(DeviceRegion.playCountry());
      }
      // Observe pending payments at startup; query prices only when needed.
    } catch (e) {
      debugPrint('IapService: init exception: $e');
      _report('iap.init', error: e);
      _isAvailable = false;
    }
  }

  void _enqueuePurchases(List<PurchaseDetails> purchases) {
    // Capture ownership when StoreKit delivers the event. Queue processing
    // may wait for another verification while the signed-in account changes.
    final ownedPurchases = purchases.map((purchase) {
      final product = purchase.productID;
      final reservedOwner = _pendingStoreOwners[product];
      final playOwner = _playPurchaseOwner(purchase);
      final owner =
          playOwner ??
          reservedOwner ??
          (purchase.productID == _currentPurchaseProductId
              ? _currentPurchaseOwner
              : _restoreOwner ?? AuthService.instance.currentUser?.id);
      if (purchase.status == PurchaseStatus.pending) {
        _pendingProducts.add(purchase.productID);
      } else {
        _pendingProducts.remove(purchase.productID);
      }
      final matchesReservation =
          reservedOwner != null &&
          (playOwner == null || _ownerMatches(playOwner, reservedOwner));
      // Play's past-purchases query marks deliveries as restored, including
      // unfinished payments after a restart. Acknowledged purchases and
      // StoreKit restores are not evidence of a new checkout.
      final isNewDelivery = purchase is GooglePlayPurchaseDetails
          ? purchase.pendingCompletePurchase
          : purchase.status == PurchaseStatus.purchased;
      final fromOnboarding =
          matchesReservation &&
          _pendingOnboarding.contains(product) &&
          isNewDelivery;
      if (purchase.status == PurchaseStatus.pending && owner != null) {
        // Ask to Buy can complete after a temporary purchase-stream error.
        if (!matchesReservation) _pendingOnboarding.remove(product);
        _pendingStoreOwners[product] =
            reservedOwner != null && matchesReservation ? reservedOwner : owner;
        unawaited(
          _saveOwners().catchError(
            (Object error) => _report('iap.owner', error: error),
          ),
        );
      }
      return (purchase, owner, fromOnboarding);
    }).toList();
    _enqueuePurchaseWork(() => _onPurchaseUpdated(ownedPurchases));
  }

  // Play binds new purchases to the app account at checkout. A stale local
  // product reservation must never override the account on a delivered receipt.
  String? _playPurchaseOwner(PurchaseDetails purchase) {
    if (purchase is! GooglePlayPurchaseDetails) return null;
    final account = purchase.billingClientPurchase.obfuscatedAccountId;
    return account == null || account.isEmpty ? null : 'googleplay:$account';
  }

  bool _ownerMatches(String? owner, String? userId) =>
      owner == userId ||
      (userId != null &&
          owner == 'googleplay:${sha256.convert(utf8.encode(userId))}');

  PurchaseResult _accountMismatch() {
    _lastFailure = PurchaseFailure.accountMismatch;
    _report('iap.buy', code: 'purchase_account_mismatch');
    debugPrint('IapService: purchase blocked by another account owner');
    return PurchaseResult.error;
  }

  Future<PurchaseResult?> _reconcilePlayOwner(
    String productId, {
    bool allPlans = false,
  }) async {
    bool matches(String id) =>
        id == productId ||
        (allPlans &&
            (id == productIdWeek ||
                _isProductForTier(id, PremiumTier.threeMonths)));
    try {
      final response =
          await (_queryPlayPurchases?.call() ??
                  _iap
                      .getPlatformAddition<
                        InAppPurchaseAndroidPlatformAddition
                      >()
                      .queryPastPurchases())
              .timeout(productQueryTimeout);
      if (response.error != null) {
        _report('iap.owner', code: ErrorReporter.sdkCode(response.error!.code));
        return PurchaseResult.storeUnavailable;
      }
      final purchases = response.pastPurchases
          .where((purchase) => matches(purchase.productID))
          .toList();
      if (purchases.isNotEmpty) {
        // Reuse delivery/verification, and return its result instead of opening
        // a second payment after successfully restoring the first one.
        final completer = Completer<PurchaseResult>();
        _currentPurchaseCompleter = completer;
        try {
          _enqueuePurchases(purchases);
          await _purchaseQueue;
          if (completer.isCompleted) return await completer.future;
          final owner =
              _playPurchaseOwner(purchases.first) ??
              _pendingStoreOwners[purchases.first.productID];
          if (owner != null &&
              !_ownerMatches(owner, AuthService.instance.currentUser?.id)) {
            return _accountMismatch();
          }
          _lastFailure = PurchaseFailure.paymentPending;
          return PurchaseResult.error;
        } finally {
          if (identical(_currentPurchaseCompleter, completer)) {
            _currentPurchaseCompleter = null;
          }
        }
      }
      await _purchaseQueue;
      if (_pendingVerification.values.any(
            (entry) => matches(entry.$1.productID),
          ) ||
          _pendingProducts.any(matches)) {
        return _accountMismatch();
      }
      for (final id in _pendingStoreOwners.keys.where(matches).toList()) {
        await _clearOwner(id);
        debugPrint('IapService: cleared stale Play reservation for $id');
      }
      return null;
    } catch (error) {
      _report('iap.owner', error: error);
      return PurchaseResult.storeUnavailable;
    }
  }

  void _enqueuePurchaseWork(Future<void> Function() work) {
    final next = _purchaseQueue.then((_) => work());
    _purchaseQueue = next.catchError((Object error) {
      _report('iap.process', error: error);
      _safeCompletePurchase(PurchaseResult.error);
      _safeCompleteRestore(false);
    });
  }

  void _onAuthChanged() {
    if (AuthService.instance.hasServerSession) {
      retryPendingPurchases();
    }
  }

  bool _retryQueued = false;

  /// Retry unacknowledged payments after reconnecting or signing in. The
  /// store remains the durable queue across app restarts; no receipt is
  /// persisted in application preferences.
  void retryPendingPurchases() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_retryQueued ||
        _pendingVerification.isEmpty ||
        !supportsStoreBilling ||
        !AuthService.instance.hasServerSession) {
      return;
    }
    _retryQueued = true;
    _enqueuePurchaseWork(() async {
      _retryQueued = false;
      // The previous queue item can finish a receipt before this retry runs.
      // Re-read both pending receipts and the current owner at execution time.
      final auth = AuthService.instance;
      if (!auth.hasServerSession) return;
      final purchases = _pendingVerification.values
          .where(
            (entry) =>
                entry.$2 == null ||
                _ownerMatches(entry.$2, auth.currentUser?.id),
          )
          .toList();
      if (purchases.isNotEmpty) await _onPurchaseUpdated(purchases);
    });
  }

  /// Pauses before re-checking an unconfirmed payment. A fixed 30 seconds
  /// re-sent the same receipt every minute while the server was still busy
  /// with the previous check; the pause now grows to ten minutes.
  static const _retryDelays = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];
  int _retryRound = 0;

  @visibleForTesting
  Duration get nextRetryDelay =>
      _retryDelays[_retryRound.clamp(0, _retryDelays.length - 1)];

  void _scheduleRetry() {
    if (_retryTimer != null || !AuthService.instance.hasServerSession) return;
    final delay = nextRetryDelay;
    _retryRound++;
    _retryTimer = Timer(delay, retryPendingPurchases);
  }

  /// Сколько раз запрашиваем тарифы, прежде чем сообщить о сбое.
  static const _productAttempts = 3;

  /// Пауза перед повтором запроса тарифов: 2 с, затем 4 с. В тестах — ноль.
  @visibleForTesting
  static Duration productRetryUnit = const Duration(seconds: 2);

  Future<void>? _loadingProducts;
  bool get loadingProducts => _loadingProducts != null;
  _StoreProductQuery? _storeProductQuery;
  bool _disposed = false;
  String? _purchaseProductId;
  ProductLoadPhase _loadPhase = ProductLoadPhase.background;
  Map<String, dynamic> _productContext = {};
  @visibleForTesting
  static Duration productQueryTimeout = const Duration(seconds: 10);

  Future<void> loadProducts({
    ProductLoadPhase phase = ProductLoadPhase.background,
    PremiumTier? purchaseTier,
  }) => _requestProducts(phase, purchaseTier);

  Future<bool> loadTrialPreview() async {
    final policy = await _loadPolicy();
    if (!policy.trial || _disposed) return false;
    await _requestProducts(ProductLoadPhase.paywall, null, policy: policy);
    return storeOffer(PremiumTier.threeMonths)?.hasTrial == true;
  }

  Future<void> _requestProducts(
    ProductLoadPhase phase,
    PremiumTier? purchaseTier, {
    NativeOfferPolicy? policy,
  }) {
    if (_disposed) return Future.value();
    if (_loadingProducts == null) {
      // Share a slow native query within one bounded load cycle. Once that
      // cycle ends, keep accepting its late success until a new load starts;
      // then allow recovery even if the previous native query never returns.
      _storeProductQuery = null;
    }
    if (_loadingProducts == null || phase.index > _loadPhase.index) {
      _loadPhase = phase;
    }
    if (phase == ProductLoadPhase.purchase && purchaseTier != null) {
      _purchaseProductId = _productIdForTier(purchaseTier);
    }
    return _loadingProducts ??=
        Future<void>.microtask(() => _loadProducts(policy)).whenComplete(() {
          _loadingProducts = null;
          _loadPhase = ProductLoadPhase.background;
          _purchaseProductId = null;
          if (!_disposed) notifyListeners();
        });
  }

  void _reportProducts(String code, {StackTrace? stack}) {
    final context = DiagnosticContext.sanitize({
      ..._productContext,
      'phase': _loadPhase.name,
    });
    _onProductDiagnostic?.call(code, context);
    _report('iap.products', code: code, stack: stack, context: context);
  }

  Future<void> _loadProducts(NativeOfferPolicy? policy) async {
    if (_disposed || !supportsStoreBilling) return;
    if (_readPolicy != null) _policy = policy ?? await _loadPolicy();
    if (_disposed) return;
    for (var attempt = 1; !_isAvailable; attempt++) {
      _productContext = {'stage': 'availability', 'attempt': attempt};
      String? failure;
      StackTrace? failureStack;
      try {
        _isAvailable = await _iap.isAvailable().timeout(productQueryTimeout);
        if (_isAvailable) break;
        failure = 'store_unavailable';
      } catch (error, stack) {
        _lastErrorMessage = error.toString();
        failure = ErrorReporter.codeFor(error);
        failureStack = stack;
      }
      if (_disposed) return;
      if (attempt >= _productAttempts || _permanentProductFailure(failure)) {
        _reportProducts(failure, stack: failureStack);
        return;
      }
      await Future<void>.delayed(productRetryUnit * attempt);
    }
    for (var attempt = 1; ; attempt++) {
      if (_disposed) return;
      _productContext = {
        'stage': 'query',
        'attempt': attempt,
        'requestedCount': _productIds.length,
      };
      final failure = await _queryProducts();
      if (failure == null) return;
      if (attempt == _productAttempts || _permanentProductFailure(failure)) {
        _reportProducts(failure);
        return;
      }
      await Future<void>.delayed(productRetryUnit * attempt);
    }
  }

  // Configuration/eligibility failures need user or console action, not a loop.
  static bool _permanentProductFailure(String code) => {
    'developer_error',
    'billing_unavailable',
    'item_unavailable',
  }.contains(code);

  Future<String?> _queryProducts() async {
    final query = _storeProductQuery ?? _startProductQuery();
    try {
      // Bound the caller's wait, not the native query. A slow success remains
      // usable by the next wait and also updates an already-open paywall.
      final failure = await query.result.timeout(productQueryTimeout);
      if (_disposed) return null;
      _productContext.addAll(query.context);
      if (identical(_storeProductQuery, query)) _storeProductQuery = null;
      return failure;
    } on TimeoutException catch (error, stack) {
      if (_disposed) return null;
      _lastErrorMessage = error.toString();
      _productContext['frames'] = DiagnosticContext.frames(stack);
      return 'timeout';
    }
  }

  _StoreProductQuery _startProductQuery() {
    final query = _StoreProductQuery(Set.unmodifiable(_productIds));
    _storeProductQuery = query;
    // A previously loaded ProductDetails may contain an expired Google Play
    // offer token. Keep display prices separately, never buy from old details.
    final hadProducts = _products.isNotEmpty;
    _products.clear();
    _trialOffer = null;
    query.result = _fetchProducts(query);
    if (hadProducts) notifyListeners();
    return query;
  }

  Future<String?> _fetchProducts(_StoreProductQuery query) async {
    try {
      final response = await _iap.queryProductDetails(query.ids);
      if (_disposed || !identical(_storeProductQuery, query)) return null;
      final products = response.productDetails
          .where((product) => query.ids.contains(product.id))
          .toList();
      final regular = <String, ProductDetails>{};
      for (final product in products) {
        if (!_isTrialProduct(product.id) &&
            IapOffer.isRegularPlan(
              product,
              quarterly: product.id != productIdWeek,
            )) {
          regular.putIfAbsent(product.id, () => product);
        }
      }
      final quarter =
          regular[productIdQuarterStandard] ?? regular[productId3Months];
      final missing = {
        if (!regular.containsKey(productIdWeek)) productIdWeek,
        if (quarter == null) productId3Months,
      };
      query.context.addAll({
        'returnedCount': products.length,
        'missingCount': missing.length,
        'missingIds': missing.toList(),
      });
      final error = response.error;
      if (error != null) {
        _lastErrorMessage = error.message;
        query.context.addAll({
          'sdkSource': error.source,
          'sdkCodeHash': sha256
              .convert(utf8.encode(error.code))
              .toString()
              .substring(0, 16),
        });
        return ErrorReporter.sdkCode(error.code);
      }
      IapOffer? trial;
      if (quarter != null && _policy.trial) {
        for (final product in products.where((p) => p.id == _selectedTrialId)) {
          try {
            final offer = await IapOffer.trialFor(
              product,
              appleEligible: _appleEligible,
            ).timeout(const Duration(seconds: 2));
            if (offer != null && offer.sameRenewal(IapOffer.paid(quarter))) {
              trial = offer;
              break;
            }
          } catch (_) {
            // Store eligibility is optional; the regular plans remain usable.
          }
        }
      }
      if (_disposed || !identical(_storeProductQuery, query)) return null;
      _products.addAll(regular);
      if (trial != null) {
        _products[trial.product.id] = trial.product;
        _trialOffer = trial;
      }
      _lastErrorMessage = '';
      if (_products.isNotEmpty) {
        notifyListeners();
        unawaited(_savePriceCache());
      }
      if (_purchaseProductId != null &&
          (_products.containsKey(_purchaseProductId) ||
              (_purchaseProductId == productId3Months && quarter != null))) {
        return null;
      }
      if (_products.isEmpty) return 'products_not_found';
      if (missing.isNotEmpty) return 'products_incomplete';
      return null;
    } catch (e, stack) {
      if (_disposed || !identical(_storeProductQuery, query)) return null;
      _lastErrorMessage = e.toString();
      query.context['frames'] = DiagnosticContext.frames(stack);
      if (e is PlatformException) {
        query.context['sdkCodeHash'] = sha256
            .convert(utf8.encode(e.code))
            .toString()
            .substring(0, 16);
      }
      return ErrorReporter.codeFor(e);
    }
  }

  ProductDetails? _findProductForTier(PremiumTier tier) {
    if (tier == PremiumTier.threeMonths && _policy.standard) {
      return _products[productIdQuarterStandard] ?? _products[productId3Months];
    }
    return _products[_productIdForTier(tier)];
  }

  static String _productIdForTier(PremiumTier tier) =>
      tier == PremiumTier.threeMonths ? productId3Months : productIdWeek;

  IapOffer? storeOffer(PremiumTier tier) {
    final regular = _findProductForTier(tier);
    if (regular == null) return null;
    final trial = _trialOffer;
    if (tier == PremiumTier.threeMonths &&
        trial != null &&
        identical(_products[trial.product.id], trial.product)) {
      return trial;
    }
    return IapOffer.paid(regular);
  }

  bool _isProductForTier(String id, PremiumTier tier) =>
      id == _productIdForTier(tier) ||
      (tier == PremiumTier.threeMonths &&
          (id == productIdQuarterStandard || _isTrialProduct(id)));

  static const _priceCacheKey = 'iap_store_prices';
  final Map<String, String> _cachedPrices = {};

  Future<void> _loadPriceCache() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        _priceCacheKey,
      );
      final data = raw == null ? null : jsonDecode(raw);
      if (data is! Map) return;
      for (final tier in PremiumTier.values) {
        final price = data[tier.name];
        if (price is String && price.isNotEmpty) {
          _cachedPrices.putIfAbsent(tier.name, () => price);
        }
      }
    } catch (_) {
      // Без запомненных цен экран просто дождётся ответа магазина.
    }
  }

  Future<void> _savePriceCache() async {
    for (final tier in PremiumTier.values) {
      final product = _findProductForTier(tier);
      if (product != null) _cachedPrices[tier.name] = product.price;
    }
    try {
      await (await SharedPreferences.getInstance()).setString(
        _priceCacheKey,
        jsonEncode(_cachedPrices),
      );
    } catch (_) {}
  }

  @visibleForTesting
  void debugClearPriceCache() => _cachedPrices.clear();

  /// Есть ли сейчас товары магазина, которые можно купить.
  bool hasProductFor(PremiumTier tier) => _findProductForTier(tier) != null;

  bool get hasStoreProducts => _products.isNotEmpty;

  /// A partial response must not stop the paywall retry for the missing tier.
  bool get hasCompleteStoreProducts => PremiumTier.values.every(hasProductFor);

  /// Цена тарифа для показа: из ответа магазина, а пока он не пришёл — та,
  /// что этот же магазин называл на этом устройстве в прошлый раз (строка
  /// магазина в валюте покупателя, не придуманная нами). null — магазин ещё
  /// ни разу не ответил. Само окно оплаты магазина всегда показывает
  /// актуальную цену.
  String? storePrice(PremiumTier tier) =>
      _findProductForTier(tier)?.price ?? _cachedPrices[tier.name];

  String getProductPrice(PremiumTier tier, String defaultPrice) {
    final product = _findProductForTier(tier);
    if (product != null) {
      return product.price;
    }

    // Store policy: the price shown must be the store's own, in the buyer's
    // currency — no price is invented from another product's currency.
    return defaultPrice;
  }

  String get _store => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? 'appstore'
      : 'googleplay';

  String _verificationError = 'verification_unavailable';

  Future<bool> _verificationAvailable() async {
    _verificationError = 'verification_unavailable';
    if (!AuthService.instance.hasServerSession || !BackendConfig.hasNotifier) {
      return false;
    }
    try {
      final response = await NotifierApi.get(
        '/api/user/store/status',
        query: {'store': _store},
        headers: AuthService.instance.serverHeaders,
      );
      return response.statusCode == 200 &&
          jsonDecode(response.body)['configured'] == true;
    } catch (error) {
      _verificationError = ErrorReporter.codeFor(error);
      return false;
    }
  }

  bool _paymentBusy = false;
  Future<PurchaseResult> buyProduct(
    PremiumTier tier, {
    IapOffer? expectedOffer,
    bool fromOnboarding = false,
  }) async {
    if (_paymentBusy) {
      _report('iap.buy', code: 'purchase_in_progress');
      return PurchaseResult.error;
    }
    _paymentBusy = true;
    try {
      // A delivered receipt takes priority over a failed availability probe.
      // Otherwise the paywall could offer another payment via SBP.
      if (_retryDeliveredProduct(tier)) return PurchaseResult.error;
      final result = await _buyNative(
        tier,
        expectedOffer,
        fromOnboarding: fromOnboarding,
      );
      if ((result == PurchaseResult.storeUnavailable ||
              result == PurchaseResult.productNotFound) &&
          _retryDeliveredProduct(tier)) {
        return PurchaseResult.error;
      }
      return result;
    } finally {
      _paymentBusy = false;
    }
  }

  bool hasDeliveredProduct(PremiumTier tier) => _pendingVerification.values.any(
    (entry) => _isProductForTier(entry.$1.productID, tier),
  );

  bool _retryDeliveredProduct(PremiumTier tier) {
    if (!hasDeliveredProduct(tier)) return false;
    final purchase = _pendingVerification.values.firstWhere(
      (entry) => _isProductForTier(entry.$1.productID, tier),
    );
    if (purchase.$2 != null &&
        !_ownerMatches(purchase.$2, AuthService.instance.currentUser?.id)) {
      _accountMismatch();
      return true;
    }
    _lastFailure = PurchaseFailure.verificationPending;
    _lastErrorMessage = appL10n.purchaseVerificationPending;
    retryPendingPurchases();
    return true;
  }

  Future<PurchaseResult> _buyNative(
    PremiumTier tier,
    IapOffer? expectedOffer, {
    required bool fromOnboarding,
  }) async {
    if (!supportsStoreBilling) {
      return PurchaseResult.storeUnavailable;
    }

    final owner = AuthService.instance.currentUser?.id;
    _lastErrorMessage = '';
    _lastFailure = PurchaseFailure.other;
    if (!AuthService.instance.hasServerSession) {
      _report('iap.buy', code: 'session_missing');
      return PurchaseResult.error;
    }
    if (!await _verificationAvailable()) {
      _report('iap.buy', code: _verificationError);
      return PurchaseResult.storeUnavailable;
    }

    if (!_isAvailable || _subscription == null) {
      await init();
      if (!_isAvailable) {
        debugPrint('IapService: Store is not available on this device');
        _report('iap.buy', code: 'store_unavailable');
        return PurchaseResult.storeUnavailable;
      }
    }

    // A display query may have started before the user saw these terms.
    // Checkout must fetch the active policy and eligible offers again.
    if (expectedOffer != null && _loadingProducts != null) {
      await _loadingProducts;
    }
    await loadProducts(phase: ProductLoadPhase.purchase, purchaseTier: tier);
    final offer = storeOffer(tier);
    if (_retryDeliveredProduct(tier)) return PurchaseResult.error;
    if (expectedOffer != null &&
        (offer == null || !expectedOffer.sameTerms(offer))) {
      return PurchaseResult.offerChanged;
    }
    if (offer?.hasTrial == true && expectedOffer == null) {
      return PurchaseResult.offerChanged;
    }
    final product = offer?.product;
    if (product == null) {
      debugPrint('IapService: Product for tier $tier not found in Store');
      _report('iap.buy', code: 'product_not_found');
      return PurchaseResult.productNotFound;
    }

    // Google treats different subscription products independently. Look for any
    // existing Premium purchase before offering a second contract in the
    // expanded catalog, including after reinstall or a change of PDD account.
    if (defaultTargetPlatform == TargetPlatform.android &&
        (expectedOffer != null ||
            _policy.standard ||
            _policy.trial ||
            _pendingOnboarding.contains(product.id))) {
      final result = await _reconcilePlayOwner(product.id, allPlans: true);
      if (result != null) return result;
      if (_retryDeliveredProduct(tier)) return PurchaseResult.error;
    }

    // Do not start a second quarterly SKU while the first awaits store approval.
    final siblingIds = {
      ..._pendingProducts,
      ..._pendingStoreOwners.keys,
    }.where((id) => id != product.id && _isProductForTier(id, tier)).toList();
    for (final id in siblingIds) {
      if (!_pendingProducts.contains(id) &&
          defaultTargetPlatform == TargetPlatform.android) {
        final result = await _reconcilePlayOwner(id);
        if (result != null) return result;
        continue;
      }
      _lastFailure = PurchaseFailure.paymentPending;
      return PurchaseResult.error;
    }
    if (_currentPurchaseCompleter != null) {
      _report('iap.buy', code: 'purchase_in_progress');
      return PurchaseResult.error;
    }
    var pendingOwner = _pendingStoreOwners[product.id];
    if (_pendingProducts.contains(product.id)) {
      if (pendingOwner != null && !_ownerMatches(pendingOwner, owner)) {
        return _accountMismatch();
      }
      _lastFailure = PurchaseFailure.paymentPending;
      return PurchaseResult.error;
    }
    if (pendingOwner != null && !_ownerMatches(pendingOwner, owner)) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final recovered = await _reconcilePlayOwner(product.id);
        if (recovered != null) return recovered;
        if (_retryDeliveredProduct(tier)) return PurchaseResult.error;
        pendingOwner = _pendingStoreOwners[product.id];
      }
      if (pendingOwner != null && !_ownerMatches(pendingOwner, owner)) {
        return _accountMismatch();
      }
    }

    final completer = Completer<PurchaseResult>();
    _currentPurchaseCompleter = completer;

    if (AuthService.instance.currentUser?.id != owner ||
        !AuthService.instance.hasServerSession) {
      _currentPurchaseCompleter = null;
      _report('iap.buy', code: 'account_changed');
      return PurchaseResult.error;
    }
    String? appleToken;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        appleToken = await _appleAccountToken();
        if (appleToken == null) {
          _safeCompletePurchase(PurchaseResult.storeUnavailable);
          return PurchaseResult.storeUnavailable;
        }
      }
      if (AuthService.instance.currentUser?.id != owner ||
          !AuthService.instance.hasServerSession) {
        _safeCompletePurchase(PurchaseResult.error);
        return PurchaseResult.error;
      }
      _pendingStoreOwners[product.id] = owner!;
      _pendingOnboarding.remove(product.id);
      if (fromOnboarding) _pendingOnboarding.add(product.id);
      // Persist before the OS payment sheet: deferred StoreKit transactions can
      // be delivered after the process dies and another account signs in.
      await _saveOwners();
    } catch (error) {
      _report('iap.owner', error: error);
      _safeCompletePurchase(PurchaseResult.error);
      return PurchaseResult.error;
    }
    final purchaseParam = PurchaseParam(
      productDetails: product,
      applicationUserName:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? sha256
                .convert(utf8.encode(AuthService.instance.currentUser!.id))
                .toString()
          : appleToken,
    );
    _currentPurchaseOwner = owner;
    _currentPurchaseProductId = product.id;
    try {
      final launched = await _iap.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      if (!launched) {
        // No OS purchase was created. Do not leave a durable reservation that
        // would prevent another signed-in account from opening this product.
        await _clearOwner(product.id);
        _report('iap.buy', code: 'purchase_not_started');
        _lastFailure = PurchaseFailure.storeRefused;
        _safeCompletePurchase(PurchaseResult.error);
        return PurchaseResult.error;
      }
    } catch (e) {
      debugPrint('IapService: buyNonConsumable exception: $e');
      _report('iap.buy', error: e);
      _lastErrorMessage = e.toString();
      _safeCompletePurchase(PurchaseResult.error);
      return PurchaseResult.error;
    }

    return completer.future;
  }

  Future<bool> restorePurchases() async {
    if (_paymentBusy) return false;
    _paymentBusy = true;
    try {
      return await _restoreNative();
    } finally {
      _paymentBusy = false;
    }
  }

  Future<bool> _restoreNative() async {
    _lastFailure = PurchaseFailure.other;
    final owner = AuthService.instance.currentUser?.id;
    if (!supportsStoreBilling || !AuthService.instance.hasServerSession) {
      return false;
    }

    if (!_isAvailable || _subscription == null) {
      await init();
      if (!_isAvailable) return false;
    }

    if (AuthService.instance.currentUser?.id != owner ||
        !AuthService.instance.hasServerSession) {
      return false;
    }

    try {
      if (_restoreCompleter != null) return false;
      final completer = Completer<bool>();
      _restoreCompleter = completer;
      _restoreOwner = owner;
      await _iap.restorePurchases();
      final result = await completer.future.timeout(
        const Duration(seconds: 35),
        onTimeout: () {
          _report('iap.restore', code: 'timeout');
          return false;
        },
      );
      _restoreCompleter = null;
      _restoreOwner = null;
      return result;
    } catch (e) {
      debugPrint('IapService: restore error: $e');
      _report('iap.restore', error: e);
      _restoreCompleter = null;
      _restoreOwner = null;
      return false;
    }
  }

  PremiumTier _tierFromProductId(String productId) {
    final id = productId.toLowerCase();
    if (id.contains('3month') ||
        id.contains('3_month') ||
        id.contains('quarter') ||
        id.contains('3m') ||
        id.contains('month_3') ||
        id.contains('three_month') ||
        id.contains('threemonth')) {
      return PremiumTier.threeMonths;
    }
    return PremiumTier.weekly;
  }

  @visibleForTesting
  static String paymentErrorCode(IAPError? error) {
    if (error?.source == 'google_play') {
      for (final response in BillingResponse.values) {
        if (response.toString() == error?.message) {
          return 'play_${response.name}';
        }
      }
    }
    return ErrorReporter.sdkCode(error?.code);
  }

  Future<void> _clearFailedPurchaseOwner(PurchaseDetails purchase) async {
    final product = purchase.productID.isNotEmpty
        ? purchase.productID
        : _currentPurchaseProductId;
    if (product != null &&
        !_pendingVerification.values.any(
          (entry) => entry.$1.productID == product,
        )) {
      await _clearOwner(product);
      _pendingProducts.remove(product);
    }
  }

  Future<void> _onPurchaseUpdated(
    List<_PendingVerification> purchaseDetailsList,
  ) async {
    if (purchaseDetailsList.isEmpty) {
      _safeCompleteRestore(false);
      return;
    }
    for (final (purchaseDetails, owner, fromOnboarding)
        in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // In progress
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          if ([
            'purchase_cancelled',
            'purchase_canceled',
            'user_canceled',
          ].contains(purchaseDetails.error?.code)) {
            await _clearFailedPurchaseOwner(purchaseDetails);
            _safeCompletePurchase(PurchaseResult.canceled);
            _safeCompleteRestore(false);
            if (purchaseDetails.pendingCompletePurchase) {
              await _iap.completePurchase(purchaseDetails);
            }
            continue;
          }
          _report('iap.payment', code: paymentErrorCode(purchaseDetails.error));
          if (purchaseDetails.productID.isNotEmpty) {
            await _clearFailedPurchaseOwner(purchaseDetails);
          }
          debugPrint('IapService: purchase error: ${purchaseDetails.error}');
          _lastErrorMessage =
              purchaseDetails.error?.message ?? appL10n.payErrorGeneric;
          _lastFailure = PurchaseFailure.storeRefused;
          _safeCompletePurchase(PurchaseResult.error);
          _safeCompleteRestore(false);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          final key =
              '${purchaseDetails.productID}:${purchaseDetails.purchaseID ?? purchaseDetails.verificationData.serverVerificationData}';
          final auth = AuthService.instance;
          final pending = _pendingVerification.putIfAbsent(
            key,
            () => (purchaseDetails, owner, fromOnboarding),
          );
          if (pending.$2 != null &&
              !_ownerMatches(pending.$2, auth.currentUser?.id)) {
            _accountMismatch();
            _safeCompletePurchase(PurchaseResult.error);
            _safeCompleteRestore(false);
            continue;
          }
          final tier = _tierFromProductId(purchaseDetails.productID);
          // The receipt may be a restore or renewal. The visible offer is not
          // evidence of the amount billed for this transaction.
          final price = _isTrialProduct(purchaseDetails.productID)
              ? ''
              : _products[purchaseDetails.productID]?.price ?? '';
          final store = _store;

          final verified = await PremiumService.instance.recordPurchase(
            tier: tier,
            price: price,
            store: store,
            transactionId: purchaseDetails.purchaseID,
            fromOnboarding: pending.$3,
            productId: purchaseDetails.productID,
            purchaseToken:
                purchaseDetails.verificationData.serverVerificationData,
          );
          if (!verified) {
            final legacy =
                PremiumService.instance.purchaseVerificationFailure ==
                PurchaseVerificationFailure.legacyOwnerRequired;
            _lastErrorMessage = legacy
                ? appL10n.purchaseLegacyOwnerRequired
                : appL10n.purchaseVerificationPending;
            _lastFailure = legacy
                ? PurchaseFailure.legacyOwnerRequired
                : PurchaseFailure.verificationPending;
            _safeCompletePurchase(PurchaseResult.error);
            _safeCompleteRestore(false);
            // Do not acknowledge a payment we could not deliver. The store
            // can redeliver it; the user can retry restoration after reconnecting.
            if (PremiumService.instance.purchaseVerificationFailure ==
                PurchaseVerificationFailure.unavailable) {
              _scheduleRetry();
            } else {
              // A rejected or expired subscription is not a network retry.
              // Leave it unfinished in the store for an explicit restore.
              _pendingVerification.remove(key);
            }
            continue;
          }
          _retryRound = 0;
          // StoreKit can report an already owned subscription as restored
          // while the user is waiting for the purchase button to finish.
          _safeCompletePurchase(PurchaseResult.success);
          _safeCompleteRestore(true);
          if (purchaseDetails.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(purchaseDetails);
            } catch (error) {
              _report('iap.complete', error: error);
              _scheduleRetry();
              continue;
            }
          }
          _pendingVerification.remove(key);
          await _clearOwner(purchaseDetails.productID);
          continue;
        } else if (purchaseDetails.status == PurchaseStatus.canceled) {
          await _clearFailedPurchaseOwner(purchaseDetails);
          _safeCompletePurchase(PurchaseResult.canceled);
          _safeCompleteRestore(false);
        }

        if (purchaseDetails.pendingCompletePurchase) {
          await _iap.completePurchase(purchaseDetails);
        }
      }
    }
  }

  void _safeCompletePurchase(PurchaseResult result) {
    if (_currentPurchaseCompleter != null &&
        !_currentPurchaseCompleter!.isCompleted) {
      _currentPurchaseCompleter!.complete(result);
    }
    _currentPurchaseCompleter = null;
    _currentPurchaseOwner = null;
    _currentPurchaseProductId = null;
  }

  void _safeCompleteRestore(bool result) {
    if (_restoreCompleter != null && !_restoreCompleter!.isCompleted) {
      _restoreCompleter!.complete(result);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _storeProductQuery = null;
    _retryTimer?.cancel();
    if (_observingAuth) AuthService.instance.removeListener(_onAuthChanged);
    _subscription?.cancel();
    super.dispose();
  }
}
