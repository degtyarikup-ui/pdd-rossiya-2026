import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/presentation/widgets/auth_provider_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserProfile profile(
  String id, [
  AuthProviderType provider = AuthProviderType.google,
]) => UserProfile(
  id: '${provider.name}_$id',
  name: 'Test',
  email: '',
  provider: provider,
  createdAt: DateTime(2026),
);
http.Response session(UserProfile user) => http.Response(
  jsonEncode({
    'user': user.toMap(),
    'token': 'session-${user.id}',
    'expiresAt': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotifierRoute.reset();
  });
  ErrorReporter reporter(List<Map<String, dynamic>> events) => ErrorReporter(
    endpoint: 'https://diagnostics.invalid',
    secret: 'test',
    metadata: () async => {},
    headers: () => {},
    userId: () => null,
    client: MockClient((request) async {
      events.addAll(
        (jsonDecode(request.body)['events'] as List)
            .cast<Map<String, dynamic>>(),
      );
      return http.Response('{}', 200);
    }),
  );

  test(
    'a second sign-in cannot borrow or overwrite the first attempt diagnostics',
    () async {
      final events = <Map<String, dynamic>>[], calls = <String>[];
      final reports = reporter(events);
      final auth = AuthService.forTesting(
        writeSession: (_) async {},
        errorReporter: reports,
      );
      final third = Completer<void>(), release = Completer<void>();
      await http.runWithClient(
        () async {
          final first = auth.signInWithGoogleWeb(() async => 'google-token');
          await third.future;
          expect(
            await auth.completeSignInForTesting(
              profile('other', AuthProviderType.yandex),
              'yandex-token',
            ),
            false,
          );
          expect(
            await auth.signInWithGoogleWeb(
              () => throw StateError('must not open another SDK'),
            ),
            false,
          );
          release.complete();
          expect(await first, false);
          await reports.flush();
        },
        () => MockClient((request) async {
          calls.add(jsonDecode(request.body)['provider'] as String);
          if (calls.length == 3) {
            third.complete();
            await release.future;
          }
          throw TimeoutException('test transport');
        }),
      );
      expect(calls, ['google', 'google', 'google']);
      expect(events, hasLength(1));
      expect(events.single['provider'], 'google');
      expect(events.single['operation'], 'auth.session');
      expect(events.single['code'], 'timeout:3x');
    },
  );

  test(
    'cancelled network result cannot create a session or send a failure alert',
    () async {
      final events = <Map<String, dynamic>>[],
          persisted = <Map<String, dynamic>>[];
      final reports = reporter(events),
          started = Completer<void>(),
          release = Completer<void>();
      final auth = AuthService.forTesting(
        writeSession: (value) async => persisted.add(value),
        errorReporter: reports,
      );
      var calls = 0;
      await http.runWithClient(
        () async {
          final login = auth.signInWithGoogleWebToken('token');
          await started.future;
          auth.cancelSignIn(auth.activeSignInId);
          expect(await login, false);
          expect(auth.isSigningIn, false);
          release.complete();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await reports.flush();
        },
        () => MockClient((_) async {
          calls++;
          started.complete();
          await release.future;
          return session(profile('late'));
        }),
      );
      expect(calls, 1);
      expect(events, isEmpty);
      expect(persisted, isEmpty);
      expect(auth.currentUser, isNull);
      expect(auth.hasServerSession, false);
    },
  );

  test(
    'late storage completion is rolled back before the next account is persisted',
    () async {
      Map<String, dynamic>? stored;
      final writes = <String>[],
          firstWrite = Completer<void>(),
          release = Completer<void>();
      final auth = AuthService.forTesting(
        writeSession: (value) async {
          writes.add(value['userId'] as String);
          if (value['userId'] == 'google_first') {
            firstWrite.complete();
            await release.future;
          }
          stored = value;
        },
        clearSession: () async {
          writes.add('clear');
          stored = null;
        },
      );
      await http.runWithClient(
        () async {
          final first = auth.completeSignInForTesting(
            profile('first'),
            'first-token',
          );
          await firstWrite.future;
          final oldId = auth.activeSignInId;
          auth.cancelSignIn(oldId);
          expect(await first, false);
          final second = auth.completeSignInForTesting(
            profile('second'),
            'second-token',
          );
          // A disposed old sheet must not cancel the newer account's attempt.
          auth.cancelSignIn(oldId);
          release.complete();
          expect(await second, true);
        },
        () => MockClient(
          (request) async => session(
            profile(
              jsonDecode(request.body)['credential'] == 'first-token'
                  ? 'first'
                  : 'second',
            ),
          ),
        ),
      );
      expect(writes, ['google_first', 'clear', 'google_second']);
      expect(stored?['userId'], 'google_second');
      expect(auth.currentUser?.id, 'google_second');
      expect(
        auth.serverHeaders['authorization'],
        'Bearer session-google_second',
      );
    },
  );

  test(
    'sign out while a write is pending cannot revive the old account',
    () async {
      Map<String, dynamic>? stored;
      final started = Completer<void>(), release = Completer<void>();
      final auth = AuthService.forTesting(
        writeSession: (value) async {
          started.complete();
          await release.future;
          stored = value;
        },
        clearSession: () async {
          stored = null;
        },
      );
      await http.runWithClient(() async {
        final login = auth.completeSignInForTesting(profile('old'), 'token');
        await started.future;
        final logout = auth.signOut();
        expect(await login, false);
        release.complete();
        await logout;
      }, () => MockClient((_) async => session(profile('old'))));
      expect(stored, isNull);
      expect(auth.currentUser, isNull);
      expect(auth.hasServerSession, false);
    },
  );

  test(
    'a timed-out old secure write cannot persist over the newer memory session',
    () async {
      Map<String, dynamic>? stored;
      final release = Completer<void>();
      final auth = AuthService.forTesting(
        writeSession: (value) async {
          if (value['userId'] == 'google_first') await release.future;
          stored = value;
        },
        clearSession: () async {
          stored = null;
        },
      );
      await http.runWithClient(
        () async {
          expect(
            await auth.completeSignInForTesting(profile('first'), 'first'),
            true,
          );
          expect(auth.sessionIsTemporary, true);
          expect(
            await auth.completeSignInForTesting(profile('newer'), 'newer'),
            true,
          );
          expect(auth.currentUser?.id, 'google_newer');
          expect(auth.sessionIsTemporary, true);
          release.complete();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        },
        () => MockClient(
          (request) async => session(
            profile(jsonDecode(request.body)['credential'] as String),
          ),
        ),
      );
      expect(stored?['userId'], 'google_newer');
      expect(auth.currentUser?.id, 'google_newer');
    },
  );

  test(
    'cancelling a replacement login restores the existing account instead of logging it out',
    () async {
      Map<String, dynamic>? stored;
      final replacementStarted = Completer<void>(), release = Completer<void>();
      final auth = AuthService.forTesting(
        writeSession: (value) async {
          if (value['userId'] == 'google_replacement') {
            replacementStarted.complete();
            await release.future;
          }
          stored = value;
        },
        clearSession: () async {
          stored = null;
        },
      );
      await http.runWithClient(
        () async {
          expect(
            await auth.completeSignInForTesting(
              profile('existing'),
              'existing',
            ),
            true,
          );
          final revision = auth.accountRevision;
          final pending = auth.completeSignInForTesting(
            profile('replacement'),
            'replacement',
          );
          await replacementStarted.future;
          auth.cancelSignIn(auth.activeSignInId);
          expect(await pending, false);
          release.complete();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(auth.accountRevision, revision);
        },
        () => MockClient(
          (request) async => session(
            profile(jsonDecode(request.body)['credential'] as String),
          ),
        ),
      );
      expect(auth.currentUser?.id, 'google_existing');
      expect(
        auth.serverHeaders['authorization'],
        'Bearer session-google_existing',
      );
      expect(stored?['userId'], 'google_existing');
    },
  );

  test(
    'account deletion cancels a pending same-account refresh and blocks fresh login until cleanup',
    () async {
      Map<String, dynamic>? stored;
      final refreshStarted = Completer<void>(),
          refreshResponse = Completer<http.Response>();
      final deletionStarted = Completer<void>(),
          deletionResponse = Completer<http.Response>();
      var sessions = 0;
      final auth = AuthService.forTesting(
        writeSession: (value) async {
          stored = value;
        },
        clearSession: () async {
          stored = null;
        },
      );
      await http.runWithClient(
        () async {
          expect(
            await auth.completeSignInForTesting(profile('same'), 'initial'),
            true,
          );
          final refresh = auth.completeSignInForTesting(
            profile('same'),
            'refresh',
          );
          await refreshStarted.future;
          final deletion = auth.deleteAccount();
          await deletionStarted.future;
          expect(await refresh, false);
          expect(
            await auth.completeSignInForTesting(profile('same'), 'blocked'),
            false,
          );
          expect(sessions, 2);
          deletionResponse.complete(
            http.Response(
              jsonEncode({'ok': true, 'deleted': 'google_same'}),
              200,
            ),
          );
          expect(await deletion, true);
          refreshResponse.complete(session(profile('same')));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/user/delete') {
            deletionStarted.complete();
            return deletionResponse.future;
          }
          if (request.url.path == '/api/auth/logout') {
            return http.Response('{}', 200);
          }
          sessions++;
          if (sessions == 1) return session(profile('same'));
          refreshStarted.complete();
          return refreshResponse.future;
        }),
      );
      expect(auth.currentUser, isNull);
      expect(auth.hasServerSession, false);
      expect(stored, isNull);
    },
  );

  test(
    'failed account deletion preserves its session and revision and releases the login guard',
    () async {
      final auth = AuthService.forTesting(
        writeSession: (_) async {},
        clearSession: () async {},
      );
      await http.runWithClient(
        () async {
          expect(
            await auth.completeSignInForTesting(profile('kept'), 'token'),
            true,
          );
          final revision = auth.accountRevision;
          expect(await auth.deleteAccount(), false);
          expect(auth.accountRevision, revision);
          expect(auth.currentUser?.id, 'google_kept');
          expect(auth.hasServerSession, true);
          expect(auth.isSigningIn, false);
        },
        () => MockClient(
          (request) async => request.url.path == '/api/user/delete'
              ? http.Response('{}', 503)
              : session(profile('kept')),
        ),
      );
    },
  );

  test(
    'Yandex callback exchanges only the credential; account fields come from the verified server response',
    () async {
      final requests = <http.Request>[],
          expected = profile('verified', AuthProviderType.yandex);
      final auth = AuthService.forTesting(writeSession: (_) async {});
      final success = await http.runWithClient(
        () => auth.completeWebSignIn({
          'provider': 'yandex',
          'access_token': 'yandex-token',
          'id': 'untrusted',
          'name': 'untrusted',
        }),
        () => MockClient((request) async {
          requests.add(request);
          return session(expected);
        }),
      );
      expect(success, true);
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/api/auth/session');
      expect(requests.single.url.host, isNot('login.yandex.ru'));
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['provider'], 'yandex');
      expect(body['credential'], 'yandex-token');
      expect(body.containsKey('userId'), false);
      expect(body.containsKey('name'), false);
      expect(auth.currentUser?.id, expected.id);
      expect(auth.currentUser?.name, expected.name);
    },
  );

  testWidgets(
    'closing and reopening a sheet cannot start another SDK until the callback or bounded hold',
    (tester) async {
      final provider = Completer<String>();
      final auth = (await tester.runAsync(
        () async => AuthService.forTesting(writeSession: (_) async {}),
      ))!;
      var sdkCalls = 0;
      Future<bool> action() => http.runWithClient(
        () => auth.signInWithGoogleWeb(() {
          sdkCalls++;
          return provider.future;
        }),
        () => MockClient(
          (_) async =>
              throw StateError('cancelled SDK must never exchange its token'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      AuthModalSheet(authService: auth, initialAction: action),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(sdkCalls, 1);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(auth.isSigningIn, true);
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(sdkCalls, 1);
      for (final button in tester.widgetList<AuthProviderButton>(
        find.byType(AuthProviderButton),
      )) {
        expect(button.onTap, isNull);
      }
      await tester.pump(const Duration(seconds: 16));
      expect(auth.isSigningIn, false);
      final loggedIn = await tester.runAsync(
        () => http.runWithClient(
          () => auth.completeSignInForTesting(profile('newest'), 'newest'),
          () => MockClient((_) async => session(profile('newest'))),
        ),
      );
      expect(loggedIn, true);
      provider.complete('late-old-credential');
      await tester.pump();
      expect(auth.currentUser?.id, 'google_newest');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'iOS Yandex SDK token goes directly to verified server exchange without client profile request',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        const channel = MethodChannel('pdd/yandex_auth');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => 'native-yandex-token',
        );
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox())),
        );
        final context = tester.element(find.byType(Scaffold));
        final calls = <http.Request>[];
        final auth = (await tester.runAsync(
          () async => AuthService.forTesting(writeSession: (_) async {}),
        ))!;
        final success = await tester.runAsync(
          () => http.runWithClient(
            () => auth.signInWithYandex(context),
            () => MockClient((request) async {
              calls.add(request);
              return session(profile('native', AuthProviderType.yandex));
            }),
          ),
        );
        expect(success, true);
        expect(calls, hasLength(1));
        expect(calls.single.url.path, '/api/auth/session');
        expect(
          jsonDecode(calls.single.body)['credential'],
          'native-yandex-token',
        );
        expect(auth.currentUser?.id, 'yandex_native');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
