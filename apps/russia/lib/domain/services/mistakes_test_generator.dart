import 'dart:math';

import 'package:pdd_app/data/models/question.dart';

/// Запись об ошибке по конкретному вопросу с историей попыток.
class MistakeQuestionEntry {
  const MistakeQuestionEntry({
    required this.question,
    required this.wrongAttempts,
    required this.attemptsCount,
    required this.isCurrentlyWrong,
    this.answeredAt,
  });

  final Question question;
  final int wrongAttempts;
  final int attemptsCount;
  final bool isCurrentlyWrong;
  final DateTime? answeredAt;
}

/// Агрегированная статистика ошибок по одной тематике ПДД.
class WeakTopicSummary {
  const WeakTopicSummary({
    required this.name,
    required this.questions,
    required this.mistakeAttempts,
    required this.activeMistakeCount,
    required this.mistakeQuestionCount,
    required this.unseenCount,
  });

  final String name;
  final List<Question> questions;
  final int mistakeAttempts;
  final int activeMistakeCount;
  final int mistakeQuestionCount;
  final int unseenCount;

  int get totalQuestions => questions.length;
}

/// Результат анализа ошибок пользователя по всему банку вопросов категории.
class MistakesAnalysis {
  const MistakesAnalysis({
    required this.activeMistakes,
    required this.frequentMistakes,
    required this.weakTopics,
    required this.allUniqueQuestions,
    required this.progressById,
    required this.entriesById,
  });

  final List<MistakeQuestionEntry> activeMistakes;
  final List<MistakeQuestionEntry> frequentMistakes;
  final List<WeakTopicSummary> weakTopics;
  final List<Question> allUniqueQuestions;
  final Map<String, Map<String, dynamic>> progressById;
  final Map<String, MistakeQuestionEntry> entriesById;

  bool get hasAnyHistory =>
      activeMistakes.isNotEmpty || frequentMistakes.isNotEmpty;

  /// Показывать ли отдельный тренажёр «Сложные вопросы за всё время»:
  /// имеет смысл, когда есть исправленные ранее ошибки или повторные промахи.
  bool get hasDrillableFrequentMistakes =>
      frequentMistakes.isNotEmpty &&
      (frequentMistakes.length > activeMistakes.length ||
          frequentMistakes.any((entry) => entry.wrongAttempts >= 2));

  static int _attemptCount(Object? value) =>
      value is num && value.isFinite ? max(0, value.toInt()) : 0;

