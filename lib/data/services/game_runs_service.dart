import 'package:flutter/foundation.dart';
import 'package:pdd_app/data/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs of the driving game for free players: up to [maxRuns] in stock, one
/// spent when a run starts. The entire stock returns [refillInterval] after
/// the first run spent from a full stock. Later runs do not restart the clock.
/// Premium is unlimited.
/// Stored as the count plus the moment the refill clock started, so the
/// refill is computed on read and survives restarts.
class GameRunsService {
  GameRunsService._()
    : _now = DateTime.now,
      _scheduleReminder = StreakNotifier.instance.scheduleGameRunReady,
      _cancelReminder = StreakNotifier.instance.cancelGameRunReady;

  @visibleForTesting
  GameRunsService.forTesting({
    required DateTime Function() now,
    Future<void> Function(DateTime)? scheduleReminder,
    Future<void> Function()? cancelReminder,
  }) : _now = now,
       _scheduleReminder = scheduleReminder ?? ((_) async {}),
       _cancelReminder = cancelReminder ?? (() async {});

  static final GameRunsService instance = GameRunsService._();

  static const int maxRuns = 3;
  static const Duration refillInterval = Duration(hours: 1);
  static const _runsKey = 'game_runs';
  static const _sinceKey = 'game_runs_since';

  final DateTime Function() _now;
  final Future<void> Function(DateTime) _scheduleReminder;
  final Future<void> Function() _cancelReminder;
  int _runs = maxRuns;
  late DateTime _since = _now();
  bool _loaded = false;

  int get runs => _runs;

  /// When the entire stock returns, or null when it is already full.
  DateTime? get nextRefillAt =>
      _runs >= maxRuns ? null : _since.add(refillInterval);

  /// When play is possible again (for the "no runs" countdown).
  DateTime? get firstUnitAt => _runs > 0 ? null : nextRefillAt;

  Future<int> load() async {
    _runs = maxRuns;
    _since = _now();
    try {
      final prefs = await SharedPreferences.getInstance();
      _runs = prefs.getInt(_runsKey) ?? maxRuns;
      // DateTime supports at most 100,000,000 days from the Unix epoch.
      // An invalid saved value must not prevent reading the remaining runs.
      _since = DateTime.fromMillisecondsSinceEpoch(
        (prefs.getInt(_sinceKey) ?? _now().millisecondsSinceEpoch).clamp(
          -8640000000000000,
          8640000000000000,
        ),
      );
    } catch (_) {
      /* No store: a full stock this session. */
    }
    _loaded = true;
    return _tick();
  }

  /// Applies the time-based refill and returns the current stock.
  int refresh() => _tick();

  int _tick() {
    final now = _now();
    var changed = false;
    final boundedRuns = _runs.clamp(0, maxRuns);
    if (_runs != boundedRuns) {
      _runs = boundedRuns;
      changed = true;
    }
    // A corrected device clock cannot leave the player waiting indefinitely.
    if (_since.isAfter(now)) {
      _since = now;
      changed = true;
    }
    if (_runs < maxRuns && now.difference(_since) >= refillInterval) {
      _runs = maxRuns;
      _since = now;
      changed = true;
    }
    if (changed) _persist();
    return _runs;
  }

  /// Spends one run; false when none is left.
  Future<bool> consume() async {
    _tick();
    if (_runs <= 0) return false;
    // The refill clock starts with the first run taken from a full stock.
    if (_runs >= maxRuns) _since = _now();
    _runs--;
    await _persist();
    // The last run is gone: a local notification says when the next is back.
    final at = nextRefillAt;
    if (_runs <= 0 && at != null) {
      await _scheduleReminder(at);
    }
    return true;
  }

  /// No reminder is needed any more (premium, or a run is in stock).
  Future<void> cancelReminder() => _cancelReminder();

  Future<void> _persist() async {
    if (!_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_runsKey, _runs);
      await prefs.setInt(_sinceKey, _since.millisecondsSinceEpoch);
    } catch (_) {
      /* Keep the in-memory value. */
    }
  }
}
