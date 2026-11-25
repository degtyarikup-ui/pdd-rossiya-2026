import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/school_group_route.dart';
import 'package:pdd_app/data/services/web_oauth_state.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/main.dart' show PddApp;
import 'package:pdd_app/presentation/screens/school_group_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final token = '00000000-0000-0000-0000-000000000000:${'a' * 43}';
  test('restores only the invitation that started the provider flow', () {
    final now = DateTime.now(), state = 'a' * 64;
    final result = validateWebOAuthReturn(
      {'provider': 'apple', 'state': state, 'school_group': 'my'},
      {
        'provider': 'apple',
        'state': state,
        'startedAt': now.millisecondsSinceEpoch,
        'school_group': token,
      },
      now,
    );
    expect(result['school_group'], token);
    expect(
      SchoolGroupRoute.fromLink(
        Uri.https('schools.pdd-drive.app', '/join/$token/'),
      ),
      token,
    );
    expect(
      SchoolGroupRoute.fromLink(Uri.https('other.example', '/join/$token/')),
      isNull,
    );
    expect(SchoolGroupRoute.parse('ABCDE-FGHJK'), 'ABCDEFGHJK');
    for (final host in ['schools.pdd-drive.app', 'join.pdd-drive.app']) {
      expect(SchoolGroupRoute.fromLink(Uri.https(host, '/student/')), 'my');
      expect(SchoolGroupRoute.fromLink(Uri.https(host, '/join/my/')), 'my');
      expect(
        SchoolGroupRoute.fromLink(Uri.https(host, '/join/$token/')),
        token,
      );
    }
    expect(SchoolGroupRoute.fromLink(Uri.parse('/join/$token/')), token);
    expect(
      SchoolGroupRoute.fromLink(Uri.parse('//other.example/join/$token/')),
      isNull,
    );
  });

  testWidgets('keeps the system link until the main navigator is mounted', (
    tester,
  ) async {
    final pending = StartupSchoolInvite();
    final warm = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: const SizedBox(),
        onGenerateRoute: (settings) {
          warm.add(settings.name);
          return MaterialPageRoute<void>(builder: (_) => const SizedBox());
        },
      ),
    );
    Future<Object?> sendLink(String host) async {
      final result = Completer<Object?>();
      final codec = SystemChannels.navigation.codec;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.navigation.name,
        codec.encodeMethodCall(
          MethodCall('pushRouteInformation', {
            'location': Uri.https(host, '/join/$token/').toString(),
          }),
        ),
        (data) => result.complete(codec.decodeEnvelope(data!)),
      );
      return result.future;
    }

    expect(await sendLink('join.pdd-drive.app'), true);
    expect(warm, isEmpty);
    expect(pending.take(), token);
    expect(await sendLink('schools.pdd-drive.app'), true);
    expect(warm, ['/join/$token/']);
  });

  testWidgets('starts the application on the group and keeps a back route', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final progress = ProgressDataSource();
    await progress.init();
    final pending = StartupSchoolInvite();
    await pending.didPushRouteInformation(
      RouteInformation(
        uri: Uri.https('schools.pdd-drive.app', '/join/$token/'),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [progressDataSourceProvider.overrideWithValue(progress)],
        child: PddApp(startupInvite: pending),
      ),
    );
    await tester.pump();
    final screen = find.byType(SchoolGroupScreen);
    expect(tester.widget<SchoolGroupScreen>(screen).invite, token);
    expect(Navigator.of(tester.element(screen)).canPop(), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only confirms membership with consent and the version shown', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    updateAppLocale(const Locale('ru'));
    final auth = AuthService.instance;
    auth.setSessionForTesting(
      user: UserProfile(
        id: 'google_student',
        name: 'Анна',
        email: '',
        provider: AuthProviderType.google,
        createdAt: DateTime(2026),
      ),
      token: 'fixture',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    addTearDown(() => auth.setSessionForTesting());
    final group = {
      'id': 'g',
      'school': 'Вектор',
      'name': 'Вечерняя',
      'instructor': 'Ирина',
    };
    final actions = <String>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: SchoolGroupScreen(invite: token),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.widgetWithText(FilledButton, 'Вступить в группу');
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        expect(actions, ['preview']);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(actions, ['preview', 'join']);
        expect(find.text('Вы в группе'), findsOneWidget);
      },
      () => MockClient((r) async {
        final op = r.url.pathSegments.last;
        actions.add(op);
        final data = jsonDecode(r.body) as Map;
        if (op == 'join') {
          expect(data, {
            'invite': token,
            'name': 'Анна',
            'version': '0',
            'consentVersion': 'v',
          });
        }
        return http.Response(
          jsonEncode(
            op == 'preview'
                ? {
                    'group': group,
                    'current': null,
                    'version': '0',
                    'consentVersion': 'v',
                  }
                : {'current': group, 'version': '1:in'},
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  });
}
