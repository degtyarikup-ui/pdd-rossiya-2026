import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:crypto/crypto.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pdd_app/data/services/premium_service.dart';

enum PurchaseResult {
  success,
  canceled,
  error,
  productNotFound,
  storeUnavailable,
}

class IapService extends ChangeNotifier {
  static final IapService instance = IapService._internal();
  IapService._internal();

  late final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _purchaseQueue = Future.value();

  static String get productIdWeek =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? 'u.pdd.pddApp.premium.week'
      : 'ru.pdd.pddapp.premium.week';

  static String get productId3Months =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? 'ru.pdd.pddApp.sub.3months'
      : 'ru.pdd.pddapp.premium.3months';

  static const Set<String> _productIds = {
    // Standard reverse-domain iOS & Android IDs
    'ru.pdd.pddApp.premium.week',
    'ru.pdd.pddApp.premium.3months',
    'ru.pdd.pddapp.premium.week',
    'ru.pdd.pddapp.premium.3months',
    'ru.pdd.pddApp.week',
    'ru.pdd.pddApp.3months',
    'ru.pdd.pddapp.week',
    'ru.pdd.pddapp.3months',
    'ru.pdd.pddApp.1week',
    'ru.pdd.pddApp.3month',
    'ru.pdd.pddApp.sub.week',
    'ru.pdd.pddApp.sub.3months',
    'u.pdd.pddApp.premium.week',
    'ru.pdd.pddapp.sub.week',
    'ru.pdd.pddapp.sub.3months',
    'ru.pdd.premium.week',
    'ru.pdd.premium.3months',
    // Short / common StoreKit IDs
    'pdd_premium_week',
    'pdd_premium_3months',
    'pdd_week',
    'pdd_3months',
    'premium_week',
    'premium_3months',
    'premium.week',
    'premium.3months',
    'week',
    '3months',
    'weekly',
    'three_months',
  };

  final Map<String, ProductDetails> _products = {};
  bool _isAvailable = false;
  String _lastErrorMessage = '';

  bool get isAvailable => _isAvailable;
  Map<String, ProductDetails> get products => _products;
  String get lastErrorMessage => _lastErrorMessage;

  Completer<PurchaseResult>? _currentPurchaseCompleter;
  Completer<bool>? _restoreCompleter;

  Future<void> init() async {
    try {
      _isAvailable = await _iap.isAvailable();
      if (!_isAvailable) {
        debugPrint('IapService: Store is not available on this device');
        return;
      }

      _subscription ??= _iap.purchaseStream.listen(
        (purchases) {
          _purchaseQueue = _purchaseQueue
              .then((_) => _onPurchaseUpdated(purchases))
              .catchError((Object _) {
                _safeCompletePurchase(PurchaseResult.error);
              });
        },
        onDone: () => _subscription?.cancel(),
        onError: (error) {
          debugPrint('IapService: stream error: $error');
          _lastErrorMessage = error.toString();
          _safeCompletePurchase(PurchaseResult.error);
          _safeCompleteRestore(false);
        },
      );

      await loadProducts();
    } catch (e) {
      debugPrint('IapService: init exception: $e');
      _isAvailable = false;
    }
  }

