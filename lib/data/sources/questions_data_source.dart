import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';

/// Загрузка контента страны (вопросы, темы, знаки) из ассетов.
/// Все пути строятся от [CountryConfig.assetsRoot] — контент каждой страны
/// лежит в assets/countries/{code}/.
/// На native разбор JSON и построение вопросов идут в отдельном isolate,
/// чтобы загрузчик продолжал двигаться. Веб-версия compute использует UI isolate.
class QuestionsDataSource {
  static const CountryConfig _config = CountryConfig.current;

  String _cat(TicketCategory category) =>
      category == TicketCategory.ab ? 'ab' : 'cd';

  Future<String> _loadStringWithFallback(
    String path,
    String fallbackPath,
  ) async {
    try {
      return await rootBundle.loadString(path);
    } catch (_) {
      return await rootBundle.loadString(fallbackPath);
    }
  }

  Future<List<Question>> loadTickets(
    TicketCategory category, [
    String? lang,
  ]) async {
    try {
      final cat = _cat(category);
      final String content = await _loadStringWithFallback(
        _config.questionsJson(cat, lang),
        _config.questionsJson(cat),
      );
      return await compute(_parseTickets, (
        content: content,
        imageDir: _config.questionImagesDir(cat),
      ), debugLabel: 'parse tickets');
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> loadTopics(
    TicketCategory category, [
    String? lang,
  ]) async {
    try {
      final cat = _cat(category);
      final String content = await _loadStringWithFallback(
        _config.topicsJson(cat, lang),
        _config.topicsJson(cat),
      );
      return await compute(_parseTopics, (
        content: content,
        imageDir: _config.questionImagesDir(cat),
      ), debugLabel: 'parse topics');
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> loadSigns([String? lang]) async {
    try {
      final String content = await _loadStringWithFallback(
        _config.signsJson(lang),
        _config.signsJson(),
      );
      final dynamic decoded = await compute(
        jsonDecode,
        content,
        debugLabel: 'parse signs',
      );
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> loadSignsFeedManifest([
    String? lang,
  ]) async {
    try {
      final String content = await _loadStringWithFallback(
        _config.signsFeedManifestJson(lang),
        _config.signsFeedManifestJson(),
      );
      final dynamic decoded = await compute(
        jsonDecode,
        content,
        debugLabel: 'parse signs feed',
      );
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
  Future<Map<String, List<Map<String, String>>>> loadMarkup([
    String? lang,
  ]) async {
    final String content = await _loadStringWithFallback(
      _config.markupJson(lang),
      _config.markupJson(),
    );
    return compute(_parseMarkup, content, debugLabel: 'parse markup');
  }

  /// Разделы текста ПДД для вкладки «ПДД»: [{'title':…, 'content':…}, …].
  Future<List<Map<String, String>>> loadPddSections([String? lang]) async {
    final String content = await _loadStringWithFallback(
      _config.pddSectionsJson(lang),
      _config.pddSectionsJson(),
    );
    return compute(_parsePddSections, content, debugLabel: 'parse PDD');
  }
}

typedef _QuestionSource = ({String content, String imageDir});

// Only sendable source text and a resolved path cross the isolate boundary.
// Asset loading and country/language fallback remain on the calling isolate.
List<Question> _parseTickets(_QuestionSource source) {
  final dynamic data = jsonDecode(source.content);
  final List<dynamic> tickets = data is Map
      ? (data['tickets'] as List<dynamic>? ?? [])
      : [];
  final allQuestions = <Question>[];
  for (final ticket in tickets) {
    if (ticket is! Map) continue;
    final ticketNumber = (ticket['number'] as num?)?.toInt() ?? 0;
    final questions = ticket['questions'] as List<dynamic>? ?? [];
    for (var index = 0; index < questions.length; index++) {
      final question = questions[index];
      if (question is! Map) continue;
      final map = _withImagePath(question, source.imageDir);
      map['ticketNumber'] = ticketNumber;
      map['questionNumber'] = index + 1;
      allQuestions.add(Question.fromJson(map));
    }
  }
  return allQuestions;
}

List<Map<String, dynamic>> _parseTopics(_QuestionSource source) {
  final dynamic data = jsonDecode(source.content);
  final List<dynamic> topics = data is Map
      ? (data['topics'] as List<dynamic>? ?? [])
      : [];
  final result = <Map<String, dynamic>>[];
  for (final topic in topics) {
    if (topic is! Map) continue;
    final questions = topic['questions'] as List<dynamic>? ?? [];
    final parsedQuestions = <Question>[];
    for (final question in questions) {
      if (question is! Map) continue;
      parsedQuestions.add(
        Question.fromJson(_withImagePath(question, source.imageDir)),
      );
    }
    result.add({
      'name': topic['name']?.toString() ?? '',
      'questions': parsedQuestions,
    });
  }
  return result;
}

Map<String, dynamic> _withImagePath(Map question, String imageDir) {
  final map = Map<String, dynamic>.from(question);
  map['image'] = map['image'] == null || map['image'] == 'no_image'
      ? null
      : '$imageDir/${map['image']}.webp';
  return map;
}

Map<String, List<Map<String, String>>> _parseMarkup(String content) {
  final dynamic decoded = jsonDecode(content);
  if (decoded is! Map) return {};
  return decoded.map((group, entries) {
    if (entries is! List) {
      return MapEntry(group.toString(), <Map<String, String>>[]);
    }
    final list = entries
        .whereType<Map>()
        .map(
          (entry) => {
            'title': (entry['title'] as String?) ?? '',
            'description': (entry['description'] as String?) ?? '',
          },
        )
        .toList();
    return MapEntry(group.toString(), list);
  });
}

List<Map<String, String>> _parsePddSections(String content) {
  final dynamic decoded = jsonDecode(content);
  if (decoded is! List) return [];
  return decoded
      .whereType<Map>()
      .map(
        (section) => {
          'title': (section['title'] as String?) ?? '',
          'content': (section['content'] as String?) ?? '',
        },
      )
      .toList();
}
