import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';

class QuestionsDataSource {
  Future<List<Question>> loadTickets(TicketCategory category) async {
    final path = category == TicketCategory.ab
        ? 'assets/questions/questions_ab.json'
        : 'assets/questions/questions_cd.json';
    final imageDir =
        category == TicketCategory.ab ? 'questions_ab' : 'questions_cd';

    final String content = await rootBundle.loadString(path);
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
          q['image'] = 'assets/images/$imageDir/${q['image']}.jpg';
        }
        allQuestions.add(Question.fromJson(q));
      }
    }
    return allQuestions;
  }

  Future<List<Map<String, dynamic>>> loadTopics(TicketCategory category) async {
    final path = category == TicketCategory.ab
        ? 'assets/questions/topics_ab.json'
        : 'assets/questions/topics_cd.json';
    final imageDir =
        category == TicketCategory.ab ? 'questions_ab' : 'questions_cd';

    final String content = await rootBundle.loadString(path);
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
          q['image'] = 'assets/images/$imageDir/${q['image']}.jpg';
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
    final String content = await rootBundle.loadString('assets/questions/signs.json');
    return json.decode(content) as Map<String, dynamic>;
  }
}
