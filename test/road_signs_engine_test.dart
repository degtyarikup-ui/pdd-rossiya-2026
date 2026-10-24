import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/game_economy.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/domain/services/road_signs_engine.dart';

void main() {
  group('RoadSignsModel Tests', () {
    test('RoadSignsProgress serialization and copyWith works correctly', () {
      const progress = RoadSignsProgress(
        bestScore: 450,
        maxCombo: 8,
        totalAnswered: 25,
        totalCorrect: 22,
      );

      final json = progress.toJson();
      final restored = RoadSignsProgress.fromJson(json);

      expect(restored.bestScore, equals(450));
      expect(restored.maxCombo, equals(8));
      expect(restored.totalAnswered, equals(25));
      expect(restored.totalCorrect, equals(22));

      final updated = progress.copyWith(bestScore: 500, maxCombo: 10);
      expect(updated.bestScore, equals(500));
      expect(updated.maxCombo, equals(10));
      expect(updated.totalAnswered, equals(25));
      expect(updated.totalCorrect, equals(22));
    });

    test('RoadSignAnswerResult computes correctSign and selectedSign correctly', () {
      const target = SignItem(
        number: '2.1',
        title: 'Главная дорога',
        image: 'priority.svg',
        category: 'Знаки приоритета',
        description: 'Дорога с преимуществом.',
      );
      const wrong = SignItem(
        number: '2.4',
        title: 'Уступите дорогу',
        image: 'yield.svg',
        category: 'Знаки приоритета',
        description: 'Уступи дорогу.',
      );
      const d1 = SignItem(
        number: '3.1',
        title: 'Въезд запрещен',
        image: 'brick.svg',
        category: 'Запрещающие знаки',
        description: 'Кирпич.',
      );
      const d2 = SignItem(
        number: '3.2',
        title: 'Движение запрещено',
        image: 'no_move.svg',
        category: 'Запрещающие знаки',
        description: 'Запрет движения.',
      );

      final question = RoadSignQuizQuestion(
        id: 'q1',
        correctSign: target,
        options: [target, wrong, d1, d2],
        correctAnswerIndex: 0,
        prompt: 'Какой из этих знаков — «Главная дорога»?',
        officialRuleQuote: 'Дорога с преимуществом.',
        type: RoadSignQuizType.titleMatch,
      );

      final correctResult = RoadSignAnswerResult(
        question: question,
        selectedIndex: 0,
        isCorrect: true,
      );
      expect(correctResult.isCorrect, isTrue);
      expect(correctResult.correctSign.number, equals('2.1'));
      expect(correctResult.selectedSign.number, equals('2.1'));

      final wrongResult = RoadSignAnswerResult(
        question: question,
        selectedIndex: 1,
        isCorrect: false,
      );
      expect(wrongResult.isCorrect, isFalse);
      expect(wrongResult.correctSign.number, equals('2.1'));
      expect(wrongResult.selectedSign.number, equals('2.4'));
    });
  });

  group('RoadSignsEngine Anti-Collision & Generation Tests', () {
    final mockJson = <String, dynamic>{
      'Предупреждающие знаки': {
        '1.17': {
          'number': '1.17',
          'title': 'Искусственная неровность',
          'image': 'bump_warning.svg',
          'description': 'Участок дороги с искусственной неровностью.',
        },
        '1.22': {
          'number': '1.22',
          'title': 'Пешеходный переход',
          'image': 'crosswalk_warning.svg',
          'description': 'Приближение к пешеходному переходу.',
        },
        '1.34.1': {
          'number': '1.34.1',
          'title': 'Направление поворота',
          'image': 'turn_1.svg',
          'description': 'Направление движения на закруглении дороги.',
          'folkName': 'ёлочка',
        },
        '1.34.2': {
          'number': '1.34.2',
          'title': 'Направление поворота',
          'image': 'turn_2.svg',
          'description': 'Направление движения на закруглении дороги вправо.',
          'folkName': 'ёлочка',
        },
      },
      'Знаки особых предписаний': {
        '5.19.1': {
          'number': '5.19.1',
          'title': 'Пешеходный переход',
          'image': 'crosswalk_special.svg',
          'description': 'Место пешеходного перехода через проезжую часть.',
          'folkName': 'зебра',
        },
        '5.19.2': {
          'number': '5.19.2',
          'title': 'Пешеходный переход',
          'image': 'crosswalk_special_2.svg',
          'description': 'Место пешеходного перехода с левой стороны.',
          'folkName': 'зебра',
        },
        '5.20': {
          'number': '5.20',
          'title': 'Искусственная неровность',
          'image': 'bump_special.svg',
          'description': 'Обозначает границы искусственной неровности.',
        },
      },
      'Знаки приоритета': {
        '2.1': {
          'number': '2.1',
          'title': 'Главная дорога',
          'image': 'main_road.svg',
          'description': 'Дорога с правом преимущественного проезда.',
          'folkName': 'главная',
        },
        '2.4': {
          'number': '2.4',
          'title': 'Уступите дорогу',
          'image': 'yield.svg',
          'description': 'Водитель должен уступить дорогу.',
          'folkName': 'уступи дорогу',
        },
      },
      'Запрещающие знаки': {
        '3.1': {
          'number': '3.1',
          'title': 'Въезд запрещен',
          'image': 'brick.svg',
          'description': 'Запрещает въезд всех транспортных средств.',
          'folkName': 'кирпич',
        },
        '3.20': {
          'number': '3.20',
          'title': 'Обгон запрещен',
          'image': 'no_overtake.svg',
          'description': 'Запрещает обгон транспортных средств.',
        },
      },
    };

    test('parseSignsJson extracts valid signs excluding incomplete entries', () {
      final signs = RoadSignsEngine.parseSignsJson(mockJson);
      expect(signs.length, equals(11));
      for (final sign in signs) {
        expect(sign.number.isNotEmpty, isTrue);
        expect(sign.title.isNotEmpty, isTrue);
        expect(sign.image.isNotEmpty, isTrue);
        expect(sign.category.isNotEmpty, isTrue);
      }
    });

    test('Anti-collision: Distractors NEVER share title with target or each other', () {
      final signs = RoadSignsEngine.parseSignsJson(mockJson);
      final engine = RoadSignsEngine(allSigns: signs);

      // 1.22 has duplicate title with 5.19.1 and 5.19.2 ("Пешеходный переход")
      final sign122 = signs.firstWhere((s) => s.number == '1.22');
      final distractorsFor122 = engine.selectDistractors(sign122, count: 3);

      expect(distractorsFor122.length, equals(3));
      for (final d in distractorsFor122) {
        expect(d.title.trim().toLowerCase(), isNot(equals('пешеходный переход')));
      }

      // Check unique titles among distractors
      final titles = distractorsFor122.map((d) => d.title.trim().toLowerCase()).toSet();
      expect(titles.length, equals(distractorsFor122.length));
    });

    test('Anti-collision: Distractors NEVER share folkName with target or each other', () {
      final signs = RoadSignsEngine.parseSignsJson(mockJson);
      final engine = RoadSignsEngine(allSigns: signs);

      // 1.34.1 has folkName "ёлочка" which is identical to 1.34.2
      final sign1341 = signs.firstWhere((s) => s.number == '1.34.1');
      final distractors = engine.selectDistractors(sign1341, count: 3);

      expect(distractors.length, equals(3));
      for (final d in distractors) {
        expect(d.folkName?.trim().toLowerCase(), isNot(equals('ёлочка')));
      }

      final folkNames = distractors
          .where((d) => d.folkName != null)
          .map((d) => d.folkName!.trim().toLowerCase())
          .toSet();
      final totalWithFolk = distractors.where((d) => d.folkName != null).length;
      expect(folkNames.length, equals(totalWithFolk));
    });

    test('generateDeck produces exactly 4 options per question with target at correctAnswerIndex', () {
      final signs = RoadSignsEngine.parseSignsJson(mockJson);
      final engine = RoadSignsEngine(allSigns: signs);

      final deck = engine.generateDeck(count: 20);
      expect(deck.length, equals(20));

      for (final q in deck) {
        expect(q.options.length, equals(4));
        expect(q.correctAnswerIndex, inInclusiveRange(0, 3));
        expect(q.options[q.correctAnswerIndex].number, equals(q.correctSign.number));

        // All 4 options must have distinct numbers
        final numbers = q.options.map((o) => o.number).toSet();
        expect(numbers.length, equals(4), reason: 'Duplicate numbers found in options');

        // All 4 options must have distinct titles
        final titles = q.options.map((o) => o.title.trim().toLowerCase()).toSet();
        expect(titles.length, equals(4), reason: 'Duplicate titles found in options: ${q.options.map((o) => o.title)}');

        // Question must have valid prompt and official quote
        expect(q.prompt.isNotEmpty, isTrue);
        expect(q.officialRuleQuote.isNotEmpty, isTrue);
      }
    });

    test('GameEconomy.signs score calculation formulas', () {
      expect(GameEconomy.signs(1), equals(12));
      expect(GameEconomy.signs(2), equals(13));
      expect(GameEconomy.signs(3), equals(14));
      expect(GameEconomy.signs(4), equals(15));
      expect(GameEconomy.signs(5), equals(16));
      expect(GameEconomy.signs(10), equals(16)); // Clamped at 12 + 4 = 16
    });

    test('Official rules quote extraction strips penalties and normalizes text', () {
      const raw =
          'Указывает на дорогу, на которой предоставлено право преимущественного проезда.\u00a0Устанавливается перед перекрестком. Наказание за нарушение требований знака:КоАП РФ 12.13 ч. 2– штраф 1000 руб.';
      final quote = RoadSignsEngine.extractOfficialQuote(raw, 'Главная дорога');

      expect(quote.contains('КоАП РФ'), isFalse);
      expect(quote.contains('штраф'), isFalse);
      expect(quote.contains('Указывает на дорогу'), isTrue);
      expect(quote.contains('\u00a0'), isFalse);
    });

    test('Works with full real signs.json dataset (312 signs, 36 duplicate titles)', () {
      final file = File('assets/countries/ru/questions/signs.json');
      if (!file.existsSync()) {
        return; // Skip if run in context without full assets
      }

      final jsonContent = file.readAsStringSync();
      final rawMap = jsonDecode(jsonContent) as Map<String, dynamic>;
      final signs = RoadSignsEngine.parseSignsJson(rawMap);

      expect(signs.length, greaterThanOrEqualTo(250));
      final engine = RoadSignsEngine(allSigns: signs);

      // Generate large batch of questions to thoroughly exercise distractor filtering
      final deck = engine.generateDeck(count: 60);
      expect(deck.length, equals(60));

      for (final q in deck) {
        expect(q.options.length, equals(4));
        final titles = q.options.map((s) => s.title.trim().toLowerCase()).toSet();
        expect(titles.length, equals(4), reason: 'Duplicate title found in question: ${q.prompt}');
        final numbers = q.options.map((s) => s.number).toSet();
        expect(numbers.length, equals(4), reason: 'Duplicate sign number in question');
        expect(q.options[q.correctAnswerIndex].number, equals(q.correctSign.number));
      }
    });
  });
}
