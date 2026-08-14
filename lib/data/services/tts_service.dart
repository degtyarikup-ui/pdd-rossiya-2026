import 'package:flutter_tts/flutter_tts.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/l10n/l10n.dart';

class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  /// Baseline rate was 0.45; user-requested 1.1×.
  static const double _speechRate = 0.45 * 1.1;

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
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;

    // Голос под язык контента страны (сербский текст ≠ русский голос).
    // Если движок не поддерживает локаль (голос не установлен) — не роняем
    // конфигурацию, платформа подберёт ближайший/дефолтный голос.
    try {
      await _tts.setLanguage(CountryConfig.current.ttsLocale);
    } catch (_) {}
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // Not every platform supports awaitSpeakCompletion.
    }

    _configured = true;
  }

  Future<void> speakQuestion({
    required String question,
    required List<String> answers,
  }) async {
    await _ensureConfigured();
    await stop();

    final buffer = StringBuffer()
      ..write(stripForSpeech(question))
      ..write(appL10n.ttsAnswerOptions);

    for (var i = 0; i < answers.length; i++) {
      buffer
        ..write(appL10n.ttsAnswer)
        ..write(i + 1)
        ..write(' ')
        ..write(stripForSpeech(answers[i]))
        ..write(' ');
    }

    await _tts.speak(buffer.toString().trim());
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
