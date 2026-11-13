import 'dart:convert';

/// Числовые поля мини-игр в слепке; все сливаются по максимуму.
/// Тот же список — в server/install-notifier/progress_merge.js.
const Map<String, List<String>> miniGameCounters = {
  'regulator': [
    'bestScore',
    'maxCombo',
    'totalSolved',
    'totalSwiped',
    'trainingCount',
  ],
  'signs': [
    'bestScore',
    'maxCombo',
    'totalSolved',
    'totalSwiped',
    'trainingCount',
  ],
  'crossroads': [
    'bestScore',
    'maxCombo',
    'totalSolved',
    'totalSwiped',
    'trainingCount',
  ],
  // level1…level25 — звёзды уровней «Парковки» (0–3), лучший результат.
  'parking': [
    'bestScore',
    'maxCombo',
    'totalSolved',
    'trainingCount',
    'level1',
    'level2',
    'level3',
    'level4',
    'level5',
    'level6',
    'level7',
    'level8',
    'level9',
    'level10',
    'level11',
    'level12',
    'level13',
    'level14',
    'level15',
    'level16',
    'level17',
    'level18',
    'level19',
    'level20',
    'level21',
    'level22',
    'level23',
    'level24',
    'level25',
  ],
  'violator': [
    'bestScore',
    'maxCombo',
    'totalViolatorsCaught',
    'totalSolved',
    'gamesPlayed',
  ],
  'roadSigns': ['bestScore', 'maxCombo', 'totalAnswered', 'totalCorrect'],
};

/// Предел списка открытых знаков в слепке (в справочнике их 312).
/// Уровней в «Парковке» (game_godot/scripts/parking_locations.gd).
const int parkingLevelCount = 25;

const int maxSignsViewed = 1000;

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
  for (final game in miniGameCounters.entries) {
    final a = map(map(local['miniGames'])[game.key]);
    final b = map(map(remote['miniGames'])[game.key]);
    miniGames[game.key] = {
      for (final key in game.value)
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
  // Счётчики ачивок, как и серия, сбрасываются вместе с прогрессом.
  final sa = time(local['resetAt']) < reset
      ? <String, dynamic>{}
      : map(local['achievementStats']);
  final sb = time(remote['resetAt']) < reset
      ? <String, dynamic>{}
      : map(remote['achievementStats']);
  String? later(String key) {
    final x = sa[key] is String ? sa[key] as String : null;
    final y = sb[key] is String ? sb[key] as String : null;
    if (x == null) return y;
    if (y == null) return x;
    return x.compareTo(y) >= 0 ? x : y;
  }

  out['achievementStats'] = {
    for (final key in ['marathonBest', 'earlyDays', 'nightDays', 'comebacks'])
      key: time(sa[key]) > time(sb[key]) ? time(sa[key]) : time(sb[key]),
    'earlyLast': later('earlyLast'),
    'nightLast': later('nightLast'),
    'signsViewed': ({
      ...list(sa['signsViewed']),
      ...list(sb['signsViewed']),
    }.toList()..sort()).take(maxSignsViewed).toList(),
  };
  out['streak'] = {
    'current': maximum('current'),
    'longest': maximum('longest'),
    'lastActiveDate': latest['lastActiveDate'],
    'startDate': latest['startDate'],
    'activeDays': days,
  };
  return out;
}
