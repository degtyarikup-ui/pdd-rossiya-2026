import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

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
    if (!GameGarageService.vehicleIds.contains(id)) {
      return null;
    }
    if (!GameGarageService.paintHex.containsKey(paint) &&
        !GameGarageService.legacyPaints.containsKey(paint)) {
      return null;
    }
    return GameCar(id, GameGarageService.normalizePaint(paint));
  }
}

/// A fixed milestone awards either one model or one colour for every model.
class GameGarageReward {
  final int threshold;
  final String? model;
  final String? paint;

  const GameGarageReward.model(this.threshold, String id)
    : model = id,
      paint = null;
  const GameGarageReward.paint(this.threshold, String id)
    : paint = id,
      model = null;

  bool get isModel => model != null;
}

/// Permanent rewards for correct answers in Living City. Ownership is split
/// into models and global colours; the legacy pair format remains compatible
/// with cloud union merging and older clients.
class GameGarageService {
  GameGarageService._();
  static final GameGarageService instance = GameGarageService._();

  static const models = ['hatch', 'sedan', 'coupe', 'wagon', 'suv', 'pickup'];
  static const cyber = 'cyber';
  static const mini = 'mini';
  static const premiumModels = [mini, cyber];
  static const vehicleIds = [...models, ...premiumModels];
  static const cyberPaint = 'yellow';
  static const paintHex = {
    'red': 0xFFED4621,
    'blue': 0xFF317ED4,
    'green': 0xFF4D7768,
    'yellow': 0xFFE8C547,
    'white': 0xFFF2F3F5,
    'black': 0xFF2B2F36,
    'pink': 0xFFF16EA3,
    'leopard': 0xFFF68A2D,
  };
  static const paints = ['red', 'blue', 'green', 'yellow', 'white', 'black'];
  static const leopard = 'leopard';
  static const premiumPaints = ['pink', leopard];
  static const allPaints = [...paints, ...premiumPaints];
  static const legacyPaints = {
    'sand': 'yellow',
    'orange': 'red',
    'purple': 'red',
    'wine': 'red',
    'silver': 'white',
    'teal': 'green',
    'gold': 'yellow',
  };
  static String normalizePaint(String paint) => paintHex.containsKey(paint)
      ? paint
      : legacyPaints[paint] ?? starter.paint;

  static const starter = GameCar('hatch', 'red');
  static const rewards = [
    GameGarageReward.model(5, 'sedan'),
    GameGarageReward.paint(10, 'blue'),
    GameGarageReward.model(20, 'wagon'),
    GameGarageReward.paint(35, 'white'),
    GameGarageReward.model(55, 'coupe'),
    GameGarageReward.paint(80, 'black'),
    GameGarageReward.model(110, 'suv'),
    GameGarageReward.model(200, 'pickup'),
    GameGarageReward.paint(260, 'green'),
    GameGarageReward.paint(330, 'yellow'),
  ];
  static const _vehicleKey = 'game_vehicle';
  static const _paintKey = 'game_vehicle_paint';
  static const _modelPaintsKey = 'game_vehicle_paints_v1';
  static const _mileageKey = 'game_garage_mileage_v1';
  static const _carsKey = 'game_garage_cars';
  static const _correctKey = 'game_garage_correct';
  static const _unlocksKey = 'game_garage_unlocks';

  Set<String> _models = {starter.id};
  Set<String> _paints = {starter.paint};
  int _correct = 0;
  bool _loaded = false;
  Future<void> _writes = Future.value();

  List<String> get ownedModels => List.unmodifiable([
    for (final id in [...models, cyber])
      if (_models.contains(id)) id,
  ]);
  List<String> get ownedPaints => List.unmodifiable([
    for (final paint in paints)
      if (_paints.contains(paint)) paint,
  ]);
  List<GameCar> get cars => List.unmodifiable([
    for (final id in ownedModels)
      for (final paint in ownedPaints) GameCar(id, paint),
  ]);
  int get correctTotal => _correct;

  List<String> availableModels({required bool premium}) =>
      premium ? vehicleIds : ownedModels;

  List<String> availablePaints({required bool premium}) =>
      premium ? allPaints : ownedPaints;

  Future<GameCar> selection({required bool premium}) async =>
      (await loadSelection(premium: premium)).car;

