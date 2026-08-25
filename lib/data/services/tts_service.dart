import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pdd_app/core/config/country_config.dart';

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
  bool _isPlayingAudio = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;

    try {
      await _tts.setLanguage(CountryConfig.current.ttsLocale);
    } catch (_) {}
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}

    _audioPlayer.onPlayerComplete.listen((_) {
      _isPlayingAudio = false;
    });

    _configured = true;
  }

  /// Plays studio-quality pre-rendered neural voice if available, otherwise falls back to system TTS.
  /// Returns the Duration of the audio track for dynamic countdown timer synchronization.
  Future<Duration?> speakOrPlayFeedItem({
    required String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async {
    await stop();

    if (rawQuestionId != null) {
      final fileName = rawQuestionId.startsWith('sign_')
          ? '$rawQuestionId.mp3'
          : 'q_$rawQuestionId.mp3';
      final assetPath = 'audio/feed/$fileName';
      try {
        await rootBundle.load('assets/$assetPath');
        _isPlayingAudio = true;
        await _audioPlayer.setSource(AssetSource(assetPath));
        final duration = await _audioPlayer.getDuration();
        await _audioPlayer.resume();
        return duration;
      } catch (_) {
        // Pre-rendered audio not found, fall back to TTS
      }
    }

    await speakQuestion(rawQuestionId: rawQuestionId, question: question, answers: answers);
    // Approximate duration: ~15.5 characters per second
    final totalChars = question.length + answers.join('').length + answers.length * 6;
    return Duration(milliseconds: (totalChars / 15.5 * 1000).round());
  }

  Future<void> speakQuestion({
    String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async {
    await _ensureConfigured();
    await stop();

    if (rawQuestionId != null) {
      final fileName = rawQuestionId.startsWith('sign_')
          ? '$rawQuestionId.mp3'
          : 'q_$rawQuestionId.mp3';
      final assetPath = 'audio/feed/$fileName';
      try {
        await rootBundle.load('assets/$assetPath');
        _isPlayingAudio = true;
        await _audioPlayer.setSource(AssetSource(assetPath));
        await _audioPlayer.resume();
        return;
      } catch (_) {
        // Fall back to system TTS
      }
    }

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

    await _tts.speak(buffer.toString().trim());
  }

  Future<void> stop() async {
    if (_isPlayingAudio) {
      try {
        await _audioPlayer.stop();
      } catch (_) {}
      _isPlayingAudio = false;
    }
    await _tts.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
  }
}
