import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/web_checkout_route.dart';
import 'package:pdd_app/data/services/web_oauth_state.dart';

void main() {
  test(
    'only explicit SBP entry opens checkout; invalid plans use a safe default',
    () {
      expect(
        WebCheckoutRoute.fromUri(Uri.parse('https://pdd-drive.app/app/')),
        isNull,
      );
      expect(
        WebCheckoutRoute.fromUri(
          Uri.parse('https://pdd-drive.app/app/?checkout=other'),
        ),
        isNull,
      );
      expect(
        WebCheckoutRoute.fromUri(
          Uri.parse('https://pdd-drive.app/app/?checkout=sbp&tier=weekly'),
        )?.tier,
        PremiumTier.weekly,
      );
      expect(
        WebCheckoutRoute.fromUri(
          Uri.parse('https://pdd-drive.app/app/?checkout=sbp&tier=free'),
        )?.tier,
        PremiumTier.threeMonths,
      );
    },
  );

  for (final provider in ['apple', 'yandex']) {
    test('$provider restores checkout only from tab-bound OAuth state', () {
      final state = newWebOAuthState(), now = DateTime.now();
      final pending = <String, dynamic>{
        'provider': provider,
        'state': state,
        'startedAt': now.millisecondsSinceEpoch,
        'nonce': 'nonce',
        'checkoutTier': 'weekly',
        'checkoutCampaign': '11111111-1111-4111-8111-111111111111',
      };
      final params = {
        'provider': provider,
        'state': state,
        'checkout_tier': 'threeMonths',
        'checkout_campaign': 'injected',
      };
      final result = validateWebOAuthReturn(params, pending, now);
      expect(
        WebCheckoutRoute.resolve(
          Uri.parse('https://pdd-drive.app/app/?oauth=2'),
          result,
        )?.tier,
        PremiumTier.weekly,
      );
      expect(
        WebCheckoutRoute.resolve(
          Uri.parse('https://pdd-drive.app/app/'),
          result,
        )?.campaignId,
        '11111111-1111-4111-8111-111111111111',
      );
      final returnUri = Uri.parse('https://pdd-drive.app/app/?oauth=2');
      final checkout = WebCheckoutRoute.resolve(returnUri, result)!;
      final reloadUri = checkout.addressFor(returnUri);
      // The one-time OAuth state is gone on reload or a second login.
      expect(
        WebCheckoutRoute.resolve(reloadUri, null)?.campaignId,
        pending['checkoutCampaign'],
      );
      final newPlanUri = WebCheckoutRoute(
        tier: PremiumTier.threeMonths,
        campaignId: WebCheckoutRoute.fromUri(reloadUri)?.campaignId,
      ).addressFor(reloadUri);
      expect(
        WebCheckoutRoute.fromUri(newPlanUri)?.tier,
        PremiumTier.threeMonths,
      );
      expect(
        WebCheckoutRoute.fromUri(newPlanUri)?.campaignId,
        pending['checkoutCampaign'],
      );
      final invalid = validateWebOAuthReturn(
        {...params, 'state': newWebOAuthState()},
        pending,
        now,
      );
      expect(
        WebCheckoutRoute.resolve(
          Uri.parse('https://pdd-drive.app/app/?oauth=2'),
          invalid,
        ),
        isNull,
      );
      final ordinary = validateWebOAuthReturn(
        params,
        {...pending}..remove('checkoutTier'),
        now,
      );
      expect(ordinary.containsKey('checkout_tier'), isFalse);
      expect(
        WebCheckoutRoute.resolve(
          Uri.parse('https://pdd-drive.app/app/'),
          ordinary,
        ),
        isNull,
      );
      final canceled = validateWebOAuthReturn(
        {...params, 'error': 'access_denied'},
        pending,
        now,
      );
      expect(canceled['error'], 'access_denied');
      expect(canceled['checkout_tier'], 'weekly');
    });
  }

  test(
    'plain checkout address does not turn other marketing tags into a banner',
    () {
      final uri = Uri.parse(
        'https://pdd-drive.app/app/?utm_source=yandex'
        '&utm_campaign=11111111-1111-4111-8111-111111111111',
      );
      expect(
        WebCheckoutRoute.fromUri(
          const WebCheckoutRoute().addressFor(uri),
        )?.campaignId,
        isNull,
      );
    },
  );

  test('a callback cannot supply a checkout URL or arbitrary plan', () {
    final now = DateTime.now(), state = newWebOAuthState();
    final result = validateWebOAuthReturn(
      {'provider': 'yandex', 'state': state, 'checkout_tier': 'weekly'},
      {
        'provider': 'yandex',
        'state': state,
        'startedAt': now.millisecondsSinceEpoch,
        'checkoutTier': 'https://attacker.invalid',
      },
      now,
    );
    expect(result.containsKey('checkout_tier'), isFalse);
    for (final invalid in [
      null,
      '',
      '../account',
      'order-1',
      '${'a' * 36}?owner=other',
    ]) {
      expect(WebCheckoutRoute.validOrder(invalid), isFalse);
    }
    expect(
      WebCheckoutRoute.validOrder('11111111-1111-4111-8111-111111111111'),
      isTrue,
    );
  });
}