  static MistakesAnalysis build({
    required List<Question> allQuestions,
    required Map<String, dynamic> progress,
    Iterable<String> activeWrongIds = const [],
  }) {
    final activeWrongSet = activeWrongIds.toSet();
    final uniqueQuestions = <Question>[];
    final seenIds = <String>{};
    for (final q in allQuestions) {
      if (q.id.isEmpty || !seenIds.add(q.id)) continue;
      uniqueQuestions.add(q);
    }

    final normalizedProgress = <String, Map<String, dynamic>>{};
    for (final entry in progress.entries) {
      if (entry.value is Map) {
        normalizedProgress[entry.key] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
    }

    final entriesById = <String, MistakeQuestionEntry>{};
    final activeMistakes = <MistakeQuestionEntry>[];
    final frequentMistakes = <MistakeQuestionEntry>[];

    final topicQuestions = <String, List<Question>>{};
    final topicMistakeAttempts = <String, int>{};
    final topicActiveCount = <String, int>{};
    final topicMistakeQuestionCount = <String, int>{};
    final topicUnseenCount = <String, int>{};

    for (final q in uniqueQuestions) {
      final snap = normalizedProgress[q.id];
      final isCorrectFlag = snap != null && snap['isCorrect'] == true;
      final isCurrentlyWrong =
          activeWrongSet.contains(q.id) ||
          (snap != null && snap['isCorrect'] == false);
      final storedWrong = _attemptCount(snap?['wrongAttempts']);
      final wrongAttempts = isCurrentlyWrong
          ? max(1, storedWrong)
          : storedWrong;
      final attemptsCount = max(
        _attemptCount(snap?['attemptsCount']),
        wrongAttempts + (isCorrectFlag ? 1 : 0),
      );
      final answeredAtRaw = snap?['answeredAt'];
      final answeredAt = answeredAtRaw is String
          ? DateTime.tryParse(answeredAtRaw)
          : null;

      final entry = MistakeQuestionEntry(
        question: q,
        wrongAttempts: wrongAttempts,
        attemptsCount: attemptsCount,
        isCurrentlyWrong: isCurrentlyWrong,
        answeredAt: answeredAt,
      );
      entriesById[q.id] = entry;

      if (isCurrentlyWrong) {
        activeMistakes.add(entry);
      }
      if (wrongAttempts > 0) {
        frequentMistakes.add(entry);
      }

      final seenTopicsForQuestion = <String>{};
      for (final rawTopic in q.topic) {
        final topic = rawTopic.trim();
        if (topic.isEmpty || !seenTopicsForQuestion.add(topic)) continue;
        topicQuestions.putIfAbsent(topic, () => []).add(q);
        if (snap == null && !isCurrentlyWrong) {
          topicUnseenCount[topic] = (topicUnseenCount[topic] ?? 0) + 1;
        }
        if (wrongAttempts > 0) {
          topicMistakeAttempts[topic] =
              (topicMistakeAttempts[topic] ?? 0) + wrongAttempts;
          topicMistakeQuestionCount[topic] =
              (topicMistakeQuestionCount[topic] ?? 0) + 1;
        }
        if (isCurrentlyWrong) {
          topicActiveCount[topic] = (topicActiveCount[topic] ?? 0) + 1;
        }
      }
    }

    int compareEntries(MistakeQuestionEntry a, MistakeQuestionEntry b) {
      final byWrong = b.wrongAttempts.compareTo(a.wrongAttempts);
      if (byWrong != 0) return byWrong;
      if (a.isCurrentlyWrong != b.isCurrentlyWrong) {
        return a.isCurrentlyWrong ? -1 : 1;
      }
      final aRate = a.attemptsCount > 0 ? a.wrongAttempts / a.attemptsCount : 0;
      final bRate = b.attemptsCount > 0 ? b.wrongAttempts / b.attemptsCount : 0;
      final byRate = bRate.compareTo(aRate);
      if (byRate != 0) return byRate;
      final byTicket = a.question.ticketNumber.compareTo(
        b.question.ticketNumber,
      );
      if (byTicket != 0) return byTicket;
      return a.question.questionNumber.compareTo(b.question.questionNumber);
    }

    activeMistakes.sort(compareEntries);
    frequentMistakes.sort(compareEntries);

    final weakTopics = <WeakTopicSummary>[
      for (final entry in topicMistakeAttempts.entries)
        if (entry.value > 0)
          WeakTopicSummary(
            name: entry.key,
            questions: List.unmodifiable(topicQuestions[entry.key]!),
            mistakeAttempts: entry.value,
            activeMistakeCount: topicActiveCount[entry.key] ?? 0,
            mistakeQuestionCount: topicMistakeQuestionCount[entry.key] ?? 0,
            unseenCount: topicUnseenCount[entry.key] ?? 0,
          ),
    ];

    weakTopics.sort((a, b) {
      final byAttempts = b.mistakeAttempts.compareTo(a.mistakeAttempts);
      if (byAttempts != 0) return byAttempts;
      final byActive = b.activeMistakeCount.compareTo(a.activeMistakeCount);
      if (byActive != 0) return byActive;
      final byQuestions = b.mistakeQuestionCount.compareTo(
        a.mistakeQuestionCount,
      );
      if (byQuestions != 0) return byQuestions;
      return a.name.compareTo(b.name);
    });

    return MistakesAnalysis(
      activeMistakes: List.unmodifiable(activeMistakes),
      frequentMistakes: List.unmodifiable(frequentMistakes),
      weakTopics: List.unmodifiable(weakTopics),
      allUniqueQuestions: List.unmodifiable(uniqueQuestions),
      progressById: Map.unmodifiable(normalizedProgress),
      entriesById: Map.unmodifiable(entriesById),
    );
  }
}

/// Генератор тренировок и общих тестов на основе частых ошибок и слабых тем.
class MistakesTestGenerator {
  MistakesTestGenerator._();

