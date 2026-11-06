import 'dart:math';

const webOAuthStorageKey = 'pdd_web_oauth_pending';
const webOAuthFragmentPrefix = '#pdd-oauth=';

bool needsAppleSafariHint(String userAgent, {int maxTouchPoints = 0}) {
  final ios =
      RegExp(r'iPhone|iPad|iPod').hasMatch(userAgent) ||
      (userAgent.contains('Macintosh') && maxTouchPoints > 1);
  final safari =
      userAgent.contains('Safari/') &&
      userAgent.contains('Version/') &&
      !RegExp(r'Telegram|CriOS|FxiOS|EdgiOS|OPiOS').hasMatch(userAgent);
  return ios && !safari;
}

String newWebOAuthState() => List.generate(
  32,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

/// The provider response is accepted only in the tab that started this login.
/// Identity is subsequently verified by the server, never by these parameters.
Map<String, String> validateWebOAuthReturn(
  Map<String, String> params,
  Map<String, dynamic>? pending,
  DateTime now,
) {
  final provider = pending?['provider'];
  final started = pending?['startedAt'];
  if (!['apple', 'yandex'].contains(provider) ||
      params['provider'] != provider ||
      pending?['state'] is! String ||
      !RegExp(r'^(app_)?[a-f0-9]{64}$').hasMatch(pending!['state'] as String) ||
      params['state'] != pending['state'] ||
      started is! int ||
      now.millisecondsSinceEpoch - started < 0 ||
      now.millisecondsSinceEpoch - started >
          const Duration(minutes: 10).inMilliseconds) {
    return {'provider': 'unknown', 'error': 'invalid_state'};
  }
  return {
    ...({...params}
      ..remove('checkout_tier')
      ..remove('checkout_campaign')),
    // The caller cannot inject a checkout destination through the callback.
    // Restore only the fixed choice saved by this tab before starting OAuth.
    if (['weekly', 'threeMonths'].contains(pending['checkoutTier']))
      'checkout_tier': pending['checkoutTier'] as String,
    if (pending['checkoutCampaign'] is String)
      'checkout_campaign': pending['checkoutCampaign'] as String,
    if (provider == 'apple')
      'expected_nonce': pending['nonce'] as String? ?? '',
  };
}
