import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/utils/pdd_point_refs.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart' as swiper;
import 'package:pdd_app/data/services/pdd_point_index.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';
import 'package:pdd_app/data/sources/sign_scenarios_library.dart';
import 'package:pdd_app/domain/services/road_signs_engine.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

dynamic readContent(String name) => jsonDecode(
  File('assets/countries/ru/questions/$name.json').readAsStringSync(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => updateAppLocale(const Locale('ru')));

  test(
    'resuming a saved session localizes its title without changing progress',
    () async {
      SharedPreferences.setMockInitialValues({});
      final progress = ProgressDataSource();
      await progress.init();
      final data = QuestionsDataSource();
      final bank = await data.loadTickets(TicketCategory.ab, 'ru');
      final topics = await data.loadTopics(TicketCategory.ab, 'ru');
      for (final feature in ['tickets', 'topics', 'mistakes', 'favorites']) {
        final ids = feature == 'topics'
            ? (topics.first['questions'] as List<Question>)
                  .map((q) => q.id)
                  .toList()
            : bank.where((q) => q.ticketNumber == 14).map((q) => q.id).toList();
        await progress.saveUnfinishedSession(
          usageFeature: feature,
          title: 'Старый русский заголовок',
          questionIds: ids,
          index: 3,
          category: TicketCategory.ab,
        );
        final container = ProviderContainer(
          overrides: [progressDataSourceProvider.overrideWithValue(progress)],
        );
        try {
          final settings = container.read(appSettingsProvider.notifier);
          await settings.ready;
          for (final lang in ['ru', 'en', 'kk', 'en']) {
            await settings.setLanguageCode(lang);
            final session = (await container.read(
              unfinishedSessionProvider.future,
            ))!;
            final strings = lookupAppLocalizations(Locale(lang));
            final expectedTitle = switch (feature) {
              'tickets' => strings.ticketNumber(14),
              'topics' => (await data.loadTopics(
                TicketCategory.ab,
                lang,
              )).first['name'],
              'mistakes' => strings.mistakesTitle,
              _ => strings.favorites,
            };
            expect(session['title'], expectedTitle);
            expect(session['index'], 3);
            expect((session['questions'] as List).map((q) => q['id']), ids);
          }
        } finally {
          container.dispose();
        }
      }
    },
  );

  test(
    'support attachment labels follow locale without translating replies',
    () {
      for (final lang in ['ru', 'en', 'kk']) {
        updateAppLocale(Locale(lang));
        final message = SupportChatMessage.fromJson({
          'sender': 'support',
          'text': 'Текст оператора [Документ]',
          'kind': 'attachment_document',
        });
        expect(
          message.displayText,
          'Текст оператора ${appL10n.supportAttachmentDocument}',
        );
        expect(
          SupportChatMessage.fromJson({
            'sender': 'support',
            'text': 'Текст оператора [Документ]',
          }).displayText,
          'Текст оператора [Документ]',
        );
        expect(
          SupportChatMessage.fromJson({
            'sender': 'user',
            'text': '[Документ]',
          }).displayText,
          '[Документ]',
        );
      }
    },
  );

  test('all ticket AND topic answers retain the exact illustration labels', () {
    Set<String> labels(String text, {bool russian = false}) {
      if (russian &&
          text.startsWith('В ') &&
          !text.startsWith('В и ') &&
          !text.startsWith('В или ')) {
        text = text.substring(2); // The Russian preposition is not a label.
      }
      return RegExp(
        r'(?<![\p{L}\d])([АБВГ])(?![\p{L}\d])',
        unicode: true,
      ).allMatches(text).map((m) => m[1]!).toSet();
    }

    var checked = 0;
    for (final category in ['ab', 'cd']) {
      for (final collection in ['questions', 'topics']) {
        final groupKey = collection == 'questions' ? 'tickets' : 'topics';
        final source = readContent('${collection}_$category') as Map;
        for (final lang in ['en', 'kk']) {
          final target = readContent('${collection}_${category}_$lang') as Map;
          final sourceGroups = source[groupKey] as List;
          final targetGroups = target[groupKey] as List;
          expect(targetGroups.length, sourceGroups.length);
          for (var g = 0; g < sourceGroups.length; g++) {
            final sourceQuestions = sourceGroups[g]['questions'] as List;
            final targetQuestions = targetGroups[g]['questions'] as List;
            expect(targetQuestions.length, sourceQuestions.length);
            for (var q = 0; q < sourceQuestions.length; q++) {
              final ru = sourceQuestions[q] as Map;
              final localized = targetQuestions[q] as Map;
              for (final field in [
                'id',
                'variantId',
                'image',
                'ticketNumber',
                'questionNumber',
              ]) {
                expect(
                  localized[field],
                  ru[field],
                  reason: '$collection $category $lang ${ru['id']} $field',
                );
              }
              final answers = ru['answers'] as List;
              final localizedAnswers = localized['answers'] as List;
              expect(localizedAnswers.length, answers.length);
              for (var a = 0; a < answers.length; a++) {
                expect(
                  localizedAnswers[a]['isCorrect'],
                  answers[a]['isCorrect'],
                );
                final expected = labels(
                  answers[a]['text'] as String,
                  russian: true,
                );
                if (expected.isEmpty) continue;
                checked++;
                expect(
                  labels(localizedAnswers[a]['text'] as String),
                  expected,
                  reason:
                      '$collection $category $lang ${ru['id']}: ${answers[a]['text']}',
                );
              }
            }
          }
        }
      }
    }
    expect(checked, greaterThan(1000));
  });

  test(
    'all translated rule points retain their original numbers and order',
    () {
      final ru = readContent('pdd_sections') as List;
      final start = RegExp(r'^(\d{1,2}(?:\.\d{1,2}){1,3})\.', multiLine: true);
      for (final lang in ['en', 'kk']) {
        final localized = readContent('pdd_sections_$lang') as List;
        expect(localized.length, ru.length);
        for (var i = 0; i < ru.length; i++) {
          List<String?> numbers(String text) =>
              start.allMatches(text).map((m) => m[1]).toList();
          expect(
            numbers(localized[i]['content'] as String),
            numbers(ru[i]['content'] as String),
          );
        }
      }
    },
  );

  test('sign quiz templates and reviewed meanings follow each locale', () {
    for (final lang in ['ru', 'en', 'kk']) {
      final l10n = lookupAppLocalizations(Locale(lang));
      final signs = RoadSignsEngine.parseSignsJson(
        readContent('signs${lang == 'ru' ? '' : '_$lang'}')
            as Map<String, dynamic>,
      );
      final engine = RoadSignsEngine(
        allSigns: signs,
        random: Random(17),
        l10n: l10n,
      );
      final sign = signs.firstWhere((s) => s.number == '3.1');
      final types = <RoadSignQuizType>{};
      for (var i = 0; i < 80; i++) {
        final question = engine.buildQuestionForSign(sign)!;
        types.add(question.type);
        expect(question.options.length, 4);
        expect(question.options[question.correctAnswerIndex], sign);
        if (lang == 'en') {
          expect(RegExp(r'[А-Яа-яЁё]').hasMatch(question.prompt), isFalse);
          expect(question.officialRuleQuote, isNot(contains('Punishment')));
          expect(
            question.officialRuleQuote,
            isNot(contains('Administrative Offenses')),
          );
        } else if (lang == 'kk') {
          expect(question.prompt, isNot(contains('Какой')));
          expect(
            question.officialRuleQuote,
            isNot(contains('бұзғаны үшін жаза')),
          );
        }
      }
      expect(types, containsAll(RoadSignQuizType.values));
    }
  });

  test(
    'sign-swiper questions and action labels survive repeated locale switches',
    () {
      for (final lang in ['ru', 'en', 'kk', 'en', 'ru']) {
        updateAppLocale(Locale(lang));
        final scenarios = SignScenariosLibrary.getScenariosForSign('1.1')!;
        expect(scenarios.first.prompt, appL10n.gameSignScenario1_1_0Prompt);
        const sign = swiper.SignItem(
          number: '1.1',
          title: '',
          image: '',
          category: '',
          description: '',
        );
        for (final scenario in scenarios) {
          final question = swiper.SignCardQuestion(
            id: '',
            sign: sign,
            prompt: scenario.prompt,
            isCorrect: scenario.isCorrect,
            explanation: scenario.explanation,
            type: scenario.type,
          );
          final permission =
              scenario.type == swiper.SignQuestionType.actionPermission;
          expect(
            question.rightActionLabel,
            permission ? appL10n.gameSignCan : appL10n.gameSignYes,
          );
          expect(
            question.leftActionLabel,
            permission ? appL10n.gameSignCannot : appL10n.gameSignNo,
          );
        }
      }
    },
  );

  test('localized references link rule numbers, never bare sign numbers', () {
    for (final example in {
      'en':
          'Signs 3.1 and 4.1.1. Paragraphs 8.1, 8.2 and 8.5 of the Traffic Rules.',
      'kk': '3.1 және 4.1.1 белгілері. ЖҚЕ 8.1, 8.2 және 8.5-тармақтары.',
    }.entries) {
      final refs = findPddPointRefs(example.value, lang: example.key);
      expect(refs.map((r) => r.point), ['8.1', '8.2', '8.5']);
      for (final ref in refs) {
        expect(example.value.substring(ref.start, ref.end), ref.point);
      }
    }
    expect(
      findPddPointRefs('Signs 3.1 and 4.1.1; markings 1.1.', lang: 'en'),
      isEmpty,
    );
    expect(
      findPddPointRefs('3.1 және 4.1.1 белгілері, 1.1 таңбасы.', lang: 'kk'),
      isEmpty,
    );
    expect(
      findPddPointRefs('ЖҚЕ 9.1(1) тармағы', lang: 'kk').single.point,
      '9.1.1',
    );
    expect(
      findPddPointRefs('(ЖҚЕ 1.2 тармағы)', lang: 'kk').single.point,
      '1.2',
    );
    expect(
      findPddPointRefs(
        '(Section 9.9 of the Traffic Rules)',
        lang: 'en',
      ).single.point,
      '9.9',
    );
  });

  test('the rule index is cached separately for every language', () async {
    final ru = await PddPointIndex.load('ru');
    final en = await PddPointIndex.load('en');
    final kk = await PddPointIndex.load('kk');
    expect(en, isNot(same(ru)));
    expect(kk, isNot(same(en)));
    expect(await PddPointIndex.load('en'), same(en));
    expect(en.sectionOf('19.11')!['content'], contains('19.11.'));
    expect(
      en.sectionOf('13.11')!['title'],
      isNot(ru.sectionOf('13.11')!['title']),
    );
    expect(
      kk.sectionOf('13.11')!['title'],
      isNot(ru.sectionOf('13.11')!['title']),
    );
  });

  test('references in real translated comments remain navigable', () async {
    final index = await PddPointIndex.load('ru');
    var checked = 0;
    for (final cat in ['ab', 'cd']) {
      final source = readContent('questions_$cat') as Map;
      for (final lang in ['en', 'kk']) {
        final target = readContent('questions_${cat}_$lang') as Map;
        for (var t = 0; t < (source['tickets'] as List).length; t++) {
          final ru = source['tickets'][t]['questions'] as List;
          final localized = target['tickets'][t]['questions'] as List;
          for (var q = 0; q < ru.length; q++) {
            final expected = findPddPointRefs(
              ru[q]['comment'] as String? ?? '',
            ).map((r) => r.point).where(index.contains).toSet();
            if (expected.isEmpty) continue;
            checked++;
            final actual = findPddPointRefs(
              localized[q]['comment'] as String? ?? '',
              lang: lang,
            ).map((r) => r.point).toSet();
            expect(
              actual,
              containsAll(expected),
              reason: '$cat $lang ${ru[q]['id']}',
            );
          }
        }
      }
    }
    expect(checked, greaterThan(900));
    expect(
      findPddPointRefs('("List of malfunctions", paragraph 5.2)', lang: 'en'),
      isEmpty,
    );
    expect(
      findPddPointRefs('«Ақаулықтардың тізімі», 5.2-тармағы', lang: 'kk'),
      isEmpty,
    );
  });
}
