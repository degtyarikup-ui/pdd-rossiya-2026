import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/question_identity.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/data/services/premium_service.dart';

enum NarrationStatus { idle, loading, playing, voiceUnavailable, unavailable }

/// Premium narration: Russian studio recordings for Russian and Kazakh, and
/// device voices for English. Russian and Kazakh never fall back to
/// synthesized speech.
class TtsService {
  TtsService._({bool gamePlayback = false})
    : _gamePlayback = gamePlayback,
      _hasPremium = (() => PremiumService.instance.isPremium),
      _premiumExpiresAt = (() => PremiumService.instance.expiresAt),
      _premiumChanges = PremiumService.instance,
      _loadAsset = ((path) async {
        await rootBundle.load(path);
      }) {
    _premiumChanges.addListener(_onPremiumChanged);
    _accountRevision = AuthService.instance.accountRevision;
    AuthService.instance.addListener(_onAuthChanged);
    _observeAuth = true;
  }

  @visibleForTesting
  TtsService.forTesting({
    required AudioPlayer player,
    required Future<void> Function(String) loadAsset,
    required ValueListenable<bool> premium,
    DateTime? Function()? premiumExpiresAt,
    FlutterTts? systemTts,
    bool gamePlayback = false,
  }) : _gamePlayback = gamePlayback,
       _audioPlayer = player,
       _tts = systemTts,
       _loadAsset = loadAsset,
       _hasPremium = (() => premium.value),
       _premiumExpiresAt = premiumExpiresAt ?? (() => null),
       _premiumChanges = premium {
    _premiumChanges.addListener(_onPremiumChanged);
  }

  /// Independent lifecycle for the native game; shares the canonical recordings.
  factory TtsService.forGame() => TtsService._(gamePlayback: true);

  static final TtsService instance = TtsService._();

  final bool _gamePlayback;
  final Future<void> Function(String) _loadAsset;
  final bool Function() _hasPremium;
  final DateTime? Function() _premiumExpiresAt;
  final Listenable _premiumChanges;
  final _status = ValueNotifier(NarrationStatus.idle);
  ValueListenable<NarrationStatus> get status => _status;
  AudioPlayer? _audioPlayer;
  StreamSubscription<void>? _completionSubscription;
  FlutterTts? _tts;
  bool _usingSystem = false;
  String _systemText = '';
  int _systemOffset = 0;
  int _utteranceId = 0;
  Future<void> _commands = Future<void>.value();
  Timer? _expiryTimer;
  bool _configured = false;
  bool _enabled = false;
  bool _appActive = true;
  bool _disposed = false;
  bool _observeAuth = false;
  bool _hasSource = false;
  bool _paused = false;
  double _speed = 1;
  String _languageCode = 'ru';
  int _activeRequestId = 0;
  int _accountRevision = 0;

  bool get _allowed =>
      !_disposed &&
      _enabled &&
      _appActive &&
      const {'ru', 'en', 'kk'}.contains(_languageCode) &&
      _hasPremium() &&
      !(_premiumExpiresAt()?.isBefore(DateTime.now()) ?? false);

  bool _isCurrent(int token) => token == _activeRequestId && _allowed;

  /// Audio mutations are serialized so a late stop/source load from an old
  /// question can never interrupt the next question.
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _commands.then((_) => action());
    _commands = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _onAuthChanged() {
    final revision = AuthService.instance.accountRevision;
    if (_accountRevision == revision) return;
    _accountRevision = revision;
    unawaited(stop());
  }

  void _onPremiumChanged() {
    _expiryTimer?.cancel();
    if (!_allowed) {
      unawaited(stop());
      return;
    }
    final expiresAt = _premiumExpiresAt();
    if (expiresAt != null) {
      _expiryTimer = Timer(expiresAt.difference(DateTime.now()), () {
        unawaited(stop());
      });
    }
  }

  Future<void> updateLanguage(String lang) async {
    if (_languageCode == lang) return;
    _languageCode = lang;
    await stop();
  }

