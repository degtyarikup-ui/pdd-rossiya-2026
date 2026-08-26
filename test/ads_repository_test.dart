import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/ad_promo_item.dart';
import 'package:pdd_app/data/models/feed_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ads Model & Config Tests', () {
    test('Default fallback config has yandex mode and clean state', () {
      final config = AdPromoConfig.defaultFallback;
      expect(config.isEnabled, true);
      expect(config.mode, 'yandex');
      expect(config.yandexAdUnitId, 'R-M-19816566-1');
      expect(config.cards.isEmpty, true);
    });

    test('FeedItem yandexAd factory creates valid yandex ad item', () {
      final item = FeedItem.yandexAd(index: 10, adUnitId: 'R-M-19816566-1');
      expect(item.isAd, true);
      expect(item.type, FeedItemType.ad);
      expect(item.badgeText, 'РЕКЛАМА');
      expect(item.adPromo, isNull);
    });

    test('AdPromoItem serialization and deserialization', () {
      const item = AdPromoItem(
        id: 'test_1',
        badge: 'СКИДКА',
        title: 'Тестовый заголовок',
        description: 'Тестовое описание',
        buttonText: 'Купить',
        buttonUrl: 'https://example.com',
        themeColor: 'green',
        icon: 'star',
      );

      final json = item.toJson();
      final fromJson = AdPromoItem.fromJson(json);

      expect(fromJson.id, 'test_1');
      expect(fromJson.badge, 'СКИДКА');
      expect(fromJson.title, 'Тестовый заголовок');
      expect(fromJson.buttonUrl, 'https://example.com');
      expect(fromJson.themeColor, 'green');
      expect(fromJson.icon, 'star');
    });

    test('FeedItem fromAdPromo factory creates valid ad card', () {
      const item = AdPromoItem(
        id: 'promo_123',
        badge: 'РЕКОМЕНДУЕМ',
        title: 'Автошкола Онлайн',
        description: 'Скидка 20% на теорию',
        buttonText: 'Записаться',
        buttonUrl: 'https://example.com/school',
      );

      final feedItem = FeedItem.fromAdPromo(item, index: 15);
      expect(feedItem.isAd, true);
      expect(feedItem.type, FeedItemType.ad);
      expect(feedItem.questionText, 'Автошкола Онлайн');
      expect(feedItem.badgeText, 'РЕКОМЕНДУЕМ');
      expect(feedItem.adPromo, isNotNull);
      expect(feedItem.adPromo!.buttonUrl, 'https://example.com/school');
    });
  });
}
