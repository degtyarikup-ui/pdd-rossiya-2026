enum FeedItemType {
  ticketQuestion,
  roadSign,
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

  const FeedItem({
    required this.id,
    required this.type,
    required this.questionText,
    this.imagePath,
    this.isSvgImage = false,
    required this.answers,
    required this.correctAnswerIndex,
    this.explanation,
    this.badgeText,
    this.rawQuestionId,
    this.signNumber,
  });
}
