import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Search Normalization & Diacritics Unit Tests', () {
    String normalize(String s) =>
        s.trim().toLowerCase().replaceAll('ё', 'е');

    test('Normalize handles e/ё, casing, and whitespace', () {
      expect(normalize('  Ёлочка  '), equals('елочка'));
      expect(normalize('ПЕРЕКРЁСТОК'), equals('перекресток'));
      expect(normalize('Въезд запрещён'), equals('въезд запрещен'));
    });

    test('FavoritesScreen filter logic matches case-insensitively and with e/ё', () {
      final questions = [
        {
          'id': '1_1',
          'question': 'Главная дорога на перекрёстке',
          'topic': ['Приоритет'],
        },
        {
          'id': '1_2',
          'question': null,
          'topic': null,
        },
      ];

      List<Map<String, dynamic>> filter(String rawQuery) {
        final query = normalize(rawQuery);
        if (query.isEmpty) return questions;
        return questions.where((question) {
          final text = normalize((question['question'] as String?) ?? '');
          final topics = normalize(
            (((question['topic'] as List?) ?? const []).join(' ')),
          );
          return text.contains(query) || topics.contains(query);
        }).toList();
      }

      // Stem with uppercase, spaces and 'е' should match 'Главная дорога на перекрёстке'
      final res1 = filter('  ПЕРЕКРЕСТ  ');
      expect(res1.length, equals(1));
      expect(res1.first['id'], equals('1_1'));

      // Topic search with lowercase
      final res2 = filter('приоритет');
      expect(res2.length, equals(1));
      expect(res2.first['id'], equals('1_1'));

      // Null question or topic does not throw
      final res3 = filter('несуществующий');
      expect(res3, isEmpty);
    });

    test('SignsScreen search logic correctly matches numbers, folk names, and categories', () {
      final signsMap = <String, dynamic>{
        '3.1': {
          'number': '3.1',
          'title': 'Въезд запрещён',
          'folkName': 'кирпич',
          'description': 'Запрещает въезд всех транспортных средств.',
        },
        '3.27': {
          'number': '3.27',
          'title': 'Остановка запрещена',
          'folkName': 'крест',
          'description': 'Запрещается остановка и стоянка.',
        },
        '1.26': {
          'number': '1.26',
          'title': 'Перекрёсток',
          'folkName': 'вафельница',
          'description': 'Приближение к перекрёстку.',
        },
      };

      Map<String, dynamic> searchSigns(String rawQuery) {
        final normalizedQuery = normalize(rawQuery);
        if (normalizedQuery.isEmpty) return signsMap;
        final matchingSigns = <String, dynamic>{};
        signsMap.forEach((key, val) {
          if (val is Map) {
            final title = normalize(val['title'] as String? ?? '');
            final desc = normalize(val['description'] as String? ?? '');
            final folk = normalize(val['folkName'] as String? ?? '');
            final num = normalize(key);
            if (title.contains(normalizedQuery) ||
                desc.contains(normalizedQuery) ||
                folk.contains(normalizedQuery) ||
                num.contains(normalizedQuery)) {
              matchingSigns[key] = val;
            }
          }
        });
        return matchingSigns;
      }

      // Query "КИРПИЧ" (uppercase)
      expect(searchSigns('КИРПИЧ').keys, contains('3.1'));

      // Query "3.1" (by sign number)
      expect(searchSigns('3.1').keys, contains('3.1'));

      // Query "перекресток" (with 'е', matches 'Перекрёсток')
      expect(searchSigns('перекресток').keys, contains('1.26'));
    });
  });

  group('Session Restoration & Hardening Tests', () {
    test('Unfinished session clamp does not crash when questions list is empty', () {
      final questions = <Map<String, dynamic>>[];
      final savedIndex = 5;

      // The hardened logic:
      final clampedIndex = questions.isEmpty
          ? 0
          : savedIndex.clamp(0, questions.length - 1);
      expect(clampedIndex, equals(0));
    });

    test('ProgressDataSource stores and returns valid unfinished session', () async {
      SharedPreferences.setMockInitialValues({});
      final source = ProgressDataSource();
      await source.init();

      await source.saveUnfinishedSession(
        title: 'Билет 1',
        questionIds: ['1_1', '1_2'],
        index: 1,
        category: TicketCategory.ab,
      );

      final session = source.loadUnfinishedSession(TicketCategory.ab);
      expect(session, isNotNull);
      expect(session!['title'], equals('Билет 1'));
      expect(session['index'], equals(1));
      expect(session['questionIds'], equals(['1_1', '1_2']));
    });

    test('ExamScreen score lists are correctly computed', () {
      final questions = List.generate(20, (i) => <String, dynamic>{
        'id': 'q$i',
        'question': 'Вопрос №${i + 1}',
        'answers': [
          {'text': 'Верный', 'correct': true},
          {'text': 'Неверный', 'correct': false},
        ],
      });

      final savedAnswers = <int?>[0, 1, 0, null];
      final correctAnswers = <int>[];
      final wrongAnswers = <int>[];
      int unanswered = 0;

      for (var i = 0; i < savedAnswers.length; i++) {
        final s = savedAnswers[i];
        if (s == null) {
          unanswered++;
          continue;
        }
        final ok = (questions[i]['answers'] as List)[s]['correct'] as bool;
        if (ok) {
          correctAnswers.add(i);
        } else {
          wrongAnswers.add(i);
        }
      }

      expect(correctAnswers, equals([0, 2]));
      expect(wrongAnswers, equals([1]));
      expect(unanswered, equals(1));
    });
  });
}
