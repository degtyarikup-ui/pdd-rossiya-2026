import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phones without Google Play services (Huawei and others) cannot run the
/// Google sign-in screen: it returned no result and a bare sign_in_failed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = AuthService.googleServicesStatus;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    AuthService.googleServicesStatus = original;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/google_sign_in_android'),
          null,
        );
  });

  test('missing services stop before Google opens and explain why', () async {
    final events = <Map<String, dynamic>>[];
    var googleOpened = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/google_sign_in_android'),
          (_) async {
            googleOpened = true;
            return null;
          },
        );
    final reports = ErrorReporter(
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
    final auth = AuthService.forTesting(
      writeSession: (_) async {},
      errorReporter: reports,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AuthService.googleServicesStatus = () async => 1;
    expect(await auth.signInWithGoogle(), isFalse);
    debugDefaultTargetPlatformOverride = null;
    await reports.flush();
    expect(googleOpened, isFalse);
    expect(auth.lastFailure, AuthFailure.googleServices);
    expect(events.single['code'], 'gms_unavailable:1');
    expect(events.single['provider'], 'google');
  });
}
