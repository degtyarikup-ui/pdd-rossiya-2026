import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/domain/services/sign_swiper_engine.dart';

void main() {
  group('SignSwiperEngine Tests', () {
    final mockJson = <String, dynamic>{
      'Знаки приоритета': {
        '2.1': {
          'number': '2.1',
          'title': 'Главная дорога',
          'image': './images/signs/priority_main.svg',
          'description': 'Предоставляет право преимущественного проезда.',
          'folkName': 'Главная',
        },
        '2.4': {
          'number': '2.4',
          'title': 'Уступите дорогу',
          'image': './images/signs/yield.svg',
          'description': 'Обязывает уступить дорогу.',
          'folkName': 'Уступи дорогу',
        },
      },
      'Запрещающие знаки': {
        '3.1': {
          'number': '3.1',
          'title': 'Въезд запрещен',
          'image': './images/signs/no_entry.svg',
          'description': 'Запрещает въезд всех транспортных средств.',
          'folkName': 'Кирпич',
        },
        '3.20': {
          'number': '3.20',
          'title': 'Обгон запрещен',
          'image': './images/signs/no_overtake.svg',
          'description': 'Запрещает обгон всех ТС.',
        },
      },
    };

    test('parseSignsJson properly extracts valid signs', () {
      final signs = SignSwiperEngine.parseSignsJson(mockJson);
      expect(signs.length, equals(4));

      final sign21 = signs.firstWhere((s) => s.number == '2.1');
      expect(sign21.title, equals('Главная дорога'));
      expect(sign21.category, equals('Знаки приоритета'));
      expect(sign21.image, equals('priority_main.svg'));
      expect(sign21.folkName, equals('Главная'));
    });

    test('generateDeck produces requested count of cards', () {
      final signs = SignSwiperEngine.parseSignsJson(mockJson);
      final engine = SignSwiperEngine(allSigns: signs);

      final deck = engine.generateDeck(count: 10);
      expect(deck.length, equals(10));
      for (final card in deck) {
        expect(card.id.isNotEmpty, isTrue);
        expect(card.prompt.isNotEmpty, isTrue);
        expect(card.explanation.isNotEmpty, isTrue);
        expect(card.sign.title.isNotEmpty, isTrue);
      }
    });

    test('generateDeck with categoryFilter filters cards', () {
      final signs = SignSwiperEngine.parseSignsJson(mockJson);
      final engine = SignSwiperEngine(allSigns: signs);

      final deck = engine.generateDeck(categoryFilter: 'Запрещающие знаки', count: 6);
      expect(deck.length, equals(6));
      for (final card in deck) {
        expect(card.sign.category, equals('Запрещающие знаки'));
      }
    });

    test('SignSwiperProgress serialization works', () {
      const progress = SignSwiperProgress(
        bestScore: 2450,
        maxCombo: 12,
        totalSwiped: 85,
        trainingCount: 3,
      );

      final json = progress.toJson();
      final restored = SignSwiperProgress.fromJson(json);

      expect(restored.bestScore, equals(2450));
      expect(restored.maxCombo, equals(12));
      expect(restored.totalSwiped, equals(85));
      expect(restored.trainingCount, equals(3));
    });
  });
}
