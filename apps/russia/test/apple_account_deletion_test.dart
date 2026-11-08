import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
    'Apple deletion distinguishes revoked, manual legacy and queued provider outage',
    () async {
      for (final state in ['manual_required', 'pending', 'revoked']) {
        final auth = AuthService.forTesting(writeSession: (_) async {});
        final user = UserProfile(
          id: 'apple_legacy',
          name: 'Test',
          email: '',
          provider: AuthProviderType.apple,
          createdAt: DateTime(2026),
        );
        var deletions = 0;
        await http.runWithClient(
          () async {
            expect(
              await auth.completeSignInForTesting(user, 'credential'),
              isTrue,
            );
            expect(await auth.deleteAccount(), isTrue);
            expect(auth.currentUser, isNull);
            expect(auth.hasServerSession, isFalse);
            expect(auth.appleRevocationPending, state == 'pending');
            expect(
              auth.appleManualRevocationUrl?.toString(),
              state == 'manual_required'
                  ? 'https://account.apple.com/account/manage'
                  : isNull,
            );
            expect(deletions, 1);
          },
          () => MockClient((request) async {
            if (request.url.path == '/api/auth/session') {
              return http.Response(
                jsonEncode({
                  'user': user.toMap(),
                  'token': 'session',
                  'expiresAt': DateTime.now()
                      .add(const Duration(days: 1))
                      .toIso8601String(),
                }),
                200,
              );
            }
            if (request.url.path == '/api/user/delete') {
              deletions++;
              expect(request.headers['authorization'], 'Bearer session');
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'deleted': user.id,
                  'appleRevocation': state,
                  'appleManageUrl': 'https://untrusted.invalid',
                }),
                200,
              );
            }
            return http.Response('{"ok":true,"isPremium":false}', 200);
          }),
        );
        auth.dispose();
      }
    },
  );
}
