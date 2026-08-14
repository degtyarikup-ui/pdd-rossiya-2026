import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';

/// Загрузка контента страны (вопросы, темы, знаки) из ассетов.
/// Все пути строятся от [CountryConfig.assetsRoot] — контент каждой страны
/// лежит в assets/countries/{code}/.
class QuestionsDataSource {
  static const CountryConfig _config = CountryConfig.current;

  String _cat(TicketCategory category) =>
      category == TicketCategory.ab ? 'ab' : 'cd';

  Future<List<Question>> loadTickets(TicketCategory category) async {
    final cat = _cat(category);
    final String content =
        await rootBundle.loadString(_config.questionsJson(cat));
    final Map<String, dynamic> data = json.decode(content);
    final List<dynamic> tickets = data['tickets'];

    final List<Question> allQuestions = [];
    for (final ticket in tickets) {
      final int ticketNumber = ticket['number'];
      final List<dynamic> questions = ticket['questions'];
      for (final q in questions) {
        q['ticketNumber'] = ticketNumber;
        if (q['image'] == null || q['image'] == 'no_image') {
          q['image'] = null;
        } else {
          q['image'] = '${_config.questionImagesDir(cat)}/${q['image']}.jpg';
        }
        allQuestions.add(Question.fromJson(q));
      }
    }
    return allQuestions;
  }

  Future<List<Map<String, dynamic>>> loadTopics(TicketCategory category) async {
    final cat = _cat(category);
    final String content =
        await rootBundle.loadString(_config.topicsJson(cat));
    final Map<String, dynamic> data = json.decode(content);
    final List<dynamic> topics = data['topics'];

    final List<Map<String, dynamic>> result = [];
    for (final topic in topics) {
      final String name = topic['name'];
      final List<dynamic> questions = topic['questions'];
      final List<Question> parsedQuestions = [];

      for (final q in questions) {
        if (q['image'] == null || q['image'] == 'no_image') {
          q['image'] = null;
        } else {
          q['image'] = '${_config.questionImagesDir(cat)}/${q['image']}.jpg';
        }
        parsedQuestions.add(Question.fromJson(q));
      }

      result.add({
        'name': name,
        'questions': parsedQuestions,
      });
    }
    return result;
  }

  Future<Map<String, dynamic>> loadSigns() async {
    final String content = await rootBundle.loadString(_config.signsJson);
    return json.decode(content) as Map<String, dynamic>;
  }

  /// Дорожная разметка по группам: { «Горизонтальная разметка»: [{title,
  /// description}, …], «Вертикальная разметка»: […] }. Страно-зависимая.
  Future<Map<String, List<Map<String, String>>>> loadMarkup() async {
    final String content = await rootBundle.loadString(_config.markupJson);
    final Map<String, dynamic> data = json.decode(content) as Map<String, dynamic>;
    return data.map((group, entries) {
      final list = (entries as List<dynamic>)
          .map((e) => {
                'title': (e as Map)['title'] as String,
                'description': e['description'] as String,
              })
          .toList();
      return MapEntry(group, list);
    });
  }

  /// Разделы текста ПДД для вкладки «ПДД»: [{'title':…, 'content':…}, …].
  Future<List<Map<String, String>>> loadPddSections() async {
    final String content =
        await rootBundle.loadString(_config.pddSectionsJson);
    final List<dynamic> sections = json.decode(content) as List<dynamic>;
    return sections
        .map((s) => {
              'title': s['title'] as String,
              'content': s['content'] as String,
            })
        .toList();
  }
}
