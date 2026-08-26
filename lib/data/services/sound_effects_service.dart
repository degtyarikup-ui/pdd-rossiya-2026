import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Service for playing UI answer feedback sound effects (correct / incorrect answers).
class SoundEffectsService {
  static final SoundEffectsService instance = SoundEffectsService._();
  SoundEffectsService._();

  AudioPlayer? _correctPlayer;
  AudioPlayer? _incorrectPlayer;

  bool _initialized = false;
  bool _enabled = true;

  bool get isEnabled => _enabled;

  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  AudioPlayer _getCorrectPlayer() => _correctPlayer ??= AudioPlayer();
  AudioPlayer _getIncorrectPlayer() => _incorrectPlayer ??= AudioPlayer();

  Future<void> init() async {
    if (_initialized) return;
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await AudioPlayer.global.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: false,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.assistanceSonification,
              audioFocus: AndroidAudioFocus.none,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.ambient,
              options: const {
                AVAudioSessionOptions.mixWithOthers,
              },
            ),
          ),
        );
      }

      final correct = _getCorrectPlayer();
      await correct.setReleaseMode(ReleaseMode.stop);
      await correct.setSource(AssetSource('audio/correct.wav'));
      await correct.setVolume(0.55);

      final incorrect = _getIncorrectPlayer();
      await incorrect.setReleaseMode(ReleaseMode.stop);
      await incorrect.setSource(AssetSource('audio/incorrect.wav'));
      await incorrect.setVolume(0.45);

      _initialized = true;
    } catch (e) {
      debugPrint('SoundEffectsService: init error: $e');
    }
  }

  /// Plays a pleasant, crystal-clear chime on correct answer with a longer reverberant sustain.
  Future<void> playCorrect({double volume = 0.55}) async {
    if (!_enabled) return;
    try {
      final player = _getCorrectPlayer();
      await player.stop();
      await player.setVolume(volume);
      await player.play(
        AssetSource('audio/correct.wav'),
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      debugPrint('SoundEffectsService: playCorrect error: $e');
    }
  }

  /// Plays a soft, mellow descending tone on incorrect answer.
  Future<void> playIncorrect({double volume = 0.45}) async {
    if (!_enabled) return;
    try {
      final player = _getIncorrectPlayer();
      await player.stop();
      await player.setVolume(volume);
      await player.play(
        AssetSource('audio/incorrect.wav'),
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      debugPrint('SoundEffectsService: playIncorrect error: $e');
    }
  }

  void dispose() {
    _correctPlayer?.dispose().ignore();
    _incorrectPlayer?.dispose().ignore();
  }
}
