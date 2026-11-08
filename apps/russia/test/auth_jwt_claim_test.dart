import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/auth_service.dart';

String _jwt(Map<String, Object?> payload) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part(payload)}.signature';
}

void main() {
  test(
    'Apple user id is read from the identity token (web has no userIdentifier)',
    () {
      final token = _jwt({'sub': '001234.abcdef.5678', 'email': 'a@b.ru'});
      expect(AuthService.jwtClaim(token, 'sub'), '001234.abcdef.5678');
      expect(AuthService.jwtClaim(token, 'email'), 'a@b.ru');
    },
  );

  test('Missing claim or broken token gives null, not an exception', () {
    expect(AuthService.jwtClaim(_jwt({'email': 'a@b.ru'}), 'sub'), isNull);
    expect(AuthService.jwtClaim(_jwt({'sub': 5}), 'sub'), isNull);
    expect(AuthService.jwtClaim('not-a-jwt', 'sub'), isNull);
    expect(AuthService.jwtClaim('a.%%%.c', 'sub'), isNull);
    expect(AuthService.jwtClaim(null, 'sub'), isNull);
    expect(AuthService.jwtClaim('', 'sub'), isNull);
  });
}
