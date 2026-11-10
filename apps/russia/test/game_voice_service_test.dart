import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/services/game_voice_service.dart';

class _Player implements AudioPlayer {
  final completion = StreamController<void>.broadcast();
  final sources = <String>[];
  final rates = <double>[];
  int starts = 0;
  int stops = 0;
  int pauses = 0;
  Duration duration = const Duration(seconds: 12);
  Duration position = Duration.zero;
  Completer<void>? sourceGate;

  @override
  Stream<void> get onPlayerComplete => completion.stream;

  @override
  Future<void> setSource(Source source) async {
    sources.add((source as AssetSource).path);
    if (sourceGate != null) await sourceGate!.future;
  }

  @override
  Future<void> setAudioContext(AudioContext audioContext) async {}
  @override
  Future<void> setPlaybackRate(double value) async => rates.add(value);
  @override
  Future<Duration?> getDuration() async => duration;
  @override
  Future<Duration?> getCurrentPosition() async => position;
  @override
  Future<void> resume() async => starts++;
  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {
    await completion.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Player player;
  late ValueNotifier<bool> premium;
  late GameVoiceService voice;
  const clip = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  Map<String, dynamic> state(
    int revision, {
    String id = clip,
    String playback = '1',
    bool paused = false,
    double speed = 1,
  }) => {
    'revision': revision,
    'clip': id,
    'playback': playback,
    'paused': paused,
    'speed': speed,
  };
  setUp(() {
    player = _Player();
    premium = ValueNotifier(true);
    voice = GameVoiceService(
      narration: TtsService.forTesting(
        player: player,
        loadAsset: (_) async {},
        premium: premium,
        gamePlayback: true,
      ),
    );
  });
  tearDown(() async {
    await voice.dispose();
    premium.dispose();
  });

  test('one canonical Opus, pause and speed retain loaded recording', () async {
    expect((await voice.apply(state(1)))['duration'], 12);
    expect(player.sources, ['audio/feed/q_$clip.opus']);
    await voice.apply(state(2, paused: true));
    expect(player.pauses, 1);
    expect((await voice.apply(state(3, speed: 1.5)))['duration'], 8);
    expect(player.sources.length, 1);
    expect(player.rates.last, 1.5);
    expect(player.starts, 2);
  });
  test('pause before first load stays silent, resume loads once', () async {
    await voice.apply(state(1, paused: true));
    expect(player.sources, isEmpty);
    await voice.apply(state(2));
    expect(player.starts, 1);
  });
  test('stop cancels an in-flight load and rejects old snapshots', () async {
    player.sourceGate = Completer<void>();
    final play = voice.apply(state(1));
    while (player.sources.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final stop = voice.apply(state(2, id: ''));
    player.sourceGate!.complete();
    await play;
    await stop;
    expect(player.starts, 0);
    expect((await voice.apply(state(1)))['ok'], false);
  });
  test(
    'pause during load never starts audio and resume preserves it',
    () async {
      player.sourceGate = Completer<void>();
      final play = voice.apply(state(1));
      while (player.sources.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final pause = voice.apply(state(2, paused: true));
      player.sourceGate!.complete();
      await play;
      await pause;
      expect(player.starts, 0);
      await voice.apply(state(3));
      expect(player.sources.length, 1);
      expect(player.starts, 1);
    },
  );
  test(
    'same question on a new card starts again, old card never resumes',
    () async {
      await voice.apply(state(1));
      await voice.apply(state(2, playback: '2'));
      expect(player.sources.length, 2);
      await voice.apply(state(3, id: ''));
      final starts = player.starts;
      await voice.apply(state(2, playback: '2'));
      expect(player.starts, starts);
    },
  );
  test('premium is checked by the existing narration service', () async {
    premium.value = false;
    expect((await voice.apply(state(1)))['ok'], false);
    expect(player.starts, 0);
  });
  test('dispose invalidates pending loads', () async {
    player.sourceGate = Completer<void>();
    final play = voice.apply(state(1));
    while (player.sources.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final closing = voice.dispose();
    player.sourceGate!.complete();
    await play;
    await closing;
    expect(player.starts, 0);
    expect((await voice.apply(state(2)))['ok'], false);
  });
  test(
    'host background blocks pending loads and foreground waits for game resume',
    () async {
      await voice.setHostActive(false);
      await voice.apply(state(1));
      expect(player.starts, 0);
      await voice.setHostActive(true);
      expect(player.starts, 0);
      await voice.apply(state(2));
      expect(player.starts, 1);
      await voice.setHostActive(false);
      await voice.setHostActive(true);
      expect(player.starts, 1);
      await voice.apply(state(3));
      expect(player.starts, 2);
      expect(player.sources.length, 1);
    },
  );
  test(
    'completed recording does not replay after pause or speed change',
    () async {
      await voice.apply(state(1));
      player.completion.add(null);
      await Future<void>.delayed(Duration.zero);
      await voice.apply(state(2, paused: true));
      await voice.apply(state(3, speed: 1.5));
      expect(player.starts, 1);
      expect(player.sources.length, 1);
    },
  );
  test('invalid paths and rates cannot enter the player', () async {
    expect((await voice.apply(state(1, id: '../secret')))['ok'], false);
    expect((await voice.apply(state(2, speed: 99)))['ok'], false);
    expect(player.sources, isEmpty);
  });
}
