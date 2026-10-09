import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/yandex_native_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pdd/yandex_auth');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'returns native credentials once and sends no credential arguments',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'signIn' ? 'test-token' : null;
      });
      expect(await YandexNativeAuth.signIn(), 'test-token');
      await YandexNativeAuth.signOut();
      expect(calls.map((call) => call.method), ['signIn', 'signOut']);
      expect(calls.every((call) => call.arguments == null), isTrue);
    },
  );

  test('native cancellation returns null, empty credentials fail', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await YandexNativeAuth.signIn(), isNull);
    messenger.setMockMethodCallHandler(channel, (_) async => '');
    await expectLater(
      YandexNativeAuth.signIn(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'missing_credential',
        ),
      ),
    );
  });

  test(
    'native SDK failures propagate instead of falling back to WebView',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'sign_in_failed'),
      );
      await expectLater(
        YandexNativeAuth.signIn(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'sign_in_failed',
          ),
        ),
      );
    },
  );
}
