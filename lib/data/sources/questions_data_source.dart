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
    try {
      final cat = _cat(category);
      final String content =
          await rootBundle.loadString(_config.questionsJson(cat));
      final dynamic data = json.decode(content);
      final List<dynamic> tickets =
          data is Map ? (data['tickets'] as List<dynamic>? ?? []) : [];

      final List<Question> allQuestions = [];
      for (final ticket in tickets) {
        if (ticket is! Map) continue;
        final int ticketNumber = (ticket['number'] as num?)?.toInt() ?? 0;
        final List<dynamic> questions =
            ticket['questions'] as List<dynamic>? ?? [];
        for (final q in questions) {
          if (q is! Map) continue;
          final map = Map<String, dynamic>.from(q);
          map['ticketNumber'] = ticketNumber;
          if (map['image'] == null || map['image'] == 'no_image') {
            map['image'] = null;
          } else {
            map['image'] = '${_config.questionImagesDir(cat)}/${map['image']}.webp';
          }
          allQuestions.add(Question.fromJson(map));
        }
      }
      return allQuestions;
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> loadTopics(TicketCategory category) async {
    try {
      final cat = _cat(category);
      final String content =
          await rootBundle.loadString(_config.topicsJson(cat));
      final dynamic data = json.decode(content);
      final List<dynamic> topics =
          data is Map ? (data['topics'] as List<dynamic>? ?? []) : [];

      final List<Map<String, dynamic>> result = [];
      for (final topic in topics) {
        if (topic is! Map) continue;
        final String name = topic['name']?.toString() ?? '';
        final List<dynamic> questions =
            topic['questions'] as List<dynamic>? ?? [];
        final List<Question> parsedQuestions = [];

        for (final q in questions) {
          if (q is! Map) continue;
          final map = Map<String, dynamic>.from(q);
          if (map['image'] == null || map['image'] == 'no_image') {
            map['image'] = null;
          } else {
            map['image'] = '${_config.questionImagesDir(cat)}/${map['image']}.webp';
          }
          parsedQuestions.add(Question.fromJson(map));
        }

        result.add({
          'name': name,
          'questions': parsedQuestions,
        });
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> loadSigns() async {
    try {
      final String content = await rootBundle.loadString(_config.signsJson);
      final dynamic decoded = json.decode(content);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> loadSignsFeedManifest() async {
    try {
      final String content =
          await rootBundle.loadString('assets/countries/ru/questions/signs_feed_manifest.json');
      final dynamic decoded = json.decode(content);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
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
