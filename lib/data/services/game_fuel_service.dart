import 'package:shared_preferences/shared_preferences.dart';

/// Fuel for the driving game: five units, one burnt per mistake, one unit
/// regenerated every [refillInterval]. Stored as the amount plus the time of
/// the last change, so regeneration is computed on read and survives restarts.
class GameFuelService {
  GameFuelService._();
  static final GameFuelService instance = GameFuelService._();

  static const int maxFuel = 5;
  static const Duration refillInterval = Duration(minutes: 20);
  static const _fuelKey = 'game_fuel';
  static const _sinceKey = 'game_fuel_since';

  int _fuel = maxFuel;
  DateTime _since = DateTime.now();
  bool _loaded = false;

  int get fuel => _fuel;

  /// When the next unit arrives, or null when the tank is full.
  DateTime? get nextRefillAt =>
      _fuel >= maxFuel ? null : _since.add(refillInterval);

  /// When the tank will have at least one unit (for the "empty" countdown).
  DateTime? get firstUnitAt => _fuel > 0 ? null : _since.add(refillInterval);

  Future<int> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _fuel = prefs.getInt(_fuelKey) ?? maxFuel;
      _since = DateTime.fromMillisecondsSinceEpoch(
        prefs.getInt(_sinceKey) ?? DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      /* No store: play with a full tank this session. */
    }
    _loaded = true;
    return _tick();
  }

  /// Applies the time-based regeneration and returns the current amount.
  int refresh() => _tick();

  int _tick() {
    if (_fuel >= maxFuel) return _fuel;
    final elapsed = DateTime.now().difference(_since);
    final gained = elapsed.inMilliseconds ~/ refillInterval.inMilliseconds;
    if (gained > 0) {
      _fuel = (_fuel + gained).clamp(0, maxFuel);
      _since = _fuel >= maxFuel
          ? DateTime.now()
          : _since.add(refillInterval * gained);
      _persist();
    }
    return _fuel;
  }

  /// Records the amount left after a run or a mistake.
  Future<void> setFuel(int fuel) async {
    final clamped = fuel.clamp(0, maxFuel);
    if (clamped == _fuel) return;
    // Burning fuel from a full tank starts the regeneration clock now; a
    // partially refilled tank keeps its clock so nothing is lost.
    if (_fuel >= maxFuel || clamped > _fuel) _since = DateTime.now();
    _fuel = clamped;
    await _persist();
  }

  Future<void> _persist() async {
    if (!_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_fuelKey, _fuel);
      await prefs.setInt(_sinceKey, _since.millisecondsSinceEpoch);
    } catch (_) {
      /* Keep the in-memory value. */
    }
  }
}
