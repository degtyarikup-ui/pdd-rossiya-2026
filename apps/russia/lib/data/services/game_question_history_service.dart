import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local exposure counts for city cards, independent of answers, accounts and fuel.
/// The Godot process stores the same snapshot to survive an interrupted native ride.
class GameQuestionHistory {
  static const version = 1;
  static const _maxValue = 9007199254740991;
  static final _validId = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');

  final int sequence;
  final Map<String, int> lastShown;
  final Map<String, int> showCounts;

  GameQuestionHistory._(
    this.sequence,
    Map<String, int> shown,
    Map<String, int> counts,
  ) : lastShown = Map.unmodifiable(shown),
      showCounts = Map.unmodifiable(counts);

  factory GameQuestionHistory.empty() => GameQuestionHistory._(0, {}, {});

  static int _number(Object? value) =>
      value is num &&
          value.isFinite &&
          value >= 0 &&
          value <= _maxValue &&
          value == value.floor()
      ? value.toInt()
      : 0;

  factory GameQuestionHistory.fromJson(Object? data) {
    if (data is! Map || data['version'] != version) {
      return GameQuestionHistory.empty();
    }
    var sequence = _number(data['sequence']);
    final shown = <String, int>{};
    final counts = <String, int>{};
    final rawShown = data['last_shown'];
    if (rawShown is Map) {
      for (final entry in rawShown.entries) {
        final id = entry.key;
        final last = _number(entry.value);
        if (id is! String || !_validId.hasMatch(id) || last == 0) continue;
        shown[id] = last;
        // A previous v1 snapshot did not yet carry per-card exposure counts.
        counts[id] = 1;
        if (last > sequence) sequence = last;
      }
    }
    final rawCounts = data['show_counts'];
    if (rawCounts is Map) {
      for (final entry in rawCounts.entries) {
        final id = entry.key;
        final count = _number(entry.value);
        if (id is! String || !_validId.hasMatch(id) || count == 0) continue;
        counts[id] = count;
      }
    }
    return GameQuestionHistory._(sequence, shown, counts);
  }

  GameQuestionHistory merge(GameQuestionHistory other) {
    Map<String, int> maximums(Map<String, int> left, Map<String, int> right) {
      final result = Map<String, int>.of(left);
      for (final entry in right.entries) {
        if (entry.value > (result[entry.key] ?? 0)) {
          result[entry.key] = entry.value;
        }
      }
      return result;
    }

    return GameQuestionHistory._(
      sequence > other.sequence ? sequence : other.sequence,
      maximums(lastShown, other.lastShown),
      maximums(showCounts, other.showCounts),
    );
  }

  Map<String, Object> toJson() => {
    'version': version,
    'sequence': sequence,
    'last_shown': lastShown,
    'show_counts': showCounts,
  };
}

/// SharedPreferences is the Flutter copy; writes are serialized so delayed
/// question events or exit summaries cannot replace newer local history.
class GameQuestionHistoryService {
  GameQuestionHistoryService._();
  static final instance = GameQuestionHistoryService._();
  static const storageKey = 'godot_city_question_history_v1';

  GameQuestionHistory _memory = GameQuestionHistory.empty();
  Future<void>? _writes;

  @visibleForTesting
  void resetForTest() {
    _memory = GameQuestionHistory.empty();
    _writes = null;
  }

  void _read(SharedPreferences prefs) {
    final value = prefs.getString(storageKey);
    if (value != null) {
      _memory = _memory.merge(GameQuestionHistory.fromJson(jsonDecode(value)));
    }
  }

  Future<Map<String, Object>> load() async {
    final pending = _writes;
    if (pending != null) await pending;
    try {
      _read(await SharedPreferences.getInstance());
    } catch (_) {
      // Keep the in-memory snapshot when storage is absent or damaged.
    }
    return _memory.toJson();
  }

  Future<void> recordSnapshot(Object? data) {
    final incoming = GameQuestionHistory.fromJson(data);
    Future<void> write() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        try {
          _read(prefs);
        } catch (_) {
          // A valid current snapshot repairs a malformed stored value.
        }
        _memory = _memory.merge(incoming);
        await prefs.setString(storageKey, jsonEncode(_memory.toJson()));
      } catch (_) {
        _memory = _memory.merge(incoming);
      }
    }

    final pending = _writes;
    return _writes = pending == null ? write() : pending.then((_) => write());
  }

  Future<void> recordEvent(Map event) async {
    if (event['event'] == 'question_shown') {
      await recordSnapshot(event['question_history']);
    }
  }
}
