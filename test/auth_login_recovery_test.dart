import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const token = 'verified-server-token';
  const diagnostic = '8d0599f3-4bab-4d2d-b224-f38ab4329275';
  final user = UserProfile(
    id: 'google_123',
    name: 'Test',
    email: '',
    provider: AuthProviderType.google,
    createdAt: DateTime(2026),
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  Future<bool> login(
    AuthService auth, {
    int status = 200,
    String? id,
    DateTime? expiry,
  }) => http.runWithClient(
    () => auth.completeSignInForTesting(user, 'provider-token'),
    () => MockClient(
      (request) async => http.Response(
        jsonEncode({
          'user': {...user.toMap(), 'id': ?id},
          'token': token,
          'expiresAt': (expiry ?? DateTime.now().add(const Duration(days: 30)))
              .toIso8601String(),
        }),
        status,
        headers: {'x-auth-diagnostic-id': diagnostic},
      ),
    ),
  );
  test(
    'broken keystore preserves verified login in memory, without writing token to preferences',
    () async {
      final auth = AuthService.forTesting(
        writeSession: (_) async =>
            throw PlatformException(code: 'storage_error'),
      );
      var notified = false;
      auth.addListener(() => notified = true);
      expect(await login(auth), isTrue);
      expect(auth.currentUser?.id, user.id);
      expect(auth.hasServerSession, isTrue);
      expect(auth.serverHeaders['authorization'], 'Bearer $token');
      expect(auth.sessionIsTemporary, isTrue);
      expect(auth.lastFailure, isNull);
      expect(notified, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_user_profile'), isNotNull);
      for (final key in prefs.getKeys()) {
        expect(prefs.get(key).toString(), isNot(contains(token)));
        expect(prefs.get(key).toString(), isNot(contains('provider-token')));
      }
      // A temporary login never becomes an unverified cached login after restart.
      final restarted = AuthService.forTesting(writeSession: (_) async {});
      await restarted.init();
      expect(restarted.currentUser, isNull);
      expect(restarted.hasServerSession, isFalse);
    },
  );
  test(
    'healthy secure storage persists login and sign out removes memory session',
    () async {
      Map<String, dynamic>? saved;
      final auth = AuthService.forTesting(
        writeSession: (session) async => saved = session,
      );
      expect(await login(auth), isTrue);
      expect(saved?['token'], token);
      expect(auth.sessionIsTemporary, isFalse);
      await http.runWithClient(
        () => auth.signOut(),
        () => MockClient((_) async => http.Response('{}', 200)),
      );
      expect(auth.hasServerSession, isFalse);
      expect(auth.currentUser, isNull);
    },
  );
  test('a hung keystore cannot hold the verified login indefinitely', () async {
    final pendingWrite = Completer<void>();
    final auth = AuthService.forTesting(
      writeSession: (_) => pendingWrite.future,
    );
    expect(await login(auth), isTrue);
    expect(auth.hasServerSession, isTrue);
    expect(auth.sessionIsTemporary, isTrue);
    pendingWrite.complete();
  });
  test(
    'server rejections retain diagnostic code and cannot create local login',
    () async {
      for (final entry in {
        401: AuthFailure.credential,
        403: AuthFailure.appKey,
        503: AuthFailure.server,
      }.entries) {
        var writes = 0;
        final auth = AuthService.forTesting(
          writeSession: (_) async {
            writes++;
          },
        );
        expect(await login(auth, status: entry.key), isFalse);
        expect(auth.lastFailure, entry.value);
        expect(auth.lastDiagnosticId, diagnostic);
        expect(auth.currentUser, isNull);
        expect(writes, 0);
      }
    },
  );
  test(
    'wrong account or expired server session cannot use memory fallback',
    () async {
      var writes = 0;
      final auth = AuthService.forTesting(
        writeSession: (_) async {
          writes++;
        },
      );
      expect(await login(auth, id: 'google_other'), isFalse);
      expect(await login(auth, expiry: DateTime(2020)), isFalse);
      expect(auth.lastFailure, AuthFailure.response);
      expect(auth.hasServerSession, isFalse);
      expect(writes, 0);
    },
  );
  test('web Google resolves the same provider account on the server', () async {
    Map<String, dynamic>? sent;
    final auth = AuthService.forTesting(writeSession: (_) async {});
    final success = await http.runWithClient(
      () => auth.signInWithGoogleWeb(() async => 'google-access-token'),
      () => MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'user': user.toMap(),
            'token': token,
            'expiresAt': DateTime.now()
                .add(const Duration(days: 30))
                .toIso8601String(),
          }),
          200,
        );
      }),
    );
    expect(success, isTrue);
    expect(sent?['provider'], 'google');
    expect(sent?['credential'], 'google-access-token');
    expect(sent?.containsKey('userId'), isFalse);
    expect(auth.currentUser?.id, user.id);
  });
  test(
    'Google web cancellation and foreign server accounts create no session',
    () async {
      final auth = AuthService.forTesting(writeSession: (_) async {});
      expect(
        await auth.signInWithGoogleWeb(
          () => throw PlatformException(code: 'sign_in_cancelled'),
        ),
        isFalse,
      );
      expect(auth.lastFailure, AuthFailure.cancelled);
      for (final id in ['apple_123', 'google_']) {
        expect(
          await http.runWithClient(
            () => auth.signInWithGoogleWebToken('google-access-token'),
            () => MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'user': {...user.toMap(), 'id': id},
                  'token': token,
                  'expiresAt': DateTime.now()
                      .add(const Duration(days: 30))
                      .toIso8601String(),
                }),
                200,
              ),
            ),
          ),
          isFalse,
        );
        expect(auth.hasServerSession, isFalse);
      }
    },
  );
}