  /// Recordings change rate in place. Device TTS restarts at the current word
  /// because native engines apply speech rate only to the next utterance.
  Future<void> configure({required bool enabled, required double speed}) async {
    final changedSpeed = _speed != AppSettings.parseVoiceSpeed(speed);
    final changedEnabled = _enabled != enabled;
    _enabled = enabled;
    _speed = AppSettings.parseVoiceSpeed(speed);
    if (!_allowed) {
      if (changedEnabled || _hasSource) await stop();
      return;
    }
    if (changedEnabled) _onPremiumChanged();
    if (changedSpeed) {
      await _enqueue(() async {
        if (_allowed && _hasSource) {
          try {
            if (_usingSystem) {
              _utteranceId++;
              await _tts?.stop();
              if (_allowed && _hasSource && !_paused) {
                await _speakSystemTail(_activeRequestId);
              }
            } else {
              await _audioPlayer?.setPlaybackRate(_speed);
            }
          } catch (_) {}
        }
      });
    }
  }

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    final player = _audioPlayer ??= AudioPlayer();
    _completionSubscription ??= player.onPlayerComplete.listen(
      (_) {
        if (!_usingSystem && _hasSource) {
          _hasSource = false;
          _status.value = NarrationStatus.idle;
        }
      },
      // The player reports a failed playback (a recording this device cannot
      // decode, a lost audio output) as a stream error. Without a handler it
      // became an unhandled application error and the button stayed "playing".
      onError: (Object error, StackTrace _) {
        if (_usingSystem || !_hasSource) return;
        _hasSource = false;
        _status.value = NarrationStatus.unavailable;
        ErrorReporter.report(
          ErrorCategory.app,
          'narration.playback',
          code: 'playback_failed',
          error: error,
        );
      },
    );
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await player.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: false,
              contentType: AndroidContentType.speech,
              usageType: AndroidUsageType.media,
              // The native game already owns focus. A second process must not
              // duck or suspend Godot when the shared narration starts.
              audioFocus: _gamePlayback
                  ? AndroidAudioFocus.none
                  : AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {AVAudioSessionOptions.mixWithOthers},
            ),
          ),
        );
      } catch (_) {}
    }
    _configured = true;
  }

  Future<Duration?> _play({
    required String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async {
    final token = ++_activeRequestId;
    _utteranceId++;
    _paused = false;
    _hasSource = false;
    _usingSystem = false;
    _status.value = NarrationStatus.idle;
    await _enqueue(() async {
      try {
        await _audioPlayer?.stop();
      } catch (_) {}
      try {
        await _tts?.stop();
      } catch (_) {}
    });
    if (!_isCurrent(token)) return null;
    _status.value = NarrationStatus.loading;
    _onPremiumChanged();
    if (_languageCode == 'en') {
      return _playSystem(token, question, answers);
    }
    if (rawQuestionId == null) {
      _status.value = NarrationStatus.unavailable;
      return null;
    }
    return _playRecording(token, rawQuestionId);
  }

  Future<Duration?> _playRecording(int token, String rawQuestionId) async {
    final sourceId = QuestionIdentity.sourceId(rawQuestionId);
    final stem = sourceId.startsWith('sign_') ? sourceId : 'q_$sourceId';
    final candidates = <String>{'$stem.opus', '$sourceId.opus', '$stem.mp3'};
    for (final fileName in candidates) {
      final assetPath = 'audio/feed/$fileName';
      try {
        await _loadAsset('assets/$assetPath');
        if (!_isCurrent(token)) return null;
        return await _enqueue(() async {
          if (!_isCurrent(token)) return null;
          await _ensureConfigured();
          if (!_isCurrent(token)) return null;
          final player = _audioPlayer!;
          await player.setSource(AssetSource(assetPath));
          if (!_isCurrent(token)) {
            await player.stop();
            return null;
          }
          await player.setPlaybackRate(_speed);
          if (!_isCurrent(token)) {
            await player.stop();
            return null;
          }
          final duration = await player.getDuration();
          if (!_isCurrent(token)) {
            await player.stop();
            return null;
          }
          _hasSource = true;
          if (!_paused) await player.resume();
          if (!_isCurrent(token)) {
            await player.stop();
            return null;
          }
          _status.value = NarrationStatus.playing;
          return duration == null
              ? null
              : Duration(
                  microseconds: (duration.inMicroseconds / _speed).round(),
                );
        });
      } catch (_) {
        // A missing/unsupported recording remains silent; try a bundled format.
        if (!_isCurrent(token)) return null;
      }
    }
    if (_isCurrent(token)) _status.value = NarrationStatus.unavailable;
    return null;
  }

  static final _speechSymbols = RegExp(r'[^\p{L}\p{N}\s]+', unicode: true);
  static String _cleanSpeech(String text) => text
      .replaceAll(_speechSymbols, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Duration _systemRemaining() => Duration(
    milliseconds:
        ((_systemText.length - _systemOffset) / (15.5 * _speed) * 1000).round(),
  );

  Future<Duration?> _playSystem(
    int token,
    String question,
    List<String> answers,
  ) => _enqueue(() async {
    if (!_isCurrent(token)) return null;
    final tts = _tts ??= FlutterTts();
    try {
      final locale = CountryConfig.current.ttsLocaleFor(_languageCode);
      final available = await tts.isLanguageAvailable(locale);
      if (!_isCurrent(token)) return null;
      if (available != true && available != 1) {
        _status.value = NarrationStatus.voiceUnavailable;
        return null;
      }
      final languageResult = await tts.setLanguage(locale);
      if (!_isCurrent(token)) return null;
      if (languageResult == 0 || languageResult == false) {
        _status.value = NarrationStatus.voiceUnavailable;
        return null;
      }
      await tts.awaitSpeakCompletion(false);
      await tts.setPitch(1);
      await tts.setVolume(1);
      if (!kIsWeb && Platform.isIOS) {
        await tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ], IosTextToSpeechAudioMode.defaultMode);
      }
      if (!_isCurrent(token)) return null;
      _systemText = [
        _cleanSpeech(question),
        for (var i = 0; i < answers.length; i++)
          '${i + 1} — ${_cleanSpeech(answers[i])}',
      ].join('. ');
      _systemOffset = 0;
      _usingSystem = true;
      _hasSource = true;
      if (!_paused) await _speakSystemTail(token);
      if (!_isCurrent(token) || !_hasSource) return null;
      return _systemRemaining();
    } catch (_) {
      if (_isCurrent(token)) {
        _hasSource = false;
        _status.value = NarrationStatus.unavailable;
      }
      return null;
    }
  });

  Future<void> _speakSystemTail(int token) async {
    if (!_isCurrent(token) || !_hasSource || _paused) return;
    final tts = _tts!;
    final utteranceId = ++_utteranceId;
    final offset = _systemOffset;
    final text = _systemText.substring(offset);
    var started = false;
    bool current() =>
        _isCurrent(token) && utteranceId == _utteranceId && _usingSystem;
    tts.setStartHandler(() {
      if (current()) started = true;
    });
    tts.setCompletionHandler(() {
      if (current() && started) {
        _systemOffset = _systemText.length;
        _hasSource = false;
        _status.value = NarrationStatus.idle;
      }
    });
    tts.setProgressHandler((spoken, start, end, word) {
      if (current() && spoken == text) {
        started = true;
        _systemOffset = (offset + start).clamp(0, _systemText.length);
      }
    });
    tts.setErrorHandler((_) {
      if (current()) {
        _hasSource = false;
        _status.value = NarrationStatus.unavailable;
      }
    });
    await tts.setSpeechRate(0.45 * _speed);
    if (!current() || _paused) return;
    final result = await tts.speak(text, focus: true);
    if (!current()) {
      await tts.stop();
      return;
    }
    if (result == 0 || result == false) {
      _hasSource = false;
      _status.value = NarrationStatus.unavailable;
    } else if (_hasSource) {
      _status.value = NarrationStatus.playing;
    }
  }

  /// Returns playback duration at the selected speed; null means unavailable.
  Future<Duration?> speakOrPlayFeedItem({
    required String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) =>
      _play(rawQuestionId: rawQuestionId, question: question, answers: answers);

  Future<void> speakQuestion({
    String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async {
    await _play(
      rawQuestionId: rawQuestionId,
      question: question,
      answers: answers,
    );
  }

  Future<Duration?> remainingPlaybackDuration() => _enqueue(() async {
    if (!_allowed || !_hasSource) return null;
    if (_usingSystem) return _systemRemaining();
    try {
      final duration = await _audioPlayer?.getDuration();
      final position = await _audioPlayer?.getCurrentPosition();
      if (duration == null || position == null || !_allowed || !_hasSource) {
        return null;
      }
      final remaining = (duration - position).inMicroseconds;
      return Duration(
        microseconds: (remaining.clamp(0, duration.inMicroseconds) / _speed)
            .round(),
      );
    } catch (_) {
      return null;
    }
  });

  Future<void> pause() {
    _paused = true;
    return _enqueue(() async {
      try {
        if (_hasSource) {
          if (_usingSystem) {
            _utteranceId++;
            await _tts?.stop();
          } else {
            await _audioPlayer?.pause();
          }
        }
      } catch (_) {}
    });
  }

  Future<void> resume() {
    if (!_paused) return Future<void>.value();
    _paused = false;
    return _enqueue(() async {
      if (!_allowed || !_hasSource || _paused) return;
      try {
        if (_usingSystem) {
          await _speakSystemTail(_activeRequestId);
        } else {
          await _audioPlayer?.resume();
        }
      } catch (_) {}
    });
  }

  /// App lifecycle pause is independent from a modal/card pause.
  Future<void> setAppActive(bool active) {
    if (_appActive == active) return Future<void>.value();
    _appActive = active;
    return _enqueue(() async {
      if (!_hasSource) return;
      if (!active) {
        if (_usingSystem) {
          _utteranceId++;
          try {
            await _tts?.stop();
          } catch (_) {}
        } else {
          try {
            await _audioPlayer?.pause();
          } catch (_) {}
        }
      } else if (_allowed && !_paused) {
        if (_usingSystem) {
          await _speakSystemTail(_activeRequestId);
        } else {
          try {
            await _audioPlayer?.resume();
          } catch (_) {}
        }
      }
    });
  }

  Future<void> stop() {
    _activeRequestId++;
    _utteranceId++;
    _hasSource = false;
    _status.value = NarrationStatus.idle;
    return _enqueue(() async {
      try {
        await _audioPlayer?.stop();
      } catch (_) {}
      try {
        await _tts?.stop();
      } catch (_) {}
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _expiryTimer?.cancel();
    _premiumChanges.removeListener(_onPremiumChanged);
    if (_observeAuth) AuthService.instance.removeListener(_onAuthChanged);
    await stop();
    await _completionSubscription?.cancel();
    await _enqueue(() async {
      await _audioPlayer?.dispose();
    });
    _status.dispose();
  }
}
