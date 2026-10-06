import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'ru.pdd.pddApp',
      version: '2.1.4',
      buildNumber: '51',
      buildSignature: '',
      installerStore: 'com.apple.appstore',
    );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'fresh launch stays new after startup services write settings',
    () async {
      SharedPreferences.setMockInitialValues({});
      await InstallReporter.captureLaunchState();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('startup_setting', true);
      Map<String, dynamic>? payload;
      await http.runWithClient(
        () => InstallReporter.reportIfNeeded(),
        () => MockClient((request) async {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        }),
      );
      expect(payload?['kind'], 'new');
      expect(payload?['source'], 'App Store');
      expect(payload?['install_id'], isNotEmpty);
      expect(prefs.getBool('install_reported'), isTrue);
    },
  );

  test('existing progress without an old report sends update once', () async {
    SharedPreferences.setMockInitialValues({
      'progress': 'saved',
      'install_id': 'existing-id',
    });
    await InstallReporter.captureLaunchState();
    var requests = 0;
    await http.runWithClient(
      () async {
        await InstallReporter.reportIfNeeded();
        await InstallReporter.captureLaunchState();
        await InstallReporter.reportIfNeeded();
      },
      () => MockClient((request) async {
        requests++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['kind'], 'update');
        expect(body['install_id'], 'existing-id');
        return http.Response('{}', 200);
      }),
    );
    expect(requests, 1);
  });

  test(
    'an already reported installation does not report after app update',
    () async {
      SharedPreferences.setMockInitialValues({
        'install_reported': true,
        'install_id': 'old-id',
        'progress': 'saved',
      });
      await InstallReporter.captureLaunchState();
      await http.runWithClient(
        () => InstallReporter.reportIfNeeded(),
        () => MockClient((_) async {
          fail('an application update must not submit another installation');
        }),
      );
    },
  );

  test(
    'failed first report retries the same ID and launch classification',
    () async {
      SharedPreferences.setMockInitialValues({});
      await InstallReporter.captureLaunchState();
      final bodies = <Map<String, dynamic>>[];
      await http.runWithClient(
        () async {
          await InstallReporter.reportIfNeeded();
          await InstallReporter.reportIfNeeded();
        },
        () => MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', bodies.length == 1 ? 503 : 200);
        }),
      );
      expect(bodies.length, 2);
      expect(bodies[0]['install_id'], bodies[1]['install_id']);
      expect(bodies.map((b) => b['kind']), ['new', 'new']);
    },
  );
}
