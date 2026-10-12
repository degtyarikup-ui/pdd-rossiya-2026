import 'dart:async';
import 'dart:math';

import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/data/services/support_chat_service.dart';

/// Operator replies while the app is open: a sound and a banner over the app, unless the
/// support chat is already on screen (it shows the reply itself and plays the sound).
///
/// Polls the server every few seconds while the app is in the foreground. The first poll only
/// marks what is already there, so old replies do not sound again.
class SupportInbox {
  SupportInbox._();
  static final SupportInbox instance = SupportInbox._();

  static const Duration interval = Duration(seconds: 5);

  Timer? _timer;
  bool _polling = false;
  bool _primed = false;
  int _since = 0;

  /// The support chat screen is on top: it handles new replies itself.
  bool chatOpen = false;

  /// Fetches replies newer than [since] (null: all). Replaced in tests.
  Future<List<SupportChatMessage>> Function({int? since}) fetch = ({int? since}) =>
      SupportChatService.instance.fetchMessages(since: since);

  /// Called with the newest operator reply when there is one to show. Set by the app.
  void Function(SupportChatMessage reply)? onReply;

  /// Sound for a new reply. Replaced in tests.
  void Function()? onSound;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(poll()));
    unawaited(poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One poll. Public for tests; the timer calls it.
  Future<void> poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final list = await fetch(since: _since > 0 ? _since : null);
      if (list.isEmpty) {
        _primed = true;
        return;
      }
      _since = list.map((m) => m.timestamp).fold<int>(_since, max);

      final wasPrimed = _primed;
      _primed = true;
      if (!wasPrimed) return;

      final replies = list.where((m) => m.isSupport).toList();
      if (replies.isEmpty || chatOpen) return;
      onSound?.call();
      onReply?.call(replies.last);
    } catch (_) {
      // A failed poll is simply retried on the next tick.
    } finally {
      _polling = false;
    }
  }
}
