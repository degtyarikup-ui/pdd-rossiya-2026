import 'package:shared_preferences/shared_preferences.dart';

/// Fuel for the driving game: five units, one burnt per mistake. The tank
/// refills completely [refillInterval] after the first unit was burnt from a
/// full tank. Stored as the amount plus the moment the clock started, so the
/// refill is computed on read and survives restarts.
class GameFuelService {
  GameFuelService._();
  static final GameFuelService instance = GameFuelService._();

  static const int maxFuel = 5;
  static const Duration refillInterval = Duration(minutes: 30);
  static const _fuelKey = 'game_fuel';
  static const _sinceKey = 'game_fuel_since';

  int _fuel = maxFuel;
  DateTime _since = DateTime.now();
  bool _loaded = false;

  int get fuel => _fuel;

  /// When the tank is full again, or null when it already is.
  DateTime? get nextRefillAt =>
      _fuel >= maxFuel ? null : _since.add(refillInterval);

  /// When play is possible again (for the "empty" countdown): the same
  /// moment, since the whole tank comes back at once.
  DateTime? get firstUnitAt => _fuel > 0 ? null : nextRefillAt;

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

  /// Applies the time-based refill and returns the current amount.
  int refresh() => _tick();

  int _tick() {
    if (_fuel >= maxFuel) return _fuel;
    if (!DateTime.now().isBefore(_since.add(refillInterval))) {
      _fuel = maxFuel;
      _since = DateTime.now();
      _persist();
    }
    return _fuel;
  }

  /// Records the amount left after a run or a mistake.
  Future<void> setFuel(int fuel) async {
    final clamped = fuel.clamp(0, maxFuel);
    if (clamped == _fuel) return;
    // The clock starts with the first unit burnt from a full tank; further
    // mistakes do not push the refill back.
    if (_fuel >= maxFuel) _since = DateTime.now();
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
