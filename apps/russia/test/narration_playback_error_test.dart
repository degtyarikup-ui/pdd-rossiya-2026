import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/tts_service.dart';

class _Player implements AudioPlayer {
  final events = StreamController<void>.broadcast();
  bool failSource = false;

  @override
  Stream<void> get onPlayerComplete => events.stream;
  @override
  Future<void> setSource(Source source) async {
    if (failSource) throw PlatformException(code: 'AndroidAudioError');
  }

  @override
  Future<void> setAudioContext(AudioContext audioContext) async {}
  @override
  Future<void> setPlaybackRate(double value) async {}
  @override
  Future<Duration?> getDuration() async => const Duration(seconds: 12);
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async => events.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a playback failure reported by the player ends the narration instead of escaping as an unhandled error',
    () async {
      final unhandled = <Object>[];
      await runZonedGuarded(() async {
        final player = _Player(), premium = ValueNotifier(true);
        final voice = TtsService.forTesting(
          player: player,
          premium: premium,
          loadAsset: (_) async {},
        );
        await voice.configure(enabled: true, speed: 1);
        Future<Duration?> play() => voice.speakOrPlayFeedItem(
          rawQuestionId: 'question',
          question: 'Вопрос?',
          answers: ['Да', 'Нет'],
        );

        expect(await play(), const Duration(seconds: 12));
        expect(voice.status.value, NarrationStatus.playing);
        // audioplayers delivers MediaPlayer failures on its event stream.
        player.events.addError(
          PlatformException(code: 'AndroidAudioError', message: 'MEDIA_ERROR'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(voice.status.value, NarrationStatus.unavailable);

        // The next question plays normally and still completes.
        expect(await play(), const Duration(seconds: 12));
        expect(voice.status.value, NarrationStatus.playing);
        player.events.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(voice.status.value, NarrationStatus.idle);

        // A stray error while nothing is playing changes nothing.
        player.events.addError(PlatformException(code: 'AndroidAudioError'));
        await Future<void>.delayed(Duration.zero);
        expect(voice.status.value, NarrationStatus.idle);

        await voice.dispose();
        premium.dispose();
      }, (error, _) => unhandled.add(error));
      expect(unhandled, isEmpty);
    },
  );
}