  /// The shared palette controls availability. Each car keeps its own choice.
  Future<({GameCar car, Map<String, String> modelPaints})> loadSelection({
    required bool premium,
    bool repair = false,
  }) => _serial(() async {
    if (!_loaded) await _load();
    final prefs = await SharedPreferences.getInstance();
    final saved = _readModelPaints(prefs);
    final id = prefs.getString(_vehicleKey);
    final available = availablePaints(premium: premium);
    final modelPaints = {
      for (final model in availableModels(premium: premium))
        model: available.contains(saved[model]) ? saved[model]! : starter.paint,
    };
    final selectedId = modelPaints.containsKey(id) ? id! : starter.id;
    final car = GameCar(selectedId, modelPaints[selectedId]!);
    if (repair && await _writeModelPaints(prefs, saved)) {
      await _writeSelection(prefs, car);
    }
    return (car: car, modelPaints: modelPaints);
  });

  /// Flutter sets one paint. Godot sends all explicit edits from the visit,
  /// including edits made to cars other than the final selection.
  Future<bool> select(
    GameCar car, {
    required bool premium,
    Map<String, String>? paintChanges,
  }) => _serial(() async {
    if (!_loaded) await _load();
    final models = availableModels(premium: premium);
    final paints = availablePaints(premium: premium);
    if (!models.contains(car.id) || !paints.contains(car.paint)) return false;
    final prefs = await SharedPreferences.getInstance();
    final saved = _readModelPaints(prefs);
    for (final entry in (paintChanges ?? {car.id: car.paint}).entries) {
      if (models.contains(entry.key) && paints.contains(entry.value)) {
        saved[entry.key] = entry.value;
      }
    }
    final paint = saved[car.id];
    final selected = GameCar(
      car.id,
      paints.contains(paint) ? paint! : starter.paint,
    );
    return await _writeModelPaints(prefs, saved) &&
        await _writeSelection(prefs, selected);
  });

  Map<String, String> _readModelPaints(SharedPreferences prefs) {
    final raw = prefs.getString(_modelPaintsKey);
    if (raw != null) {
      try {
        final saved = jsonDecode(raw);
        if (saved is Map) {
          return {
            for (final id in vehicleIds)
              if (saved[id] case final String paint) id: normalizePaint(paint),
          };
        }
      } on FormatException {
        // Fall back to the last selection if the new data is damaged.
      }
    }
    final id = prefs.getString(_vehicleKey);
    final paint = prefs.getString(_paintKey);
    return {
      if (paint != null)
        (vehicleIds.contains(id) ? id! : starter.id): normalizePaint(paint),
    };
  }

  Future<bool> _writeModelPaints(
    SharedPreferences prefs,
    Map<String, String> paints,
  ) async {
    final encoded = jsonEncode(paints);
    return prefs.getString(_modelPaintsKey) == encoded ||
        await prefs.setString(_modelPaintsKey, encoded);
  }

  Future<bool> _writeSelection(SharedPreferences prefs, GameCar car) async {
    if (prefs.getString(_paintKey) != car.paint &&
        !await prefs.setString(_paintKey, car.paint)) {
      return false;
    }
    return prefs.getString(_vehicleKey) == car.id ||
        await prefs.setString(_vehicleKey, car.id);
  }

  /// An identifier independent of the competitive leaderboard run.
  static String newVisitId() =>
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${Random.secure().nextInt(0x7FFFFFFF).toRadixString(16)}';

  Future<Map<String, int>> mileage(String? account) => _serial(() async {
    if (account == null) return const {};
    final prefs = await SharedPreferences.getInstance();
    return _readMileage(prefs, account).totals;
  });

  /// Each summary is cumulative for this visit. Save its checkpoint and
  /// the odometer together so retries and later checkpoints only add new travel.
  Future<void> recordMileage(
    String? account,
    Object? visit,
    Object? millimeters,
  ) async {
    if (account == null ||
        visit is! String ||
        !RegExp(r'^[0-9]+-[a-f0-9]+-[0-9]+$').hasMatch(visit) ||
        millimeters is! Map ||
        millimeters.isEmpty) {
      return;
    }
    try {
      await _serial(() async {
        final prefs = await SharedPreferences.getInstance();
        final data = _readMileage(prefs, account);
        final previous = _distances(data.visits[visit]);
        var changed = false;
        for (final entry in _distances(millimeters).entries) {
          final delta = entry.value - (previous[entry.key] ?? 0);
          if (delta <= 0) continue;
          previous[entry.key] = entry.value;
          data.totals.update(
            entry.key,
            (total) => total + delta,
            ifAbsent: () => delta,
          );
          changed = true;
        }
        if (!changed) return;
        data.visits.remove(visit);
        data.visits[visit] = previous;
        if (data.visits.length > 256) {
          data.visits.remove(data.visits.keys.first);
        }
        await prefs.setString(
          '$_mileageKey:$account',
          jsonEncode({'totals': data.totals, 'visits': data.visits}),
        );
      });
    } catch (_) {
      // Storage failure must not interrupt existing score and reward handling.
    }
  }