  /// Формирует общий тест (по умолчанию 20 вопросов):
  /// 1) Якоря — самые частые / текущие ошибки (до ~35%, с разбросом по темам).
  /// 2) Расширение — новые и смежные вопросы из слабых тем, пропорционально
  ///    числу ошибок в каждой теме.
  /// 3) Добор до [targetCount] из остального банка (сначала неизученные),
  ///    если суммарно в слабых темах меньше вопросов, чем размер теста.
  static List<Question> generateFrequentMistakesTest(
    MistakesAnalysis analysis, {
    int targetCount = 20,
    Random? random,
  }) {
    if (!analysis.hasAnyHistory || targetCount <= 0) return const [];
    final all = analysis.allUniqueQuestions;
    final limit = min(targetCount, all.length);
    if (limit == 0) return const [];

    final rng = random ?? Random();
    final picked = <Question>[];
    final pickedIds = <String>{};

    void addQuestion(Question q) {
      if (picked.length >= limit) return;
      if (pickedIds.add(q.id)) {
        picked.add(q);
      }
    }

    // 1. Якорные вопросы — частые ошибки, сначала по одному из разных тем.
    final anchorLimit = (limit * 0.35).round().clamp(1, limit);
    final anchorCandidates = List<MistakeQuestionEntry>.of(
      analysis.frequentMistakes,
    );
    final coveredTopics = <String>{};
    for (final entry in anchorCandidates) {
      if (picked.length >= anchorLimit) break;
      final primaryTopic = entry.question.topic
          .map((t) => t.trim())
          .firstWhere((t) => t.isNotEmpty, orElse: () => '');
      if (primaryTopic.isNotEmpty && coveredTopics.add(primaryTopic)) {
        addQuestion(entry.question);
      }
    }
    for (final entry in anchorCandidates) {
      if (picked.length >= anchorLimit) break;
      addQuestion(entry.question);
    }

    // 2. Расширение по слабым темам пропорционально числу ошибок.
    if (picked.length < limit && analysis.weakTopics.isNotEmpty) {
      final topicQueues = <WeakTopicSummary, List<Question>>{
        for (final topic in analysis.weakTopics)
          topic: _rankCandidates(
            topic.questions,
            analysis: analysis,
            excludedIds: pickedIds,
            preferUnseenBeforePastMistakes: true,
            random: rng,
          ),
      };

      // Взвешенный round-robin (Д'Ондт): чем больше ошибок в теме, тем чаще
      // берётся следующий вопрос из неё, но более редкие слабые темы тоже
      // получают долю вопросов.
      final topicCounts = <WeakTopicSummary, int>{
        for (final topic in analysis.weakTopics) topic: 0,
      };

      while (picked.length < limit) {
        WeakTopicSummary? bestTopic;
        double bestScore = -1;
        for (final topic in analysis.weakTopics) {
          final queue = topicQueues[topic]!;
          while (queue.isNotEmpty && pickedIds.contains(queue.first.id)) {
            queue.removeAt(0);
          }
          if (queue.isEmpty) continue;
          final score = topic.mistakeAttempts / (topicCounts[topic]! + 1);
          if (score > bestScore) {
            bestScore = score;
            bestTopic = topic;
          }
        }
        if (bestTopic == null) break;
        final next = topicQueues[bestTopic]!.removeAt(0);
        topicCounts[bestTopic] = topicCounts[bestTopic]! + 1;
        addQuestion(next);
      }
    }

    // 3. Общий добор до целевого размера, если слабых тем недостаточно.
    if (picked.length < limit) {
      final fallback = _rankCandidates(
        all,
        analysis: analysis,
        excludedIds: pickedIds,
        preferUnseenBeforePastMistakes: true,
        random: rng,
      );
      for (final q in fallback) {
        if (picked.length >= limit) break;
        addQuestion(q);
      }
    }

    picked.shuffle(rng);
    return picked;
  }

  /// Генерирует общий тест по конкретной слабой теме (до [maxQuestions]).
  /// Включает текущие и прошлые ошибки этой темы, затем неизученные вопросы
  /// темы, затем давно решённые вопросы темы для закрепления.
  static List<Question> generateTopicTest(
    MistakesAnalysis analysis,
    WeakTopicSummary topic, {
    int maxQuestions = 20,
    Random? random,
  }) {
    if (topic.questions.isEmpty || maxQuestions <= 0) return const [];
    final rng = random ?? Random();
    final limit = min(maxQuestions, topic.questions.length);

    final ranked = _rankCandidates(
      topic.questions,
      analysis: analysis,
      excludedIds: const {},
      preferUnseenBeforePastMistakes: false,
      random: rng,
    );
    final selected = ranked.take(limit).toList()..shuffle(rng);
    return selected;
  }

  /// Список самых сложных вопросов (по числу ошибок, включая уже исправленные).
  static List<Question> generateHardestMistakesTest(
    MistakesAnalysis analysis, {
    int maxQuestions = 20,
  }) {
    if (maxQuestions <= 0) return const [];
    return analysis.frequentMistakes
        .take(maxQuestions)
        .map((e) => e.question)
        .toList();
  }

  static List<Question> _rankCandidates(
    List<Question> candidates, {
    required MistakesAnalysis analysis,
    required Set<String> excludedIds,
    required bool preferUnseenBeforePastMistakes,
    required Random random,
  }) {
    final activeMistakes = <Question>[];
    final pastMistakes = <Question>[];
    final unseen = <Question>[];
    final mastered = <MapEntry<DateTime?, Question>>[];

    for (final q in candidates) {
      if (excludedIds.contains(q.id)) continue;
      final entry = analysis.entriesById[q.id];
      final snap = analysis.progressById[q.id];

      if (entry != null && entry.isCurrentlyWrong) {
        activeMistakes.add(q);
      } else if (entry != null && entry.wrongAttempts > 0) {
        pastMistakes.add(q);
      } else if (snap == null) {
        unseen.add(q);
      } else {
        mastered.add(MapEntry(entry?.answeredAt, q));
      }
    }

    int byMistakeCountDesc(Question a, Question b) {
      final wa = analysis.entriesById[a.id]?.wrongAttempts ?? 0;
      final wb = analysis.entriesById[b.id]?.wrongAttempts ?? 0;
      return wb.compareTo(wa);
    }

    activeMistakes.sort(byMistakeCountDesc);
    pastMistakes.sort(byMistakeCountDesc);
    unseen.shuffle(random);
    mastered.shuffle(random);
    mastered.sort((a, b) {
      if (a.key == null && b.key == null) return 0;
      if (a.key == null) return -1;
      if (b.key == null) return 1;
      return a.key!.compareTo(b.key!);
    });

    if (preferUnseenBeforePastMistakes) {
      return [
        ...unseen,
        ...pastMistakes,
        ...activeMistakes,
        for (final m in mastered) m.value,
      ];
    }
    return [
      ...activeMistakes,
      ...pastMistakes,
      ...unseen,
      for (final m in mastered) m.value,
    ];
  }
}
