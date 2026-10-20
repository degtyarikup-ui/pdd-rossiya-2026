import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/domain/services/road_signs_engine.dart';

void main() {
  group('Milestone 1 Empirical Stress Harness — RoadSignsEngine & Distractor Logic', () {
    late List<SignItem> allSigns;
    late RoadSignsEngine engine;

    setUpAll(() {
      final file = File('assets/countries/ru/questions/signs.json');
      expect(file.existsSync(), isTrue, reason: 'signs.json must exist in project assets');

      final jsonContent = file.readAsStringSync();
      final rawMap = jsonDecode(jsonContent) as Map<String, dynamic>;
      allSigns = RoadSignsEngine.parseSignsJson(rawMap);
      engine = RoadSignsEngine(allSigns: allSigns);
    });

    test('Dataset completeness: all 298 signs loaded across 8 categories', () {
      expect(allSigns.length, equals(298), reason: 'Expected full 298 Russian road signs dataset');
      expect(engine.availableCategories.length, equals(8), reason: 'Expected 8 sign categories');

      for (final sign in allSigns) {
        expect(sign.number.trim(), isNotEmpty);
        expect(sign.title.trim(), isNotEmpty);
        expect(sign.image.trim(), isNotEmpty);
        expect(sign.category.trim(), isNotEmpty);
      }
    });

    test('EMPIRICAL STRESS TEST: 2,000+ generated questions strictly satisfy all 6 invariants', () {
      const totalRuns = 2500;
      final rnd = Random(42);
      final stressEngine = RoadSignsEngine(allSigns: allSigns, random: rnd);

      int totalQuestionsTested = 0;
      final Set<String> allTargetNumbersEncountered = {};
      final Map<RoadSignQuizType, int> typeCounts = {
        RoadSignQuizType.titleMatch: 0,
        RoadSignQuizType.meaningDefinition: 0,
        RoadSignQuizType.folkNameMatch: 0,
      };

      // Generate 100 decks of 25 questions = 2,500 questions
      for (int run = 0; run < 100; run++) {
        final deck = stressEngine.generateDeck(count: 25);
        expect(deck.length, equals(25));

        for (final q in deck) {
          totalQuestionsTested++;
          allTargetNumbersEncountered.add(q.correctSign.number);
          typeCounts[q.type] = (typeCounts[q.type] ?? 0) + 1;

          // Invariant 1: Exactly 4 options
          expect(q.options.length, equals(4),
              reason: 'Question ${q.id} has ${q.options.length} options instead of 4');

          // Invariant 2: Zero duplicate numbers in options
          final numbers = q.options.map((o) => o.number.trim()).toList();
          final uniqueNumbers = numbers.toSet();
          expect(uniqueNumbers.length, equals(4),
              reason: 'Duplicate sign number in options: $numbers for target ${q.correctSign.number}');

          // Invariant 3: Zero duplicate titles in options (case-insensitive, trimmed)
          final titles = q.options.map((o) => o.title.trim().toLowerCase()).toList();
          final uniqueTitles = titles.toSet();
          expect(uniqueTitles.length, equals(4),
              reason: 'Duplicate sign title in options: $titles for target ${q.correctSign.title} (${q.correctSign.number})');

          // Invariant 4: Zero duplicate folk names in options
          final folkNames = q.options
              .where((o) => o.folkName != null && o.folkName!.trim().isNotEmpty)
              .map((o) => o.folkName!.trim().toLowerCase())
              .toList();
          final uniqueFolkNames = folkNames.toSet();
          expect(uniqueFolkNames.length, equals(folkNames.length),
              reason: 'Duplicate folk name in options: $folkNames for target ${q.correctSign.number}');

          // If target has a folk name, none of the distractors can have the same folk name
          if (q.correctSign.folkName != null && q.correctSign.folkName!.trim().isNotEmpty) {
            final targetFolk = q.correctSign.folkName!.trim().toLowerCase();
            for (int i = 0; i < 4; i++) {
              if (i == q.correctAnswerIndex) continue;
              final distractorFolk = q.options[i].folkName?.trim().toLowerCase();
              expect(distractorFolk, isNot(equals(targetFolk)),
                  reason: 'Distractor $i has identical folkName "$targetFolk" as target');
            }
          }

          // Invariant 5: options[correctAnswerIndex] always equals correctSign
          expect(q.correctAnswerIndex, inInclusiveRange(0, 3));
          expect(q.options[q.correctAnswerIndex], equals(q.correctSign));
          expect(q.options[q.correctAnswerIndex].number, equals(q.correctSign.number));

          // Invariant 5b: Zero duplicate images among options
          final images = q.options.map((o) => o.image.trim()).toSet();
          expect(images.length, equals(4),
              reason: 'Duplicate sign image in options: ${q.options.map((o) => o.image)}');

          // Invariant 6: officialRuleQuote accurately contains genuine PDD rule definitions
          expect(q.officialRuleQuote.trim(), isNotEmpty,
              reason: 'officialRuleQuote is empty for ${q.correctSign.number}');
          expect(q.officialRuleQuote.contains('КоАП РФ'), isFalse,
              reason: 'officialRuleQuote contains KoAP penalty text for ${q.correctSign.number}');
          expect(q.officialRuleQuote.contains('Наказание'), isFalse,
              reason: 'officialRuleQuote contains penalty section for ${q.correctSign.number}');
          expect(q.officialRuleQuote.contains('\u00a0'), isFalse,
              reason: 'officialRuleQuote contains non-breaking spaces for ${q.correctSign.number}');
          expect(q.officialRuleQuote.contains('\r'), isFalse,
              reason: 'officialRuleQuote contains raw carriage returns for ${q.correctSign.number}');

          // Invariant 7: Prompt validity, cleanliness and length constraints
          expect(q.prompt.trim(), isNotEmpty);
          expect(q.prompt.length, lessThanOrEqualTo(160),
              reason: 'Prompt excessively long (${q.prompt.length} chars) for ${q.correctSign.number}: ${q.prompt}');
          expect(q.prompt.contains('Устанавливается в н'), isFalse,
              reason: 'Prompt contains truncated installation phrase for ${q.correctSign.number}');
          expect(q.prompt.contains('КоАП'), isFalse,
              reason: 'Prompt contains KoAP for ${q.correctSign.number}');
          expect(q.prompt.contains('штраф'), isFalse,
              reason: 'Prompt contains fine for ${q.correctSign.number}');
          expect(RegExp(r'\bзнак[а-я]*\s+\d', caseSensitive: false).hasMatch(q.prompt), isFalse,
              reason: 'Leaked sign number in prompt: ${q.prompt}');

          if (q.type == RoadSignQuizType.titleMatch) {
            expect(q.prompt.contains(q.correctSign.title.trim()), isTrue);
          } else if (q.type == RoadSignQuizType.folkNameMatch) {
            expect(q.prompt.contains(q.correctSign.folkName!.trim()), isTrue);
          } else if (q.type == RoadSignQuizType.meaningDefinition) {
            expect(q.prompt.toLowerCase().contains(q.correctSign.title.toLowerCase()), isFalse,
                reason: 'Meaning definition leaks sign title for ${q.correctSign.number}: ${q.prompt}');
            expect(q.prompt.toLowerCase().contains('устанавл'), isFalse,
                reason: 'Meaning definition contains installation jargon: ${q.prompt}');
          }
        }
      }

      expect(totalQuestionsTested, equals(totalRuns));
      expect(allTargetNumbersEncountered.length, greaterThan(200),
          reason: 'Generated questions must cover a wide distribution of signs');
      expect(typeCounts[RoadSignQuizType.titleMatch]!, greaterThan(0));
      expect(typeCounts[RoadSignQuizType.meaningDefinition]!, greaterThan(0));
      expect(typeCounts[RoadSignQuizType.folkNameMatch]!, greaterThan(0));
    });

    test('Adversarial Test: 100% of all 298 signs can serve as valid target signs with 3 unique distractors', () {
      final rnd = Random(999);
      final stressEngine = RoadSignsEngine(allSigns: allSigns, random: rnd);

      for (final sign in allSigns) {
        // Attempt to build question for every sign across 5 independent random trials
        for (int trial = 0; trial < 5; trial++) {
          final q = stressEngine.buildQuestionForSign(sign);
          expect(q, isNotNull,
              reason: 'Failed to build question for sign ${sign.number} "${sign.title}"');

          expect(q!.options.length, equals(4));
          expect(q.options[q.correctAnswerIndex].number, equals(sign.number));

          final uniqueTitles = q.options.map((o) => o.title.trim().toLowerCase()).toSet();
          expect(uniqueTitles.length, equals(4),
              reason: 'Duplicate titles in question for sign ${sign.number}');

          final uniqueNumbers = q.options.map((o) => o.number.trim()).toSet();
          expect(uniqueNumbers.length, equals(4),
              reason: 'Duplicate numbers in question for sign ${sign.number}');
        }
      }
    });

    test('Adversarial Test: Explicit stress testing on all 33 duplicate-title collision groups', () {
      // Find all signs that share a title with at least one other sign in the dataset
      final titleMap = <String, List<SignItem>>{};
      for (final s in allSigns) {
        titleMap.putIfAbsent(s.title.trim().toLowerCase(), () => []).add(s);
      }
      final duplicateGroups = titleMap.entries.where((e) => e.value.length > 1).toList();
      expect(duplicateGroups.length, equals(33), reason: 'Expected exactly 33 duplicate title groups in signs.json');

      final rnd = Random(777);
      final stressEngine = RoadSignsEngine(allSigns: allSigns, random: rnd);

      for (final group in duplicateGroups) {
        for (final targetSign in group.value) {
          // Generate 10 questions for this collision-prone target
          for (int t = 0; t < 10; t++) {
            final q = stressEngine.buildQuestionForSign(targetSign);
            expect(q, isNotNull);

            // Verify NONE of the other signs from the same duplicate group are in the options
            final otherCollisionNumbers = group.value
                .where((s) => s.number != targetSign.number)
                .map((s) => s.number)
                .toSet();

            for (final opt in q!.options) {
              if (opt.number != targetSign.number) {
                expect(otherCollisionNumbers.contains(opt.number), isFalse,
                    reason: 'Collision detected: Distractor ${opt.number} "${opt.title}" shares title with target ${targetSign.number}');
              }
            }
          }
        }
      }
    });

    test('Adversarial Test: Explicit stress testing on duplicate folkName collision groups', () {
      final folkMap = <String, List<SignItem>>{};
      for (final s in allSigns) {
        if (s.folkName != null && s.folkName!.trim().isNotEmpty) {
          folkMap.putIfAbsent(s.folkName!.trim().toLowerCase(), () => []).add(s);
        }
      }
      final duplicateFolkGroups = folkMap.entries.where((e) => e.value.length > 1).toList();

      final rnd = Random(555);
      final stressEngine = RoadSignsEngine(allSigns: allSigns, random: rnd);

      for (final group in duplicateFolkGroups) {
        for (final targetSign in group.value) {
          for (int t = 0; t < 20; t++) {
            final q = stressEngine.buildQuestionForSign(targetSign);
            expect(q, isNotNull);

            final otherCollisionNumbers = group.value
                .where((s) => s.number != targetSign.number)
                .map((s) => s.number)
                .toSet();

            for (final opt in q!.options) {
              if (opt.number != targetSign.number) {
                expect(otherCollisionNumbers.contains(opt.number), isFalse,
                    reason: 'Folk name collision detected: Distractor ${opt.number} shares folkName with target ${targetSign.number}');
              }
            }
          }
        }
      }
    });

    test('Category Filter Invariance: generateDeck across all 8 individual categories', () {
      final rnd = Random(123);
      final stressEngine = RoadSignsEngine(allSigns: allSigns, random: rnd);

      for (final cat in engine.availableCategories) {
        final deck = stressEngine.generateDeck(count: 20, categoryFilter: cat);
        expect(deck.length, equals(20), reason: 'Failed to generate 20 questions for category $cat');

        for (final q in deck) {
          expect(q.correctSign.category, equals(cat));
          expect(q.options.length, equals(4));
          expect(q.options.map((o) => o.number).toSet().length, equals(4));
          expect(q.options.map((o) => o.title.trim().toLowerCase()).toSet().length, equals(4));
        }
      }
    });

    test('Official Quote Integrity: all 298 signs produce clean, genuine PDD definitions', () {
      for (final sign in allSigns) {
        final quote = RoadSignsEngine.extractOfficialQuote(sign.description, sign.title);
        expect(quote.trim(), isNotEmpty, reason: 'Empty quote for ${sign.number}');
        expect(quote.contains('КоАП'), isFalse, reason: 'Contains KoAP for ${sign.number}: $quote');
        expect(quote.contains('штраф'), isFalse, reason: 'Contains fine for ${sign.number}: $quote');
        expect(quote.contains('\u00a0'), isFalse, reason: 'Contains non-breaking space for ${sign.number}');
        expect(quote.contains('\r'), isFalse, reason: 'Contains carriage return for ${sign.number}');
        expect(quote.length, lessThanOrEqualTo(1000), reason: 'Quote excessively long for ${sign.number}: ${quote.length}');
      }
    });

    test('Regression: Group 8.2 signs (8.2.1-8.2.6) NEVER produce composite text prompts or duplicate images', () {
      final group82 = allSigns.where((s) => s.number.startsWith('8.2.')).toList();
      expect(group82.length, equals(6));

      for (final sign in group82) {
        for (int i = 0; i < 15; i++) {
          final q = engine.buildQuestionForSign(sign);
          expect(q, isNotNull);
          // Must not be meaning definition with composite text
          expect(q!.prompt.length, lessThanOrEqualTo(80),
              reason: 'Prompt for ${sign.number} was too long: ${q.prompt}');
          expect(q.prompt.contains('8.2.1 указывает протяженность'), isFalse);
          expect(q.prompt.contains('8.2.2 указывает зону'), isFalse);
          expect(q.prompt.contains('8.2.3 указывает конец'), isFalse);
          // Images must be unique
          final images = q.options.map((o) => o.image).toSet();
          expect(images.length, equals(4));
        }
      }

      // Official quote for 8.2.4 must be specific to 8.2.4
      final quote824 = RoadSignsEngine.extractOfficialQuote(
        allSigns.firstWhere((s) => s.number == '8.2.4').description,
        'Зона действия',
        signNumber: '8.2.4',
      );
      expect(quote824.contains('8.2.4 информирует'), isTrue);
      expect(quote824.contains('8.2.1 указывает'), isFalse);
    });

    test('Regression: Signs with installation descriptions (1.5, 1.6, 1.7, 1.13, 1.14, 1.22) produce clean prompts', () {
      final testNumbers = ['1.5', '1.6', '1.7', '1.13', '1.14', '1.22', '1.35', '2.4'];
      for (final num in testNumbers) {
        final sign = allSigns.firstWhere((s) => s.number == num);
        for (int i = 0; i < 10; i++) {
          final q = engine.buildQuestionForSign(sign);
          expect(q, isNotNull);
          expect(q!.prompt.contains('Устанавливается в н'), isFalse);
          expect(q.prompt.length, lessThanOrEqualTo(120));
          expect(q.prompt.contains('КоАП'), isFalse);
          expect(q.prompt.contains('штраф'), isFalse);
        }
      }
    });
  });
}
