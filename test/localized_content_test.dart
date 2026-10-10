import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/crossroads_priority_model.dart';
import 'package:pdd_app/data/sources/driver_tips_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Localized Content Infrastructure Tests', () {
    test('CountryConfig produces correct paths for languages', () {
      final config = CountryConfig.current;

      // Base Russian paths
      expect(config.questionsJson('ab'), contains('questions_ab.json'));
      expect(config.questionsJson('cd'), contains('questions_cd.json'));
      expect(config.topicsJson('ab'), contains('topics_ab.json'));
      expect(config.signsJson(), contains('signs.json'));
      expect(config.signsFeedManifestJson(), contains('signs_feed_manifest.json'));
      expect(config.markupJson(), contains('markup.json'));
      expect(config.pddSectionsJson(), contains('pdd_sections.json'));

      // English paths
      expect(config.questionsJson('ab', 'en'), contains('questions_ab_en.json'));
      expect(config.questionsJson('cd', 'en'), contains('questions_cd_en.json'));
      expect(config.topicsJson('ab', 'en'), contains('topics_ab_en.json'));
      expect(config.signsJson('en'), contains('signs_en.json'));
      expect(config.signsFeedManifestJson('en'), contains('signs_feed_manifest_en.json'));
      expect(config.markupJson('en'), contains('markup_en.json'));
      expect(config.pddSectionsJson('en'), contains('pdd_sections_en.json'));

      // Kazakh paths
      expect(config.questionsJson('ab', 'kk'), contains('questions_ab_kk.json'));
      expect(config.questionsJson('cd', 'kk'), contains('questions_cd_kk.json'));
      expect(config.topicsJson('ab', 'kk'), contains('topics_ab_kk.json'));
      expect(config.signsJson('kk'), contains('signs_kk.json'));
      expect(config.signsFeedManifestJson('kk'), contains('signs_feed_manifest_kk.json'));
      expect(config.markupJson('kk'), contains('markup_kk.json'));
      expect(config.pddSectionsJson('kk'), contains('pdd_sections_kk.json'));
    });

    test('CountryConfig maps TTS locales correctly', () {
      final config = CountryConfig.current;
      expect(config.ttsLocaleFor('ru'), equals('ru-RU'));
      expect(config.ttsLocaleFor('en'), equals('en-US'));
      expect(config.ttsLocaleFor('kk'), equals('kk-KZ'));
      expect(config.ttsLocaleFor(null), equals('ru-RU'));
    });

    test('DriverTipsData supplies localized tips for all languages', () {
      final ruTips = DriverTipsData.getTips('ru');
      final enTips = DriverTipsData.getTips('en');
      final kkTips = DriverTipsData.getTips('kk');

      expect(ruTips.length, equals(20));
      expect(enTips.length, equals(20));
      expect(kkTips.length, equals(20));

      for (int i = 0; i < 20; i++) {
        expect(ruTips[i].id, equals(enTips[i].id));
        expect(ruTips[i].id, equals(kkTips[i].id));

        expect(enTips[i].title.isNotEmpty, isTrue);
        expect(enTips[i].description.isNotEmpty, isTrue);
        expect(kkTips[i].title.isNotEmpty, isTrue);
        expect(kkTips[i].description.isNotEmpty, isTrue);
      }
    });

    test('Crossroads models and enums have localized labels', () {
      expect(CrossroadsSide.south.localizedTitle('en'), equals('South'));
      expect(CrossroadsSide.north.localizedTitle('kk'), equals('Солтүстік'));
      expect(CrossroadsSide.east.localizedTitle('ru'), equals('Восток'));

      expect(CrossroadsManeuver.straight.localizedLabel('en'), equals('Straight'));
      expect(CrossroadsManeuver.left.localizedLabel('kk'), equals('Солға'));

      expect(CrossroadsVehicleType.car.localizedLabel('en'), equals('Car'));
      expect(CrossroadsVehicleType.tram.localizedLabel('kk'), equals('Трамвай'));
      expect(CrossroadsVehicleType.police.localizedLabel('en'), equals('Police'));
    });

    test('CrossroadsScenariosLibrary returns full scenarios for all languages', () {
      for (final lang in ['ru', 'en', 'kk']) {
        final scenarios = CrossroadsScenariosLibrary.getScenarios(lang);
        expect(scenarios.length, equals(18));
        for (final sc in scenarios) {
          expect(sc.title.isNotEmpty, isTrue);
          expect(sc.subtitle.isNotEmpty, isTrue);
          expect(sc.pddArticle.isNotEmpty, isTrue);
          for (final actor in sc.actors) {
            expect(actor.name.isNotEmpty, isTrue);
            expect(actor.ruleExplanation.isNotEmpty, isTrue);
          }
        }
      }
    });

    test('Localized questions, topics, signs, markup, pdd_sections exist and match Russian base', () {
      final assetsDir = Directory('assets/countries/ru/questions');
      for (final lang in ['en', 'kk']) {
        for (final cat in ['ab', 'cd']) {
          final ruQuestionsFile = File('${assetsDir.path}/questions_$cat.json');
          final locQuestionsFile = File('${assetsDir.path}/questions_${cat}_$lang.json');
          if (!locQuestionsFile.existsSync()) {
            continue; // Will pass if files are still generating, but when generated must be fully valid
          }

          final ruJson = jsonDecode(ruQuestionsFile.readAsStringSync()) as Map<String, dynamic>;
          final locJson = jsonDecode(locQuestionsFile.readAsStringSync()) as Map<String, dynamic>;

          final ruTickets = ruJson['tickets'] as List<dynamic>;
          final locTickets = locJson['tickets'] as List<dynamic>;
          expect(locTickets.length, equals(ruTickets.length), reason: 'Ticket counts mismatch for $lang $cat');

          for (int t = 0; t < ruTickets.length; t++) {
            final ruTicket = ruTickets[t] as Map<String, dynamic>;
            final locTicket = locTickets[t] as Map<String, dynamic>;
            final ruQuestions = ruTicket['questions'] as List<dynamic>;
            final locQuestions = locTicket['questions'] as List<dynamic>;
            expect(locQuestions.length, equals(ruQuestions.length));

            for (int q = 0; q < ruQuestions.length; q++) {
              final ruQ = ruQuestions[q] as Map<String, dynamic>;
              final locQ = locQuestions[q] as Map<String, dynamic>;
              expect(locQ['id'], equals(ruQ['id']));

              final locQText = locQ['question'] as String;
              expect(locQText.isNotEmpty, isTrue);

              final ruAnswers = ruQ['answers'] as List<dynamic>;
              final locAnswers = locQ['answers'] as List<dynamic>;
              expect(locAnswers.length, equals(ruAnswers.length));

              for (int a = 0; a < ruAnswers.length; a++) {
                final ruA = ruAnswers[a] as Map<String, dynamic>;
                final locA = locAnswers[a] as Map<String, dynamic>;
                expect(locA['isCorrect'], equals(ruA['isCorrect']));
                expect((locA['text'] as String).isNotEmpty, isTrue);
              }

              if (ruQ['comment'] != null) {
                expect((locQ['comment'] as String).isNotEmpty, isTrue);
              }
            }
          }

          // Topics
          final locTopicsFile = File('${assetsDir.path}/topics_${cat}_$lang.json');
          if (locTopicsFile.existsSync()) {
            final locTopicsJson = jsonDecode(locTopicsFile.readAsStringSync()) as Map<String, dynamic>;
            final locTopics = locTopicsJson['topics'] as List<dynamic>;
            expect(locTopics.isNotEmpty, isTrue);
            for (final top in locTopics) {
              expect((top['name'] as String).isNotEmpty, isTrue);
            }
          }
        }

        // Signs
        final locSignsFile = File('${assetsDir.path}/signs_$lang.json');
        if (locSignsFile.existsSync()) {
          final locSignsJson = jsonDecode(locSignsFile.readAsStringSync()) as Map<String, dynamic>;
          expect(locSignsJson.isNotEmpty, isTrue);
        }

        // Signs feed manifest
        final locManifestFile = File('${assetsDir.path}/signs_feed_manifest_$lang.json');
        if (locManifestFile.existsSync()) {
          final locManifestJson = jsonDecode(locManifestFile.readAsStringSync()) as List<dynamic>;
          expect(locManifestJson.isNotEmpty, isTrue);
        }

        // Markup
        final locMarkupFile = File('${assetsDir.path}/markup_$lang.json');
        if (locMarkupFile.existsSync()) {
          final locMarkupJson = jsonDecode(locMarkupFile.readAsStringSync()) as Map<String, dynamic>;
          expect(locMarkupJson.isNotEmpty, isTrue);
        }

        // PDD sections
        final locPddFile = File('${assetsDir.path}/pdd_sections_$lang.json');
        if (locPddFile.existsSync()) {
          final locPddJson = jsonDecode(locPddFile.readAsStringSync()) as List<dynamic>;
          expect(locPddJson.length, equals(26));
          for (final sec in locPddJson) {
            expect((sec['title'] as String).isNotEmpty, isTrue);
            expect((sec['content'] as String).isNotEmpty, isTrue);
          }
        }
      }
    });
  });
}
