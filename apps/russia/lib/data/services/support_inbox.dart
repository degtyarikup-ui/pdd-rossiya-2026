import 'dart:async';
import 'dart:math';

import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/data/services/support_chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Operator replies while the app is open: a sound and a banner over the app, unless the
/// support chat is already on screen (it shows the reply itself and plays the sound).
///
/// The newest reply already seen is kept on disk per support client, so a reply notifies at
/// most once — not again after a restart, a failed poll or a switch of account. Without a mark
/// yet, the first successful poll only marks what is already there.
///
/// Как часто спрашивать сервер — как в чатах поддержки других приложений: при запуске и
/// возврате в приложение всегда, а по таймеру — только пока разговор живой, и всё реже по
/// мере затихания ([pollEvery]). Нет переписки, обращение закрыто (/close) или чат открыт
/// (он опрашивает сам) — по таймеру не спрашиваем. Если ответы приходят пушем, частый опрос
/// нужен только первые минуты после сообщения.
class SupportInbox {
  SupportInbox._();
  static final SupportInbox instance = SupportInbox._();

  /// Как часто просыпается таймер; запрос уходит, только если подошёл срок.
  static const Duration interval = Duration(seconds: 5);
  static const String _prefSeenPrefix = 'support_inbox_seen_';
  static const String _prefActivePrefix = 'support_inbox_active_';
  static const String _prefClosedPrefix = 'support_inbox_closed_';

  /// Пауза между проверками по таймеру, если последнее сообщение в переписке было
  /// [sinceActivity] назад; null — по таймеру не проверять (только запуск и возврат).
  static Duration? pollEvery(
    Duration sinceActivity, {
    required bool pushActive,
  }) {
    if (sinceActivity < const Duration(minutes: 2)) return interval;
    if (pushActive) return null;
    if (sinceActivity < const Duration(minutes: 10)) {
      return const Duration(seconds: 15);
    }
    if (sinceActivity < const Duration(hours: 1)) {
      return const Duration(minutes: 1);
    }
    if (sinceActivity < const Duration(hours: 24)) {
      return const Duration(minutes: 5);
    }
    return null;
  }

  Timer? _timer;
  bool _polling = false;
  DateTime? _lastFetch;

  /// The support chat screen is on top: it polls and handles new replies itself.
  bool chatOpen = false;

  /// Fetches replies newer than [since] (null: all); null result = the fetch failed.
  /// Replaced in tests.
  Future<List<SupportChatMessage>?> Function({int? since}) fetch =
      ({int? since}) =>
          SupportChatService.instance.tryFetchMessages(since: since);

  /// Whose thread is polled. Replaced in tests.
  Future<String> Function() clientId = () =>
      SupportChatService.instance.getClientId();

  /// Ответы оператора приходят этому устройству пушем. Задаёт приложение.
  bool Function() pushActive = () => false;

  /// Текущее время. Replaced in tests.
  DateTime Function() now = DateTime.now;

  /// Called with the newest operator reply when there is one to show. Set by the app.
  void Function(SupportChatMessage reply)? onReply;

  /// Sound for a new reply. Replaced in tests.
  void Function()? onSound;

  /// Запуск и возврат в приложение: проверяем сразу, дальше — по [tick].
  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(tick()));
    unawaited(poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Пришёл пуш об ответе поддержки: забираем его сразу.
  void pollNow() => unawaited(poll());

  /// The chat screen showed [messages]: they must not notify later, and they tell
  /// whether the conversation is alive or closed.
  Future<void> markShown(List<SupportChatMessage> messages) async {
    if (messages.isEmpty) return;
    final id = await clientId();
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getInt(_prefSeenPrefix + id) ?? 0;
    final newest = messages.reduce(
      (a, b) => a.timestamp >= b.timestamp ? a : b,
    );
    if (newest.timestamp > seen) {
      await prefs.setInt(_prefSeenPrefix + id, newest.timestamp);
      await prefs.setInt(_prefActivePrefix + id, now().millisecondsSinceEpoch);
      await prefs.setBool(_prefClosedPrefix + id, newest.isClosedNotice);
    }
  }

  /// Человек отправил сообщение: разговор снова живой (и закрытое обращение открыто).
  Future<void> noteSent() async {
    final id = await clientId();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefActivePrefix + id, now().millisecondsSinceEpoch);
    await prefs.setBool(_prefClosedPrefix + id, false);
  }

  /// Шаг таймера: спрашивает сервер, только если по [pollEvery] подошёл срок.
  Future<void> tick() async {
    if (chatOpen || _polling) return;
    try {
      final id = await clientId();
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefClosedPrefix + id) ?? false) return;
      final seen = prefs.getInt(_prefSeenPrefix + id) ?? 0;
      // Переписка есть, если человек писал (отметка отправки) или в ней уже
      // есть сообщения; иначе ответа ждать не от кого.
      final active =
          prefs.getInt(_prefActivePrefix + id) ?? (seen > 0 ? seen : null);
      if (active == null) return;
      final every = pollEvery(
        now().difference(DateTime.fromMillisecondsSinceEpoch(active)),
        pushActive: pushActive(),
      );
      if (every == null) return;
      final last = _lastFetch;
      if (last != null && now().difference(last) < every) return;
      await poll();
    } catch (_) {
      // Следующий шаг таймера попробует снова.
    }
  }

  /// One poll. Public for tests; launch, resume, push and [tick] call it.
  Future<void> poll() async {
    if (_polling) return;
    _polling = true;
    _lastFetch = now();
    try {
      final id = await clientId();
      final key = _prefSeenPrefix + id;
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getInt(key);
      final list = await fetch(since: (seen ?? 0) > 0 ? seen : null);
      if (list == null) return; // Failed: retried next tick, nothing is marked.

      final newest = list.map((m) => m.timestamp).fold<int>(seen ?? 0, max);
      if (seen == null || newest > seen) await prefs.setInt(key, newest);
      if (list.isNotEmpty) {
        final last = list.reduce((a, b) => a.timestamp >= b.timestamp ? a : b);
        await prefs.setBool(_prefClosedPrefix + id, last.isClosedNotice);
        // Новое сообщение — разговор живой. При первом взгляде на старую переписку
        // время берём из самого сообщения, чтобы она не опрашивалась как свежая.
        await prefs.setInt(
          _prefActivePrefix + id,
          seen == null ? newest : now().millisecondsSinceEpoch,
        );
      }
      if (seen == null) {
        return; // First look at this thread: old replies stay silent.
      }

      final replies = list
          .where((m) => m.isSupport && !m.isClosedNotice && m.timestamp > seen)
          .toList();
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