  Future<void> loadProducts() async {
    try {
      if (!_isAvailable) {
        _isAvailable = await _iap.isAvailable();
        if (!_isAvailable) return;
      }
      final response = await _iap.queryProductDetails(_productIds);
      if (response.error != null) {
        debugPrint('IapService: query error: ${response.error}');
        _lastErrorMessage = response.error!.message;
      }
      if (response.productDetails.isNotEmpty) {
        for (final product in response.productDetails) {
          _products[product.id] = product;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('IapService: loadProducts error: $e');
      _lastErrorMessage = e.toString();
    }
  }

  ProductDetails? _findProductForTier(PremiumTier tier) {
    if (_products.isEmpty) return null;

    final primaryId = tier == PremiumTier.threeMonths
        ? productId3Months
        : productIdWeek;
    if (_products.containsKey(primaryId)) {
      return _products[primaryId];
    }

    if (tier == PremiumTier.threeMonths) {
      for (final entry in _products.entries) {
        final id = entry.key.toLowerCase();
        if (id.contains('3month') ||
            id.contains('3_month') ||
            id.contains('quarter') ||
            id.contains('3m') ||
            id.contains('month_3') ||
            id.contains('three_month') ||
            id.contains('threemonth')) {
          return entry.value;
        }
      }
    } else {
      for (final entry in _products.entries) {
        final id = entry.key.toLowerCase();
        if (id.contains('week') ||
            id.contains('1w') ||
            id.contains('7day') ||
            id.contains('1_week') ||
            id.contains('weekly')) {
          return entry.value;
        }
      }
    }

    return null;
  }

  String getProductPrice(PremiumTier tier, String defaultPrice) {
    final product = _findProductForTier(tier);
    if (product != null) {
      return product.price;
    }

    if (_products.isNotEmpty) {
      final samplePrice = _products.values.first.price;
      if (samplePrice.contains(r'$')) {
        return tier == PremiumTier.threeMonths ? r'2,99 $' : r'0,99 $';
      } else if (samplePrice.contains('€')) {
        return tier == PremiumTier.threeMonths ? '2,99 €' : '0,99 €';
      } else if (samplePrice.contains('₽')) {
        return tier == PremiumTier.threeMonths ? '290 ₽' : '99 ₽';
      }
    }

    return defaultPrice;
  }

  String get _store => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? 'appstore'
      : 'googleplay';

  Future<bool> _verificationAvailable() async {
    if (!AuthService.instance.hasServerSession || !BackendConfig.hasNotifier) {
      return false;
    }
    try {
      final response = await http
          .get(
            Uri.parse(
              '${BackendConfig.notifierUrl}/api/user/store/status',
            ).replace(queryParameters: {'store': _store}),
            headers: AuthService.instance.serverHeaders,
          )
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200 &&
          jsonDecode(response.body)['configured'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<PurchaseResult> buyProduct(PremiumTier tier) async {
    if (kIsWeb) {
      return PurchaseResult.storeUnavailable;
    }

    _lastErrorMessage = '';
    if (!AuthService.instance.hasServerSession) return PurchaseResult.error;
    if (!await _verificationAvailable()) return PurchaseResult.storeUnavailable;

    if (!_isAvailable || _subscription == null) {
      await init();
      if (!_isAvailable) {
        debugPrint('IapService: Store is not available on this device');
        return PurchaseResult.storeUnavailable;
      }
    }

    var product = _findProductForTier(tier);
    if (product == null) {
      await loadProducts();
      product = _findProductForTier(tier);
    }

    if (product == null) {
      debugPrint('IapService: Product for tier $tier not found in Store');
      return PurchaseResult.productNotFound;
    }

    if (_currentPurchaseCompleter != null) return PurchaseResult.error;
    final completer = Completer<PurchaseResult>();
    _currentPurchaseCompleter = completer;

    final purchaseParam = PurchaseParam(
      productDetails: product,
      applicationUserName:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? sha256
                .convert(utf8.encode(AuthService.instance.currentUser!.id))
                .toString()
          : null,
    );
    try {
      final launched = await _iap.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      if (!launched) {
        _currentPurchaseCompleter = null;
        return PurchaseResult.error;
      }
    } catch (e) {
      debugPrint('IapService: buyNonConsumable exception: $e');
      _lastErrorMessage = e.toString();
      _currentPurchaseCompleter = null;
      return PurchaseResult.error;
    }

    return completer.future;
  }

  Future<bool> restorePurchases() async {
    if (kIsWeb || !AuthService.instance.hasServerSession) {
      return false;
    }

    if (!_isAvailable || _subscription == null) {
      await init();
      if (!_isAvailable) return false;
    }

    try {
      if (_restoreCompleter != null) return false;
      final completer = Completer<bool>();
      _restoreCompleter = completer;
      await _iap.restorePurchases();
      final result = await completer.future.timeout(
        const Duration(seconds: 35),
        onTimeout: () => false,
      );
      _restoreCompleter = null;
      return result;
    } catch (e) {
      debugPrint('IapService: restore error: $e');
      _restoreCompleter = null;
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

  Future<void> _onPurchaseUpdated(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // In progress
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          debugPrint('IapService: purchase error: ${purchaseDetails.error}');
          _lastErrorMessage = purchaseDetails.error?.message ?? 'Ошибка оплаты';
          _safeCompletePurchase(PurchaseResult.error);
          _safeCompleteRestore(false);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          final tier = _tierFromProductId(purchaseDetails.productID);
          final price = getProductPrice(
            tier,
            tier == PremiumTier.threeMonths ? '290 ₽' : '99 ₽',
          );
          final store = _store;

          final verified = await PremiumService.instance.recordPurchase(
            tier: tier,
            price: price,
            store: store,
            transactionId: purchaseDetails.purchaseID,
            productId: purchaseDetails.productID,
            purchaseToken:
                purchaseDetails.verificationData.serverVerificationData,
          );
          if (!verified) {
            _safeCompletePurchase(PurchaseResult.error);
            // Do not acknowledge a payment we could not deliver. The store
            // can redeliver it; the user can retry restoration after reconnecting.
            continue;
          }
          if (purchaseDetails.status == PurchaseStatus.purchased) {
            _safeCompletePurchase(PurchaseResult.success);
          } else {
            _safeCompleteRestore(true);
          }
        } else if (purchaseDetails.status == PurchaseStatus.canceled) {
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
  }

  void _safeCompleteRestore(bool result) {
    if (_restoreCompleter != null && !_restoreCompleter!.isCompleted) {
      _restoreCompleter!.complete(result);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
