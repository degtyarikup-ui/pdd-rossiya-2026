import 'dart:async';
import 'dart:convert';

import 'package:web/web.dart' as web;
import 'package:pdd_app/data/services/web_oauth_state.dart';

bool get appleWebNeedsSafariHint => needsAppleSafariHint(
  web.window.navigator.userAgent,
  maxTouchPoints: web.window.navigator.maxTouchPoints,
);

Future<Never> startWebOAuth(String provider, Uri authorizationUrl) {
  // Only state/nonce are stored, never provider tokens or account information.
  web.window.sessionStorage.setItem(
    webOAuthStorageKey,
    jsonEncode({
      'provider': provider,
      'state': authorizationUrl.queryParameters['state'],
      'nonce': authorizationUrl.queryParameters['nonce'],
      'startedAt': DateTime.now().millisecondsSinceEpoch,
    }),
  );
  web.window.location.assign(authorizationUrl.toString());
  // Navigation replaces this page; don't show a cancellation in the meantime.
  return Completer<Never>().future;
}

Map<String, String>? takeWebOAuthReturn() {
  final fragment = web.window.location.hash;
  if (!fragment.startsWith(webOAuthFragmentPrefix)) return null;
  // Remove credentials before Flutter routing, analytics or diagnostics start.
  web.window.history.replaceState(
    null,
    '',
    '${web.window.location.pathname}${web.window.location.search}',
  );
  try {
    final raw = web.window.sessionStorage.getItem(webOAuthStorageKey);
    web.window.sessionStorage.removeItem(webOAuthStorageKey);
    final pending = raw == null
        ? null
        : jsonDecode(raw) as Map<String, dynamic>;
    final params = Uri.splitQueryString(
      Uri.decodeComponent(fragment.substring(webOAuthFragmentPrefix.length)),
    );
    return validateWebOAuthReturn(params, pending, DateTime.now());
  } catch (_) {
    return {'provider': 'unknown', 'error': 'invalid_state'};
  }
}
