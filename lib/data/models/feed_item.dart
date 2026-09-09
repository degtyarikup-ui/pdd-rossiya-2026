import 'package:pdd_app/data/sources/driver_tips_data.dart';

enum FeedItemType {
  ticketQuestion,
  roadSign,
  driverTip,
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
  final DriverTip? driverTip;
  final bool isAiSmart;

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
    this.driverTip,
    this.isAiSmart = false,
  });

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
}
