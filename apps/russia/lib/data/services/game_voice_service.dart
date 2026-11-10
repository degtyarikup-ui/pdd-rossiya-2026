import 'dart:async';

import 'package:pdd_app/data/services/tts_service.dart';

/// One player per game run. Godot sends complete desired-state snapshots, so a
/// pause/stop cannot be lost when iOS coalesces requests between its polls.
/// Recordings, entitlement checks and playback are the same as in the feed.
class GameVoiceService {
  GameVoiceService({TtsService? narration})
    : _narration = narration ?? TtsService.forGame();

  final TtsService _narration;
  Future<void> _queue = Future<void>.value();
  int _revision = -1;
  String _clip = '';
  String _playback = '';
  bool _loaded = false;
  bool _disposed = false;
  bool _hostActive = true;
  double _duration = 0;

  Future<Map<String, dynamic>> apply(Map<String, dynamic> state) {
    final revision = state['revision'];
    final clip = state['clip'];
    final playback = state['playback'];
    final paused = state['paused'];
    final rate = state['speed'];
    if (_disposed ||
        revision is! int ||
        revision <= _revision ||
        clip is! String ||
        playback is! String ||
        paused is! bool ||
        rate is! num ||
        ![0.8, 1.0, 1.2, 1.5].contains(rate.toDouble()) ||
        (clip.isNotEmpty && !RegExp(r'^[a-f0-9]{32}$').hasMatch(clip))) {
      return Future.value({'ok': false});
    }
    _revision = revision;
    final changed = clip != _clip || playback != _playback;
    _clip = clip;
    _playback = playback;
    // Invalidate an in-flight load immediately, before the serialized task runs.
    if (changed || clip.isEmpty) {
      _loaded = false;
      unawaited(_narration.stop());
    } else if (paused) {
      unawaited(_narration.pause());
    }
    bool current() => !_disposed && revision == _revision;
    final task = _queue.then<Map<String, dynamic>>((_) async {
      if (!current()) return {'ok': false};
      if (clip.isEmpty) return {'ok': true, 'playing': false};
      await _narration.configure(enabled: true, speed: rate.toDouble());
      if (!current()) return {'ok': false};
      // A new question enabled in the garage must remain silent until resume.
      if (!_loaded && !paused && _hostActive) {
        final duration = await _narration.speakOrPlayFeedItem(
          rawQuestionId: clip,
          question: '',
          answers: const [],
        );
        // Pause/speed snapshots can arrive during loading. They still own this
        // clip; record the successful load so resume never restarts its phrase.
        if (!_disposed &&
            _clip == clip &&
            _playback == playback &&
            duration != null) {
          _loaded = true;
          _duration = duration.inMicroseconds / 1000000 * rate.toDouble();
        }
      } else if (_loaded) {
        if (!paused && _hostActive) await _narration.resume();
      }
      if (!current()) return {'ok': false};
      return {
        'ok': paused || !_hostActive || _loaded,
        'playing': !paused && _hostActive && _loaded,
        'duration': _duration / rate.toDouble(),
      };
    });
    _queue = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task.catchError((Object _) => <String, dynamic>{'ok': false});
  }

  /// iOS/web can suspend their render/poll loop before Godot's pause arrives.
  /// Foregrounding alone never resumes: the game must send its resume state.
  Future<void> setHostActive(bool active) async {
    _hostActive = active;
    if (!active) await _narration.pause();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    await _narration.dispose();
  }
}
