import 'dart:async';
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
  test(
    'restored login completes while the premium server is still pending',
    () async {
      final user = UserProfile(
        id: 'apple_test',
        name: 'Test',
        email: '',
        provider: AuthProviderType.apple,
        createdAt: DateTime(2026),
      );
      SharedPreferences.setMockInitialValues({
        'auth_user_profile': user.toJson(),
      });
      FlutterSecureStorage.setMockInitialValues({
        'pdd_server_session': jsonEncode({
          'userId': user.id,
          'token': 'verified-session',
          'expiresAt': DateTime.now()
              .add(const Duration(days: 30))
              .toIso8601String(),
        }),
      });
      final requestStarted = Completer<void>();
      final server = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await AuthService.instance.init().timeout(const Duration(seconds: 2));
          expect(AuthService.instance.currentUser?.id, user.id);
          expect(AuthService.instance.hasServerSession, isTrue);
          await requestStarted.future.timeout(const Duration(seconds: 3));
          expect(server.isCompleted, isFalse);
          server.complete(http.Response('{}', 200));
        },
        () => MockClient((request) {
          expect(request.url.path, '/api/user/sync');
          expect(request.headers['authorization'], 'Bearer verified-session');
          if (!requestStarted.isCompleted) requestStarted.complete();
          return server.future;
        }),
      );
    },
  );
}
