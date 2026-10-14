import 'dart:convert';

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
    if (!GameGarageService.models.contains(id) &&
        id != GameGarageService.cyber) {
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
  static const cyberPaint = 'yellow';
  static const paintHex = {
    'red': 0xFFED4621,
    'blue': 0xFF317ED4,
    'green': 0xFF4D7768,
    'white': 0xFFF2F3F5,
    'black': 0xFF2B2F36,
    'silver': 0xFFB9C0C7,
    'yellow': 0xFFE8C547,
    'wine': 0xFF8B1E2D,
  };
  static const paints = [
    'red',
    'blue',
    'green',
    'white',
    'black',
    'silver',
    'yellow',
    'wine',
  ];
  static const legacyPaints = {
    'sand': 'yellow',
    'orange': 'red',
    'purple': 'wine',
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
    GameGarageReward.paint(150, 'silver'),
    GameGarageReward.model(200, 'pickup'),
    GameGarageReward.paint(260, 'green'),
    GameGarageReward.paint(330, 'yellow'),
    GameGarageReward.paint(420, 'wine'),
  ];
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
              _models.add(car.id);
              _paints.add(car.paint);
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
