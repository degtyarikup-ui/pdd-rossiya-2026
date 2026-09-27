import 'package:pdd_app/data/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs of the driving game for free players: up to [maxRuns] in stock, one
/// spent when a run starts, one earned back every [refillInterval] until the
/// stock is full again (wait an hour — three runs). Premium is unlimited.
/// Stored as the count plus the moment the refill clock started, so the
/// refill is computed on read and survives restarts.
class GameRunsService {
  GameRunsService._();
  static final GameRunsService instance = GameRunsService._();

  static const int maxRuns = 3;
  static const Duration refillInterval = Duration(minutes: 20);
  static const _runsKey = 'game_runs';
  static const _sinceKey = 'game_runs_since';

  int _runs = maxRuns;
  DateTime _since = DateTime.now();
  bool _loaded = false;

  int get runs => _runs;

  /// When the next run is earned, or null when the stock is full.
  DateTime? get nextRefillAt =>
      _runs >= maxRuns ? null : _since.add(refillInterval);

  /// When play is possible again (for the "no runs" countdown).
  DateTime? get firstUnitAt => _runs > 0 ? null : nextRefillAt;

  Future<int> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _runs = prefs.getInt(_runsKey) ?? maxRuns;
      _since = DateTime.fromMillisecondsSinceEpoch(
        prefs.getInt(_sinceKey) ?? DateTime.now().millisecondsSinceEpoch,
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
    if (_runs >= maxRuns) return _runs;
    final earned =
        DateTime.now().difference(_since).inSeconds ~/ refillInterval.inSeconds;
    if (earned > 0) {
      _runs = (_runs + earned).clamp(0, maxRuns);
      _since = _runs >= maxRuns
          ? DateTime.now()
          : _since.add(refillInterval * earned);
      _persist();
    }
    return _runs;
  }

  /// Spends one run; false when none is left.
  Future<bool> consume() async {
    _tick();
    if (_runs <= 0) return false;
    // The refill clock starts with the first run taken from a full stock.
    if (_runs >= maxRuns) _since = DateTime.now();
    _runs--;
    await _persist();
    // The last run is gone: a local notification says when the next is back.
    final at = nextRefillAt;
    if (_runs <= 0 && at != null) {
      await StreakNotifier.instance.scheduleGameRunReady(at);
    }
    return true;
  }

  /// No reminder is needed any more (premium, or a run is in stock).
  Future<void> cancelReminder() => StreakNotifier.instance.cancelGameRunReady();

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
