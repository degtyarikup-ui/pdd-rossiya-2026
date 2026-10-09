import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/web_oauth_state.dart';

void main() {
  final now = DateTime.utc(2026, 10, 9);
  final state = newWebOAuthState();
  Map<String, dynamic> pending(String provider) => {
    'provider': provider,
    'state': state,
    'nonce': 'expected-nonce',
    'startedAt': now
        .subtract(const Duration(minutes: 1))
        .millisecondsSinceEpoch,
  };
  test(
    'same-tab return binds the result to the originating provider and state',
    () {
      final params = {
        'provider': 'yandex',
        'state': state,
        'access_token': 'credential',
      };
      expect(validateWebOAuthReturn(params, pending('yandex'), now), params);
      for (final invalid in [
        null,
        pending('apple'),
        {...pending('yandex'), 'state': newWebOAuthState()},
        {
          ...pending('yandex'),
          'startedAt': now
              .subtract(const Duration(minutes: 11))
              .millisecondsSinceEpoch,
        },
        {
          ...pending('yandex'),
          'startedAt': now
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        },
      ]) {
        expect(
          validateWebOAuthReturn(params, invalid, now)['error'],
          'invalid_state',
        );
      }
    },
  );
  test('Apple nonce comes from the saved request, not from the callback', () {
    final params = {
      'provider': 'apple',
      'state': state,
      'expected_nonce': 'attacker',
      'id_token': 'credential',
    };
    expect(
      validateWebOAuthReturn(params, pending('apple'), now)['expected_nonce'],
      'expected-nonce',
    );
  });
  test(
    'cancellation retains state validation and missing state cannot log in',
    () {
      expect(
        validateWebOAuthReturn(
          {'provider': 'apple', 'state': state, 'error': 'access_denied'},
          pending('apple'),
          now,
        )['error'],
        'access_denied',
      );
      expect(
        validateWebOAuthReturn(
          {'provider': 'apple', 'id_token': 'credential'},
          pending('apple'),
          now,
        )['error'],
        'invalid_state',
      );
    },
  );
}
