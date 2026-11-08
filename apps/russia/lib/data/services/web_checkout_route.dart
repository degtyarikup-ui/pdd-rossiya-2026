import 'package:pdd_app/data/services/premium_service.dart';

/// Only fixed checkout choices survive OAuth. Never store a redirect URL or
/// credentials in checkout state.
class WebCheckoutRoute {
  const WebCheckoutRoute({
    this.tier = PremiumTier.threeMonths,
    this.campaignId,
  });

  final PremiumTier tier;
  final String? campaignId;

  static String? _campaign(String? id) => validOrder(id) ? id : null;

  static PremiumTier? parseTier(String? value) => switch (value) {
    'weekly' => PremiumTier.weekly,
    'threeMonths' => PremiumTier.threeMonths,
    _ => null,
  };

  static WebCheckoutRoute? fromUri(Uri uri) =>
      uri.queryParameters['checkout'] == 'sbp'
      ? WebCheckoutRoute(
          campaignId: uri.queryParameters['utm_source'] == 'in_app_banner'
              ? _campaign(uri.queryParameters['utm_campaign'])
              : null,
          tier:
              parseTier(uri.queryParameters['tier']) ?? PremiumTier.threeMonths,
        )
      : null;

  static WebCheckoutRoute? resolve(Uri uri, Map<String, String>? authReturn) {
    final direct = fromUri(uri);
    if (direct != null) return direct;
    final tier = parseTier(authReturn?['checkout_tier']);
    return tier == null
        ? null
        : WebCheckoutRoute(
            tier: tier,
            campaignId: _campaign(authReturn?['checkout_campaign']),
          );
  }

  static bool validOrder(String? order) =>
      order != null &&
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      ).hasMatch(order);
}
