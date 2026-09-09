import 'dart:math';

import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/sources/driver_tips_data.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';

class FeedRepository {
  final QuestionsDataSource _questionsDataSource;
  final ProgressDataSource _progressDataSource;
  final List<DriverTip> _tipPool = [];

  FeedRepository(this._questionsDataSource, this._progressDataSource);

  DriverTip _getNextRandomTip(Random random) {
    if (_tipPool.isEmpty) {
      _tipPool.addAll(List.of(DriverTipsData.tips)..shuffle(random));
    }
    return _tipPool.removeAt(0);
  }

  /// Builds a smart adaptive batch of FeedItem cards tailored to the user's
  /// actual mistakes, weak topics, and spaced repetition intervals.
  /// 
  /// Priority:
  /// 1. Unresolved Mistakes (questions with wrong answers)
  /// 2. Weak Areas (questions where mistakes occurred in the past)
  /// 3. Unseen Questions (new questions the user has never practiced)
  /// 4. Road Signs
  /// 5. Mastered Questions (ONLY if all unseen & mistakes are exhausted, sorted by oldest answered time)
  Future<List<FeedItem>> generateFeedItems({
    required TicketCategory category,
    int count = 60,
    Set<String>? excludeQuestionIds,
  }) async {
    final random = Random();
    final List<Question> allQuestions =
        await _questionsDataSource.loadTickets(category);
    final List<Map<String, dynamic>> signsManifest =
        await _questionsDataSource.loadSignsFeedManifest();

    final excluded = excludeQuestionIds ?? const <String>{};

    // 1. Fetch user progress & mistake history
    final Map<String, dynamic> userProgress =
        await _progressDataSource.getAllQuestionProgress(category);

    // 2. Parse ticket questions & categorize by mastery level
    final Map<int, List<Question>> ticketGroups = {};
    for (final q in allQuestions) {
      if (excluded.contains(q.id) || excluded.contains('q_${q.id}')) continue;
      ticketGroups.putIfAbsent(q.ticketNumber, () => []).add(q);
    }

    final List<FeedItem> unresolvedMistakes = [];
    final List<FeedItem> weakSpotItems = [];
    final List<FeedItem> unseenItems = [];
    final List<MapEntry<DateTime?, FeedItem>> masteredItems = [];

    ticketGroups.forEach((tNum, qList) {
      for (int i = 0; i < qList.length; i++) {
        final q = qList[i];
        final correctIdx = q.answers.indexWhere((a) => a.isCorrect);
        if (correctIdx == -1 || q.answers.isEmpty) continue;

        final qNum = i + 1;
        final qProgress = userProgress[q.id] as Map<String, dynamic>?;

        final badge =
            tNum > 0 ? 'Билет $tNum · Вопрос $qNum' : 'Вопрос $qNum';

        final item = FeedItem(
          id: 'q_${q.id}',
          type: FeedItemType.ticketQuestion,
          questionText: q.question,
          imagePath: q.image,
          isSvgImage: false,
          answers: q.answers.map((a) => a.text).toList(),
          correctAnswerIndex: correctIdx,
          explanation: q.comment,
          badgeText: badge,
          rawQuestionId: q.id,
          isAiSmart: false,
        );

        if (qProgress == null) {
          // Never seen yet
          unseenItems.add(item);
        } else {
          final isCorrect = qProgress['isCorrect'] == true;
          final wrongAttempts = qProgress['wrongAttempts'] as int? ?? 0;
          final answeredAtStr = qProgress['answeredAt'] as String?;
          final answeredAt = answeredAtStr != null ? DateTime.tryParse(answeredAtStr) : null;

          if (!isCorrect) {
            // Unresolved mistake: highest priority
            unresolvedMistakes.add(item);
          } else if (wrongAttempts > 0) {
            // Corrected, but had past mistakes: weak spot
            weakSpotItems.add(item);
          } else {
            // Mastered on first attempt without mistakes
            masteredItems.add(MapEntry(answeredAt, item));
          }
        }
      }
    });

    // 3. Parse road signs from manifest
    final List<FeedItem> signFeedItems = [];
    if (signsManifest.isNotEmpty) {
      for (final s in signsManifest) {
        try {
          final signId = s['id']?.toString() ?? 'sign_${signFeedItems.length}';
          if (excluded.contains(signId)) continue;

          final signImg = s['image'] as String? ?? '';
          final isSvg = signImg.toLowerCase().endsWith('.svg');
          final fullImgPath = '${CountryConfig.current.signImagesDir}/$signImg';
          final rawAnswers = s['answers'];
          final List<String> answersList = rawAnswers is List
              ? rawAnswers.map((e) => e.toString()).toList()
              : <String>[];

          if (answersList.isEmpty) continue;

          signFeedItems.add(
            FeedItem(
              id: signId,
              type: FeedItemType.roadSign,
              questionText: s['questionText'] as String? ?? 'Что означает этот дорожный знак?',
              imagePath: fullImgPath,
              isSvgImage: isSvg,
              answers: answersList,
              correctAnswerIndex: (s['correctAnswerIndex'] as num?)?.toInt() ?? 0,
              explanation: (s['description'] as String?)?.isNotEmpty == true ? s['description'] as String : null,
              badgeText: 'Знак № ${s['number'] ?? ''}',
              signNumber: s['number']?.toString(),
              rawQuestionId: signId,
              isAiSmart: false,
            ),
          );
        } catch (_) {}
      }
    }

    // Sort mastered items by oldest answered date (spaced repetition)
    masteredItems.sort((a, b) {
      if (a.key == null) return -1;
      if (b.key == null) return 1;
      return a.key!.compareTo(b.key!);
    });
    final List<FeedItem> sortedMastered = masteredItems.map((e) => e.value).toList();

    unresolvedMistakes.shuffle(random);
    weakSpotItems.shuffle(random);
    unseenItems.shuffle(random);
    signFeedItems.shuffle(random);

    // 4. Adaptive Assembly: Focus heavily on Mistakes, Weak spots & Unseen
    final List<FeedItem> combined = [];
    int unresIdx = 0;
    int weakIdx = 0;
    int unseenIdx = 0;
    int signIdx = 0;
    int masteredIdx = 0;

    while (combined.length < count) {
      bool addedAny = false;

      // 1-2 Unresolved Mistakes
      for (int i = 0; i < 2 && unresIdx < unresolvedMistakes.length; i++) {
        combined.add(unresolvedMistakes[unresIdx++]);
        addedAny = true;
      }

      // 1 Weak Spot Question (past mistakes)
      if (weakIdx < weakSpotItems.length) {
        combined.add(weakSpotItems[weakIdx++]);
        addedAny = true;
      }

      // 2-3 Unseen Fresh Questions
      for (int i = 0; i < 3 && unseenIdx < unseenItems.length; i++) {
        combined.add(unseenItems[unseenIdx++]);
        addedAny = true;
      }

      // 1 Road Sign
      if (signIdx < signFeedItems.length) {
        combined.add(signFeedItems[signIdx++]);
        addedAny = true;
      }

      // If we don't have enough unseen/mistakes, only then pull from mastered (oldest first)
      if (!addedAny && masteredIdx < sortedMastered.length) {
        combined.add(sortedMastered[masteredIdx++]);
        addedAny = true;
      }

      if (!addedAny) {
        // All candidate pools exhausted
        break;
      }
    }

    // 5. Insert Driver Tips every 6 questions
    final List<FeedItem> resultFeed = [];
    int questionCounter = 0;

    for (final item in combined) {
      resultFeed.add(item);
      questionCounter++;

      if (questionCounter % 6 == 0) {
        final tip = _getNextRandomTip(random);
        resultFeed.add(FeedItem.fromDriverTip(tip));
      }
    }

    return resultFeed;
  }
}
