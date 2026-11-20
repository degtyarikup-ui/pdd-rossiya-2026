import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

/// The store terms shown before the user opens its confirmation sheet.
/// Play's ProductDetails.price is the first phase (zero on a trial).
class IapOffer {
  IapOffer.paid(this.product)
    : renewalPrice = product.price,
      renewalAmount = product.rawPrice,
      hasTrial = false;

  IapOffer._trial(this.product, this.renewalPrice, this.renewalAmount)
    : hasTrial = true;

  final ProductDetails product;
  final String renewalPrice;
  final double renewalAmount;
  final bool hasTrial;

  bool sameRenewal(IapOffer other) =>
      renewalAmount == other.renewalAmount &&
      product.currencyCode == other.product.currencyCode &&
      _appleGroup(product) == _appleGroup(other.product);

  static String? _appleGroup(ProductDetails product) =>
      product is AppStoreProduct2Details
      ? product.sk2Product.subscription?.subscriptionGroupID
      : null;

  bool sameTerms(IapOffer other) =>
      product.id == other.product.id &&
      hasTrial == other.hasTrial &&
      renewalPrice == other.renewalPrice &&
      sameRenewal(other) &&
      _playPlan(product)?.basePlanId == _playPlan(other.product)?.basePlanId;

  static SubscriptionOfferDetailsWrapper? _playPlan(ProductDetails product) {
    if (product is! GooglePlayProductDetails) return null;
    final index = product.subscriptionIndex;
    final plans = product.productDetails.subscriptionOfferDetails;
    if (index == null || plans == null || index >= plans.length) return null;
    return plans[index];
  }

  static bool isRegularPlan(ProductDetails product, {required bool quarterly}) {
    if (product is GooglePlayProductDetails) {
      final plan = _playPlan(product);
      if (plan == null ||
          plan.offerId != null ||
          plan.offerIdToken.isEmpty ||
          plan.installmentPlanDetails != null ||
          plan.pricingPhases.length != 1) {
        return false;
      }
      final phase = plan.pricingPhases.single;
      return phase.priceAmountMicros > 0 &&
          phase.recurrenceMode == RecurrenceMode.infiniteRecurring &&
          (quarterly
              ? phase.billingPeriod == 'P3M'
              : const {'P1W', 'P7D'}.contains(phase.billingPeriod));
    }
    if (product is AppStoreProduct2Details) {
      final sub = product.sk2Product.subscription;
      if (sub == null ||
          product.sk2Product.type != SK2ProductType.autoRenewable) {
        return false;
      }
      final period = sub.subscriptionPeriod;
      return product.rawPrice > 0 &&
          (quarterly
              ? period.unit == SK2SubscriptionPeriodUnit.month &&
                    period.value == 3
              : ((period.unit == SK2SubscriptionPeriodUnit.week &&
                        period.value == 1) ||
                    (period.unit == SK2SubscriptionPeriodUnit.day &&
                        period.value == 7)));
    }
    // StoreKit 1 and generic ProductDetails have no Play offer variants.
    return true;
  }

  static Future<IapOffer?> trialFor(
    ProductDetails product, {
    required Future<bool> Function(String productId) appleEligible,
  }) async {
    if (product is GooglePlayProductDetails) {
      final plan = _playPlan(product);
      if (plan == null ||
          plan.offerId != 'trial-3-days' ||
          plan.offerIdToken.isEmpty ||
          plan.installmentPlanDetails != null ||
          plan.pricingPhases.length != 2) {
        return null;
      }
      final first = plan.pricingPhases.first;
      final renewal = plan.pricingPhases.last;
      if (first.billingPeriod != 'P3D' ||
          first.priceAmountMicros != 0 ||
          first.recurrenceMode != RecurrenceMode.finiteRecurring ||
          first.billingCycleCount != 1 ||
          first.priceCurrencyCode != renewal.priceCurrencyCode ||
          renewal.billingPeriod != 'P3M' ||
          renewal.recurrenceMode != RecurrenceMode.infiniteRecurring ||
          renewal.priceAmountMicros <= 0 ||
          renewal.formattedPrice.isEmpty) {
        return null;
      }
      return IapOffer._trial(
        product,
        renewal.formattedPrice,
        renewal.priceAmountMicros / 1000000,
      );
    }
    if (product is AppStoreProduct2Details &&
        isRegularPlan(product, quarterly: true)) {
      final offers = product.sk2Product.subscription!.promotionalOffers;
      final exactIntro = offers.any(
        (o) =>
            o.type == SK2SubscriptionOfferType.introductory &&
            o.paymentMode == SK2SubscriptionOfferPaymentMode.freeTrial &&
            o.price == 0 &&
            o.period.unit == SK2SubscriptionPeriodUnit.day &&
            o.period.value == 3 &&
            o.periodCount == 1,
      );
      if (exactIntro && await appleEligible(product.id)) {
        return IapOffer._trial(product, product.price, product.rawPrice);
      }
    }
    return null;
  }
}
