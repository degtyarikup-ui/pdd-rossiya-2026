import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/feed_item.dart';

void main() {
  group('FeedItem Model Tests', () {
    test('creates ticket question FeedItem correctly', () {
      const item = FeedItem(
        id: 'q_1',
        type: FeedItemType.ticketQuestion,
        questionText: 'Разрешен ли вам разворот?',
        answers: ['Разрешен', 'Запрещен'],
        correctAnswerIndex: 0,
        explanation: 'Разворот разрешен согласно пункту 8.11.',
        badgeText: 'Билет 1',
        rawQuestionId: '1',
      );

      expect(item.id, 'q_1');
      expect(item.type, FeedItemType.ticketQuestion);
      expect(item.answers.length, 2);
      expect(item.correctAnswerIndex, 0);
      expect(item.explanation, contains('8.11'));
      expect(item.isSvgImage, isFalse);
    });

    test('creates road sign FeedItem correctly', () {
      const item = FeedItem(
        id: 'sign_warning_1.1',
        type: FeedItemType.roadSign,
        questionText: 'Что означает этот дорожный знак?',
        imagePath: 'assets/countries/ru/images/signs/c6a558e6fbb120c93d55d8fd967dbe12.svg',
        isSvgImage: true,
        answers: [
          'Железнодорожный переезд со шлагбаумом',
          'Железнодорожный переезд без шлагбаума',
          'Однопутная железная дорога',
          'Многопутная железная дорога',
        ],
        correctAnswerIndex: 0,
        badgeText: 'Предупреждающие знаки · № 1.1',
        signNumber: '1.1',
      );

      expect(item.type, FeedItemType.roadSign);
      expect(item.isSvgImage, isTrue);
      expect(item.answers.length, 4);
      expect(item.correctAnswerIndex, 0);
      expect(item.signNumber, '1.1');
    });
  });
}
