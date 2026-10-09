import 'dart:math';

const webOAuthStorageKey = 'pdd_web_oauth_pending';
const webOAuthFragmentPrefix = '#pdd-oauth=';

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
      (pending!['state'] as String).length != 64 ||
      params['state'] != pending['state'] ||
      started is! int ||
      now.millisecondsSinceEpoch - started < 0 ||
      now.millisecondsSinceEpoch - started >
          const Duration(minutes: 10).inMilliseconds) {
    return {'provider': 'unknown', 'error': 'invalid_state'};
  }
  return {
    ...params,
    if (provider == 'apple')
      'expected_nonce': pending['nonce'] as String? ?? '',
  };
}
