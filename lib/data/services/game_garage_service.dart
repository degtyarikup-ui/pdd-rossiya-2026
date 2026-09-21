import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// One car in the player's garage: a model and a paint name from the engine's
/// palette (`PDD_VEHICLES.paints`).
class GameCar {
  final String id;
  final String paint;
  const GameCar(this.id, this.paint);

  String get key => '$id:$paint';

  Map<String, String> toJson() => {'id': id, 'paint': paint};

  static GameCar? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], paint = json['paint'];
    if (id is! String || paint is! String) return null;
    if (!GameGarageService.models.contains(id) &&
        id != GameGarageService.cyber) {
      return null;
    }
    return GameCar(id, paint);
  }
}

/// The garage: cars are earned with correct answers. The first car is the red
/// hatch; the next one comes after 5 correct answers, then 10 more, then 20
/// more, then every 20. Each unlock is a random model the player does not
/// have yet in a random paint; once all models are owned, new paints.
/// Premium players also get the gold cyber truck.
class GameGarageService {
  GameGarageService._();
  static final GameGarageService instance = GameGarageService._();

  static const models = ['hatch', 'sedan', 'coupe', 'wagon', 'suv', 'pickup'];
  static const cyber = 'cyber';
  static const cyberPaint = 'gold';
  static const paints = [
    'red',
    'blue',
    'green',
    'sand',
    'white',
    'black',
    'silver',
    'orange',
    'purple',
    'teal',
    'yellow',
    'wine',
  ];
  static const starter = GameCar('hatch', 'red');
  static const _steps = [5, 10, 20];
  static const _carsKey = 'game_garage_cars';
  static const _correctKey = 'game_garage_correct';
  static const _unlocksKey = 'game_garage_unlocks';

  final _random = Random();
  List<GameCar> _cars = const [starter];
  int _correct = 0;
  int _unlocks = 0;
  bool _loaded = false;

  List<GameCar> get cars => List.unmodifiable(_cars);
  int get correctTotal => _correct;

  /// Correct answers needed for the next car.
  int get nextThreshold {
    var total = 0;
    for (var i = 0; i <= _unlocks; i++) {
      total += i < _steps.length ? _steps[i] : _steps.last;
    }
    return total;
  }

  int get correctUntilNext => (nextThreshold - _correct).clamp(0, 1 << 30);

  bool owns(String id, String paint) =>
      _cars.any((c) => c.id == id && c.paint == paint);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_carsKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List<dynamic>)
            .map(GameCar.fromJson)
            .whereType<GameCar>()
            .toList();
        if (list.isNotEmpty) _cars = list;
      }
      _correct = prefs.getInt(_correctKey) ?? 0;
      _unlocks = prefs.getInt(_unlocksKey) ?? 0;
    } catch (_) {
      /* Start with the red hatch this session. */
    }
    _loaded = true;
  }

  /// Counts a correct answer; returns the car unlocked by it, if any.
  Future<GameCar?> recordCorrect() async {
    _correct++;
    GameCar? unlocked;
    if (_correct >= nextThreshold) {
      unlocked = _pickNew();
      _unlocks++;
      _cars = [..._cars, unlocked];
    }
    await _persist();
    return unlocked;
  }

  GameCar _pickNew() {
    final ownedModels = _cars.map((c) => c.id).toSet();
    final fresh = models.where((m) => !ownedModels.contains(m)).toList();
    final id = fresh.isNotEmpty
        ? fresh[_random.nextInt(fresh.length)]
        : models[_random.nextInt(models.length)];
    final usedPaints = _cars
        .where((c) => c.id == id)
        .map((c) => c.paint)
        .toSet();
    final freshPaints = paints.where((p) => !usedPaints.contains(p)).toList();
    final paint = freshPaints.isNotEmpty
        ? freshPaints[_random.nextInt(freshPaints.length)]
        : paints[_random.nextInt(paints.length)];
    return GameCar(id, paint);
  }

  Future<void> _persist() async {
    if (!_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _carsKey,
        jsonEncode(_cars.map((c) => c.toJson()).toList()),
      );
      await prefs.setInt(_correctKey, _correct);
      await prefs.setInt(_unlocksKey, _unlocks);
    } catch (_) {
      /* Keep the in-memory garage. */
    }
  }

  /// Test hook: resets to the starter garage without touching storage.
  void resetForTest() {
    _cars = const [starter];
    _correct = 0;
    _unlocks = 0;
    _loaded = false;
  }
}
