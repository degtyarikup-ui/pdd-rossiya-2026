import 'dart:math';

const webOAuthStorageKey = 'pdd_web_oauth_pending';
const webOAuthFragmentPrefix = '#pdd-oauth=';

/// Both sites use the existing Apple Services ID, but return to the origin
/// that owns the pending state in sessionStorage. The callback URL is fixed;
/// page paths and query parameters can never select an arbitrary return site.
Uri appleWebOAuthCallback(Uri pageUri, {required String notifierUrl}) {
  if (pageUri.scheme == 'https' &&
      pageUri.userInfo.isEmpty &&
      pageUri.origin == 'https://pdd-drive.app') {
    return Uri.parse('https://pdd-drive.app/auth/apple/callback');
  }
  return Uri.parse('$notifierUrl/auth/apple/callback');
}

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
  Map<String, String> invalid(String issue) => {
    'provider': 'unknown',
    'error': 'invalid_state',
    'return_issue': issue,
  };
  if (pending == null) return invalid('missing');
  final provider = pending['provider'];
  final started = pending['startedAt'];
  if (!['apple', 'yandex'].contains(provider) ||
      pending['state'] is! String ||
      (pending['state'] as String).length != 64 ||
      started is! int ||
      (provider == 'apple' &&
          pending['nonce'] != null &&
          pending['nonce'] is! String)) {
    return invalid('malformed');
  }
  if (params['provider'] != provider || params['state'] != pending['state']) {
    return invalid('mismatch');
  }
  final age = now.millisecondsSinceEpoch - started;
  if (age < 0) return invalid('future');
  if (age > const Duration(minutes: 10).inMilliseconds) {
    return invalid('expired');
  }
  // A reason is assigned only by validation, never by provider parameters.
  final validated = {...params}..remove('return_issue');
  return {
    ...validated,
    if (provider == 'apple')
      'expected_nonce': pending['nonce'] as String? ?? '',
  };
}
