import 'dart:math';

import 'package:pdd_app/core/config/country_config.dart';

/// The four source positions are groups; a ticket contributes one intact
/// five-question block to each group. Individual questions are never shuffled.
class ExamQuestionBank {
  ExamQuestionBank(List<Map<String, dynamic>> questions, this.rules) {
    final positions = <int, int>{};
    for (final question in questions) {
      final ticket = (question['ticketNumber'] as num?)?.toInt() ?? 0;
      final fallback = positions.update(
        ticket,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      final explicit = (question['questionNumber'] as num?)?.toInt();
      final position = explicit != null && explicit > 0 ? explicit : fallback;
      // Legacy in-memory fixtures can contain several tickets under one number.
      // Production loaders provide the explicit original question number.
      final group = ((position - 1) % rules.mainCount) ~/ rules.blockSize;
      final key = '$ticket:${(position - 1) ~/ rules.mainCount}:$group';
      final block = _blocks.putIfAbsent(key, () => []);
      block.add({
        ...question,
        'questionNumber': position,
        'examGroup': group,
        'examBlock': key,
      });
    }
    _blocks.removeWhere((_, block) => block.length != rules.blockSize);
    for (final block in _blocks.values) {
      block.sort(
        (a, b) =>
            (a['questionNumber'] as int).compareTo(b['questionNumber'] as int),
      );
    }
  }

  final ExamRules rules;
  final _blocks = <String, List<Map<String, dynamic>>>{};

  List<List<Map<String, dynamic>>> _group(int group) => _blocks.values
      .where((block) => block.first['examGroup'] == group)
      .toList();

  List<Map<String, dynamic>> mainQuestions(Random random) {
    final result = <Map<String, dynamic>>[];
    for (var group = 0; group < rules.mainCount ~/ rules.blockSize; group++) {
      final candidates = _group(group);
      if (candidates.isEmpty) return [];
      result.addAll(candidates[random.nextInt(candidates.length)]);
    }
    return result;
  }

  List<Map<String, dynamic>> additionalQuestions({
    required Iterable<int> groups,
    required Set<String> usedIds,
    required Random random,
  }) {
    final result = <Map<String, dynamic>>[];
    final used = {...usedIds};
    for (final group in groups) {
      final candidates = _group(
        group,
      ).where((block) => block.every((q) => !used.contains(q['id']))).toList();
      if (candidates.isEmpty) return [];
      final block = candidates[random.nextInt(candidates.length)];
      result.addAll(block);
      used.addAll(block.map((q) => q['id'] as String));
    }
    return result;
  }
}
