import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/question_identity.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final category in ['ab', 'cd']) {
    for (final language in ['', '_en', '_kk']) {
      test(
        '$category$language: 800 independent questions agree with topics',
        () {
          final base = 'assets/countries/ru/questions';
          final tickets =
              jsonDecode(
                    File(
                      '$base/questions_$category$language.json',
                    ).readAsStringSync(),
                  )
                  as Map;
          final byId = <String, Map<String, dynamic>>{};
          for (final ticket in tickets['tickets'] as List) {
            final questions = ticket['questions'] as List;
            expect(questions, hasLength(20));
            for (var i = 0; i < questions.length; i++) {
              final raw = Map<String, dynamic>.from(questions[i] as Map);
              final question = Question.fromJson(raw);
              expect(question.ticketNumber, ticket['number']);
              expect(question.questionNumber, i + 1);
              expect(byId.containsKey(question.id), false, reason: question.id);
              expect(QuestionIdentity.sourceId(question.id), raw['id']);
              expect(question.answers.where((a) => a.isCorrect), hasLength(1));
              byId[question.id] = raw;
            }
          }
          expect(byId, hasLength(800));
          final topics =
              jsonDecode(
                    File(
                      '$base/topics_$category$language.json',
                    ).readAsStringSync(),
                  )
                  as Map;
          final seen = <String>{};
          for (final topic in topics['topics'] as List) {
            for (final raw in topic['questions'] as List) {
              final question = Question.fromJson(
                Map<String, dynamic>.from(raw as Map),
              );
              final canonical = byId[question.id];
              expect(canonical, isNotNull);
              for (final field in [
                'question',
                'answers',
                'comment',
                'pddPoints',
                'image',
                'ticketNumber',
                'questionNumber',
              ]) {
                expect(
                  raw[field],
                  canonical![field],
                  reason: '${question.id}: $field',
                );
              }
              seen.add(question.id);
            }
          }
          expect(seen, hasLength(800));
        },
      );
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameGarageService.instance.resetForTest();
  });

  for (final category in TicketCategory.values) {
    final alias = QuestionIdentity.aliases[category]!.entries.first;
    test(
      '${category.name}: old progress survives split; future answers stay independent',
      () async {
        final suffix = category.name;
        SharedPreferences.setMockInitialValues({
          'question_progress_$suffix': jsonEncode({
            alias.value: {
              'isCorrect': true,
              'selectedAnswerIndex': 1,
              'answeredAt': '2026-10-01T10:00:00.000',
              'attemptsCount': 3,
            },
          }),
          'favorites_$suffix': jsonEncode([alias.value]),
        });
        final ds = ProgressDataSource();
        await ds.init();
        expect(
          (await ds.getQuestionProgress(alias.key, category))!['attemptsCount'],
          3,
        );
        expect(await ds.isFavorite(alias.key, category), true);
        await ds.saveAnswer(
          questionId: alias.key,
          isCorrect: false,
          selectedAnswerIndex: 0,
          category: category,
        );
        await ds.toggleFavorite(alias.key, category);
        final stale = <String, dynamic>{
          'questionProgress${suffix == 'ab' ? 'Ab' : 'Cd'}': {
            alias.value: {
              'isCorrect': true,
              'selectedAnswerIndex': 1,
              'answeredAt': '2026-10-01T10:00:00.000',
            },
          },
          'favorites${suffix == 'ab' ? 'Ab' : 'Cd'}': [alias.value],
        };
        await ds.importProgressSnapshot(stale);
        await ds.init();
        expect(
          (await ds.getQuestionProgress(alias.key, category))!['isCorrect'],
          false,
        );
        expect(
          (await ds.getQuestionProgress(alias.value, category))!['isCorrect'],
          true,
        );
        expect(await ds.isFavorite(alias.key, category), false);
        expect(await ds.isFavorite(alias.value, category), true);
        await ds.resetAllProgress();
        await ds.importProgressSnapshot(stale);
        expect(await ds.isQuestionAnswered(alias.key, category), false);
        expect(await ds.isFavorite(alias.key, category), false);
      },
    );

    test('${category.name}: legacy cloud expands on a fresh device', () async {
      final ds = ProgressDataSource();
      await ds.init();
      final suffix = category == TicketCategory.ab ? 'Ab' : 'Cd';
      await ds.importProgressSnapshot({
        'questionProgress$suffix': {
          alias.value: {
            'isCorrect': false,
            'selectedAnswerIndex': 0,
            'answeredAt': '2026-10-01T10:00:00.000',
          },
        },
        'favorites$suffix': [alias.value],
      });
      expect(await ds.isQuestionAnswered(alias.key, category), true);
      expect(await ds.isFavorite(alias.key, category), true);
    });
  }
}
