import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/question_report_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final user = UserProfile(
    id: 'google_reporter',
    name: 'Reporter Name',
    email: 'reporter@example.com',
    provider: AuthProviderType.google,
    createdAt: DateTime.utc(2026),
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/device_info'),
          (_) async => {
            'name': 'iPhone',
            'systemName': 'iOS',
            'systemVersion': '18.0',
            'model': 'iPhone',
            'modelName': 'iPhone 15 Pro',
            'localizedModel': 'iPhone',
            'isPhysicalDevice': true,
            'isiOSAppOnMac': false,
            'isiOSAppOnVision': false,
            'freeDiskSize': 1000,
            'totalDiskSize': 2000,
            'physicalRamSize': 8000,
            'availableRamSize': 4000,
            'utsname': {
              'sysname': 'Darwin',
              'nodename': 'test',
              'release': '24.0',
              'version': 'test',
              'machine': 'iPhone16,1',
            },
          },
        );
    SharedPreferences.setMockInitialValues({'install_id': 'reporter-install'});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'ru.pdd.pddApp',
      version: '2.3.0',
      buildNumber: '59',
      buildSignature: '',
      installerStore: 'com.apple.appstore',
    );
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<http.Request> send(AuthService auth) async {
    http.Request? sent;
    final success = await http.runWithClient(
      () => QuestionReportService.send(
        message: '  Ошибка в вопросе  ',
        questionId: 'question-21-3',
        questionText: 'Продолжить буксировку можно?',
        ticketNumber: 21,
        category: 'cd',
        auth: auth,
      ),
      () => MockClient((request) async {
        sent = request;
        return http.Response('{}', 200);
      }),
    );
    expect(success, isTrue);
    expect(sent?.url, Uri.parse(BackendConfig.notifierUrl));
    expect(sent?.headers['content-type'], 'application/json');
    expect(
      sent?.headers['x-install-secret'],
      BackendConfig.notifierSecret.isEmpty
          ? isNull
          : BackendConfig.notifierSecret,
    );
    final payload = jsonDecode(sent!.body) as Map<String, dynamic>;
    expect(payload['kind'], 'report');
    expect(payload['source'], 'training');
    expect(payload['message'], 'Ошибка в вопросе');
    expect(payload['question_id'], 'question-21-3');
    expect(payload['category'], 'cd');
    expect(payload['install_id'], 'reporter-install');
    expect(payload['device'], 'iPhone16,1');
    expect(payload['os'], 'iOS 18.0');
    // Личные данные берутся только из подтверждённого сервером аккаунта.
    expect(sent!.body, isNot(contains(user.id)));
    expect(sent!.body, isNot(contains(user.name)));
    expect(sent!.body, isNot(contains(user.email)));
    return sent!;
  }

  test('a guest can submit a report without authorization', () async {
    final auth = AuthService.forTesting(writeSession: (_) async {});
    addTearDown(auth.dispose);
    final request = await send(auth);
    expect(request.headers, isNot(contains('authorization')));
  });

  test('a signed-in report uses the verified server session', () async {
    final auth = AuthService.forTesting(writeSession: (_) async {});
    addTearDown(auth.dispose);
    await auth.completeServerSession(
      user: user,
      token: 'verified-server-session',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );

    final request = await send(auth);
    expect(request.headers['authorization'], 'Bearer verified-server-session');
    expect(request.body, isNot(contains('verified-server-session')));
  });

  test('an expired session is omitted while the report still sends', () async {
    final auth = AuthService.forTesting(writeSession: (_) async {});
    addTearDown(auth.dispose);
    await auth.completeServerSession(
      user: user,
      token: 'expired-server-session',
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );

    final request = await send(auth);
    expect(request.headers, isNot(contains('authorization')));
    expect(request.body, isNot(contains('expired-server-session')));
  });

  test(
    'game reports keep scene, question, device and verified session',
    () async {
      final auth = AuthService.forTesting(writeSession: (_) async {});
      addTearDown(auth.dispose);
      await auth.completeServerSession(
        user: user,
        token: 'game-session',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      await http.runWithClient(
        () async {
          for (final id in ['ticket_8_15', 'ticket_cd_8_15']) {
            expect(
              await QuestionReportService.sendGameReport({
                'question_id': id,
                'question_text': 'Кому уступить дорогу?',
                'message': '  Машина едет неверно  ',
                'email': 'forged@example.com',
                'device': 'forged device',
              }, auth: auth),
              isTrue,
            );
          }
        },
        () => MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          expect(body['question_id'], startsWith('ticket_'));
          expect(body['ticket'], 8);
          expect(body['question_text'], 'Кому уступить дорогу?');
          expect(body['mode'], 'city');
          expect(body['source'], 'game');
          expect(body['message'], 'Машина едет неверно');
          expect(body['device'], 'iPhone16,1');
          expect(body['os'], 'iOS 18.0');
          expect(body, isNot(contains('email')));
          expect(request.headers['authorization'], 'Bearer game-session');
          expect(request.body, isNot(contains('game-session')));
          return http.Response('{}', 200);
        }),
      );
    },
  );

  test('invalid game data and empty reports never issue a request', () async {
    await http.runWithClient(() async {
      for (final report in <Map<String, dynamic>>[
        {},
        {'question_id': 8, 'message': 'bug'},
        {'question_id': 'ticket_8_15'},
        {'question_id': 'ticket_8_15', 'message': '   '},
      ]) {
        expect(await QuestionReportService.sendGameReport(report), isFalse);
      }
    }, () => MockClient((_) async => fail('Unexpected report request')));
  });

  test('game reports expose network and server failures for retry', () async {
    for (final status in [429, 500]) {
      await http.runWithClient(() async {
        expect(
          await QuestionReportService.sendGameReport({
            'question_id': 'ticket_8_15',
            'message': 'Ошибка',
          }),
          isFalse,
        );
      }, () => MockClient((_) async => http.Response('{}', status)));
    }
    await http.runWithClient(() async {
      expect(
        await QuestionReportService.sendGameReport({
          'question_id': 'ticket_8_15',
          'message': 'Ошибка',
        }),
        isFalse,
      );
    }, () => MockClient((_) async => throw http.ClientException('Offline')));
  });
}
