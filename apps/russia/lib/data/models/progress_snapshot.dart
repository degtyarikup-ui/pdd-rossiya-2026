import 'dart:convert';

/// Offline changes are merged at import, rather than replaced by a snapshot
/// that was sent before the user answered. Deletions carry a timestamp too.
Map<String, dynamic> mergeProgressSnapshots(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) {
  int time(Object? value) {
    if (value is num && value.isFinite) {
      return value.toInt().clamp(0, 9007199254740991);
    }
    return value is String
        ? DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0
        : 0;
  }

  Map<String, dynamic> map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  List<String> list(Object? value) =>
      value is List ? value.whereType<String>().toList() : [];
  final reset = [
    time(local['resetAt']),
    time(remote['resetAt']),
  ].reduce((a, b) => a > b ? a : b);
  Map<String, dynamic> records(String field, {bool favorites = false}) {
    final result = <String, dynamic>{};
    for (final source in [local, remote]) {
      for (final entry in map(source[field]).entries) {
        if (entry.value is! Map) continue;
        final value = map(entry.value);
        final stamp = time(value[favorites ? 'updatedAt' : 'answeredAt']);
        if (reset > 0 && stamp <= reset) continue;
        final previous = map(result[entry.key]);
        final oldStamp = time(previous[favorites ? 'updatedAt' : 'answeredAt']);
        final attempts = value['attemptsCount'] is num
            ? (value['attemptsCount'] as num).toInt()
            : 0;
        final oldAttempts = previous['attemptsCount'] is num
            ? (previous['attemptsCount'] as num).toInt()
            : 0;
        if (!result.containsKey(entry.key) ||
            stamp > oldStamp ||
            (stamp == oldStamp &&
                (favorites
                    ? value['present'] == false
                    : attempts >= oldAttempts))) {
          result[entry.key] = value;
        }
      }
    }
    return result;
  }

  final out = <String, dynamic>{...remote, 'resetAt': reset};
  for (final suffix in ['Ab', 'Cd']) {
    for (final prefix in ['questionProgress', 'ticketProgress']) {
      out['$prefix$suffix'] = records('$prefix$suffix');
    }
    final states = records('favoriteStates$suffix', favorites: true);
    final favorites = <String>{};
    if (reset == 0) {
      favorites.addAll([
        ...list(local['favorites$suffix']),
        ...list(remote['favorites$suffix']),
      ]);
    }
    for (final entry in states.entries) {
      if (entry.value['present'] == true) {
        favorites.add(entry.key);
      } else if (entry.value['present'] == false) {
        favorites.remove(entry.key);
      }
    }
    out['favorites$suffix'] = favorites.toList();
    out['favoriteStates$suffix'] = states;
    final exams = <String>{};
    final oldExams = local['examResults$suffix'];
    final newExams = remote['examResults$suffix'];
    for (final raw in [
      if (oldExams is List) ...oldExams,
      if (newExams is List) ...newExams,
    ]) {
      final item = raw is String ? raw : jsonEncode(raw);
      try {
        final result = jsonDecode(item);
        if (result is Map &&
            (reset == 0 ||
                time(result['completedAt'] ?? result['date']) > reset)) {
          exams.add(item);
        }
      } catch (_) {
        /* Ignore damaged history entries. */
      }
    }
    out['examResults$suffix'] = exams.toList();
  }
  final miniGames = <String, dynamic>{};
  for (final game in ['regulator', 'signs', 'crossroads']) {
    final a = map(map(local['miniGames'])[game]);
    final b = map(map(remote['miniGames'])[game]);
    miniGames[game] = {
      for (final key in [
        'bestScore',
        'maxCombo',
        'totalSolved',
        'totalSwiped',
        'trainingCount',
      ])
        key: time(a[key]) > time(b[key]) ? time(a[key]) : time(b[key]),
    };
  }
  out['miniGames'] = miniGames;
  final a = time(local['resetAt']) < reset
      ? <String, dynamic>{}
      : map(local['streak']);
  final b = time(remote['resetAt']) < reset
      ? <String, dynamic>{}
      : map(remote['streak']);
  final days = {...list(a['activeDays']), ...list(b['activeDays'])}.toList()
    ..sort();
  final latest = time(a['lastActiveDate']) > time(b['lastActiveDate']) ? a : b;
  int maximum(String key) =>
      time(a[key]) > time(b[key]) ? time(a[key]) : time(b[key]);
  out['streak'] = {
    'current': maximum('current'),
    'longest': maximum('longest'),
    'lastActiveDate': latest['lastActiveDate'],
    'startDate': latest['startDate'],
    'activeDays': days,
  };
  return out;
}
