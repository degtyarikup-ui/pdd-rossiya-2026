import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'first speech keeps selected locale and numbers answers in that locale',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
        call,
      ) async {
        calls.add(call);
        return 1;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global/events'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (call) async {
          if (call.method == 'create') {
            final id = (call.arguments as Map)['playerId'];
            messenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$id'),
              (_) async => null,
            );
          }
          return null;
        },
      );
      final tts = TtsService.instance;
      await tts.updateLanguage('en');
      await tts.speakQuestion(
        question: 'May you turn left?',
        answers: ['Yes', 'No'],
      );
      final languages = calls
          .where((c) => c.method == 'setLanguage')
          .map((c) => c.arguments);
      expect(languages, isNotEmpty);
      expect(languages.every((l) => l == 'en-US'), true);
      final speechArgs = calls.lastWhere((c) => c.method == 'speak').arguments;
      final speech = speechArgs is Map ? speechArgs['text'] : speechArgs;
      expect(speech, contains('1 — Yes'));
      expect(speech, isNot(contains('Один')));
      calls.clear();
      await tts.updateLanguage('kk');
      await tts.speakQuestion(
        question: 'Бұрылуға бола ма?',
        answers: ['Иә', 'Жоқ'],
      );
      expect(
        calls.firstWhere((c) => c.method == 'setLanguage').arguments,
        'kk-KZ',
      );
      await tts.dispose();
    },
  );
}
