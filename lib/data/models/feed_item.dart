import 'package:pdd_app/data/models/ad_promo_item.dart';

enum FeedItemType {
  ticketQuestion,
  roadSign,
  ad,
}

class FeedItem {
  final String id;
  final FeedItemType type;
  final String questionText;
  final String? imagePath;
  final bool isSvgImage;
  final List<String> answers;
  final int correctAnswerIndex;
  final String? explanation;
  final String? badgeText;
  final String? rawQuestionId;
  final String? signNumber;
  final AdPromoItem? adPromo;

  const FeedItem({
    required this.id,
    required this.type,
    required this.questionText,
    this.imagePath,
    this.isSvgImage = false,
    this.answers = const [],
    this.correctAnswerIndex = -1,
    this.explanation,
    this.badgeText,
    this.rawQuestionId,
    this.signNumber,
    this.adPromo,
  });

  bool get isAd => type == FeedItemType.ad;

  factory FeedItem.fromAdPromo(AdPromoItem promo, {required int index}) {
    return FeedItem(
      id: 'ad_${promo.id}_$index',
      type: FeedItemType.ad,
      questionText: promo.title,
      badgeText: promo.badge,
      answers: const [],
      correctAnswerIndex: -1,
      adPromo: promo,
    );
  }

  factory FeedItem.yandexAd({required int index, String? adUnitId}) {
    return FeedItem(
      id: 'ad_yandex_$index',
      type: FeedItemType.ad,
      questionText: 'Яндекс Реклама',
      badgeText: 'РЕКЛАМА',
      answers: const [],
      correctAnswerIndex: -1,
      adPromo: null,
    );
  }
}