  static Map<String, int> _distances(Object? value) => {
    if (value is Map)
      for (final id in vehicleIds)
        if (value[id] case final num distance
            when distance.isFinite && distance >= 1)
          id: distance.toInt(),
  };

  static ({Map<String, int> totals, Map<String, dynamic> visits}) _readMileage(
    SharedPreferences prefs,
    String account,
  ) {
    try {
      final data = jsonDecode(prefs.getString('$_mileageKey:$account') ?? '{}');
      if (data is Map<String, dynamic>) {
        return (
          totals: _distances(data['totals']),
          visits: data['visits'] is Map<String, dynamic>
              ? data['visits'] as Map<String, dynamic>
              : {},
        );
      }
    } on FormatException {
      // A damaged odometer entry does not affect rewards or selection.
    }
    return (totals: {}, visits: {});
  }

  bool owns(String id, String paint) {
    final canonical = paintHex.containsKey(paint) ? paint : legacyPaints[paint];
    return canonical != null &&
        _models.contains(id) &&
        _paints.contains(canonical);
  }

  bool hasReward(GameGarageReward reward) => reward.isModel
      ? _models.contains(reward.model)
      : _paints.contains(reward.paint);
  GameGarageReward? get nextReward {
    for (final reward in rewards) {
      if (!hasReward(reward)) return reward;
    }
    return null;
  }

  int get nextThreshold => nextReward?.threshold ?? _correct;
  int get correctUntilNext => (nextThreshold - _correct).clamp(0, 1 << 30);

  Future<T> _serial<T>(Future<T> Function() action) {
    final operation = _writes.then((_) => action());
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> load() => _serial(() async {
    if (!_loaded) await _load();
  });

  /// Cloud imports share the same storage queue as local awards. A late
  /// response cannot overwrite a collection that is being saved by a ride.
  Future<void> importFromCloud(Future<void> Function() update) =>
      _serial(() async {
        try {
          await update();
        } finally {
          _loaded = false;
        }
      });

  Future<void> _load() async {
    _models = {starter.id};
    _paints = {starter.paint};
    _correct = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      _correct = (prefs.getInt(_correctKey) ?? 0).clamp(0, 1 << 30);
      final raw = prefs.getString(_carsKey);
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final car
                in decoded.map(GameCar.fromJson).whereType<GameCar>()) {
              // Premium-only Mini never becomes a permanent garage reward.
              if (car.id == mini) continue;
              _models.add(car.id);
              if (!premiumPaints.contains(car.paint)) _paints.add(car.paint);
            }
          }
        } catch (_) {
          // Damaged cars must not discard the saved answer total.
        }
      }
      _grantDue();
      _loaded = true;
      await _persist();
    } catch (_) {
      _loaded = true;
    }
  }

  List<GameGarageReward> _grantDue() {
    final unlocked = <GameGarageReward>[];
    for (final reward in rewards) {
      if (_correct < reward.threshold) break;
      if (hasReward(reward)) continue;
      if (reward.isModel) {
        _models.add(reward.model!);
      } else {
        _paints.add(reward.paint!);
      }
      unlocked.add(reward);
    }
    return unlocked;
  }

  /// Resumed visits pass just their new answers. Batches can cross several
  /// milestones; serial writes prevent simultaneous visits losing progress.
  Future<List<GameGarageReward>> recordCorrectAnswers(int count) =>
      _serial(() async {
        if (!_loaded) await _load();
        if (count <= 0) return <GameGarageReward>[];
        _correct += count;
        final unlocked = _grantDue();
        await _persist();
        return unlocked;
      });

  Future<void> _persist() async {
    if (!_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Old clients also see the global colours through the cross-product.
      await prefs.setString(
        _carsKey,
        jsonEncode(cars.map((c) => c.toJson()).toList()),
      );
      await prefs.setInt(_correctKey, _correct);
      await prefs.setInt(_unlocksKey, rewards.where(hasReward).length);
    } catch (_) {
      // Keep the in-memory collection if device storage is unavailable.
    }
  }

  void invalidate() {
    _loaded = false;
  }

  void resetForTest() {
    _models = {starter.id};
    _paints = {starter.paint};
    _correct = 0;
    _loaded = false;
    _writes = Future.value();
  }
}
