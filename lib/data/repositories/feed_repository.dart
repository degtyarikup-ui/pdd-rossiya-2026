import 'dart:math';

import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/ads_repository.dart';
import 'package:pdd_app/data/services/yandex_ad_preloader.dart';
import 'package:pdd_app/data/sources/driver_tips_data.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';

class FeedRepository {
  final QuestionsDataSource _questionsDataSource;
  final AdsRepository? _adsRepository;
  final List<DriverTip> _tipPool = [];

  FeedRepository(this._questionsDataSource, [this._adsRepository]);

  DriverTip _getNextRandomTip(Random random) {
    if (_tipPool.isEmpty) {
      _tipPool.addAll(List.of(DriverTipsData.tips)..shuffle(random));
    }
    return _tipPool.removeAt(0);
  }

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
        try {
          final signImg = s['image'] as String? ?? '';
          final isSvg = signImg.toLowerCase().endsWith('.svg');
          final fullImgPath = '${CountryConfig.current.signImagesDir}/$signImg';
          final signId = s['id']?.toString() ?? 'sign_${signFeedItems.length}';
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
            ),
          );
        } catch (_) {}
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

    final List<FeedItem> resultFeed = [];
    int questionCounter = 0;

    final adsRepo = _adsRepository;
    final adsEnabled = adsRepo != null && adsRepo.currentConfig.isEnabled;
    final adFreq = adsRepo?.currentConfig.frequency.clamp(3, 50) ?? 12;

    for (final item in combined) {
      resultFeed.add(item);
      questionCounter++;

      // Every 6 questions -> insert Driver Tip (uniformly shuffled pool)
      if (questionCounter % 6 == 0) {
        final tip = _getNextRandomTip(random);
        resultFeed.add(FeedItem.fromDriverTip(tip));
      }

      // Ad insertion every 12 questions (only if verified/ready)
      if (adsEnabled && questionCounter % adFreq == 0) {
        if (adsRepo.currentConfig.mode == 'yandex') {
          final adUnitId = adsRepo.currentConfig.yandexAdUnitId;
          if (YandexAdPreloader.instance.hasReadyAd) {
            final preloaded = YandexAdPreloader.instance.consumeReadyBanner();
            resultFeed.add(FeedItem.yandexAd(
              index: questionCounter,
              adUnitId: adUnitId,
              preloadedBanner: preloaded,
            ));
          } else {
            // Trigger preload in background for future questions
            if (adUnitId.isNotEmpty) {
              YandexAdPreloader.instance.preloadNext(adUnitId).ignore();
            }
            // Fallback to custom promo card if available
            final promo = adsRepo.getNextPromoCard();
            if (promo != null) {
              resultFeed.add(FeedItem.fromAdPromo(promo, index: questionCounter));
            }
            // If neither is ready, no ad item is inserted -> zero visual glitch!
          }
        } else {
          final promo = adsRepo.getNextPromoCard();
          if (promo != null) {
            resultFeed.add(FeedItem.fromAdPromo(promo, index: questionCounter));
          }
        }
      }
    }

    return resultFeed;
  }
}
