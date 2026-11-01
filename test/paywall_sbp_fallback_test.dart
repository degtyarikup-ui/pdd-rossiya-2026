import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/payment_mode.dart';
import 'package:pdd_app/presentation/widgets/premium_plans_sheet.dart';

/// A refused Google Play payment switches to SBP only where the payment-mode
/// resolver already offered SBP and Platega is live.
void main() {
  const russian = [PaymentMode.sbp, PaymentMode.storeBilling];
  bool offer({
    List<PaymentMode> modes = russian,
    PaymentMode? mode = PaymentMode.storeBilling,
    bool sbpLive = true,
    PurchaseResult result = PurchaseResult.error,
    PurchaseFailure failure = PurchaseFailure.storeRefused,
  }) => PremiumPlansSheet.offerSbpAfterStoreFailure(
    modes: modes,
    mode: mode,
    sbpLive: sbpLive,
    result: result,
    failure: failure,
  );

  test('store refusal or a missing catalogue offers SBP to Russian users', () {
    expect(offer(), isTrue);
    expect(offer(result: PurchaseResult.productNotFound), isTrue);
    expect(offer(result: PurchaseResult.storeUnavailable), isTrue);
  });

  test('never outside the resolver, before Platega is live, or on cancel', () {
    expect(offer(modes: const [PaymentMode.storeBilling]), isFalse);
    expect(offer(sbpLive: false), isFalse);
    expect(offer(mode: PaymentMode.sbp), isFalse);
    expect(offer(result: PurchaseResult.canceled), isFalse);
  });

  test(
    'a paid but unconfirmed purchase is not redirected to a second payment',
    () {
      for (final failure in [
        PurchaseFailure.verificationPending,
        PurchaseFailure.legacyOwnerRequired,
        PurchaseFailure.other,
      ]) {
        expect(offer(failure: failure), isFalse, reason: failure.name);
      }
    },
  );
}
