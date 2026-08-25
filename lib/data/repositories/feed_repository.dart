import 'dart:math';

import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';

class FeedRepository {
  final QuestionsDataSource _questionsDataSource;

  FeedRepository(this._questionsDataSource);

  /// Builds a randomized batch of FeedItem cards (70% ticket questions, 30% signs quiz).
  Future<List<FeedItem>> generateFeedItems({
    required TicketCategory category,
    int count = 50,
  }) async {
    final random = Random();
    final List<Question> allQuestions =
        await _questionsDataSource.loadTickets(category);
    final List<Map<String, dynamic>> signsManifest =
        await _questionsDataSource.loadSignsFeedManifest();

    // 1. Parse ticket questions
    final Map<int, List<Question>> ticketGroups = {};
    for (final q in allQuestions) {
      ticketGroups.putIfAbsent(q.ticketNumber, () => []).add(q);
    }

    final List<FeedItem> ticketFeedItems = [];
    ticketGroups.forEach((tNum, qList) {
      for (int i = 0; i < qList.length; i++) {
        final q = qList[i];
        final correctIdx = q.answers.indexWhere((a) => a.isCorrect);
        if (correctIdx == -1 || q.answers.isEmpty) continue;

        final qNum = i + 1;
        final badge = tNum > 0 ? 'Билет $tNum · Вопрос $qNum' : 'Вопрос $qNum';

        ticketFeedItems.add(
          FeedItem(
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
          ),
        );
      }
    });

    // 2. Parse road signs from manifest (exact match with audio)
    final List<FeedItem> signFeedItems = [];
    if (signsManifest.isNotEmpty) {
      for (final s in signsManifest) {
        final signImg = s['image'] as String? ?? '';
        final isSvg = signImg.toLowerCase().endsWith('.svg');
        final fullImgPath = '${CountryConfig.current.signImagesDir}/$signImg';
        final signId = s['id'] as String;

        signFeedItems.add(
          FeedItem(
            id: signId,
            type: FeedItemType.roadSign,
            questionText: s['questionText'] as String? ?? 'Что означает этот дорожный знак?',
            imagePath: fullImgPath,
            isSvgImage: isSvg,
            answers: (s['answers'] as List).cast<String>(),
            correctAnswerIndex: s['correctAnswerIndex'] as int? ?? 0,
            explanation: (s['description'] as String?)?.isNotEmpty == true ? s['description'] as String : null,
            badgeText: '${s['category']} · № ${s['number']}',
            signNumber: s['number'] as String?,
            rawQuestionId: signId,
          ),
        );
      }
    }

    ticketFeedItems.shuffle(random);
    signFeedItems.shuffle(random);

    final List<FeedItem> combined = [];
    int ticketIdx = 0;
    int signIdx = 0;

    // 70% tickets, 30% signs
    while (combined.length < count &&
        (ticketIdx < ticketFeedItems.length || signIdx < signFeedItems.length)) {
      final ticketsToAdd = random.nextBool() ? 2 : 3;
      for (int i = 0; i < ticketsToAdd && ticketIdx < ticketFeedItems.length; i++) {
        combined.add(ticketFeedItems[ticketIdx++]);
      }
      if (signIdx < signFeedItems.length) {
        combined.add(signFeedItems[signIdx++]);
      }
    }

    if (combined.isEmpty) {
      combined.addAll(ticketFeedItems);
      combined.addAll(signFeedItems);
      combined.shuffle(random);
    }

    return combined;
  }
}
