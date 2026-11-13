import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/services/tts_service.dart';

class _Player implements AudioPlayer {
  final sources = <String>[];
  final rates = <double>[];
  int starts = 0;
  int stops = 0;
  int pauses = 0;
  Duration duration = const Duration(seconds: 12);
  Duration position = Duration.zero;
  Completer<void>? sourceGate;

  @override
  Stream<void> get onPlayerComplete => const Stream.empty();

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
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SystemTts implements FlutterTts {
  final languages = <String>[];
  final spoken = <String>[];
  final rates = <double>[];
  bool available = true;
  int stops = 0;
  ProgressHandler? progress;
  VoidCallback? completion;
  VoidCallback? started;
  @override
  Future<dynamic> isLanguageAvailable(String language) async => available;
  @override
  Future<dynamic> setLanguage(String language) async {
    languages.add(language);
    return 1;
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool value) async => 1;
  @override
  Future<dynamic> setPitch(double value) async => 1;
  @override
  Future<dynamic> setVolume(double value) async => 1;
  @override
  Future<dynamic> setSpeechRate(double value) async {
    rates.add(value);
    return 1;
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    started?.call();
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    stops++;
    return 1;
  }

  @override
  void setCompletionHandler(VoidCallback callback) => completion = callback;
  @override
  void setStartHandler(VoidCallback callback) => started = callback;
  @override
  void setProgressHandler(ProgressHandler callback) => progress = callback;
  @override
  void setErrorHandler(ErrorHandler handler) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Player player;
  late ValueNotifier<bool> premium;
  late TtsService voice;
  late _SystemTts systemTts;
  late List<String> loads;

  setUp(() async {
    player = _Player();
    premium = ValueNotifier(true);
    loads = [];
    systemTts = _SystemTts();
    voice = TtsService.forTesting(
      player: player,
      premium: premium,
      systemTts: systemTts,
      loadAsset: (path) async => loads.add(path),
    );
    await voice.configure(enabled: true, speed: 1);
  });

  tearDown(() async {
    await voice.dispose();
    premium.dispose();
  });

  Future<Duration?> play([String? id = 'question']) =>
      voice.speakOrPlayFeedItem(
        rawQuestionId: id,
        question: 'Вопрос?',
        answers: ['Да', 'Нет'],
      );

  test(
    'free accounts and disabled narration cannot load or synthesize',
    () async {
      premium.value = false;
      expect(await play(), isNull);
      for (final language in ['ru', 'en', 'kk']) {
        await voice.updateLanguage(language);
        expect(await play(), isNull);
      }
      premium.value = true;
      await voice.updateLanguage('ru');
      await voice.configure(enabled: false, speed: 1);
      expect(await play(), isNull);
      expect(loads, isEmpty);
      expect(player.sources, isEmpty);
      expect(player.starts, 0);
      expect(systemTts.spoken, isEmpty);
    },
  );

  test(
    'missing IDs never fall back to synthesis or invented duration',
    () async {
      expect(await play(null), isNull);
      expect(loads, isEmpty);
      expect(player.starts, 0);
    },
  );

  test(
    'recordings use canonical IDs and report speed-adjusted duration',
    () async {
      await voice.configure(enabled: true, speed: 1.5);
      expect(await play('question:v:ticket_2_3'), const Duration(seconds: 8));
      expect(loads, ['assets/audio/feed/q_question.opus']);
      expect(player.sources, ['audio/feed/q_question.opus']);
      expect(player.rates, [1.5]);
      expect(player.starts, 1);
    },
  );

  test(
    'speed changes keep source and position; paused audio resumes in place',
    () async {
      await play();
      player.position = const Duration(seconds: 3);
      await voice.pause();
      await voice.configure(enabled: true, speed: 1.5);
      expect(
        await voice.remainingPlaybackDuration(),
        const Duration(seconds: 6),
      );
      expect(player.sources, hasLength(1));
      expect(player.starts, 1);
      expect(player.pauses, 1);
      expect(player.position, const Duration(seconds: 3));
      expect(player.rates, [1, 1.5]);
      await voice.resume();
      expect(player.starts, 2);
    },
  );

  test('revoked premium stops playback and blocks resume', () async {
    await play();
    final stops = player.stops;
    premium.value = false;
    await voice.resume();
    expect(player.stops, greaterThan(stops));
    expect(player.starts, 1);
    expect(await voice.remainingPlaybackDuration(), isNull);
    expect(await play(), isNull);
  });

  test(
    'language or enabled preference change immediately stops recording',
    () async {
      await play();
      final stops = player.stops;
      await voice.updateLanguage('en');
      expect(player.stops, greaterThan(stops));
      expect(await voice.remainingPlaybackDuration(), isNull);
      await voice.updateLanguage('ru');
      await play();
      await voice.configure(enabled: false, speed: 1);
      await voice.resume();
      expect(player.starts, 2);
    },
  );

  test('a late old asset load cannot replace the new question', () async {
    await voice.dispose();
    final firstLoad = Completer<void>();
    voice = TtsService.forTesting(
      player: player,
      premium: premium,
      systemTts: systemTts,
      loadAsset: (path) async {
        loads.add(path);
        if (path.contains('q_old.')) await firstLoad.future;
      },
    );
    await voice.configure(enabled: true, speed: 1);
    final old = play('old');
    await Future<void>.delayed(Duration.zero);
    await play('new');
    firstLoad.complete();
    await old;
    expect(player.sources, ['audio/feed/q_new.opus']);
    expect(player.starts, 1);
  });

  test(
    'cancel during player source loading cannot start stale audio',
    () async {
      player.sourceGate = Completer<void>();
      final loading = play();
      await Future<void>.delayed(Duration.zero);
      final stopping = voice.stop();
      player.sourceGate!.complete();
      await Future.wait([loading, stopping]);
      expect(player.starts, 0);
      expect(await voice.remainingPlaybackDuration(), isNull);
    },
  );

  test(
    'unavailable recordings stay silent and return no fake duration',
    () async {
      await voice.dispose();
      voice = TtsService.forTesting(
        player: player,
        premium: premium,
        loadAsset: (path) async {
          throw StateError('missing asset');
        },
      );
      await voice.configure(enabled: true, speed: 1);
      expect(await play(), isNull);
      expect(player.starts, 0);
      expect(player.sources, isEmpty);
    },
  );

  test('entitlement expiration stops an already playing recording', () async {
    await voice.dispose();
    final expires = DateTime.now().add(const Duration(milliseconds: 100));
    voice = TtsService.forTesting(
      player: player,
      premium: premium,
      premiumExpiresAt: () => expires,
      loadAsset: (_) async {},
    );
    await voice.configure(enabled: true, speed: 1);
    await play();
    final stops = player.stops;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(player.stops, greaterThan(stops));
    expect(await play(), isNull);
  });

  test(
    'Kazakh uses Russian studio recordings and never system TTS',
    () async {
      await voice.updateLanguage('kk');
      await voice.configure(enabled: true, speed: 1.5);
      expect(await play('question:v:ticket_2_3'), const Duration(seconds: 8));
      expect(loads, ['assets/audio/feed/q_question.opus']);
      expect(player.sources, ['audio/feed/q_question.opus']);
      expect(player.rates, [1.5]);
      expect(player.starts, 1);
      expect(systemTts.languages, isEmpty);
      expect(systemTts.spoken, isEmpty);
    },
  );

  test('missing recording in Kazakh never falls back to system TTS', () async {
    final kkPlayer = _Player();
    final kkTts = _SystemTts();
    final kkPremium = ValueNotifier(true);
    final kkVoice = TtsService.forTesting(
      player: kkPlayer,
      systemTts: kkTts,
      loadAsset: (_) => Future<void>.error(StateError('missing')),
      premium: kkPremium,
    );
    addTearDown(() async {
      await kkVoice.dispose();
      kkPremium.dispose();
    });
    await kkVoice.updateLanguage('kk');
    await kkVoice.configure(enabled: true, speed: 1);
    expect(
      await kkVoice.speakOrPlayFeedItem(
        rawQuestionId: 'missing',
        question: 'Сұрақ?',
        answers: ['Иә', 'Жоқ'],
      ),
      isNull,
    );
    expect(kkVoice.status.value, NarrationStatus.unavailable);
    expect(kkTts.spoken, isEmpty);
    expect(kkTts.languages, isEmpty);
  });

  test(
    'English uses selected device locale and never Russian audio',
    () async {
      await voice.updateLanguage('en');
      expect(await play(), isNotNull);
      expect(systemTts.languages, ['en-US']);
      expect(systemTts.spoken, hasLength(1));
      expect(systemTts.spoken.single, contains('1 — Да'));
      expect(player.sources, isEmpty);
      expect(loads, isEmpty);
    },
  );

  test('missing device language reports explicit unavailable voice', () async {
    systemTts.available = false;
    await voice.updateLanguage('en');
    expect(await play(), isNull);
    expect(voice.status.value, NarrationStatus.voiceUnavailable);
    expect(systemTts.spoken, isEmpty);
    expect(player.starts, 0);
  });

  test('device speed and resume preserve the current word', () async {
    await voice.updateLanguage('en');
    await play();
    final full = systemTts.spoken.single;
    final offset = full.indexOf('1 —');
    systemTts.progress!(full, offset, offset + 1, '1');
    await voice.configure(enabled: true, speed: 1.5);
    expect(systemTts.rates, [0.45, closeTo(0.675, 0.001)]);
    expect(systemTts.spoken.last, full.substring(offset));
    await voice.pause();
    await voice.resume();
    expect(systemTts.spoken.last, full.substring(offset));
    expect(voice.status.value, NarrationStatus.playing);
    systemTts.completion!();
    expect(voice.status.value, NarrationStatus.idle);
    expect(await voice.remainingPlaybackDuration(), isNull);
  });

  test('late device completion cannot clear a newer question', () async {
    await voice.updateLanguage('en');
    await play('first');
    final oldCompletion = systemTts.completion!;
    await play('second');
    oldCompletion();
    expect(voice.status.value, NarrationStatus.playing);
    expect(await voice.remainingPlaybackDuration(), isNotNull);
  });

  test('foreground restoration respects the modal pause', () async {
    await play();
    await voice.pause();
    await voice.setAppActive(false);
    await voice.setAppActive(true);
    expect(player.starts, 1);
    await voice.resume();
    expect(player.starts, 2);
  });

  test('speed preference survives JSON and rejects invalid stored values', () {
    expect(AppSettings.fromJson({}).voiceSpeed, 1);
    for (final speed in AppSettings.voiceSpeeds) {
      final settings = const AppSettings().copyWith(voiceSpeed: speed);
      expect(AppSettings.fromJson(settings.toJson()).voiceSpeed, speed);
    }
    for (final invalid in [null, -1, 0, 1.35, 5, '1.2', double.nan]) {
      expect(AppSettings.fromJson({'voiceSpeed': invalid}).voiceSpeed, 1);
    }
  });
}
