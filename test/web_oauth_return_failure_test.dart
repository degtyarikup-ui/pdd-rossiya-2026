import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _identityToken(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part(claims)}.signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'expired and other rejected returns never contact the account server',
    () async {
      final cases = <String?, AuthFailure>{
        'expired': AuthFailure.webExpired,
        'missing': AuthFailure.webState,
        'mismatch': AuthFailure.webState,
        'future': AuthFailure.webState,
        'malformed': AuthFailure.webState,
        null: AuthFailure.webState,
      };
      var requests = 0;
      var writes = 0;
      for (final entry in cases.entries) {
        final auth = AuthService.forTesting(
          writeSession: (_) async => writes++,
        );
        final result = await http.runWithClient(
          () => auth.completeWebSignIn({
            'provider': 'unknown',
            'error': 'invalid_state',
            if (entry.key != null) 'return_issue': entry.key!,
          }),
          () => MockClient((_) async {
            requests++;
            return http.Response('{}', 503);
          }),
        );
        expect(result, isFalse);
        expect(auth.lastFailure, entry.value);
        expect(auth.currentUser, isNull);
        expect(auth.hasServerSession, isFalse);
      }
      expect(requests, 0);
      expect(writes, 0);
    },
  );

  test(
    'missing or mismatched Apple nonce cannot reach server sign-in',
    () async {
      final cases = <Map<String, String>>[
        {
          'id_token': _identityToken({'sub': 'test-user', 'nonce': 'expected'}),
        },
        {
          'id_token': _identityToken({'sub': 'test-user'}),
          'expected_nonce': 'expected',
        },
        {
          'id_token': _identityToken({'sub': 'test-user', 'nonce': 'other'}),
          'expected_nonce': 'expected',
        },
        {'id_token': 'malformed-token', 'expected_nonce': 'expected'},
        {'expected_nonce': 'expected'},
      ];
      var requests = 0;
      var writes = 0;
      for (final params in cases) {
        final auth = AuthService.forTesting(
          writeSession: (_) async => writes++,
        );
        final result = await http.runWithClient(
          () => auth.completeWebSignIn({'provider': 'apple', ...params}),
          () => MockClient((_) async {
            requests++;
            return http.Response('{}', 503);
          }),
        );
        expect(result, isFalse);
        expect(auth.lastFailure, AuthFailure.webNonce);
        expect(auth.currentUser, isNull);
        expect(auth.hasServerSession, isFalse);
      }
      expect(requests, 0);
      expect(writes, 0);
    },
  );

  test(
    'matching nonce still requires the server to verify Apple identity',
    () async {
      var requests = 0;
      var writes = 0;
      final auth = AuthService.forTesting(writeSession: (_) async => writes++);
      final result = await http.runWithClient(
        () => auth.completeWebSignIn({
          'provider': 'apple',
          'id_token': _identityToken({'sub': 'test-user', 'nonce': 'expected'}),
          'expected_nonce': 'expected',
          'code': 'test-code',
        }),
        () => MockClient((request) async {
          requests++;
          expect(request.url.path, '/api/auth/session');
          expect(jsonDecode(request.body)['provider'], 'apple');
          return http.Response('{}', 401);
        }),
      );
      expect(result, isFalse);
      expect(auth.lastFailure, AuthFailure.credential);
      expect(auth.hasServerSession, isFalse);
      expect(auth.currentUser, isNull);
      expect(requests, 1);
      expect(writes, 0);
    },
  );
}
