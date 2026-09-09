import 'dart:async';
import 'dart:io' show Platform;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/services/premium_service.dart';

class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  /// Baseline rate was 0.45; user-requested faster natural speed (1.20×).
  static const double _speechRate = 0.45 * 1.20;

  static final RegExp _punctuationAndSymbols = RegExp(
    r'[^\p{L}\p{N}\s]+',
    unicode: true,
  );

  static final RegExp _spaces = RegExp(r'\s+');

  /// Removes punctuation and collapses whitespace so TTS does not read it aloud.
  static String stripForSpeech(String text) {
    var s = text.trim();
    if (s.isEmpty) return s;
    s = s.replaceAll(_punctuationAndSymbols, ' ');
    s = s.replaceAll(_spaces, ' ').trim();
    return s;
  }

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _configured = false;
  int _activeRequestId = 0;

  Future<void> _ensureConfigured() async {
    if (_configured) return;

    try {
      await _tts.setLanguage(CountryConfig.current.ttsLocale);
    } catch (_) {}
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    if (!kIsWeb && Platform.isIOS) {
      try {
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ],
          IosTextToSpeechAudioMode.defaultMode,
        );
      } catch (_) {}
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await _audioPlayer.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: false,
              contentType: AndroidContentType.speech,
              usageType: AndroidUsageType.media,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {
                AVAudioSessionOptions.mixWithOthers,
              },
            ),
          ),
        );
      } catch (_) {}
    }

    try {
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {}

    _configured = true;
  }

  /// Plays studio-quality pre-rendered neural voice if PRO is active and audio exists,
  /// otherwise falls back to phone system TTS.
  /// Returns the Duration of the audio track for dynamic countdown timer synchronization.
  Future<Duration?> speakOrPlayFeedItem({
    required String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async {
    await stop();
    final currentId = _activeRequestId;
    await _ensureConfigured();
    if (currentId != _activeRequestId) return null;

    final isPremium = PremiumService.instance.isPremium;
    if (isPremium && rawQuestionId != null) {
      final candidates = [
        rawQuestionId.startsWith('sign_')
            ? '$rawQuestionId.opus'
            : 'q_$rawQuestionId.opus',
        '$rawQuestionId.opus',
        rawQuestionId.startsWith('sign_')
            ? '$rawQuestionId.mp3'
            : 'q_$rawQuestionId.mp3',
      ];
      for (final fileName in candidates) {
        final assetPath = 'audio/feed/$fileName';
        try {
          await rootBundle.load('assets/$assetPath');
          if (currentId != _activeRequestId) return null;

          await _audioPlayer.setSource(AssetSource(assetPath));
          if (currentId != _activeRequestId) {
            await _audioPlayer.stop();
            return null;
          }

          final duration = await _audioPlayer.getDuration();
          if (currentId != _activeRequestId) {
            await _audioPlayer.stop();
            return null;
          }

          await _audioPlayer.resume();
          return duration;
        } catch (_) {
          // Pre-rendered audio not found for this candidate
        }
      }
    }

    if (currentId != _activeRequestId) return null;
    await speakQuestion(
      rawQuestionId: rawQuestionId,
      question: question,
      answers: answers,
    );

    // Approximate duration: ~15.5 characters per second
    final totalChars = question.length + answers.join('').length + answers.length * 6;
    return Duration(milliseconds: (totalChars / 15.5 * 1000).round());
  }

  Future<void> speakQuestion({
    String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async {
    await stop();
    final currentId = _activeRequestId;
    await _ensureConfigured();
    if (currentId != _activeRequestId) return;

    // Free users get device system TTS in training modes; Premium gets studio neural voice (.opus)
    final isPremium = PremiumService.instance.isPremium;
    if (isPremium && rawQuestionId != null) {
      final candidates = [
        rawQuestionId.startsWith('sign_')
            ? '$rawQuestionId.opus'
            : 'q_$rawQuestionId.opus',
        '$rawQuestionId.opus',
        rawQuestionId.startsWith('sign_')
            ? '$rawQuestionId.mp3'
            : 'q_$rawQuestionId.mp3',
      ];
      for (final fileName in candidates) {
        final assetPath = 'audio/feed/$fileName';
        try {
          await rootBundle.load('assets/$assetPath');
          if (currentId != _activeRequestId) return;

          await _audioPlayer.setSource(AssetSource(assetPath));
          if (currentId != _activeRequestId) {
            await _audioPlayer.stop();
            return;
          }

          await _audioPlayer.resume();
          return;
        } catch (_) {
          // Fall back to next candidate or system TTS
        }
      }
    }

    if (currentId != _activeRequestId) return;

    const numberWords = ['Один', 'Два', 'Три', 'Четыре', 'Пять', 'Шесть'];
    final buffer = StringBuffer()
      ..write(stripForSpeech(question))
      ..write('. ');

    for (var i = 0; i < answers.length; i++) {
      final numPrefix = i < numberWords.length ? numberWords[i] : '${i + 1}';
      buffer
        ..write(numPrefix)
        ..write(' — ')
        ..write(stripForSpeech(answers[i]))
        ..write('. ');
    }

    if (currentId != _activeRequestId) return;
    try {
      await _tts.speak(buffer.toString().trim(), focus: true);
    } catch (_) {}
    if (currentId != _activeRequestId) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _activeRequestId++;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
  }
}
