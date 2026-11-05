import 'package:pdd_app/data/services/premium_service.dart';

/// Only fixed checkout choices survive OAuth. Never store a redirect URL or
/// credentials in checkout state.
class WebCheckoutRoute {
  const WebCheckoutRoute({this.tier = PremiumTier.threeMonths});

  final PremiumTier tier;

  static PremiumTier? parseTier(String? value) => switch (value) {
    'weekly' => PremiumTier.weekly,
    'threeMonths' => PremiumTier.threeMonths,
    _ => null,
  };

  static WebCheckoutRoute? fromUri(Uri uri) =>
      uri.queryParameters['checkout'] == 'sbp'
      ? WebCheckoutRoute(
          tier:
              parseTier(uri.queryParameters['tier']) ?? PremiumTier.threeMonths,
        )
      : null;

  static WebCheckoutRoute? resolve(Uri uri, Map<String, String>? authReturn) {
    final direct = fromUri(uri);
    if (direct != null) return direct;
    final tier = parseTier(authReturn?['checkout_tier']);
    return tier == null ? null : WebCheckoutRoute(tier: tier);
  }

  static bool validOrder(String? order) =>
      order != null &&
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      ).hasMatch(order);
}
