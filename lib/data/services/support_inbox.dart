import 'dart:async';
import 'dart:math';

import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/data/services/support_chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Operator replies while the app is open: a sound and a banner over the app, unless the
/// support chat is already on screen (it shows the reply itself and plays the sound).
///
/// Polls the server every few seconds while the app is in the foreground. The newest reply
/// already seen is kept on disk per support client, so a reply notifies at most once — not
/// again after a restart, a failed poll or a switch of account. Without a mark yet, the first
/// successful poll only marks what is already there.
class SupportInbox {
  SupportInbox._();
  static final SupportInbox instance = SupportInbox._();

  static const Duration interval = Duration(seconds: 5);
  static const String _prefSeenPrefix = 'support_inbox_seen_';

  Timer? _timer;
  bool _polling = false;

  /// The support chat screen is on top: it handles new replies itself.
  bool chatOpen = false;

  /// Fetches replies newer than [since] (null: all); null result = the fetch failed.
  /// Replaced in tests.
  Future<List<SupportChatMessage>?> Function({int? since}) fetch = ({int? since}) =>
      SupportChatService.instance.tryFetchMessages(since: since);

  /// Whose thread is polled. Replaced in tests.
  Future<String> Function() clientId = () => SupportChatService.instance.getClientId();

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

  /// The chat screen showed messages up to [timestamp]: they must not notify later.
  Future<void> markSeen(int timestamp) async {
    final key = _prefSeenPrefix + await clientId();
    final prefs = await SharedPreferences.getInstance();
    if (timestamp > (prefs.getInt(key) ?? -1)) await prefs.setInt(key, timestamp);
  }

  /// One poll. Public for tests; the timer calls it.
  Future<void> poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final key = _prefSeenPrefix + await clientId();
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getInt(key);
      final list = await fetch(since: (seen ?? 0) > 0 ? seen : null);
      if (list == null) return; // Failed: retried next tick, nothing is marked.

      final newest = list.map((m) => m.timestamp).fold<int>(seen ?? 0, max);
      if (seen == null || newest > seen) await prefs.setInt(key, newest);
      if (seen == null) return; // First look at this thread: old replies stay silent.

      final replies = list.where((m) => m.isSupport && !m.isClosedNotice && m.timestamp > seen).toList();
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
