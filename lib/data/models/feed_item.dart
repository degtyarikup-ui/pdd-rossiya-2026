import 'package:pdd_app/data/models/ad_promo_item.dart';
import 'package:pdd_app/data/sources/driver_tips_data.dart';

enum FeedItemType {
  ticketQuestion,
  roadSign,
  driverTip,
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
  final DriverTip? driverTip;
  final dynamic preloadedBanner;

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
    this.driverTip,
    this.preloadedBanner,
  });

  bool get isAd => type == FeedItemType.ad;
  bool get isTip => type == FeedItemType.driverTip;

  factory FeedItem.fromDriverTip(DriverTip tip) {
    return FeedItem(
      id: 'tip_${tip.id}',
      type: FeedItemType.driverTip,
      questionText: tip.title,
      explanation: tip.description,
      badgeText: 'СОВЕТ',
      driverTip: tip,
    );
  }

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

  factory FeedItem.yandexAd({
    required int index,
    String? adUnitId,
    dynamic preloadedBanner,
  }) {
    return FeedItem(
      id: 'ad_yandex_$index',
      type: FeedItemType.ad,
      questionText: 'Яндекс Реклама',
      badgeText: 'РЕКЛАМА',
      answers: const [],
      correctAnswerIndex: -1,
      adPromo: null,
      preloadedBanner: preloadedBanner,
    );
  }
}
