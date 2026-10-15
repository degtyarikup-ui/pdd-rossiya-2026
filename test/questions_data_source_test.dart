import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const config = CountryConfig.current;
  final assets = <String, String>{};
  final requested = <String>[];
  final source = QuestionsDataSource();
  final paths = <String>{
    for (final lang in ['ru', 'en', 'kk']) ...[
      for (final cat in ['ab', 'cd']) ...[
        config.questionsJson(cat, lang),
        config.topicsJson(cat, lang),
      ],
      config.signsJson(lang),
      config.signsFeedManifestJson(lang),
      config.markupJson(lang),
      config.pddSectionsJson(lang),
    ],
  };

  setUp(() {
    assets.clear();
    requested.clear();
    for (final path in paths) {
      rootBundle.evict(path);
    }
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final path = utf8.decode(
        message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      requested.add(path);
      final content = assets[path];
      if (content == null) return null;
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    for (final path in paths) {
      rootBundle.evict(path);
    }
  });

  test(
    'ticket parsing retains category paths, order and localized fallback',
    () async {
      assets[config.questionsJson('cd')] = jsonEncode({
        'tickets': [
          null,
          {
            'number': 7,
            'questions': [
              false,
              {
                'id': 42,
                'question': 'Исходный вопрос',
                'ticketNumber': 99,
                'image': 'photo_hash',
                'comment': 'Разбор',
                'pddPoints': ['13.1'],
                'topic': ['Перекрёстки'],
                'answers': [
                  {'answer_text': 'Да', 'is_correct': true},
                  {'text': 'Нет', 'correct': false},
                ],
              },
              {'id': 'no-photo', 'image': 'no_image'},
              {'id': 'missing-photo'},
            ],
          },
        ],
      });
      final questions = await source.loadTickets(TicketCategory.cd, 'en');
      expect(requested, [
        config.questionsJson('cd', 'en'),
        config.questionsJson('cd'),
      ]);
      expect(questions.map((question) => question.id), [
        '42',
        'no-photo',
        'missing-photo',
      ]);
      expect(questions.first.toMap(), {
        'id': '42',
        'question': 'Исходный вопрос',
        'ticketNumber': 7,
        'image': '${config.questionImagesDir('cd')}/photo_hash.webp',
        'comment': 'Разбор',
        'pddPoints': ['13.1'],
        'topic': ['Перекрёстки'],
        'answers': [
          {'text': 'Да', 'correct': true},
          {'text': 'Нет', 'correct': false},
        ],
      });
      expect(questions[1].image, isNull);
      expect(questions[2].image, isNull);
      expect(questions.every((question) => question.ticketNumber == 7), isTrue);
    },
  );

  test(
    'topic parsing keeps localized names and the authored ticket number',
    () async {
      assets[config.topicsJson('ab', 'kk')] = jsonEncode({
        'topics': [
          'ignore',
          {
            'name': 'Жол қиылыстары',
            'questions': [
              {
                'id': 'q1',
                'question': 'Сұрақ',
                'ticketNumber': 12,
                'image': 'same_picture',
                'answers': [
                  {'text': 'Жауап', 'correct': true},
                ],
              },
              null,
              {'id': 'q2', 'image': 'no_image'},
            ],
          },
          {'name': 123},
        ],
      });
      final topics = await source.loadTopics(TicketCategory.ab, 'kk');
      expect(requested, [config.topicsJson('ab', 'kk')]);
      expect(topics.map((topic) => topic['name']), ['Жол қиылыстары', '123']);
      final questions = topics.first['questions'] as List<Question>;
      expect(questions.map((question) => question.id), ['q1', 'q2']);
      expect(questions.first.ticketNumber, 12);
      expect(
        questions.first.image,
        '${config.questionImagesDir('ab')}/same_picture.webp',
      );
      expect(questions.first.correctAnswerIndex, 0);
      expect(questions[1].image, isNull);
      expect(topics.last['questions'], isEmpty);
    },
  );

  test(
    'missing or malformed ticket and topic data still returns an empty list',
    () async {
      expect(await source.loadTickets(TicketCategory.ab), isEmpty);
      expect(await source.loadTopics(TicketCategory.ab), isEmpty);
      for (final content in [
        '{invalid',
        '[]',
        '{"tickets":false,"topics":false}',
      ]) {
        assets[config.questionsJson('ab')] = content;
        assets[config.topicsJson('ab')] = content;
        rootBundle.evict(config.questionsJson('ab'));
        rootBundle.evict(config.topicsJson('ab'));
        expect(await source.loadTickets(TicketCategory.ab), isEmpty);
        expect(await source.loadTopics(TicketCategory.ab), isEmpty);
      }
    },
  );

  test(
    'signs and feed parsing preserve nested data and filter invalid rows',
    () async {
      assets[config.signsJson('en')] = jsonEncode({
        'Warning': [
          {'title': 'Crossroads', 'image': '1.6'},
        ],
      });
      assets[config.signsFeedManifestJson('en')] = jsonEncode([
        {'id': '1.6', 'title': 'Crossroads'},
        null,
        false,
      ]);
      expect(await source.loadSigns('en'), {
        'Warning': [
          {'title': 'Crossroads', 'image': '1.6'},
        ],
      });
      expect(await source.loadSignsFeedManifest('en'), [
        {'id': '1.6', 'title': 'Crossroads'},
      ]);
      rootBundle.evict(config.signsJson('en'));
      rootBundle.evict(config.signsFeedManifestJson('en'));
      assets[config.signsJson('en')] = '{invalid';
      assets[config.signsFeedManifestJson('en')] = '{invalid';
      expect(await source.loadSigns('en'), isEmpty);
      expect(await source.loadSignsFeedManifest('en'), isEmpty);
    },
  );

  test(
    'PDD and markup parsers retain fallback and empty-field behavior',
    () async {
      assets[config.markupJson()] = jsonEncode({
        'Горизонтальная': [
          {'title': '1.1', 'description': 'Линия'},
          {'title': '1.2'},
          false,
        ],
        'Не список': null,
      });
      assets[config.pddSectionsJson()] = jsonEncode([
        {'title': '1. Общие положения', 'content': 'Текст'},
        {'content': 'Без заголовка'},
        false,
      ]);
      expect(await source.loadMarkup('kk'), {
        'Горизонтальная': [
          {'title': '1.1', 'description': 'Линия'},
          {'title': '1.2', 'description': ''},
        ],
        'Не список': <Map<String, String>>[],
      });
      expect(await source.loadPddSections('kk'), [
        {'title': '1. Общие положения', 'content': 'Текст'},
        {'title': '', 'content': 'Без заголовка'},
      ]);
      expect(requested, [
        config.markupJson('kk'),
        config.markupJson(),
        config.pddSectionsJson('kk'),
        config.pddSectionsJson(),
      ]);
    },
  );

  test('PDD and markup parse errors remain visible to the caller', () async {
    assets[config.markupJson()] = '{invalid';
    assets[config.pddSectionsJson()] = '{invalid';
    await expectLater(source.loadMarkup(), throwsFormatException);
    await expectLater(source.loadPddSections(), throwsFormatException);
  });
}
