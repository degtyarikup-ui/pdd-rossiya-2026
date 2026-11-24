import 'dart:async';
import 'dart:convert';
import 'school_login_route.dart';

import 'package:pdd_app/data/services/browser_info_web.dart';
import 'package:web/web.dart' as web;
import 'package:pdd_app/data/services/web_oauth_state.dart';
import 'package:pdd_app/data/services/web_checkout_route.dart';

bool get appleWebNeedsSafariHint => needsAppleSafariHint(
  web.window.navigator.userAgent,
  maxTouchPoints: web.window.navigator.maxTouchPoints,
);

String webOAuthReturnState(String randomState) =>
    web.window.location.hostname == 'pdd-drive.app'
    ? 'app_$randomState'
    : randomState;

Future<Never> startWebOAuth(String provider, Uri authorizationUrl) {
  // Capture first-touch tags while this page still has them. An existing
  // guest may have already reported installation and skip metadata collection.
  browserAcquisitionFields();
  // Only state/nonce are stored, never provider tokens or account information.
  web.window.sessionStorage.setItem(
    webOAuthStorageKey,
    jsonEncode({
      'provider': provider,
      'state': authorizationUrl.queryParameters['state'],
      'nonce': authorizationUrl.queryParameters['nonce'],
      'startedAt': DateTime.now().millisecondsSinceEpoch,
      if (SchoolLoginRoute.resolve(Uri.base, null) case final school?) ...{
        'school_login': school.challenge,
        'school_state': school.state,
      },
      if (WebCheckoutRoute.fromUri(Uri.base) case final checkout?) ...{
        'checkoutTier': checkout.tier.name,
        if (checkout.campaignId != null)
          'checkoutCampaign': checkout.campaignId,
      },
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
    final result = validateWebOAuthReturn(params, pending, DateTime.now());
    final school = SchoolLoginRoute.parse(
      result['school_login'],
      result['school_state'],
    );
    if (school != null) {
      final address = Uri(
        path: '/app/',
        queryParameters: {
          'school_login': school.challenge,
          'school_state': school.state,
        },
      );
      web.window.history.replaceState(null, '', address.toString());
    }
    return result;
  } catch (_) {
    return {'provider': 'unknown', 'error': 'invalid_state'};
  }
}
