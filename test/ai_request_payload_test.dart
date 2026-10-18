import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/services/gemini_ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<http.Request> send({
    required List<AiChatMessage> history,
    String question = 'Что означает сигнал свистком регулировщика?',
    List<String> answers = const ['Привлечение внимания', 'Начало движения'],
    String explanation = 'Сигнал подаётся для привлечения внимания.',
    String userMessage = 'Объясни подробнее',
  }) async {
    late http.Request sent;
    await http.runWithClient(
      () => GeminiAiService.instance.askAiQuestion(
        questionId: 'fixture-question',
        questionText: question,
        answers: answers,
        correctAnswerIndex: 0,
        officialExplanation: explanation,
        conversationHistory: history,
        userMessage: userMessage,
      ),
      () => MockClient((request) async {
        sent = request;
        return http.Response('{"reply":"fixture reply"}', 200);
      }),
    );
    return sent;
  }

  test(
    'ordinary AI request preserves the question and recent conversation',
    () async {
      final history = [
        AiChatMessage(
          text: 'Первый вопрос',
          isUser: true,
          timestamp: DateTime(2026),
        ),
      ];
      final request = await send(history: history);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(
        body['questionText'],
        'Что означает сигнал свистком регулировщика?',
      );
      expect(body['answers'], ['Привлечение внимания', 'Начало движения']);
      expect(
        body['officialExplanation'],
        'Сигнал подаётся для привлечения внимания.',
      );
      expect(body['messages'], [
        {'text': 'Первый вопрос', 'isUser': true},
      ]);
      expect(body['userMessage'], 'Объясни подробнее');
      expect(request.bodyBytes.length, lessThanOrEqualTo(65536));
    },
  );

  test(
    'long multibyte chat fits the worker body limit without changing local history',
    () async {
      final history = List.generate(
        300,
        (i) => AiChatMessage(
          text: '$i: ${'Дорожная ситуация 🚦\\" ' * 150}',
          isUser: i.isEven,
          timestamp: DateTime(2026),
        ),
      );
      final originalLast = history.last.text;
      final request = await send(history: history);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final sentHistory = (body['messages'] as List)
          .cast<Map<String, dynamic>>();
      expect(request.bodyBytes.length, lessThanOrEqualTo(65536));
      expect(sentHistory.length, inInclusiveRange(1, 20));
      expect(sentHistory.last['text'], startsWith('299:'));
      expect(
        sentHistory.every(
          (message) => (message['text'] as String).length <= 2000,
        ),
        isTrue,
      );
      expect(history.length, 300);
      expect(history.last.text, originalLast);
    },
  );

  test('escaped base content also remains within the byte limit', () async {
    final request = await send(
      history: const [],
      question: '\u0000' * 1000,
      answers: List.filled(6, '\u0000' * 1000),
      explanation: '\u0000' * 8000,
      userMessage: '\u0000' * 4000,
    );
    expect(request.bodyBytes.length, lessThanOrEqualTo(65536));
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['correctAnswerIndex'], 0);
    expect((body['answers'] as List).length, 6);
  });
}
