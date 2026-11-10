import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserProfile profile(String id) => UserProfile(
  id: 'google_$id',
  name: 'Test',
  email: '',
  provider: AuthProviderType.google,
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
    'after a lost connection the chosen account signs in without opening the provider again',
    () async {
      final events = <Map<String, dynamic>>[],
          bodies = <Map<String, dynamic>>[];
      final reports = reporter(events);
      final auth = AuthService.forTesting(
        writeSession: (_) async {},
        errorReporter: reports,
      );
      var online = false, providerWindows = 0;
      await http.runWithClient(
        () async {
          expect(auth.canRetrySignIn, false);
          expect(
            await auth.signInWithGoogleWeb(() async {
              providerWindows++;
              return 'google-token';
            }),
            false,
          );
          expect(auth.lastFailure, AuthFailure.network);
          expect(auth.canRetrySignIn, true);
          expect(auth.isAuthenticated, false);

          // Still offline: the confirmation is kept for another try.
          expect(await auth.retrySignIn(), false);
          expect(auth.canRetrySignIn, true);

          online = true;
          expect(await auth.retrySignIn(), true);
          expect(auth.currentUser?.id, 'google_one');
          expect(auth.canRetrySignIn, false);
          expect(await auth.retrySignIn(), false, reason: 'nothing left');
          await reports.flush();
        },
        () => MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (!online) throw http.ClientException('offline');
          return session(profile('one'));
        }),
      );
      expect(providerWindows, 1);
      expect(bodies.map((body) => body['credential']).toSet(), {
        'google-token',
      });
      expect(bodies.map((body) => body['provider']).toSet(), {'google'});
      // The failures were reported; the eventual success is not an error.
      expect(events.map((event) => event['code']).toSet(), {'network:3x'});
    },
  );

  test(
    'a kept confirmation never survives a refusal, another attempt, a closed screen or its deadline',
    () async {
      final auth = AuthService.forTesting(writeSession: (_) async {});
      Future<bool> fail(Object Function() answer, [String token = 'token']) =>
          http.runWithClient(
            () => auth.signInWithGoogleWebToken(token),
            () => MockClient((_) async {
              final result = answer();
              if (result is http.Response) return result;
              throw result;
            }),
          );
      Object offline() => http.ClientException('offline');

      // A server answer is final: only a connection failure can be retried.
      expect(await fail(() => http.Response('{}', 401)), false);
      expect(auth.lastFailure, AuthFailure.credential);
      expect(auth.canRetrySignIn, false);
      expect(await fail(() => http.Response('{}', 403)), false);
      expect(auth.canRetrySignIn, false);

      expect(await fail(offline), false);
      expect(auth.canRetrySignIn, true);
      auth.discardSignInRetry();
      expect(auth.canRetrySignIn, false);

      // Starting any other sign-in replaces what could be retried.
      expect(await fail(offline, 'first'), false);
      expect(auth.canRetrySignIn, true);
      expect(await fail(() => http.Response('{}', 401), 'second'), false);
      expect(auth.canRetrySignIn, false);

      expect(await fail(offline), false);
      await auth.signOut();
      expect(auth.canRetrySignIn, false);
      expect(
        AuthService.retryWindow,
        lessThanOrEqualTo(const Duration(minutes: 5)),
      );
    },
  );

  test(
    'a system sign-in window left open ends like a closed window, without an error report',
    () async {
      final events = <Map<String, dynamic>>[];
      final reports = reporter(events);
      final auth = AuthService.forTesting(
        writeSession: (_) async {},
        errorReporter: reports,
      );
      final window = Completer<String>();
      final limit = AuthService.browserWindowLimit;
      AuthService.browserWindowLimit = const Duration(milliseconds: 50);
      addTearDown(() => AuthService.browserWindowLimit = limit);
      final signIn = http.runWithClient(
        () => auth.signInWithGoogleWeb(() => window.future),
        () => MockClient(
          (_) async => throw StateError('an unfinished window sends nothing'),
        ),
      );
      expect(await signIn, false);
      expect(auth.lastFailure, AuthFailure.cancelled);
      expect(auth.isSigningIn, false);
      expect(auth.canRetrySignIn, false);
      await reports.flush();
      expect(events, isEmpty);
      expect(
        AuthService.interactiveWindowLimit,
        greaterThanOrEqualTo(const Duration(minutes: 5)),
        reason: 'adding an account to the phone takes several minutes',
      );
      window.complete('late');
    },
  );

  testWidgets(
    'the sign-in sheet offers one-tap retry only after a lost connection',
    (tester) async {
      final auth = (await tester.runAsync(
        () async => AuthService.forTesting(writeSession: (_) async {}),
      ))!;
      var online = false, providerWindows = 0;
      Future<T> network<T>(Future<T> Function() body) => http.runWithClient(
        body,
        () => MockClient((_) async {
          if (!online) throw http.ClientException('offline');
          return session(profile('one'));
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ru'),
          home: Scaffold(
            body: AuthModalSheet(
              authService: auth,
              embedded: true,
              initialAction: () => network(
                () => auth.signInWithGoogleWeb(() async {
                  providerWindows++;
                  return 'google-token';
                }),
              ),
            ),
          ),
        ),
      );
      final retry = find.byKey(const ValueKey('auth-retry-button'));
      expect(retry, findsNothing);
      // Three attempts with one-second pauses between them.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text(appL10n.authErrorNetwork), findsOneWidget);
      expect(retry, findsOneWidget);
      expect(find.text(appL10n.authRetry), findsOneWidget);

      online = true;
      await network(() async {
        await tester.tap(retry);
        // Under fake time the platform lookups of a sign-in run into their
        // own limits (2 s metadata, 5 s storage) before the session is accepted.
        for (var i = 0; i < 9; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
      });
      expect(auth.currentUser?.id, 'google_one');
      expect(providerWindows, 1);
      expect(retry, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 7));
    },
  );
}
